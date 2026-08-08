/*
 * Zigbee / Thread RPC from P4 wireless_shim.
 * Zigbee: framed UART link to the NanoH2 hub (dedicated 802.15.4 radio).
 * Thread: SDIO to the C6 (unchanged).
 */
#include "wireless_rpc.h"
#include "wireless_shim.h"
#include "wireless_shim_802154.h"

#include "c6_sdio_host.h"
#include "c6_thread_proto.h"
#include "zb_link_proto.h"
#include "zb_devdb.h"
#include "zb_uart_host.h"

#include "esp_hosted_interface.h"
#include "esp_log.h"

#include <stdio.h>
#include <string.h>

static const char *TAG = "wl_rpc";

static bool s_zb_joined;
static bool s_zb_hub_fw; /* true once any EVT_HUB_STATE arrives */
static uint8_t s_zb_ch;
static uint16_t s_zb_pan;
static uint8_t s_zb_permit_s;

static bool s_th_attached;
static uint8_t s_th_role;
static uint8_t s_th_ch;
static uint16_t s_th_pan;

/* Interview cache: mfr/model per short addr (RAM only; refreshed on every
 * join interview). Model string is the zigbee2mqtt DB key. */
typedef struct {
    uint16_t short_addr;
    char mfr[17];
    char model[17];
} zb_dev_info_t;
static zb_dev_info_t s_zb_info[16];

static void zb_info_upsert(uint16_t short_addr, const char *mfr, const char *model)
{
    int free_i = -1;
    for (int i = 0; i < (int)(sizeof(s_zb_info) / sizeof(s_zb_info[0])); i++) {
        if (s_zb_info[i].short_addr == short_addr) {
            free_i = i;
            break;
        }
        if (free_i < 0 && s_zb_info[i].short_addr == 0) {
            free_i = i;
        }
    }
    if (free_i < 0) {
        free_i = 0; /* full: overwrite oldest slot deterministically */
    }
    s_zb_info[free_i].short_addr = short_addr;
    strlcpy(s_zb_info[free_i].mfr, mfr, sizeof(s_zb_info[free_i].mfr));
    strlcpy(s_zb_info[free_i].model, model, sizeof(s_zb_info[free_i].model));
}

bool modulus_wireless_zb_dev_info(uint16_t short_addr,
                                         const char **mfr, const char **model)
{
    for (int i = 0; i < (int)(sizeof(s_zb_info) / sizeof(s_zb_info[0])); i++) {
        if (s_zb_info[i].short_addr == short_addr && short_addr != 0) {
            if (mfr) {
                *mfr = s_zb_info[i].mfr;
            }
            if (model) {
                *model = s_zb_info[i].model;
            }
            return true;
        }
    }
    return false;
}

void modulus_wireless_zb_seed_dev_info(uint16_t short_addr, const char *model)
{
    if (short_addr == 0 || !model || !model[0]) {
        return;
    }
    zb_info_upsert(short_addr, "", model);
}

