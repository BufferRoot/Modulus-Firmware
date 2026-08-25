/*
 * ZBOSS ZC hub — NanoH2 dedicated 802.15.4 radio (Tier-1 hardened).
 * Protocol mirrored in firmware/tab5/.../zb_link_proto.h.
 */
#include "zigbee_hub.h"
#include "zb_proto.h"
#include "zb_uart_link.h"

#include "esp_check.h"
#include "esp_log.h"
#include "esp_zigbee_core.h"
#include "ha/esp_zigbee_ha_standard.h"
#include "nwk/esp_zigbee_nwk.h"
#include "zcl/esp_zigbee_zcl_common.h"
#include "zdo/esp_zigbee_zdo_command.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include <stdbool.h>
#include <string.h>

static const char *TAG = "zb_hub";

#define HUB_EP              1
#define HUB_MAX_CHILDREN    32
#define HUB_DEV_MAX         HUB_MAX_CHILDREN
#define HUB_ZB_TASK_STACK   8192
#define HUB_SCAN_DURATION   3 /* ((1<<3)+1) beacon times per channel */

typedef struct {
    bool     used;
    uint16_t short_addr;
    uint8_t  ieee_msb[8];
    uint8_t  ep;
    uint8_t  caps;
    uint16_t device_id;
    uint8_t  lqi;
    int8_t   rssi;
    uint8_t  age;
} hub_dev_t;

static bool          s_task_up;
static volatile bool s_stack_ready;
static volatile bool s_user_permit;
static volatile bool s_formed;
static uint8_t       s_req_channel; /* 0 = auto energy-scan */
static bool          s_channel_forced;
static bool          s_form_after_scan;
static uint8_t       s_permit_s;
static uint8_t       s_reply_seq; /* non-zero while handling a sequenced host cmd */
static hub_dev_t     s_devs[HUB_DEV_MAX];

#define HUB_HEARTBEAT_TICKS 20 /* 20 * 100 ms = 2 s (was 5 s) */

/* reportable_change blobs must outlive async ZCL config-report TX */
static uint8_t  s_chg_u8 = 1;
static int16_t  s_chg_s16 = 50; /* 0.5 C for LocalTemperature */
static uint16_t s_chg_u16 = 1;

static void send_evt(uint8_t evt, const uint8_t *data, uint16_t data_len)
{
    uint8_t buf[1 + ZB_LINK_MAX_PAYLOAD];
    if (data_len > ZB_LINK_MAX_PAYLOAD - 1) {
        return;
    }
    buf[0] = evt;
    if (data && data_len) {
        memcpy(buf + 1, data, data_len);
    }
    if (!zb_uart_link_send(buf, (uint16_t)(1 + data_len))) {
        ESP_LOGW(TAG, "link TX failed for evt 0x%02x", evt);
    }
}

static void send_ok(void)
{
    if (s_reply_seq) {
        uint8_t d[1] = {s_reply_seq};
        send_evt(ZIGBEE_EVT_ACK, d, 1);
    } else {
        send_evt(ZIGBEE_EVT_OK, NULL, 0);
    }
}

static void send_fail(uint8_t reason)
{
    if (s_reply_seq) {
        uint8_t d[2] = {s_reply_seq, reason};
        send_evt(ZIGBEE_EVT_NAK, d, 2);
    } else {
        send_evt(ZIGBEE_EVT_FAIL, &reason, 1);
    }
}

bool zigbee_hub_formed(void)
{
    return s_formed;
}

static void ieee_msb(const esp_zb_ieee_addr_t in, uint8_t out[8])
{
    for (int i = 0; i < 8; i++) {
        out[i] = in[7 - i];
    }
}

static void ieee_msb_to_lsb(const uint8_t in_msb[8], esp_zb_ieee_addr_t out)
{
    for (int i = 0; i < 8; i++) {
        out[i] = in_msb[7 - i];
    }
}

/* ── Device table ───────────────────────────────────────────────────────── */

static hub_dev_t *dev_find_short(uint16_t short_addr)
{
    for (int i = 0; i < HUB_DEV_MAX; i++) {
        if (s_devs[i].used && s_devs[i].short_addr == short_addr) {
            return &s_devs[i];
        }
    }
    return NULL;
}

static hub_dev_t *dev_find_ieee(const uint8_t ieee_msb_in[8])
{
    for (int i = 0; i < HUB_DEV_MAX; i++) {
        if (s_devs[i].used && memcmp(s_devs[i].ieee_msb, ieee_msb_in, 8) == 0) {
            return &s_devs[i];
        }
    }
    return NULL;
}

static hub_dev_t *dev_alloc(void)
{
    for (int i = 0; i < HUB_DEV_MAX; i++) {
        if (!s_devs[i].used) {
            memset(&s_devs[i], 0, sizeof(s_devs[i]));
            s_devs[i].used = true;
            return &s_devs[i];
        }
    }
    return NULL;
}

static void dev_upsert_joined(uint16_t short_addr, const uint8_t ieee_msb_in[8])
{
    hub_dev_t *d = dev_find_ieee(ieee_msb_in);
    if (!d) {
        d = dev_find_short(short_addr);
    }
    if (!d) {
        d = dev_alloc();
    }
    if (!d) {
        ESP_LOGW(TAG, "device table full (%d)", HUB_DEV_MAX);
        return;
    }
    d->short_addr = short_addr;
    memcpy(d->ieee_msb, ieee_msb_in, 8);
}

static void dev_set_caps(uint16_t short_addr, uint8_t ep, uint8_t caps, uint16_t device_id)
{
    hub_dev_t *d = dev_find_short(short_addr);
    if (!d) {
        d = dev_alloc();
        if (!d) {
            return;
        }
        d->short_addr = short_addr;
    }
    d->ep = ep;
    d->caps = caps;
    d->device_id = device_id;
}

static void dev_remove_ieee(const uint8_t ieee_msb_in[8])
{
    hub_dev_t *d = dev_find_ieee(ieee_msb_in);
    if (d) {
        d->used = false;
    }
}

static void hub_bdb_commission(uint8_t mode)
{
    (void)esp_zb_bdb_start_top_level_commissioning(mode);
}

static void hub_send_state(void)
{
    uint8_t st[5];
    uint16_t pan = 0;
    uint8_t ch = (s_req_channel >= 11 && s_req_channel <= 26) ? s_req_channel : 0;
    if (s_formed && s_task_up && s_stack_ready) {
        esp_zb_lock_acquire(portMAX_DELAY);
        pan = esp_zb_get_pan_id();
        ch = esp_zb_get_current_channel();
        esp_zb_lock_release();
    }
    st[0] = s_formed ? 1 : 0;
    st[1] = ch;
    st[2] = (uint8_t)(pan >> 8);
    st[3] = (uint8_t)pan;
    st[4] = s_permit_s;
    send_evt(ZIGBEE_EVT_HUB_STATE, st, sizeof(st));
    uint8_t leg[6] = {st[1], st[2], st[3], 0, 0, st[0]};
    send_evt(ZIGBEE_EVT_STATE, leg, sizeof(leg));
}

/* ── Bind + configure reporting ─────────────────────────────────────────── */

static void hub_bind_cb(esp_zb_zdp_status_t status, void *user_ctx)
{
    ESP_LOGI(TAG, "Bind 0x%04x cluster 0x%04x: %s",
             (uint16_t)((uintptr_t)user_ctx >> 16),
             (uint16_t)((uintptr_t)user_ctx & 0xFFFF),
             status == ESP_ZB_ZDP_STATUS_SUCCESS ? "ok" : "failed");
}

static void hub_bind_cluster(uint16_t short_addr, uint8_t src_ep, uint16_t cluster)
{
    esp_zb_zdo_bind_req_param_t req = {0};
    if (esp_zb_ieee_address_by_short(short_addr, req.src_address) != ESP_OK) {
        ESP_LOGW(TAG, "Bind: no IEEE for 0x%04x yet", short_addr);
        return;
    }
    req.src_endp = src_ep;
    req.cluster_id = cluster;
    req.dst_addr_mode = ESP_ZB_ZDO_BIND_DST_ADDR_MODE_64_BIT_EXTENDED;
    esp_zb_get_long_address(req.dst_address_u.addr_long);
    req.dst_endp = HUB_EP;
    req.req_dst_addr = short_addr;
    esp_zb_zdo_device_bind_req(&req, hub_bind_cb,
                               (void *)(uintptr_t)(((uint32_t)short_addr << 16) | cluster));
}

static void hub_cfg_report(uint16_t short_addr, uint8_t ep, uint16_t cluster,
                           uint16_t attr, uint8_t attr_type, void *change)
{
    esp_zb_zcl_config_report_record_t rec = {
        .direction = ESP_ZB_ZCL_REPORT_DIRECTION_SEND,
        .attributeID = attr,
        .attrType = attr_type,
        .min_interval = 0,
        .max_interval = 60,
        .reportable_change = change,
    };
    esp_zb_zcl_config_report_cmd_t cmd = {
        .zcl_basic_cmd = {
            .dst_addr_u.addr_short = short_addr,
            .dst_endpoint = ep,
            .src_endpoint = HUB_EP,
        },
        .address_mode = ESP_ZB_APS_ADDR_MODE_16_ENDP_PRESENT,
        .clusterID = cluster,
        .record_number = 1,
        .record_field = &rec,
    };
    esp_zb_zcl_config_report_cmd_req(&cmd);
}

static void hub_bind_and_report(uint16_t short_addr, uint8_t ep, uint8_t caps)
{
    if (caps & ZIGBEE_CAP_ONOFF) {
        hub_bind_cluster(short_addr, ep, 0x0006);
        hub_cfg_report(short_addr, ep, 0x0006, 0x0000, ESP_ZB_ZCL_ATTR_TYPE_BOOL, &s_chg_u8);
    }
    if (caps & ZIGBEE_CAP_LEVEL) {
        hub_bind_cluster(short_addr, ep, 0x0008);
        hub_cfg_report(short_addr, ep, 0x0008, 0x0000, ESP_ZB_ZCL_ATTR_TYPE_U8, &s_chg_u8);
    }
    if (caps & ZIGBEE_CAP_COVER) {
        hub_bind_cluster(short_addr, ep, 0x0102);
        /* CurrentPositionLiftPercentage */
        hub_cfg_report(short_addr, ep, 0x0102, 0x0008, ESP_ZB_ZCL_ATTR_TYPE_U8, &s_chg_u8);
    }
    if (caps & ZIGBEE_CAP_THERMOSTAT) {
        hub_bind_cluster(short_addr, ep, 0x0201);
        hub_cfg_report(short_addr, ep, 0x0201, 0x0000, ESP_ZB_ZCL_ATTR_TYPE_S16, &s_chg_s16);
        hub_cfg_report(short_addr, ep, 0x0201, 0x0012, ESP_ZB_ZCL_ATTR_TYPE_S16, &s_chg_s16);
    }
    if (caps & ZIGBEE_CAP_SENSOR) {
        hub_bind_cluster(short_addr, ep, 0x0500);
        /* ZoneStatus — many devices use Zone Status Change Notification instead */
        hub_cfg_report(short_addr, ep, 0x0500, 0x0002, ESP_ZB_ZCL_ATTR_TYPE_16BITMAP, &s_chg_u16);
    }
    if (caps & ZIGBEE_CAP_COLOR) {
        hub_bind_cluster(short_addr, ep, 0x0300);
        hub_cfg_report(short_addr, ep, 0x0300, 0x0007, ESP_ZB_ZCL_ATTR_TYPE_U16, &s_chg_u16); /* CCT */
    }
    if (caps & ZIGBEE_CAP_POWER) {
        hub_bind_cluster(short_addr, ep, 0x0B04);
        hub_cfg_report(short_addr, ep, 0x0B04, 0x050B, ESP_ZB_ZCL_ATTR_TYPE_S16, &s_chg_s16); /* ActivePower */
    }
    if (caps & ZIGBEE_CAP_METER) {
        /* Bind only — summation is U48; host polls via READ_SENSORS. */
        hub_bind_cluster(short_addr, ep, 0x0702);
    }
}

static uint8_t caps_from_simple_desc(const esp_zb_af_simple_desc_1_1_t *sd)
{
    uint8_t caps = 0;
    for (int i = 0; i < sd->app_input_cluster_count; i++) {
        switch (sd->app_cluster_list[i]) {
        case 0x0006: caps |= ZIGBEE_CAP_ONOFF; break;
        case 0x0008: caps |= ZIGBEE_CAP_LEVEL; break;
        case 0x0102: caps |= ZIGBEE_CAP_COVER; break;
        case 0x0201: caps |= ZIGBEE_CAP_THERMOSTAT; break;
        case 0x0500: caps |= ZIGBEE_CAP_SENSOR; break;
        case 0x0B04: caps |= ZIGBEE_CAP_POWER; break;
        case 0x0702: caps |= ZIGBEE_CAP_METER; break;
        case 0x0300: caps |= ZIGBEE_CAP_COLOR; break;
        default: break;
        }
    }
    return caps;
}

/* Interview: read Basic cluster ManufacturerName (0x0004) + ModelIdentifier
 * (0x0005). The model string is the zigbee2mqtt lookup key — the P4 resolves
 * it against its on-flash device database for a friendly name + quirks.
 * Runs in ZBOSS callback context (no lock needed). */
static void hub_read_basic_info(uint16_t short_addr, uint8_t ep)
{
    static uint16_t k_basic_attrs[] = {0x0004, 0x0005};
    esp_zb_zcl_read_attr_cmd_t cmd = {
        .zcl_basic_cmd = {
            .dst_addr_u.addr_short = short_addr,
            .dst_endpoint = ep,
            .src_endpoint = HUB_EP,
        },
        .address_mode = ESP_ZB_APS_ADDR_MODE_16_ENDP_PRESENT,
        .clusterID = 0x0000,
        .attr_number = 2,
        .attr_field = k_basic_attrs,
    };
    esp_zb_zcl_read_attr_cmd_req(&cmd);
}