static void zigbee_rx(const uint8_t *payload, uint16_t len, void *ctx)
{
    (void)ctx;
    if (!payload || len < 1) {
        return;
    }
    const uint8_t evt = payload[0];
    const uint8_t *args = payload + 1;
    const uint16_t args_len = len - 1;

    switch (evt) {
    case ZIGBEE_EVT_ACK:
        if (args_len >= 1) {
            modulus_zb_uart_note_ack(args[0], false, 0);
        }
        break;
    case ZIGBEE_EVT_NAK:
        if (args_len >= 1) {
            modulus_zb_uart_note_ack(args[0], true, args_len >= 2 ? args[1] : 0);
        }
        break;
    case ZIGBEE_EVT_OK:
        ESP_LOGI(TAG, "Zigbee cmd OK");
        break;
    case ZIGBEE_EVT_STATE:
        if (args_len >= 6) {
            s_zb_ch = args[0];
            s_zb_pan = ((uint16_t)args[1] << 8) | args[2];
            s_zb_joined = args[5] != 0;
        }
        break;
    case ZIGBEE_EVT_HUB_STATE:
        if (args_len >= 5) {
            s_zb_hub_fw = true;
            const bool changed = (s_zb_joined != (args[0] != 0)) || (s_zb_ch != args[1]) ||
                                 (s_zb_pan != ((uint16_t)(((uint16_t)args[2] << 8) | args[3]))) ||
                                 (s_zb_permit_s != args[4]);
            s_zb_joined = args[0] != 0;
            s_zb_ch = args[1];
            s_zb_pan = ((uint16_t)args[2] << 8) | args[3];
            s_zb_permit_s = args[4];
            if (changed) { /* the periodic GET_STATE poll otherwise floods the log */
                ESP_LOGI(TAG, "Zigbee hub formed=%u ch=%u pan=0x%04x permit=%us",
                         (unsigned)args[0], (unsigned)s_zb_ch, (unsigned)s_zb_pan,
                         (unsigned)s_zb_permit_s);
            }
            /* No coex refresh: Zigbee lives on the NanoH2's own radio now;
             * the C6 Wi-Fi channel never moves for it. */
        }
        break;
    case ZIGBEE_EVT_DEV_JOINED:
        if (args_len >= 10) {
            const uint16_t short_addr = ((uint16_t)args[0] << 8) | args[1];
            modulus_wireless_zb_note_device_joined(short_addr, args + 2);
        }
        break;
    case ZIGBEE_EVT_DEV_LEFT:
        if (args_len >= 8) {
            modulus_wireless_zb_note_device_left(args);
        }
        break;
    case ZIGBEE_EVT_DEV_CAPS:
        if (args_len >= 6) {
            const uint16_t short_addr = ((uint16_t)args[0] << 8) | args[1];
            modulus_wireless_zb_note_device_caps(short_addr, args[2], args[3],
                                                        ((uint16_t)args[4] << 8) | args[5]);
        }
        break;
    case ZIGBEE_EVT_DEV_SENSOR:
        if (args_len >= 10) {
            modulus_wireless_zb_note_device_sensor(
                ((uint16_t)args[0] << 8) | args[1], ((uint16_t)args[2] << 8) | args[3],
                ((uint16_t)args[4] << 8) | args[5],
                ((uint32_t)args[6] << 24) | ((uint32_t)args[7] << 16) |
                    ((uint32_t)args[8] << 8) | args[9]);
        }
        break;
    case ZIGBEE_EVT_DEV_STATE:
        if (args_len >= 6) {
            modulus_wireless_zb_note_device_state(
                ((uint16_t)args[0] << 8) | args[1], ((uint16_t)args[2] << 8) | args[3],
                ((uint16_t)args[4] << 8) | args[5]);
        }
        break;
    case ZIGBEE_EVT_DEV_LQI:
        /* [short:2BE][lqi][rssi:s8][age] — neighbor-table telemetry */
        if (args_len >= 4) {
            modulus_wireless_zb_note_device_lqi(
                ((uint16_t)args[0] << 8) | args[1], args[2], (int8_t)args[3]);
        }
        break;
    case ZIGBEE_EVT_ENERGY_CH:
        if (args_len >= 2) {
            modulus_wireless_zb_note_energy_ch(args[0], (int8_t)args[1]);
        }
        break;
    case ZIGBEE_EVT_ENERGY_DONE:
        if (args_len >= 2) {
            modulus_wireless_zb_note_energy_done(args[0], (int8_t)args[1]);
        }
        break;
    case ZIGBEE_EVT_DEV_INFO:
        /* [short:2BE][mfr\0model\0] — strings NUL-terminated by the hub;
         * bound the scan to args_len so a truncated frame can't overrun. */
        if (args_len >= 4) {
            const uint16_t short_addr = ((uint16_t)args[0] << 8) | args[1];
            const char *mfr = (const char *)&args[2];
            size_t ml = strnlen(mfr, args_len - 2);
            if (2 + ml + 1 < args_len) {
                const char *model = (const char *)&args[2 + ml + 1];
                const size_t dmax = args_len - 2 - ml - 1;
                if (strnlen(model, dmax) < dmax) { /* model NUL present */
                    zb_info_upsert(short_addr, mfr, model);
                    const zb_devdb_entry_t *e = zb_devdb_find(model);
                    if (e) {
                        ESP_LOGI(TAG, "Zigbee 0x%04x: %s %s (%s)", short_addr,
                                 e->vendor, e->model, e->description);
                    } else {
                        ESP_LOGI(TAG, "Zigbee 0x%04x: \"%s\" / \"%s\" (not in devdb)",
                                 short_addr, mfr, model);
                    }
                    modulus_wireless_zb_note_device_info(short_addr, mfr, model, e);
                }
            }
        }
        break;
    case ZIGBEE_EVT_FAIL:
        /* Reason map (zigbee_handler.c): 10 init-signal 11 task-create
         * 12 not-ready 13 onoff 14 level 15 raw-op-refused 16 cover
         * 17 thermo 18 install-code 1A platform-config(+err) 1B start(+err) */
        if (args_len >= 2) {
            ESP_LOGW(TAG, "Zigbee evt FAIL reason=0x%02x err=0x%02x", args[0], args[1]);
        } else if (args_len >= 1) {
            ESP_LOGW(TAG, "Zigbee evt FAIL reason=0x%02x", args[0]);
        } else {
            ESP_LOGW(TAG, "Zigbee evt FAIL (no reason)");
        }
        break;
    default:
        ESP_LOGD(TAG, "Zigbee evt 0x%02x", evt);
        break;
    }
}