static void hub_simple_desc_cb(esp_zb_zdp_status_t status,
                               esp_zb_af_simple_desc_1_1_t *simple_desc, void *user_ctx)
{
    const uint16_t short_addr = (uint16_t)(uintptr_t)user_ctx;
    if (status != ESP_ZB_ZDP_STATUS_SUCCESS || !simple_desc) {
        ESP_LOGW(TAG, "Simple desc 0x%04x failed (%d)", short_addr, status);
        return;
    }
    const uint8_t caps = caps_from_simple_desc(simple_desc);
    uint8_t evt[6];
    evt[0] = (uint8_t)(short_addr >> 8);
    evt[1] = (uint8_t)short_addr;
    evt[2] = simple_desc->endpoint;
    evt[3] = caps;
    evt[4] = (uint8_t)(simple_desc->app_device_id >> 8);
    evt[5] = (uint8_t)simple_desc->app_device_id;
    ESP_LOGI(TAG, "Dev 0x%04x ep%u caps=0x%02x dev_id=0x%04x", short_addr,
             (unsigned)evt[2], (unsigned)caps, (unsigned)simple_desc->app_device_id);
    send_evt(ZIGBEE_EVT_DEV_CAPS, evt, sizeof(evt));
    dev_set_caps(short_addr, simple_desc->endpoint, caps, simple_desc->app_device_id);
    hub_bind_and_report(short_addr, simple_desc->endpoint, caps);
    hub_read_basic_info(short_addr, simple_desc->endpoint);
}

static void hub_active_ep_cb(esp_zb_zdp_status_t status, uint8_t ep_count,
                             uint8_t *ep_id_list, void *user_ctx)
{
    const uint16_t short_addr = (uint16_t)(uintptr_t)user_ctx;
    if (status != ESP_ZB_ZDP_STATUS_SUCCESS || ep_count == 0 || !ep_id_list) {
        ESP_LOGW(TAG, "Active EP 0x%04x failed (%d)", short_addr, status);
        return;
    }
    esp_zb_zdo_simple_desc_req_param_t req = {
        .addr_of_interest = short_addr,
        .endpoint = ep_id_list[0],
    };
    esp_zb_zdo_simple_desc_req(&req, hub_simple_desc_cb, (void *)(uintptr_t)short_addr);
}

static void hub_discover_caps(uint16_t short_addr)
{
    esp_zb_zdo_active_ep_req_param_t req = {.addr_of_interest = short_addr};
    esp_zb_zdo_active_ep_req(&req, hub_active_ep_cb, (void *)(uintptr_t)short_addr);
}

/* ── Energy scan (form + diagnostic) ────────────────────────────────────── */

static void hub_start_form(void)
{
    const uint8_t ch = (s_req_channel >= 11 && s_req_channel <= 26) ? s_req_channel : 16;
    s_req_channel = ch;
    esp_zb_set_primary_network_channel_set(1u << ch);
    ESP_LOGI(TAG, "Forming network on ch %u", (unsigned)ch);
    esp_zb_bdb_start_top_level_commissioning(ESP_ZB_BDB_MODE_NETWORK_FORMATION);
}

static void hub_energy_cb(esp_zb_zdp_status_t status, uint16_t count,
                          esp_zb_energy_detect_channel_info_t *channel_info)
{
    uint8_t best_ch = 16;
    int8_t best_e = 127;
    if (status == ESP_ZB_ZDP_STATUS_SUCCESS && channel_info && count > 0) {
        for (uint16_t i = 0; i < count; i++) {
            const uint8_t ch = channel_info[i].channel_number;
            const int8_t e = channel_info[i].energy_detected;
            uint8_t ev[2] = {ch, (uint8_t)e};
            send_evt(ZIGBEE_EVT_ENERGY_CH, ev, sizeof(ev));
            if (ch >= 11 && ch <= 26 && e < best_e) {
                best_e = e;
                best_ch = ch;
            }
        }
    } else {
        ESP_LOGW(TAG, "Energy scan failed status=%d — fallback ch 16", status);
        best_e = 0;
    }
    uint8_t done[2] = {best_ch, (uint8_t)best_e};
    send_evt(ZIGBEE_EVT_ENERGY_DONE, done, sizeof(done));
    ESP_LOGI(TAG, "Energy scan best ch %u (%d dBm)", (unsigned)best_ch, (int)best_e);

    if (s_form_after_scan) {
        s_form_after_scan = false;
        s_req_channel = best_ch;
        hub_start_form();
    }
}

static void hub_energy_scan(bool form_after)
{
    if (!s_stack_ready) {
        send_fail(0x1D);
        return;
    }
    s_form_after_scan = form_after;
    ESP_LOGI(TAG, "Energy detect start (form_after=%d)", (int)form_after);
    esp_zb_zdo_energy_detect_request(ESP_ZB_TRANSCEIVER_ALL_CHANNELS_MASK,
                                     HUB_SCAN_DURATION, hub_energy_cb);
}

/* ── Neighbor / LQI ─────────────────────────────────────────────────────── */

static void hub_refresh_lqi(void)
{
    if (!s_stack_ready || !s_formed) {
        send_fail(0x1C);
        return;
    }
    uint8_t n = 0;
    esp_zb_nwk_info_iterator_t it = ESP_ZB_NWK_INFO_ITERATOR_INIT;
    esp_zb_nwk_neighbor_info_t nbr;
    esp_zb_lock_acquire(portMAX_DELAY);
    while (esp_zb_nwk_get_next_neighbor(&it, &nbr) == ESP_OK) {
        uint8_t ieee[8];
        ieee_msb(nbr.ieee_addr, ieee);
        hub_dev_t *d = dev_find_short(nbr.short_addr);
        if (!d) {
            d = dev_find_ieee(ieee);
        }
        if (d) {
            d->lqi = nbr.lqi;
            d->rssi = nbr.rssi;
            d->age = nbr.age;
            d->short_addr = nbr.short_addr;
        }
        uint8_t ev[5] = {
            (uint8_t)(nbr.short_addr >> 8),
            (uint8_t)nbr.short_addr,
            nbr.lqi,
            (uint8_t)nbr.rssi,
            nbr.age,
        };
        send_evt(ZIGBEE_EVT_DEV_LQI, ev, sizeof(ev));
        n++;
    }
    esp_zb_lock_release();
    uint8_t done[2] = {2 /* lqi refresh */, n};
    send_evt(ZIGBEE_EVT_TABLE_DONE, done, sizeof(done));
    send_ok();
}

static void hub_dump_devices(void)
{
    uint8_t n = 0;
    for (int i = 0; i < HUB_DEV_MAX; i++) {
        const hub_dev_t *d = &s_devs[i];
        if (!d->used) {
            continue;
        }
        uint8_t ev[16];
        ev[0] = (uint8_t)(d->short_addr >> 8);
        ev[1] = (uint8_t)d->short_addr;
        memcpy(&ev[2], d->ieee_msb, 8);
        ev[10] = d->ep;
        ev[11] = d->caps;
        ev[12] = (uint8_t)(d->device_id >> 8);
        ev[13] = (uint8_t)d->device_id;
        ev[14] = d->lqi;
        ev[15] = (uint8_t)d->rssi;
        send_evt(ZIGBEE_EVT_DEV_ENTRY, ev, sizeof(ev));
        n++;
    }
    uint8_t done[2] = {0, n};
    send_evt(ZIGBEE_EVT_TABLE_DONE, done, sizeof(done));
    send_ok();
}

static void hub_dump_neighbors(void)
{
    if (!s_stack_ready || !s_formed) {
        send_fail(0x1B);
        return;
    }
    uint8_t n = 0;
    esp_zb_nwk_info_iterator_t it = ESP_ZB_NWK_INFO_ITERATOR_INIT;
    esp_zb_nwk_neighbor_info_t nbr;
    esp_zb_lock_acquire(portMAX_DELAY);
    while (esp_zb_nwk_get_next_neighbor(&it, &nbr) == ESP_OK) {
        uint8_t ev[15];
        ev[0] = (uint8_t)(nbr.short_addr >> 8);
        ev[1] = (uint8_t)nbr.short_addr;
        ieee_msb(nbr.ieee_addr, &ev[2]);
        ev[10] = nbr.relationship;
        ev[11] = nbr.lqi;
        ev[12] = (uint8_t)nbr.rssi;
        ev[13] = nbr.age;
        ev[14] = nbr.depth;
        send_evt(ZIGBEE_EVT_NBR_ENTRY, ev, sizeof(ev));
        n++;
    }
    esp_zb_lock_release();
    uint8_t done[2] = {1, n};
    send_evt(ZIGBEE_EVT_TABLE_DONE, done, sizeof(done));
    send_ok();
}

static void hub_leave_cb(esp_zb_zdp_status_t zdo_status, void *user_ctx)
{
    ESP_LOGI(TAG, "Leave req status %d ctx=%p", zdo_status, user_ctx);
}

static void hub_dev_leave(const uint8_t *a, uint16_t n)
{
    if (!s_stack_ready || !s_formed || n < 8) {
        send_fail(0x19);
        return;
    }
    esp_zb_ieee_addr_t ieee;
    ieee_msb_to_lsb(a, ieee);
    uint16_t short_addr = esp_zb_address_short_by_ieee(ieee);
    if (short_addr == 0xFFFF) {
        /* Still drop local row if we only know IEEE from join table */
        hub_dev_t *d = dev_find_ieee(a);
        if (d) {
            short_addr = d->short_addr;
        }
    }
    esp_zb_zdo_mgmt_leave_req_param_t req = {0};
    memcpy(req.device_address, ieee, sizeof(ieee));
    req.dst_nwk_addr = (short_addr != 0xFFFF) ? short_addr : 0x0000;
    req.remove_children = 0;
    req.rejoin = 0;
    esp_zb_lock_acquire(portMAX_DELAY);
    esp_zb_zdo_device_leave_req(&req, hub_leave_cb, NULL);
    esp_zb_lock_release();
    /* Optimistic local remove; LEAVE_INDICATION confirms to host */
    dev_remove_ieee(a);
    send_evt(ZIGBEE_EVT_DEV_LEFT, a, 8);
    send_ok();
}

/* ── Signal handler ─────────────────────────────────────────────────────── */

void esp_zb_app_signal_handler(esp_zb_app_signal_t *signal_struct)
{
    uint32_t *p_sg_p = signal_struct->p_app_signal;
    esp_err_t err = signal_struct->esp_err_status;
    esp_zb_app_signal_type_t sig = *p_sg_p;

    switch (sig) {
    case ESP_ZB_ZDO_SIGNAL_SKIP_STARTUP:
        ESP_LOGI(TAG, "ZB stack initialized");
        s_stack_ready = true;
        esp_zb_bdb_start_top_level_commissioning(ESP_ZB_BDB_MODE_INITIALIZATION);
        break;
    case ESP_ZB_BDB_SIGNAL_DEVICE_FIRST_START:
    case ESP_ZB_BDB_SIGNAL_DEVICE_REBOOT:
        if (err == ESP_OK) {
            if (esp_zb_bdb_is_factory_new()) {
                if (s_channel_forced && s_req_channel >= 11 && s_req_channel <= 26) {
                    hub_start_form();
                } else {
                    hub_energy_scan(true);
                }
            } else {
                s_formed = true;
                s_req_channel = esp_zb_get_current_channel();
                ESP_LOGI(TAG, "Rebooted into existing network (pan 0x%04x ch %u)",
                         esp_zb_get_pan_id(), (unsigned)s_req_channel);
                hub_send_state();
            }
        } else {
            ESP_LOGW(TAG, "ZB init signal err %d", err);
            send_fail(0x10);
        }
        break;
    case ESP_ZB_BDB_SIGNAL_FORMATION:
        if (err == ESP_OK) {
            s_formed = true;
            s_req_channel = esp_zb_get_current_channel();
            ESP_LOGI(TAG, "Formed network pan 0x%04x ch %u",
                     esp_zb_get_pan_id(), (unsigned)s_req_channel);
            esp_zb_bdb_start_top_level_commissioning(ESP_ZB_BDB_MODE_NETWORK_STEERING);
            hub_send_state();
        } else {
            ESP_LOGW(TAG, "Formation failed (%d), retrying", err);
            esp_zb_scheduler_alarm((esp_zb_callback_t)hub_bdb_commission,
                                   ESP_ZB_BDB_MODE_NETWORK_FORMATION, 1000);
        }
        break;
    case ESP_ZB_BDB_SIGNAL_STEERING:
        hub_send_state();
        break;
    case ESP_ZB_ZDO_SIGNAL_DEVICE_ANNCE: {
        esp_zb_zdo_signal_device_annce_params_t *ann =
            (esp_zb_zdo_signal_device_annce_params_t *)esp_zb_app_signal_get_params(p_sg_p);
        if (ann) {
            uint8_t evt[11];
            evt[0] = (uint8_t)(ann->device_short_addr >> 8);
            evt[1] = (uint8_t)ann->device_short_addr;
            ieee_msb(ann->ieee_addr, &evt[2]);
            evt[10] = ann->capability;
            ESP_LOGI(TAG, "Device joined short=0x%04x", ann->device_short_addr);
            send_evt(ZIGBEE_EVT_DEV_JOINED, evt, sizeof(evt));
            dev_upsert_joined(ann->device_short_addr, &evt[2]);
            hub_discover_caps(ann->device_short_addr);
        }
        break;
    }
    case ESP_ZB_NWK_SIGNAL_DEVICE_ASSOCIATED: {
        esp_zb_nwk_signal_device_associated_params_t *a =
            (esp_zb_nwk_signal_device_associated_params_t *)esp_zb_app_signal_get_params(p_sg_p);
        if (a) {
            ESP_LOGI(TAG, "NWK associated ieee=%02x:%02x:%02x:%02x:%02x:%02x:%02x:%02x",
                     a->device_addr[7], a->device_addr[6], a->device_addr[5], a->device_addr[4],
                     a->device_addr[3], a->device_addr[2], a->device_addr[1], a->device_addr[0]);
        }
        break;
    }
    case ESP_ZB_ZDO_SIGNAL_DEVICE_UPDATE: {
        esp_zb_zdo_signal_device_update_params_t *u =
            (esp_zb_zdo_signal_device_update_params_t *)esp_zb_app_signal_get_params(p_sg_p);
        if (u) {
            ESP_LOGI(TAG, "Device update short=0x%04x status=%u tc_action=%u",
                     u->short_addr, (unsigned)u->status, (unsigned)u->tc_action);
        }
        break;
    }
    case ESP_ZB_ZDO_SIGNAL_DEVICE_AUTHORIZED: {
        esp_zb_zdo_signal_device_authorized_params_t *auth =
            (esp_zb_zdo_signal_device_authorized_params_t *)esp_zb_app_signal_get_params(p_sg_p);
        if (auth) {
            ESP_LOGI(TAG, "Device auth short=0x%04x type=%u status=%u",
                     auth->short_addr, (unsigned)auth->authorization_type,
                     (unsigned)auth->authorization_status);
        }
        break;
    }
    case ESP_ZB_ZDO_SIGNAL_LEAVE_INDICATION: {
        esp_zb_zdo_signal_leave_indication_params_t *lv =
            (esp_zb_zdo_signal_leave_indication_params_t *)esp_zb_app_signal_get_params(p_sg_p);
        if (lv) {
            uint8_t evt[8];
            ieee_msb(lv->device_addr, evt);
            dev_remove_ieee(evt);
            send_evt(ZIGBEE_EVT_DEV_LEFT, evt, sizeof(evt));
        }
        break;
    }
    case ESP_ZB_NWK_SIGNAL_PERMIT_JOIN_STATUS: {
        uint8_t *dur = (uint8_t *)esp_zb_app_signal_get_params(p_sg_p);
        s_permit_s = dur ? *dur : 0;
        if (s_permit_s == 0) {
            s_user_permit = false;
        }
        if (s_permit_s > 0 && !s_user_permit) {
            ESP_LOGW(TAG, "Closing unrequested permit-join window (%us)",
                     (unsigned)s_permit_s);
            esp_zb_bdb_open_network(0);
            break;
        }
        ESP_LOGI(TAG, "Permit join: %us", (unsigned)s_permit_s);
        hub_send_state();
        break;
    }
    default:
        ESP_LOGD(TAG, "ZB signal 0x%x status %d", (unsigned)sig, err);
        break;
    }
}