static void thread_rx(const uint8_t *payload, uint16_t len, void *ctx)
{
    (void)ctx;
    if (!payload || len < 1) {
        return;
    }
    const uint8_t evt = payload[0];
    const uint8_t *args = payload + 1;
    const uint16_t args_len = len - 1;

    switch (evt) {
    case THREAD_EVT_OK:
        ESP_LOGI(TAG, "Thread cmd OK");
        break;
    case THREAD_EVT_FAIL:
        s_th_attached = false;
        ESP_LOGW(TAG, "Thread evt FAIL");
        break;
    case THREAD_EVT_STATE:
        if (args_len >= 4) {
            s_th_role = args[0];
            s_th_ch = args[1];
            s_th_pan = ((uint16_t)args[2] << 8) | args[3];
            s_th_attached = s_th_role >= 2;
            ESP_LOGI(TAG, "Thread role=%u ch=%u pan=0x%04x",
                     (unsigned)s_th_role, (unsigned)s_th_ch, (unsigned)s_th_pan);
        }
        break;
    case THREAD_EVT_DEVICE_JOIN:
        if (args_len >= 8) {
            modulus_wireless_th_note_device_join(args);
        }
        break;
    case THREAD_EVT_DEVICE_LEAVE:
        if (args_len >= 8) {
            modulus_wireless_th_note_device_leave(args);
        }
        break;
    default:
        ESP_LOGD(TAG, "Thread evt 0x%02x", evt);
        break;
    }
}

void modulus_wireless_rpc_init(void)
{
    modulus_c6_sdio_host_init();
    modulus_zb_uart_init(zigbee_rx, NULL); /* Zigbee -> NanoH2 UART link */
    modulus_c6_sdio_register_rx(ESP_THREAD_IF, thread_rx, NULL);
}

bool modulus_wireless_zb_link_up(void)
{
    return modulus_zb_uart_ready();
}

bool modulus_wireless_zb_hub_offline(void)
{
    return modulus_zb_uart_hub_offline();
}

bool modulus_wireless_zb_join(void)
{
    /* HUB_START forms/reopens the ZBOSS network (hub picks the channel). */
    uint8_t cmd[] = {ZIGBEE_CMD_HUB_START, 0};
    if (!modulus_zb_uart_send_cmd(cmd, sizeof(cmd))) {
        return false;
    }
    uint8_t st[] = {ZIGBEE_CMD_GET_STATE};
    (void)modulus_zb_uart_send_cmd(st, sizeof(st));
    return true;
}

bool modulus_wireless_zb_permit_join(uint8_t seconds)
{
    uint8_t cmd[] = {ZIGBEE_CMD_PERMIT_JOIN, seconds};
    return modulus_zb_uart_send_cmd(cmd, sizeof(cmd));
}

uint8_t modulus_wireless_zb_permit_remaining(void)
{
    return s_zb_permit_s;
}

bool modulus_wireless_zb_hub_fw(void)
{
    return s_zb_hub_fw;
}

bool modulus_wireless_zb_leave(void)
{
    uint8_t cmd[] = {ZIGBEE_CMD_DISABLE};
    if (!modulus_zb_uart_send_cmd(cmd, sizeof(cmd))) {
        return false;
    }
    s_zb_joined = false;
    return true;
}