/* ── Attribute / IAS notifications -> host ──────────────────────────────── */

static void emit_dev_state(uint16_t short_addr, uint16_t cluster, uint16_t val)
{
    uint8_t evt[6];
    evt[0] = (uint8_t)(short_addr >> 8);
    evt[1] = (uint8_t)short_addr;
    evt[2] = (uint8_t)(cluster >> 8);
    evt[3] = (uint8_t)cluster;
    evt[4] = (uint8_t)(val >> 8);
    evt[5] = (uint8_t)val;
    send_evt(ZIGBEE_EVT_DEV_STATE, evt, sizeof(evt));
}

static esp_err_t hub_action_handler(esp_zb_core_action_callback_id_t callback_id,
                                    const void *message)
{
    if (!message) {
        return ESP_OK;
    }
    if (callback_id == ESP_ZB_CORE_CMD_IAS_ZONE_ZONE_STATUS_CHANGE_NOT_ID) {
        const esp_zb_zcl_ias_zone_status_change_notification_message_t *zn = message;
        if (zn->info.src_address.addr_type == ESP_ZB_ZCL_ADDR_TYPE_SHORT) {
            emit_dev_state(zn->info.src_address.u.short_addr, 0x0500, zn->zone_status);
        }
        return ESP_OK;
    }
    if (callback_id == ESP_ZB_CORE_CMD_READ_ATTR_RESP_CB_ID) {
        const esp_zb_zcl_cmd_read_attr_resp_message_t *rr = message;
        if (rr->info.status != ESP_ZB_ZCL_STATUS_SUCCESS ||
            rr->info.src_address.addr_type != ESP_ZB_ZCL_ADDR_TYPE_SHORT) {
            return ESP_OK;
        }
        const uint16_t cl = rr->info.cluster;
        if (cl == 0x0000) {
            /* Interview response: ZCL char strings [len][bytes], not
             * NUL-terminated. Cap 16 chars each; emit as mfr\0model\0. */
            char mfr[17] = "", model[17] = "";
            for (esp_zb_zcl_read_attr_resp_variable_t *v = rr->variables; v; v = v->next) {
                if (v->status != ESP_ZB_ZCL_STATUS_SUCCESS || !v->attribute.data.value) {
                    continue;
                }
                const uint8_t *s = v->attribute.data.value;
                uint8_t n = s[0];
                if (n > 16) {
                    n = 16;
                }
                if (v->attribute.id == 0x0004) {
                    memcpy(mfr, s + 1, n);
                    mfr[n] = '\0';
                } else if (v->attribute.id == 0x0005) {
                    memcpy(model, s + 1, n);
                    model[n] = '\0';
                }
            }
            if (mfr[0] || model[0]) {
                uint8_t evt[2 + 17 + 17];
                evt[0] = (uint8_t)(rr->info.src_address.u.short_addr >> 8);
                evt[1] = (uint8_t)rr->info.src_address.u.short_addr;
                const size_t ml = strlen(mfr), dl = strlen(model);
                memcpy(&evt[2], mfr, ml + 1);
                memcpy(&evt[2 + ml + 1], model, dl + 1);
                ESP_LOGI(TAG, "Dev 0x%04x is \"%s\" / \"%s\"",
                         rr->info.src_address.u.short_addr, mfr, model);
                send_evt(ZIGBEE_EVT_DEV_INFO, evt, (uint16_t)(2 + ml + 1 + dl + 1));
            }
            return ESP_OK;
        }
        if (cl != 0x0B04 && cl != 0x0702) {
            return ESP_OK;
        }
        for (esp_zb_zcl_read_attr_resp_variable_t *v = rr->variables; v; v = v->next) {
            if (v->status != ESP_ZB_ZCL_STATUS_SUCCESS || !v->attribute.data.value) {
                continue;
            }
            uint32_t val = 0;
            const uint8_t sz = v->attribute.data.size;
            const uint8_t *pv = v->attribute.data.value;
            for (uint8_t i = 0; i < sz && i < 4; i++) {
                val |= (uint32_t)pv[i] << (8 * i);
            }
            uint8_t evt[10];
            evt[0] = (uint8_t)(rr->info.src_address.u.short_addr >> 8);
            evt[1] = (uint8_t)rr->info.src_address.u.short_addr;
            evt[2] = (uint8_t)(cl >> 8);
            evt[3] = (uint8_t)cl;
            evt[4] = (uint8_t)(v->attribute.id >> 8);
            evt[5] = (uint8_t)v->attribute.id;
            evt[6] = (uint8_t)(val >> 24);
            evt[7] = (uint8_t)(val >> 16);
            evt[8] = (uint8_t)(val >> 8);
            evt[9] = (uint8_t)val;
            send_evt(ZIGBEE_EVT_DEV_SENSOR, evt, sizeof(evt));
        }
        return ESP_OK;
    }
    if (callback_id != ESP_ZB_CORE_REPORT_ATTR_CB_ID) {
        return ESP_OK;
    }
    const esp_zb_zcl_report_attr_message_t *msg = message;
    if (msg->status != ESP_ZB_ZCL_STATUS_SUCCESS ||
        msg->src_address.addr_type != ESP_ZB_ZCL_ADDR_TYPE_SHORT ||
        !msg->attribute.data.value) {
        return ESP_OK;
    }
    const uint16_t short_addr = msg->src_address.u.short_addr;
    const uint16_t cl = msg->cluster;
    const uint16_t attr = msg->attribute.id;
    uint16_t val = 0;

    if (cl == 0x0006 && attr == 0x0000) {
        val = *(const uint8_t *)msg->attribute.data.value;
        emit_dev_state(short_addr, cl, val);
    } else if (cl == 0x0008 && attr == 0x0000) {
        val = *(const uint8_t *)msg->attribute.data.value;
        emit_dev_state(short_addr, cl, val);
    } else if (cl == 0x0102 && attr == 0x0008) {
        val = *(const uint8_t *)msg->attribute.data.value;
        emit_dev_state(short_addr, cl, val);
    } else if (cl == 0x0201 && (attr == 0x0000 || attr == 0x0012)) {
        /* s16 little-endian */
        if (msg->attribute.data.size >= 2) {
            const uint8_t *p = msg->attribute.data.value;
            val = (uint16_t)p[0] | ((uint16_t)p[1] << 8);
        }
        emit_dev_state(short_addr, cl, val);
    } else if (cl == 0x0500 && attr == 0x0002) {
        if (msg->attribute.data.size >= 2) {
            const uint8_t *p = msg->attribute.data.value;
            val = (uint16_t)p[0] | ((uint16_t)p[1] << 8);
        }
        emit_dev_state(short_addr, cl, val);
    } else if (cl == 0x0B04 && attr == 0x050B) {
        /* ActivePower s16 — also as DEV_SENSOR for P4 meter cache */
        int16_t pwr = 0;
        if (msg->attribute.data.size >= 2) {
            const uint8_t *p = msg->attribute.data.value;
            pwr = (int16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
        }
        uint8_t evt[10];
        evt[0] = (uint8_t)(short_addr >> 8);
        evt[1] = (uint8_t)short_addr;
        evt[2] = 0x0B;
        evt[3] = 0x04;
        evt[4] = 0x05;
        evt[5] = 0x0B;
        const uint32_t u = (uint16_t)pwr;
        evt[6] = 0;
        evt[7] = 0;
        evt[8] = (uint8_t)(u >> 8);
        evt[9] = (uint8_t)u;
        send_evt(ZIGBEE_EVT_DEV_SENSOR, evt, sizeof(evt));
    }
    return ESP_OK;
}

static void hub_zb_task(void *arg)
{
    (void)arg;
    ESP_LOGI(TAG, "zb task: platform config (native H2 radio, no coex)");
    esp_zb_platform_config_t pcfg = {
        .radio_config = {.radio_mode = ZB_RADIO_MODE_NATIVE},
        .host_config = {.host_connection_mode = ZB_HOST_CONNECTION_MODE_NONE},
    };
    esp_err_t err = esp_zb_platform_config(&pcfg);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "esp_zb_platform_config: 0x%x (%s)", err, esp_err_to_name(err));
        const uint8_t e[2] = {0x1A, (uint8_t)err};
        send_evt(ZIGBEE_EVT_FAIL, e, sizeof(e));
        s_task_up = false;
        vTaskDelete(NULL);
        return;
    }

    ESP_LOGI(TAG, "zb task: esp_zb_init (ZC, max_children=%d, IC policy off)",
             HUB_MAX_CHILDREN);
    esp_zb_cfg_t zc_cfg = {
        .esp_zb_role = ESP_ZB_DEVICE_TYPE_COORDINATOR,
        /* MUST be false: install-code-ONLY policy silently rejects the join
         * handshake of every device without a pre-provisioned code — which is
         * virtually all consumer Zigbee gear (they join with the well-known
         * HA key). Symptom was "permit join open, device in pair mode,
         * nothing joins". Devices WITH codes still get per-device keys via
         * CMD_IC_ADD before pairing; this flag only stops being a hard gate. */
        .install_code_policy = false,
        .nwk_cfg = {.zczr_cfg = {.max_children = HUB_MAX_CHILDREN}},
    };
    esp_zb_init(&zc_cfg);
    (void)esp_zb_nwk_set_max_children(HUB_MAX_CHILDREN);

    if (s_req_channel >= 11 && s_req_channel <= 26) {
        esp_zb_set_primary_network_channel_set(1u << s_req_channel);
    } else {
        esp_zb_set_primary_network_channel_set(ESP_ZB_TRANSCEIVER_ALL_CHANNELS_MASK);
    }

    esp_zb_on_off_switch_cfg_t sw_cfg = ESP_ZB_DEFAULT_ON_OFF_SWITCH_CONFIG();
    esp_zb_device_register(esp_zb_on_off_switch_ep_create(HUB_EP, &sw_cfg));
    esp_zb_core_action_handler_register(hub_action_handler);
    /* Max TX power (~+20 dBm on H2): dedicated hub, no coex neighbor to
     * protect — buy the extra range/link margin for free. */
    esp_zb_set_tx_power(20);

    ESP_LOGI(TAG, "zb task: esp_zb_start");
    err = esp_zb_start(false);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "esp_zb_start: 0x%x (%s)", err, esp_err_to_name(err));
        const uint8_t e[2] = {0x1B, (uint8_t)err};
        send_evt(ZIGBEE_EVT_FAIL, e, sizeof(e));
        s_task_up = false;
        vTaskDelete(NULL);
        return;
    }
    ESP_LOGI(TAG, "zb task: entering ZBOSS main loop");
    esp_zb_stack_main_loop();
    ESP_LOGE(TAG, "zb task: main loop EXITED (stack stopped)");
    s_stack_ready = false;
    s_task_up = false;
    vTaskDelete(NULL);
}

void zigbee_hub_start(uint8_t channel)
{
    if (channel >= 11 && channel <= 26) {
        s_req_channel = channel;
        s_channel_forced = true;
    }
    /* channel 0 = keep auto / previously forced */
    if (!s_task_up) {
        if (xTaskCreate(hub_zb_task, "zb_hub", HUB_ZB_TASK_STACK, NULL, 5, NULL) != pdPASS) {
            send_fail(0x11);
            return;
        }
        s_task_up = true;
    }
    send_ok();
    hub_send_state();
}

static void hub_permit_join(uint8_t seconds)
{
    if (!s_task_up || !s_stack_ready || !s_formed) {
        send_fail(0x12);
        return;
    }
    s_user_permit = seconds > 0;
    esp_zb_zdo_permit_joining_req_param_t req = {
        .dst_nwk_addr = 0x0000,
        .permit_duration = seconds,
        .tc_significance = 1,
    };
    esp_zb_lock_acquire(portMAX_DELAY);
    esp_zb_zdo_permit_joining_req(&req, NULL, NULL);
    (void)esp_zb_bdb_open_network(seconds);
    esp_zb_lock_release();
    send_ok();
}

static void hub_onoff(const uint8_t *a, uint16_t n)
{
    if (!s_stack_ready || !s_formed || n < 4) {
        send_fail(0x13);
        return;
    }
    esp_zb_zcl_on_off_cmd_t cmd = {
        .zcl_basic_cmd = {
            .dst_addr_u.addr_short = (uint16_t)(((uint16_t)a[0] << 8) | a[1]),
            .dst_endpoint = a[2],
            .src_endpoint = HUB_EP,
        },
        .address_mode = ESP_ZB_APS_ADDR_MODE_16_ENDP_PRESENT,
        .on_off_cmd_id = (a[3] == 0) ? ESP_ZB_ZCL_CMD_ON_OFF_OFF_ID
                       : (a[3] == 1) ? ESP_ZB_ZCL_CMD_ON_OFF_ON_ID
                                     : ESP_ZB_ZCL_CMD_ON_OFF_TOGGLE_ID,
    };
    esp_zb_lock_acquire(portMAX_DELAY);
    esp_zb_zcl_on_off_cmd_req(&cmd);
    esp_zb_lock_release();
    send_ok();
}