bool modulus_wireless_th_attach(void)
{
    uint8_t cmd[] = {THREAD_CMD_ENABLE};
    if (!modulus_c6_sdio_send(ESP_THREAD_IF, cmd, sizeof(cmd))) {
        return false;
    }
    uint8_t st[] = {THREAD_CMD_GET_STATE};
    (void)modulus_c6_sdio_send(ESP_THREAD_IF, st, sizeof(st));
    return true;
}

bool modulus_wireless_th_detach(void)
{
    uint8_t cmd[] = {THREAD_CMD_DISABLE};
    if (!modulus_c6_sdio_send(ESP_THREAD_IF, cmd, sizeof(cmd))) {
        return false;
    }
    s_th_attached = false;
    s_th_role = 0;
    return true;
}

bool modulus_wireless_th_refresh_devices(void)
{
    uint8_t st[] = {THREAD_CMD_GET_STATE};
    return modulus_c6_sdio_send(ESP_THREAD_IF, st, sizeof(st));
}

bool modulus_wireless_zb_set_onoff(const modulus_zb_device_t *dev, bool on)
{
    if (!dev || !dev->id[0]) {
        return false;
    }
    if (dev->short_addr == 0) {
        /* No NWK address learned yet — device must (re)join while the hub is
         * up so the announce populates it. Cache-only until then. */
        ESP_LOGW(TAG, "Zigbee ON/OFF: %s has no short addr (re-pair via permit join)", dev->id);
        return false;
    }
    uint8_t cmd[5];
    cmd[0] = ZIGBEE_CMD_ONOFF;
    cmd[1] = (dev->short_addr >> 8) & 0xFF;
    cmd[2] = dev->short_addr & 0xFF;
    cmd[3] = dev->endpoint ? dev->endpoint : 1;
    cmd[4] = on ? 1 : 0;
    if (!modulus_zb_uart_send_cmd(cmd, sizeof(cmd))) {
        return false;
    }
    ESP_LOGI(TAG, "Zigbee ZCL On/Off -> 0x%04x ep%u %s", dev->short_addr,
             (unsigned)cmd[3], on ? "ON" : "OFF");
    return true;
}

bool modulus_wireless_zb_set_level(const modulus_zb_device_t *dev, uint8_t level)
{
    if (!dev || !dev->id[0] || dev->short_addr == 0) {
        return false;
    }
    uint8_t cmd[8];
    cmd[0] = ZIGBEE_CMD_LEVEL;
    cmd[1] = (dev->short_addr >> 8) & 0xFF;
    cmd[2] = dev->short_addr & 0xFF;
    cmd[3] = dev->endpoint ? dev->endpoint : 1;
    cmd[4] = level > 254 ? 254 : level;
    cmd[5] = 0;   /* transition_time = 5 deciseconds (0.5 s fade) */
    cmd[6] = 5;
    if (!modulus_zb_uart_send_cmd(cmd, 7)) {
        return false;
    }
    ESP_LOGI(TAG, "Zigbee ZCL Level -> 0x%04x ep%u %u", dev->short_addr,
             (unsigned)cmd[3], (unsigned)cmd[4]);
    return true;
}

bool modulus_wireless_zb_cover(const modulus_zb_device_t *dev, uint8_t op)
{
    if (!dev || dev->short_addr == 0 || op > 2) {
        return false;
    }
    uint8_t cmd[5];
    cmd[0] = ZIGBEE_CMD_COVER;
    cmd[1] = (dev->short_addr >> 8) & 0xFF;
    cmd[2] = dev->short_addr & 0xFF;
    cmd[3] = dev->endpoint ? dev->endpoint : 1;
    cmd[4] = op;
    return modulus_zb_uart_send_cmd(cmd, sizeof(cmd));
}

bool modulus_wireless_zb_thermo_sp(const modulus_zb_device_t *dev, uint16_t sp_c_x10)
{
    if (!dev || dev->short_addr == 0) {
        return false;
    }
    uint8_t cmd[6];
    cmd[0] = ZIGBEE_CMD_THERMO_SP;
    cmd[1] = (dev->short_addr >> 8) & 0xFF;
    cmd[2] = dev->short_addr & 0xFF;
    cmd[3] = dev->endpoint ? dev->endpoint : 1;
    cmd[4] = (sp_c_x10 >> 8) & 0xFF;
    cmd[5] = sp_c_x10 & 0xFF;
    return modulus_zb_uart_send_cmd(cmd, sizeof(cmd));
}