static void hub_level(const uint8_t *a, uint16_t n)
{
    if (!s_stack_ready || !s_formed || n < 6) {
        send_fail(0x14);
        return;
    }
    esp_zb_zcl_move_to_level_cmd_t cmd = {
        .zcl_basic_cmd = {
            .dst_addr_u.addr_short = (uint16_t)(((uint16_t)a[0] << 8) | a[1]),
            .dst_endpoint = a[2],
            .src_endpoint = HUB_EP,
        },
        .address_mode = ESP_ZB_APS_ADDR_MODE_16_ENDP_PRESENT,
        .level = a[3],
        .transition_time = (uint16_t)(((uint16_t)a[4] << 8) | a[5]),
    };
    esp_zb_lock_acquire(portMAX_DELAY);
    esp_zb_zcl_level_move_to_level_with_onoff_cmd_req(&cmd);
    esp_zb_lock_release();
    send_ok();
}

static void hub_cover(const uint8_t *a, uint16_t n)
{
    if (!s_stack_ready || !s_formed || n < 4 || a[3] > 2) {
        send_fail(0x16);
        return;
    }
    esp_zb_zcl_custom_cluster_cmd_req_t cmd = {
        .zcl_basic_cmd = {
            .dst_addr_u.addr_short = (uint16_t)(((uint16_t)a[0] << 8) | a[1]),
            .dst_endpoint = a[2],
            .src_endpoint = HUB_EP,
        },
        .address_mode = ESP_ZB_APS_ADDR_MODE_16_ENDP_PRESENT,
        .profile_id = ESP_ZB_AF_HA_PROFILE_ID,
        .cluster_id = 0x0102,
        .custom_cmd_id = a[3],
        .direction = ESP_ZB_ZCL_CMD_DIRECTION_TO_SRV,
        .data = {.type = ESP_ZB_ZCL_ATTR_TYPE_NULL, .value = NULL},
    };
    esp_zb_lock_acquire(portMAX_DELAY);
    esp_zb_zcl_custom_cluster_cmd_req(&cmd);
    esp_zb_lock_release();
    send_ok();
}

static void hub_thermo_sp(const uint8_t *a, uint16_t n)
{
    if (!s_stack_ready || !s_formed || n < 5) {
        send_fail(0x17);
        return;
    }
    static int16_t s_sp_c100;
    s_sp_c100 = (int16_t)((((uint16_t)a[3] << 8) | a[4]) * 10);
    esp_zb_zcl_attribute_t attr = {
        .id = 0x0012,
        .data = {.type = ESP_ZB_ZCL_ATTR_TYPE_S16,
                 .size = sizeof(s_sp_c100), .value = &s_sp_c100},
    };
    esp_zb_zcl_write_attr_cmd_t cmd = {
        .zcl_basic_cmd = {
            .dst_addr_u.addr_short = (uint16_t)(((uint16_t)a[0] << 8) | a[1]),
            .dst_endpoint = a[2],
            .src_endpoint = HUB_EP,
        },
        .address_mode = ESP_ZB_APS_ADDR_MODE_16_ENDP_PRESENT,
        .clusterID = 0x0201,
        .attr_number = 1,
        .attr_field = &attr,
    };
    esp_zb_lock_acquire(portMAX_DELAY);
    esp_zb_zcl_write_attr_cmd_req(&cmd);
    esp_zb_lock_release();
    send_ok();
}

static void hub_ic_add(const uint8_t *a, uint16_t n)
{
    if (!s_stack_ready || n < 10 || a[8] == 0 || (uint16_t)(9 + a[8]) > n || a[8] > 18) {
        send_fail(0x18);
        return;
    }
    esp_zb_ieee_addr_t ieee;
    for (int i = 0; i < 8; i++) {
        ieee[i] = a[7 - i];
    }
    esp_zb_lock_acquire(portMAX_DELAY);
    const esp_err_t err = esp_zb_secur_ic_add(ieee, ESP_ZB_IC_TYPE_128, (uint8_t *)&a[9]);
    esp_zb_lock_release();
    if (err == ESP_OK) {
        send_ok();
    } else {
        send_fail((uint8_t)err);
    }
}

static void hub_read_sensors(const uint8_t *a, uint16_t n)
{
    if (!s_stack_ready || !s_formed || n < 3) {
        send_fail(0x19);
        return;
    }
    const uint16_t short_addr = (uint16_t)(((uint16_t)a[0] << 8) | a[1]);
    static uint16_t k_em_attrs[] = {0x0505, 0x0508, 0x050B};
    static uint16_t k_mt_attrs[] = {0x0000};
    esp_zb_zcl_read_attr_cmd_t cmd = {
        .zcl_basic_cmd = {
            .dst_addr_u.addr_short = short_addr,
            .dst_endpoint = a[2],
            .src_endpoint = HUB_EP,
        },
        .address_mode = ESP_ZB_APS_ADDR_MODE_16_ENDP_PRESENT,
        .clusterID = 0x0B04,
        .attr_number = 3,
        .attr_field = k_em_attrs,
    };
    esp_zb_lock_acquire(portMAX_DELAY);
    esp_zb_zcl_read_attr_cmd_req(&cmd);
    cmd.clusterID = 0x0702;
    cmd.attr_number = 1;
    cmd.attr_field = k_mt_attrs;
    esp_zb_zcl_read_attr_cmd_req(&cmd);
    esp_zb_lock_release();
    send_ok();
}

static void hub_identify(const uint8_t *a, uint16_t n)
{
    if (!s_stack_ready || !s_formed || n < 4) {
        send_fail(0x1E);
        return;
    }
    esp_zb_zcl_identify_cmd_t cmd = {
        .zcl_basic_cmd = {
            .dst_addr_u.addr_short = (uint16_t)(((uint16_t)a[0] << 8) | a[1]),
            .dst_endpoint = a[2],
            .src_endpoint = HUB_EP,
        },
        .address_mode = ESP_ZB_APS_ADDR_MODE_16_ENDP_PRESENT,
        .identify_time = a[3],
    };
    esp_zb_lock_acquire(portMAX_DELAY);
    esp_zb_zcl_identify_cmd_req(&cmd);
    esp_zb_lock_release();
    send_ok();
}

/* Groups (0x0004): put a device endpoint in / out of a group. One group cast
 * then replaces N unicasts for scene-style control ("all lights off"). */