static int hex_nib(char c)
{
    if (c >= '0' && c <= '9') {
        return c - '0';
    }
    if (c >= 'A' && c <= 'F') {
        return c - 'A' + 10;
    }
    if (c >= 'a' && c <= 'f') {
        return c - 'a' + 10;
    }
    return -1;
}

static int hex_to_bytes(const char *s, uint8_t *out, int max)
{
    int n = 0;
    while (s[0] && s[1] && n < max) {
        const int hi = hex_nib(s[0]);
        const int lo = hex_nib(s[1]);
        if (hi < 0 || lo < 0) {
            return -1;
        }
        out[n++] = (uint8_t)((hi << 4) | lo);
        s += 2;
    }
    return s[0] ? -1 : n; /* odd length or overflow -> reject */
}

bool modulus_wireless_zb_ic_add(const char *ieee_hex, const char *code_hex)
{
    if (!ieee_hex || !code_hex) {
        return false;
    }
    uint8_t cmd[1 + 8 + 1 + 18];
    cmd[0] = ZIGBEE_CMD_IC_ADD;
    if (hex_to_bytes(ieee_hex, &cmd[1], 8) != 8) {
        return false;
    }
    const int code_n = hex_to_bytes(code_hex, &cmd[10], 18);
    if (code_n != 18) { /* 128-bit code + CRC16 = 18 bytes (36 hex chars) */
        ESP_LOGW(TAG, "Install code must be 36 hex chars incl. CRC (got %d bytes)", code_n);
        return false;
    }
    cmd[9] = (uint8_t)code_n;
    return modulus_zb_uart_send_cmd(cmd, (uint16_t)(10 + code_n));
}

bool modulus_wireless_zb_read_sensors(const modulus_zb_device_t *dev)
{
    if (!dev || dev->short_addr == 0) {
        return false;
    }
    uint8_t cmd[4] = {ZIGBEE_CMD_READ_SENSORS, (uint8_t)(dev->short_addr >> 8),
                      (uint8_t)dev->short_addr, dev->endpoint ? dev->endpoint : 1};
    return modulus_zb_uart_send_cmd(cmd, sizeof(cmd));
}

bool modulus_wireless_zb_identify(const modulus_zb_device_t *dev, uint8_t seconds)
{
    if (!dev || dev->short_addr == 0) {
        return false;
    }
    uint8_t cmd[5] = {ZIGBEE_CMD_IDENTIFY, (uint8_t)(dev->short_addr >> 8),
                      (uint8_t)dev->short_addr, dev->endpoint ? dev->endpoint : 1, seconds};
    return modulus_zb_uart_send_cmd(cmd, sizeof(cmd));
}

bool modulus_wireless_zb_group_set(const modulus_zb_device_t *dev,
                                          uint16_t group_id, bool add)
{
    if (!dev || dev->short_addr == 0) {
        return false;
    }
    uint8_t cmd[7] = {ZIGBEE_CMD_GROUP_SET, (uint8_t)(dev->short_addr >> 8),
                      (uint8_t)dev->short_addr, dev->endpoint ? dev->endpoint : 1,
                      (uint8_t)(group_id >> 8), (uint8_t)group_id, add ? 1 : 0};
    return modulus_zb_uart_send_cmd(cmd, sizeof(cmd));
}

bool modulus_wireless_zb_group_onoff(uint16_t group_id, uint8_t op)
{
    if (op > 2) {
        return false;
    }
    uint8_t cmd[4] = {ZIGBEE_CMD_GROUP_ONOFF, (uint8_t)(group_id >> 8),
                      (uint8_t)group_id, op};
    return modulus_zb_uart_send_cmd(cmd, sizeof(cmd));
}

bool modulus_wireless_zb_dev_leave(const char *ieee_hex)
{
    if (!ieee_hex) {
        return false;
    }
    uint8_t cmd[9];
    cmd[0] = ZIGBEE_CMD_DEV_LEAVE;
    if (hex_to_bytes(ieee_hex, &cmd[1], 8) != 8) {
        return false;
    }
    return modulus_zb_uart_send_cmd(cmd, sizeof(cmd));
}