static void hub_group_set(const uint8_t *a, uint16_t n)
{
    if (!s_stack_ready || !s_formed || n < 6) {
        send_fail(0x1F);
        return;
    }
    esp_zb_zcl_groups_add_group_cmd_t cmd = {
        .zcl_basic_cmd = {
            .dst_addr_u.addr_short = (uint16_t)(((uint16_t)a[0] << 8) | a[1]),
            .dst_endpoint = a[2],
            .src_endpoint = HUB_EP,
        },
        .address_mode = ESP_ZB_APS_ADDR_MODE_16_ENDP_PRESENT,
        .group_id = (uint16_t)(((uint16_t)a[3] << 8) | a[4]),
    };
    esp_zb_lock_acquire(portMAX_DELAY);
    if (a[5]) {
        esp_zb_zcl_groups_add_group_cmd_req(&cmd);
    } else {
        esp_zb_zcl_groups_remove_group_cmd_req(&cmd);
    }
    esp_zb_lock_release();
    send_ok();
}

/* Group-addressed On/Off: one broadcast to the whole group. */
static void hub_group_onoff(const uint8_t *a, uint16_t n)
{
    if (!s_stack_ready || !s_formed || n < 3 || a[2] > 2) {
        send_fail(0x20);
        return;
    }
    esp_zb_zcl_on_off_cmd_t cmd = {
        .zcl_basic_cmd = {
            .dst_addr_u.addr_short = (uint16_t)(((uint16_t)a[0] << 8) | a[1]),
            .src_endpoint = HUB_EP,
        },
        .address_mode = ESP_ZB_APS_ADDR_MODE_16_GROUP_ENDP_NOT_PRESENT,
        .on_off_cmd_id = (a[2] == 0) ? ESP_ZB_ZCL_CMD_ON_OFF_OFF_ID
                       : (a[2] == 1) ? ESP_ZB_ZCL_CMD_ON_OFF_ON_ID
                                     : ESP_ZB_ZCL_CMD_ON_OFF_TOGGLE_ID,
    };
    esp_zb_lock_acquire(portMAX_DELAY);
    esp_zb_zcl_on_off_cmd_req(&cmd);
    esp_zb_lock_release();
    send_ok();
}

/* Color Control (0x0300). mode 0: move-to-color-temperature (a=mireds,
 * b=transition ds). mode 1: move-to-hue-and-saturation (a=hue, b=sat). */
static void hub_color(const uint8_t *a, uint16_t n)
{
    if (!s_stack_ready || !s_formed || n < 8) {
        send_fail(0x21);
        return;
    }
    const uint16_t short_addr = (uint16_t)(((uint16_t)a[0] << 8) | a[1]);
    const uint8_t ep = a[2];
    const uint16_t va = (uint16_t)(((uint16_t)a[4] << 8) | a[5]);
    const uint16_t vb = (uint16_t)(((uint16_t)a[6] << 8) | a[7]);

    esp_zb_lock_acquire(portMAX_DELAY);
    if (a[3] == 0) {
        esp_zb_zcl_color_move_to_color_temperature_cmd_t cmd = {
            .zcl_basic_cmd = {
                .dst_addr_u.addr_short = short_addr,
                .dst_endpoint = ep,
                .src_endpoint = HUB_EP,
            },
            .address_mode = ESP_ZB_APS_ADDR_MODE_16_ENDP_PRESENT,
            .color_temperature = va,
            .transition_time = vb,
        };
        esp_zb_zcl_color_move_to_color_temperature_cmd_req(&cmd);
    } else {
        esp_zb_color_move_to_hue_saturation_cmd_t cmd = {
            .zcl_basic_cmd = {
                .dst_addr_u.addr_short = short_addr,
                .dst_endpoint = ep,
                .src_endpoint = HUB_EP,
            },
            .address_mode = ESP_ZB_APS_ADDR_MODE_16_ENDP_PRESENT,
            .hue = (uint8_t)(va > 254 ? 254 : va),
            .saturation = (uint8_t)(vb > 254 ? 254 : vb),
            .transition_time = 1,
        };
        esp_zb_zcl_color_move_to_hue_and_saturation_cmd_req(&cmd);
    }
    esp_zb_lock_release();
    send_ok();
}

void zigbee_hub_process_cmd(const uint8_t *payload, uint16_t len)
{
    if (!payload || len < 2) {
        return;
    }
    /* Sequenced host cmds: [seq:1][cmd:1][args...] */
    s_reply_seq = payload[0];
    if (s_reply_seq == 0) {
        return;
    }
    const uint8_t cmd = payload[1];
    const uint8_t *args = payload + 2;
    const uint16_t args_len = len - 2;

    switch (cmd) {
    case ZIGBEE_CMD_HUB_START:
    case ZIGBEE_CMD_ENABLE:
        zigbee_hub_start(args_len >= 1 ? args[0] : 0);
        break;
    case ZIGBEE_CMD_PERMIT_JOIN:
        hub_permit_join(args_len >= 1 ? args[0] : 60);
        break;
    case ZIGBEE_CMD_ONOFF:
        hub_onoff(args, args_len);
        break;
    case ZIGBEE_CMD_LEVEL:
        hub_level(args, args_len);
        break;
    case ZIGBEE_CMD_COVER:
        hub_cover(args, args_len);
        break;
    case ZIGBEE_CMD_THERMO_SP:
        hub_thermo_sp(args, args_len);
        break;
    case ZIGBEE_CMD_IC_ADD:
        hub_ic_add(args, args_len);
        break;
    case ZIGBEE_CMD_READ_SENSORS:
        hub_read_sensors(args, args_len);
        break;
    case ZIGBEE_CMD_IDENTIFY:
        hub_identify(args, args_len);
        break;
    case ZIGBEE_CMD_DEV_LEAVE:
        hub_dev_leave(args, args_len);
        break;
    case ZIGBEE_CMD_GET_DEVICES:
        hub_dump_devices();
        break;
    case ZIGBEE_CMD_GET_NEIGHBORS:
        hub_dump_neighbors();
        break;
    case ZIGBEE_CMD_REFRESH_LQI:
        hub_refresh_lqi();
        break;
    case ZIGBEE_CMD_ENERGY_SCAN:
        hub_energy_scan(false);
        if (s_stack_ready) {
            send_ok(); /* accept; ENERGY_CH/DONE follow async */
        }
        break;
    case ZIGBEE_CMD_GROUP_SET:
        hub_group_set(args, args_len);
        break;
    case ZIGBEE_CMD_GROUP_ONOFF:
        hub_group_onoff(args, args_len);
        break;
    case ZIGBEE_CMD_COLOR:
        hub_color(args, args_len);
        break;
    case ZIGBEE_CMD_DISABLE:
        hub_permit_join(0);
        break;
    case ZIGBEE_CMD_GET_STATE:
        hub_send_state();
        send_ok();
        break;
    default:
        send_ok();
        break;
    }
    s_reply_seq = 0;
}

void zigbee_hub_poll(void)
{
    static uint8_t ticks;
    if (!s_formed) {
        ticks = 0;
        return;
    }
    if (++ticks < HUB_HEARTBEAT_TICKS) {
        return;
    }
    ticks = 0;
    hub_send_state();
}