bool modulus_wireless_zb_energy_scan(void)
{
    uint8_t cmd[] = {ZIGBEE_CMD_ENERGY_SCAN};
    return modulus_zb_uart_send_cmd(cmd, sizeof(cmd));
}

/* mode 0: a=color temp (mireds 153-500 typical), b=transition deciseconds.
 * mode 1: a=hue 0-254, b=saturation 0-254. */
bool modulus_wireless_zb_color(const modulus_zb_device_t *dev, uint8_t mode,
                                      uint16_t a, uint16_t b)
{
    if (!dev || dev->short_addr == 0 || mode > 1 || !(dev->caps & ZIGBEE_CAP_COLOR)) {
        return false;
    }
    uint8_t cmd[9] = {ZIGBEE_CMD_COLOR, (uint8_t)(dev->short_addr >> 8),
                      (uint8_t)dev->short_addr, dev->endpoint ? dev->endpoint : 1,
                      mode, (uint8_t)(a >> 8), (uint8_t)a, (uint8_t)(b >> 8), (uint8_t)b};
    return modulus_zb_uart_send_cmd(cmd, sizeof(cmd));
}

void modulus_wireless_rpc_poll_state(bool zigbee_on, bool thread_on)
{
    static uint8_t tick;
    if (++tick < 5) {
        return;
    }
    tick = 0;
    if (zigbee_on) {
        /* Hub pushes HUB_STATE every ~5 s when formed (keeps uart_ready).
         * Rare GET_STATE is only a backup while waiting for first contact. */
        static uint8_t zb_beat;
        static bool offline_logged;
        if (modulus_zb_uart_hub_offline()) {
            if (!offline_logged) {
                offline_logged = true;
                ESP_LOGW(TAG, "Zigbee hub offline - check wiring/power");
            }
        } else {
            offline_logged = false;
        }
        const uint8_t need = modulus_wireless_zb_hub_fw() ? 12 : 1; /* ~60s / ~5s */
        if (++zb_beat >= need) {
            zb_beat = 0;
            uint8_t st[] = {ZIGBEE_CMD_GET_STATE};
            (void)modulus_zb_uart_send_cmd(st, sizeof(st));
            /* Piggyback link-quality telemetry: hub walks its neighbor table
             * and pushes one EVT_DEV_LQI per device (signal bars in the UI). */
            if (s_zb_joined) {
                uint8_t lq[] = {ZIGBEE_CMD_REFRESH_LQI};
                (void)modulus_zb_uart_send_cmd(lq, sizeof(lq));
            }
        }
    }
    if (thread_on && modulus_c6_sdio_ready()) {
        uint8_t st[] = {THREAD_CMD_GET_STATE};
        (void)modulus_c6_sdio_send(ESP_THREAD_IF, st, sizeof(st));
    }
}

void modulus_wireless_rpc_poll(void)
{
    modulus_wireless_rpc_poll_state(false, false);
}

const char *modulus_wireless_zb_network_text(void)
{
    static char buf[40];
    if (modulus_zb_uart_hub_offline()) {
        return "Hub offline - check wiring/power";
    }
    if (!modulus_zb_uart_ready()) {
        return "Hub not connected";
    }
    if (!s_zb_joined) {
        return "Not joined";
    }
    snprintf(buf, sizeof(buf), "Ch %u PAN 0x%04X", (unsigned)s_zb_ch, (unsigned)s_zb_pan);
    return buf;
}

const char *modulus_wireless_th_network_text(void)
{
    static char buf[48];
    if (!s_th_attached) {
        return "Detached";
    }
    static const char *roles[] = {"Off", "Detached", "Child", "Router", "Leader"};
    const char *role = (s_th_role < 5) ? roles[s_th_role] : "Active";
    snprintf(buf, sizeof(buf), "%s ch%u pan 0x%04X", role, (unsigned)s_th_ch, (unsigned)s_th_pan);
    return buf;
}

bool modulus_wireless_zb_joined(void) { return s_zb_joined; }
bool modulus_wireless_th_attached(void) { return s_th_attached; }
