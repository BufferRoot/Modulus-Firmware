/*
 * Zigbee / Thread device registry, discovery scan, ON/OFF cache (P4 host).
 * Control frames require C6 raw 802.15.4 (Thread detached) or future esp-zb RPC.
 */
#include "wireless_shim_802154.h"
#include "wireless_rpc.h"
#include "wireless_shim.h"
#include "zb_automation.h"

#include "zb_link_proto.h"
#include "nvs_shim.h"

#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/portmacro.h"
#include "freertos/task.h"

#include <stdio.h>
#include <string.h>

static const char *TAG = "wl_802154";

#define ZB_SCAN_MS 60000
#define TH_SCAN_MS 3000

static portMUX_TYPE s_mux = portMUX_INITIALIZER_UNLOCKED;

static modulus_zb_device_t s_zb_devs[MODULUS_ZB_MAX_DEVICES];
static int s_zb_dev_n;
/* Bumped on every live attribute report so the UI timer can detect
 * out-of-band state changes and rebuild without polling each device. */
static volatile uint32_t s_zb_state_gen;

static modulus_zb_device_t s_zb_scan[MODULUS_ZB_MAX_SCAN];
static int s_zb_scan_n;
static bool s_zb_scan_active;
static bool s_zb_scan_done;
static TickType_t s_zb_scan_deadline;

static modulus_th_device_t s_th_devs[MODULUS_TH_MAX_DEVICES];
static int s_th_dev_n;

static modulus_th_device_t s_th_scan[MODULUS_TH_MAX_SCAN];
static int s_th_scan_n;
static bool s_th_scan_active;
static bool s_th_scan_done;
static TickType_t s_th_scan_deadline;

static bool ieee_valid(const char *s)
{
    if (!s || strlen(s) != 16) {
        return false;
    }
    for (int i = 0; i < 16; i++) {
        const char c = s[i];
        if (!((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f'))) {
            return false;
        }
    }
    return true;
}

static void ieee_to_upper(char *s)
{
    if (!s) {
        return;
    }
    for (; *s; s++) {
        if (*s >= 'a' && *s <= 'f') {
            *s = (char)(*s - ('a' - 'A'));
        }
    }
}

/* ieee_valid() above is the canonical EUI-64 string check — no duplicate. */

static void zb_save_nvs(void); /* used by the load-time ghost sweep */

static void fmt_ieee(const uint8_t raw[8], char *out, size_t out_len)
{
    if (!raw || !out || out_len < 17) {
        return;
    }
    snprintf(out, out_len, "%02X%02X%02X%02X%02X%02X%02X%02X",
             raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7]);
}

static void zb_dev_key(char *buf, size_t len, int idx, const char *field)
{
    snprintf(buf, len, "zb%d_%s", idx, field);
}

static void th_dev_key(char *buf, size_t len, int idx, const char *field)
{
    snprintf(buf, len, "th%d_%s", idx, field);
}

static void zb_load_nvs(void)
{
    s_zb_dev_n = (int)modulus_nvs_get_u8("zb_n", 0);
    if (s_zb_dev_n > MODULUS_ZB_MAX_DEVICES) {
        s_zb_dev_n = MODULUS_ZB_MAX_DEVICES;
    }
    for (int i = 0; i < s_zb_dev_n; i++) {
        char key[12];
        char id[17] = {};
        char name[24] = {};
        zb_dev_key(key, sizeof(key), i, "id");
        modulus_nvs_get_str(key, id, sizeof(id));
        zb_dev_key(key, sizeof(key), i, "nm");
        modulus_nvs_get_str(key, name, sizeof(name));
        ieee_to_upper(id);
        strncpy(s_zb_devs[i].id, id, sizeof(s_zb_devs[i].id) - 1);
        strncpy(s_zb_devs[i].name, name, sizeof(s_zb_devs[i].name) - 1);
        zb_dev_key(key, sizeof(key), i, "ep");
        s_zb_devs[i].endpoint = modulus_nvs_get_u8(key, 1);
        zb_dev_key(key, sizeof(key), i, "on");
        s_zb_devs[i].on = modulus_nvs_get_u8(key, 0) != 0;
        zb_dev_key(key, sizeof(key), i, "sa");
        s_zb_devs[i].short_addr = modulus_nvs_get_u16(key, 0);
        zb_dev_key(key, sizeof(key), i, "lv");
        s_zb_devs[i].level = modulus_nvs_get_u8(key, 254);
        zb_dev_key(key, sizeof(key), i, "cp");
        s_zb_devs[i].caps = modulus_nvs_get_u8(key, 0);
        zb_dev_key(key, sizeof(key), i, "md");
        modulus_nvs_get_str(key, s_zb_devs[i].model, sizeof(s_zb_devs[i].model));
        s_zb_devs[i].rssi = 0;
        /* Re-seed RAM interview cache so post-reboot quirk/devdb lookups work
         * without waiting for another Basic cluster interview. */
        if (s_zb_devs[i].short_addr && s_zb_devs[i].model[0]) {
            modulus_wireless_zb_seed_dev_info(s_zb_devs[i].short_addr,
                                                     s_zb_devs[i].model);
        }
    }
    /* Ghost sweep: installs that hit the pre-fix strncpy bug persisted
     * corrupt/duplicate ids. Drop anything that is not a clean EUI-64 so
     * those registries self-heal on the first boot with this firmware. */
    int w = 0;
    for (int i = 0; i < s_zb_dev_n; i++) {
        if (!ieee_valid(s_zb_devs[i].id)) {
            ESP_LOGW(TAG, "Dropping corrupt Zigbee registry entry %d", i);
            continue;
        }
        if (w != i) {
            s_zb_devs[w] = s_zb_devs[i];
        }
        w++;
    }
    if (w != s_zb_dev_n) {
        s_zb_dev_n = w;
        zb_save_nvs();
    }
}

static void zb_save_nvs(void)
{
    modulus_nvs_set_u8("zb_n", (uint8_t)s_zb_dev_n);
    for (int i = 0; i < s_zb_dev_n; i++) {
        char key[12];
        zb_dev_key(key, sizeof(key), i, "id");
        modulus_nvs_set_str(key, s_zb_devs[i].id);
        zb_dev_key(key, sizeof(key), i, "nm");
        modulus_nvs_set_str(key, s_zb_devs[i].name);
        zb_dev_key(key, sizeof(key), i, "ep");
        modulus_nvs_set_u8(key, s_zb_devs[i].endpoint);
        zb_dev_key(key, sizeof(key), i, "on");
        modulus_nvs_set_u8(key, s_zb_devs[i].on ? 1 : 0);
        zb_dev_key(key, sizeof(key), i, "sa");
        modulus_nvs_set_u16(key, s_zb_devs[i].short_addr);
        zb_dev_key(key, sizeof(key), i, "lv");
        modulus_nvs_set_u8(key, s_zb_devs[i].level);
        zb_dev_key(key, sizeof(key), i, "cp");
        modulus_nvs_set_u8(key, s_zb_devs[i].caps);
        zb_dev_key(key, sizeof(key), i, "md");
        modulus_nvs_set_str(key, s_zb_devs[i].model);
    }
}

static void th_load_nvs(void)
{
    s_th_dev_n = (int)modulus_nvs_get_u8("th_n", 0);
    if (s_th_dev_n > MODULUS_TH_MAX_DEVICES) {
        s_th_dev_n = MODULUS_TH_MAX_DEVICES;
    }
    for (int i = 0; i < s_th_dev_n; i++) {
        char key[12];
        char ext[17] = {};
        char name[24] = {};
        th_dev_key(key, sizeof(key), i, "id");
        modulus_nvs_get_str(key, ext, sizeof(ext));
        th_dev_key(key, sizeof(key), i, "nm");
        modulus_nvs_get_str(key, name, sizeof(name));
        ieee_to_upper(ext);
        strncpy(s_th_devs[i].ext_addr, ext, sizeof(s_th_devs[i].ext_addr) - 1);
        strncpy(s_th_devs[i].name, name, sizeof(s_th_devs[i].name) - 1);
        th_dev_key(key, sizeof(key), i, "on");
        s_th_devs[i].on = modulus_nvs_get_u8(key, 0) != 0;
    }
}

static void th_save_nvs(void)
{
    modulus_nvs_set_u8("th_n", (uint8_t)s_th_dev_n);
    for (int i = 0; i < s_th_dev_n; i++) {
        char key[12];
        th_dev_key(key, sizeof(key), i, "id");
        modulus_nvs_set_str(key, s_th_devs[i].ext_addr);
        th_dev_key(key, sizeof(key), i, "nm");
        modulus_nvs_set_str(key, s_th_devs[i].name);
        th_dev_key(key, sizeof(key), i, "on");
        modulus_nvs_set_u8(key, s_th_devs[i].on ? 1 : 0);
    }
}

static void zb_scan_note(const char *id, int8_t rssi)
{
    if (!id || !id[0]) {
        return;
    }
    taskENTER_CRITICAL(&s_mux);
    for (int i = 0; i < s_zb_scan_n; i++) {
        if (strcmp(s_zb_scan[i].id, id) == 0) {
            if (rssi > s_zb_scan[i].rssi) {
                s_zb_scan[i].rssi = rssi;
            }
            taskEXIT_CRITICAL(&s_mux);
            return;
        }
    }
    if (s_zb_scan_n < MODULUS_ZB_MAX_SCAN) {
        modulus_zb_device_t *d = &s_zb_scan[s_zb_scan_n++];
        memset(d, 0, sizeof(*d));
        strncpy(d->id, id, sizeof(d->id) - 1);
        snprintf(d->name, sizeof(d->name), "Dev %.8s", id);
        d->endpoint = 1;
        d->rssi = rssi;
    }
    taskEXIT_CRITICAL(&s_mux);
}

static void th_scan_note(const char *ext, const char *name)
{
    if (!ext || !ext[0]) {
        return;
    }
    taskENTER_CRITICAL(&s_mux);
    for (int i = 0; i < s_th_scan_n; i++) {
        if (strcmp(s_th_scan[i].ext_addr, ext) == 0) {
            taskEXIT_CRITICAL(&s_mux);
            return;
        }
    }
    if (s_th_scan_n < MODULUS_TH_MAX_SCAN) {
        modulus_th_device_t *d = &s_th_scan[s_th_scan_n++];
        memset(d, 0, sizeof(*d));
        strncpy(d->ext_addr, ext, sizeof(d->ext_addr) - 1);
        if (name && name[0]) {
            strncpy(d->name, name, sizeof(d->name) - 1);
        } else {
            snprintf(d->name, sizeof(d->name), "Node %.8s", ext);
        }
    }
    taskEXIT_CRITICAL(&s_mux);
}

static bool zb_find_idx(const char *id)
{
    for (int i = 0; i < s_zb_dev_n; i++) {
        if (strcmp(s_zb_devs[i].id, id) == 0) {
            return true;
        }
    }
    return false;
}

static bool th_find_idx(const char *ext)
{
    for (int i = 0; i < s_th_dev_n; i++) {
        if (strcmp(s_th_devs[i].ext_addr, ext) == 0) {
            return true;
        }
    }
    return false;
}

static void zb_scan_finish(void)
{
    if (!s_zb_scan_active) {
        return;
    }
    if (modulus_wireless_zb_joined()) {
        (void)modulus_wireless_zb_permit_join(0); /* close the network */
    }
    s_zb_scan_active = false;
    s_zb_scan_done = true;
}

static void th_scan_finish(void)
{
    s_th_scan_active = false;
    s_th_scan_done = true;
}

void modulus_wireless_802154_poll(void)
{
    static bool loaded;
    if (!loaded) {
        zb_load_nvs();
        th_load_nvs();
        loaded = true;
    }
    modulus_zb_auto_poll(); /* also driven by always-on zb_auto task */

    const TickType_t now = xTaskGetTickCount();
    if (s_zb_scan_active && now >= s_zb_scan_deadline) {
        zb_scan_finish();
    }
    if (s_th_scan_active && now >= s_th_scan_deadline) {
        th_scan_finish();
    }
}

/* Hub mode: a device completed Zigbee joining on the NanoH2 coordinator.
 * Upsert into the registry (auto-pair) and mirror into the scan list so an
 * open Discovery page shows it immediately. */
void modulus_wireless_zb_note_device_joined(uint16_t short_addr, const uint8_t ieee_msb[8])
{
    if (!ieee_msb) {
        return;
    }
    char id[17];
    fmt_ieee(ieee_msb, id, sizeof(id));
    zb_scan_note(id, 0);
    bool save = false;
    taskENTER_CRITICAL(&s_mux);
    int found = -1;
    for (int i = 0; i < s_zb_dev_n; i++) {
        if (strcmp(s_zb_devs[i].id, id) == 0) {
            found = i;
            s_zb_devs[i].short_addr = short_addr;
            save = true;
            break;
        }
    }
    if (found < 0 && s_zb_dev_n < MODULUS_ZB_MAX_DEVICES) {
        modulus_zb_device_t *d = &s_zb_devs[s_zb_dev_n++];
        memset(d, 0, sizeof(*d));
        strncpy(d->id, id, sizeof(d->id) - 1);
        snprintf(d->name, sizeof(d->name), "Dev %.8s", id);
        d->endpoint = 1;
        d->short_addr = short_addr;
        d->level = 254;
        save = true;
    }
    if (save) {
        s_zb_state_gen++; /* UI rebuild while Discovery scan is still open */
    }
    taskEXIT_CRITICAL(&s_mux);
    if (save) {
        zb_save_nvs(); /* NVS outside the critical section (flash I/O) */
        ESP_LOGI(TAG, "Zigbee device %s short=0x%04x", id, short_addr);
    } else {
        ESP_LOGW(TAG, "Zigbee registry full; %s not saved", id);
    }
}

/* Capability report from the C6's ZDO Simple Descriptor query. Also updates
 * the endpoint (many plugs/covers are not on EP 1) and upgrades a generic
 * auto-name to a category name so the list is readable. */
void modulus_wireless_zb_note_device_caps(uint16_t short_addr, uint8_t endpoint,
                                                 uint8_t caps, uint16_t device_id)
{
    (void)device_id;
    bool save = false;
    taskENTER_CRITICAL(&s_mux);
    for (int i = 0; i < s_zb_dev_n; i++) {
        if (s_zb_devs[i].short_addr != short_addr || short_addr == 0) {
            continue;
        }
        s_zb_devs[i].endpoint = endpoint ? endpoint : 1;
        s_zb_devs[i].caps = caps;
        if (strncmp(s_zb_devs[i].name, "Dev ", 4) == 0) {
            const char *kind = (caps & ZIGBEE_CAP_LEVEL)      ? "Light"
                               : (caps & ZIGBEE_CAP_COVER)      ? "Cover"
                               : (caps & ZIGBEE_CAP_THERMOSTAT) ? "Thermostat"
                               : (caps & ZIGBEE_CAP_ONOFF)      ? "Switch"
                               : (caps & ZIGBEE_CAP_SENSOR)     ? "Sensor"
                                                                : "Device";
            char id_copy[17];
            memcpy(id_copy, s_zb_devs[i].id, sizeof(id_copy));
            id_copy[sizeof(id_copy) - 1] = '\0';
            snprintf(s_zb_devs[i].name, sizeof(s_zb_devs[i].name), "%s %.6s", kind, id_copy);
        }
        save = true;
        break;
    }
    taskEXIT_CRITICAL(&s_mux);
    if (save) {
        zb_save_nvs();
        ESP_LOGI(TAG, "Zigbee 0x%04x ep%u caps=0x%02x", short_addr, (unsigned)endpoint,
                 (unsigned)caps);
    }
}

/* Interview result: upgrade auto-generated names ("Dev XXXXXX", "Switch
 * XXXXXX") to the devdb friendly name; user-set names are never touched.
 * Always persist the model key so reboot can re-seed the interview cache. */
void modulus_wireless_zb_note_device_info(uint16_t short_addr, const char *mfr,
                                                 const char *model,
                                                 const zb_devdb_entry_t *db)
{
    if (short_addr == 0 || !model || !model[0]) {
        return;
    }
    bool save = false;
    taskENTER_CRITICAL(&s_mux);
    for (int i = 0; i < s_zb_dev_n; i++) {
        if (s_zb_devs[i].short_addr != short_addr) {
            continue;
        }
        if (strncmp(s_zb_devs[i].model, model, sizeof(s_zb_devs[i].model)) != 0) {
            strncpy(s_zb_devs[i].model, model, sizeof(s_zb_devs[i].model) - 1);
            s_zb_devs[i].model[sizeof(s_zb_devs[i].model) - 1] = '\0';
            save = true;
        }
        const bool auto_name =
            strncmp(s_zb_devs[i].name, "Dev ", 4) == 0 ||
            strncmp(s_zb_devs[i].name, "Light ", 6) == 0 ||
            strncmp(s_zb_devs[i].name, "Cover ", 6) == 0 ||
            strncmp(s_zb_devs[i].name, "Thermostat ", 11) == 0 ||
            strncmp(s_zb_devs[i].name, "Switch ", 7) == 0 ||
            strncmp(s_zb_devs[i].name, "Sensor ", 7) == 0 ||
            strncmp(s_zb_devs[i].name, "Device ", 7) == 0;
        if (auto_name) {
            if (db) {
                snprintf(s_zb_devs[i].name, sizeof(s_zb_devs[i].name), "%s %s",
                         db->vendor, db->model);
            } else if (mfr && mfr[0]) {
                snprintf(s_zb_devs[i].name, sizeof(s_zb_devs[i].name), "%s %s",
                         mfr, model);
            } else {
                snprintf(s_zb_devs[i].name, sizeof(s_zb_devs[i].name), "%s", model);
            }
            save = true;
        }
        break;
    }
    taskEXIT_CRITICAL(&s_mux);
    if (save) {
        zb_save_nvs();
    }
}

void modulus_wireless_zb_note_device_lqi(uint16_t short_addr, uint8_t lqi,
                                                int8_t rssi)
{
    if (short_addr == 0) {
        return;
    }
    taskENTER_CRITICAL(&s_mux);
    for (int i = 0; i < s_zb_dev_n; i++) {
        if (s_zb_devs[i].short_addr == short_addr) {
            s_zb_devs[i].lqi = lqi;
            if (rssi != 0) { /* some stacks report 0 = "no measurement" */
                s_zb_devs[i].rssi = rssi;
            }
            break;
        }
    }
    taskEXIT_CRITICAL(&s_mux); /* RAM only — no NVS churn for telemetry */
}

void modulus_wireless_zb_note_device_left(const uint8_t ieee_msb[8])
{
    if (!ieee_msb) {
        return;
    }
    char id[17];
    fmt_ieee(ieee_msb, id, sizeof(id));
    bool save = false;
    taskENTER_CRITICAL(&s_mux);
    for (int i = 0; i < s_zb_dev_n; i++) {
        if (strcmp(s_zb_devs[i].id, id) == 0) {
            /* Keep the saved device (user may re-pair) but drop the stale
             * short address so control honestly reports unreachable. */
            s_zb_devs[i].short_addr = 0;
            save = true;
            break;
        }
    }
    taskEXIT_CRITICAL(&s_mux);
    if (save) {
        zb_save_nvs();
        ESP_LOGI(TAG, "Zigbee device %s left the network", id);
    }
}

/* Live attribute report from a bound device (physical switch, other remote).
 * Updates the cached on/off or level so the UI reflects reality on next
 * rebuild. RX-task context -> registry lock. Does NOT persist to NVS: reports
 * are frequent and transient; the periodic device save covers durability. */
void modulus_wireless_zb_note_device_state(uint16_t short_addr, uint16_t cluster,
                                                  uint16_t value)
{
    if (short_addr == 0) {
        return;
    }
    taskENTER_CRITICAL(&s_mux);
    for (int i = 0; i < s_zb_dev_n; i++) {
        if (s_zb_devs[i].short_addr != short_addr) {
            continue;
        }
        /* Only bump the UI generation on a real change — devices report
         * repeatedly (each level step of a fade, periodic confirms); a full
         * page rebuild per redundant report would churn the UI. */
        if (cluster == 0x0006) {
            const bool on = value != 0;
            if (s_zb_devs[i].on != on) {
                s_zb_devs[i].on = on;
                s_zb_state_gen++;
            }
        } else if (cluster == 0x0008) {
            const uint8_t lvl = value > 254 ? 254 : (uint8_t)value;
            const bool on = value > 0;
            if (s_zb_devs[i].level != lvl || s_zb_devs[i].on != on) {
                s_zb_devs[i].level = lvl;
                s_zb_devs[i].on = on;
                s_zb_state_gen++;
            }
        } else if (cluster == 0x0500) {
            if (!s_zb_devs[i].zone_seen || s_zb_devs[i].zone_status != value) {
                s_zb_devs[i].zone_status = value;
                s_zb_devs[i].zone_seen = true;
                s_zb_state_gen++;
            }
        } else if (cluster == 0x0B04) {
            /* ActivePower reports land as DEV_STATE with raw value in some stacks;
             * prefer DEV_SENSOR path, but accept here too. */
            const int16_t p = (int16_t)value;
            if (s_zb_devs[i].power_raw != p) {
                s_zb_devs[i].power_raw = p;
                s_zb_devs[i].sensors_seen |= 0x04;
                s_zb_state_gen++;
            }
        }
        break;
    }
    taskEXIT_CRITICAL(&s_mux);
}

uint32_t modulus_wireless_zigbee_state_gen(void)
{
    return s_zb_state_gen;
}

void modulus_wireless_th_note_device_join(const uint8_t ext[8])
{
    if (!ext) {
        return;
    }
    char id[17];
    fmt_ieee(ext, id, sizeof(id));
    th_scan_note(id, NULL);
    if (s_th_scan_active) {
        return;
    }
    if (th_find_idx(id) || s_th_dev_n >= MODULUS_TH_MAX_DEVICES) {
        return;
    }
    modulus_th_device_t *d = &s_th_devs[s_th_dev_n++];
    memset(d, 0, sizeof(*d));
    strncpy(d->ext_addr, id, sizeof(d->ext_addr) - 1);
    snprintf(d->name, sizeof(d->name), "Node %.8s", id);
    th_save_nvs();
}

void modulus_wireless_th_note_device_leave(const uint8_t ext[8])
{
    if (!ext) {
        return;
    }
    char id[17];
    fmt_ieee(ext, id, sizeof(id));
    for (int i = 0; i < s_th_dev_n; i++) {
        if (strcmp(s_th_devs[i].ext_addr, id) == 0) {
            s_th_dev_n--;
            memmove(&s_th_devs[i], &s_th_devs[i + 1], (size_t)(s_th_dev_n - i) * sizeof(s_th_devs[0]));
            th_save_nvs();
            return;
        }
    }
}

const char *modulus_wireless_zigbee_scan_text(void)
{
    if (s_zb_scan_active) {
        return "Scanning...";
    }
    if (!s_zb_scan_done) {
        return "Tap scan";
    }
    static char buf[24];
    snprintf(buf, sizeof(buf), "%d device(s)", s_zb_scan_n);
    return buf;
}

bool modulus_wireless_zigbee_scan_start(void)
{
    /* Zigbee lives on the NanoH2 hub — the C6 SDIO transport is irrelevant. */
    if (!modulus_wireless_zb_link_up()) {
        ESP_LOGW(TAG, "Zigbee scan: NanoH2 hub link down");
        return false;
    }
    if (!modulus_wireless_zb_joined()) {
        /* Network not formed yet — UI says join first. */
        return false;
    }
    taskENTER_CRITICAL(&s_mux);
    s_zb_scan_n = 0;
    s_zb_scan_done = false;
    s_zb_scan_active = true;
    s_zb_scan_deadline = xTaskGetTickCount() + pdMS_TO_TICKS(ZB_SCAN_MS);
    taskEXIT_CRITICAL(&s_mux);
    /* Discovery is Zigbee pairing — open the network so devices put in
     * pairing mode join; announces land in the registry + list. */
    if (!modulus_wireless_zb_permit_join((uint8_t)(ZB_SCAN_MS / 1000))) {
        s_zb_scan_active = false;
        s_zb_scan_done = true;
        return false;
    }
    return true;
}

void modulus_wireless_zigbee_scan_stop(void)
{
    zb_scan_finish();
}

bool modulus_wireless_zigbee_scan_done(void)
{
    return !s_zb_scan_active && s_zb_scan_done;
}

int modulus_wireless_zigbee_scan_count(void)
{
    return s_zb_scan_n;
}

bool modulus_wireless_zigbee_scan_get(int idx, modulus_zb_device_t *out)
{
    if (!out || idx < 0 || idx >= s_zb_scan_n) {
        return false;
    }
    taskENTER_CRITICAL(&s_mux);
    *out = s_zb_scan[idx];
    taskEXIT_CRITICAL(&s_mux);
    return true;
}

bool modulus_wireless_zigbee_scan_select(int idx)
{
    modulus_zb_device_t d = {};
    if (!modulus_wireless_zigbee_scan_get(idx, &d)) {
        return false;
    }
    return modulus_wireless_zigbee_device_add(d.name, d.id, d.endpoint, NULL);
}

int modulus_wireless_zigbee_device_count(void)
{
    return s_zb_dev_n;
}

bool modulus_wireless_zigbee_device_get(int idx, modulus_zb_device_t *out)
{
    if (!out || idx < 0 || idx >= s_zb_dev_n) {
        return false;
    }
    /* RX task (join/caps/leave events) mutates the registry concurrently. */
    taskENTER_CRITICAL(&s_mux);
    *out = s_zb_devs[idx];
    taskEXIT_CRITICAL(&s_mux);
    return true;
}

bool modulus_wireless_zigbee_device_add(const char *name, const char *ieee, uint8_t endpoint,
                                        const char *install_code)
{
    (void)install_code;
    if (!ieee || !ieee_valid(ieee) || s_zb_dev_n >= MODULUS_ZB_MAX_DEVICES) {
        return false;
    }
    char id[17];
    strncpy(id, ieee, sizeof(id) - 1);
    id[sizeof(id) - 1] = '\0'; /* strncpy does NOT terminate a 16-char source:
                                * unterminated id corrupted logs, broke dedupe
                                * (duplicate no-short_addr entries), and let
                                * ieee_to_upper scribble past the buffer. */
    ieee_to_upper(id);
    if (zb_find_idx(id)) {
        /* Already registered (e.g. auto-paired via device-announce). Treat a
         * manual save as a refresh, not an error — the scan-row tap should
         * succeed instead of playing the error sound. */
        return true;
    }
    modulus_zb_device_t *d = &s_zb_devs[s_zb_dev_n++];
    memset(d, 0, sizeof(*d));
    strncpy(d->id, id, sizeof(d->id) - 1);
    if (name && name[0]) {
        strncpy(d->name, name, sizeof(d->name) - 1);
    } else {
        snprintf(d->name, sizeof(d->name), "Dev %.8s", id);
    }
    d->endpoint = endpoint ? endpoint : 1;
    d->on = false;
    d->level = 254;
    zb_save_nvs();
    ESP_LOGI(TAG, "Zigbee device saved %s ep=%u", id, (unsigned)d->endpoint);
    return true;
}

bool modulus_wireless_zigbee_device_toggle(int idx)
{
    modulus_zb_device_t snap = {};
    bool next = false;
    taskENTER_CRITICAL(&s_mux);
    if (idx < 0 || idx >= s_zb_dev_n) {
        taskEXIT_CRITICAL(&s_mux);
        return false;
    }
    next = !s_zb_devs[idx].on;
    snap = s_zb_devs[idx];
    taskEXIT_CRITICAL(&s_mux);

    if (modulus_wireless_zigbee_can_control()) {
        if (!modulus_wireless_zb_set_onoff(&snap, next)) {
            ESP_LOGW(TAG, "Zigbee ON/OFF RPC failed (cache only)");
        }
    }

    taskENTER_CRITICAL(&s_mux);
    if (idx >= 0 && idx < s_zb_dev_n) {
        s_zb_devs[idx].on = next;
    }
    taskEXIT_CRITICAL(&s_mux);
    zb_save_nvs();
    return true;
}

bool modulus_wireless_zigbee_device_set_level(int idx, uint8_t level)
{
    modulus_zb_device_t snap = {};
    bool rpc_ok = false;
    if (level > 254) {
        level = 254;
    }
    taskENTER_CRITICAL(&s_mux);
    if (idx < 0 || idx >= s_zb_dev_n) {
        taskEXIT_CRITICAL(&s_mux);
        return false;
    }
    snap = s_zb_devs[idx];
    taskEXIT_CRITICAL(&s_mux);

    if (modulus_wireless_zigbee_can_control()) {
        rpc_ok = modulus_wireless_zb_set_level(&snap, level);
        if (!rpc_ok) {
            ESP_LOGW(TAG, "Zigbee Level RPC failed (cache only)");
        }
    }

    taskENTER_CRITICAL(&s_mux);
    if (idx >= 0 && idx < s_zb_dev_n) {
        s_zb_devs[idx].level = level;
        if (rpc_ok) {
            /* move_to_level_with_onoff: level > 0 also turns the light on. */
            s_zb_devs[idx].on = level > 0;
        }
    }
    taskEXIT_CRITICAL(&s_mux);
    zb_save_nvs();
    return true;
}

/* Sensor read response: cache raw values (RAM only) and bump the UI gen. */
void modulus_wireless_zb_note_device_sensor(uint16_t short_addr, uint16_t cluster,
                                                   uint16_t attr, uint32_t value)
{
    if (short_addr == 0) {
        return;
    }
    taskENTER_CRITICAL(&s_mux);
    for (int i = 0; i < s_zb_dev_n; i++) {
        if (s_zb_devs[i].short_addr != short_addr) {
            continue;
        }
        if (cluster == 0x0B04 && attr == 0x0505) {
            s_zb_devs[i].volt_raw = (uint16_t)value;
            s_zb_devs[i].sensors_seen |= 0x01;
        } else if (cluster == 0x0B04 && attr == 0x0508) {
            s_zb_devs[i].curr_raw = (uint16_t)value;
            s_zb_devs[i].sensors_seen |= 0x02;
        } else if (cluster == 0x0B04 && attr == 0x050B) {
            s_zb_devs[i].power_raw = (int16_t)(uint16_t)value;
            s_zb_devs[i].sensors_seen |= 0x04;
        } else if (cluster == 0x0702 && attr == 0x0000) {
            s_zb_devs[i].energy_raw = value;
            s_zb_devs[i].sensors_seen |= 0x08;
        }
        s_zb_state_gen++;
        break;
    }
    taskEXIT_CRITICAL(&s_mux);
}

bool modulus_wireless_zigbee_device_rename(int idx, const char *name)
{
    if (idx < 0 || idx >= s_zb_dev_n || !name || !name[0]) {
        return false;
    }
    taskENTER_CRITICAL(&s_mux);
    strncpy(s_zb_devs[idx].name, name, sizeof(s_zb_devs[idx].name) - 1);
    s_zb_devs[idx].name[sizeof(s_zb_devs[idx].name) - 1] = '\0';
    s_zb_state_gen++;
    taskEXIT_CRITICAL(&s_mux);
    zb_save_nvs();
    return true;
}

bool modulus_wireless_zigbee_device_read_sensors(int idx)
{
    modulus_zb_device_t d = {};
    if (!modulus_wireless_zigbee_device_get(idx, &d) || !modulus_wireless_zigbee_can_control()) {
        return false;
    }
    return modulus_wireless_zb_read_sensors(&d);
}

bool modulus_wireless_zigbee_device_identify(int idx)
{
    modulus_zb_device_t d = {};
    if (!modulus_wireless_zigbee_device_get(idx, &d) || !modulus_wireless_zigbee_can_control()) {
        return false;
    }
    return modulus_wireless_zb_identify(&d, 5);
}

bool modulus_wireless_zigbee_device_leave(int idx)
{
    modulus_zb_device_t d = {};
    if (!modulus_wireless_zigbee_device_get(idx, &d)) {
        return false;
    }
    if (d.id[0] && modulus_wireless_zigbee_can_control()) {
        (void)modulus_wireless_zb_dev_leave(d.id);
    }
    return modulus_wireless_zigbee_device_remove(idx);
}

static uint8_t s_energy_best_ch;
static int8_t s_energy_best_dbm;
static bool s_energy_have;

void modulus_wireless_zb_note_energy_ch(uint8_t ch, int8_t energy_dbm)
{
    ESP_LOGI(TAG, "Energy ch %u: %d dBm", (unsigned)ch, (int)energy_dbm);
}

void modulus_wireless_zb_note_energy_done(uint8_t best_ch, int8_t best_dbm)
{
    s_energy_best_ch = best_ch;
    s_energy_best_dbm = best_dbm;
    s_energy_have = true;
    s_zb_state_gen++;
    ESP_LOGI(TAG, "Energy scan best ch %u (%d dBm)", (unsigned)best_ch, (int)best_dbm);
}

bool modulus_wireless_zigbee_energy_scan(void)
{
    if (!modulus_wireless_zigbee_can_control()) {
        return false;
    }
    s_energy_have = false;
    return modulus_wireless_zb_energy_scan();
}

const char *modulus_wireless_zigbee_energy_text(void)
{
    static char buf[40];
    if (!s_energy_have) {
        return "Tap to scan ch 11-26";
    }
    snprintf(buf, sizeof(buf), "Best ch %u (%d dBm)", (unsigned)s_energy_best_ch,
             (int)s_energy_best_dbm);
    return buf;
}

bool modulus_wireless_zigbee_device_cover(int idx, uint8_t op)
{
    modulus_zb_device_t d = {};
    if (!modulus_wireless_zigbee_device_get(idx, &d) || !modulus_wireless_zigbee_can_control()) {
        return false;
    }
    return modulus_wireless_zb_cover(&d, op);
}

bool modulus_wireless_zigbee_device_color(int idx, uint8_t mode, uint16_t a, uint16_t b)
{
    modulus_zb_device_t d = {};
    if (!modulus_wireless_zigbee_device_get(idx, &d) || !modulus_wireless_zigbee_can_control()) {
        return false;
    }
    return modulus_wireless_zb_color(&d, mode, a, b);
}

bool modulus_wireless_zigbee_device_ic_add(int idx, const char *code_hex)
{
    modulus_zb_device_t d = {};
    if (!modulus_wireless_zigbee_device_get(idx, &d)) {
        return false;
    }
    return modulus_wireless_zb_ic_add(d.id, code_hex);
}

bool modulus_wireless_zigbee_device_remove(int idx)
{
    if (idx < 0 || idx >= s_zb_dev_n) {
        return false;
    }
    taskENTER_CRITICAL(&s_mux);
    s_zb_dev_n--;
    memmove(&s_zb_devs[idx], &s_zb_devs[idx + 1], (size_t)(s_zb_dev_n - idx) * sizeof(s_zb_devs[0]));
    taskEXIT_CRITICAL(&s_mux);
    modulus_zb_auto_on_remove(idx, s_zb_dev_n); /* keep NVS modes index-aligned */
    zb_save_nvs();
    return true;
}

void modulus_wireless_zigbee_devices_clear(void)
{
    modulus_zb_auto_clear_all(s_zb_dev_n);
    s_zb_dev_n = 0;
    modulus_nvs_set_u8("zb_n", 0);
}

bool modulus_wireless_zigbee_can_control(void)
{
    return modulus_wireless_zb_link_up() && modulus_wireless_zb_joined();
}

const char *modulus_wireless_thread_scan_text(void)
{
    if (s_th_scan_active) {
        return "Refreshing...";
    }
    if (!s_th_scan_done) {
        return "Tap refresh";
    }
    static char buf[24];
    snprintf(buf, sizeof(buf), "%d node(s)", s_th_scan_n);
    return buf;
}

bool modulus_wireless_thread_scan_start(void)
{
    if (!modulus_wireless_transport_up()) {
        return false;
    }
    taskENTER_CRITICAL(&s_mux);
    s_th_scan_n = 0;
    s_th_scan_done = false;
    s_th_scan_active = true;
    s_th_scan_deadline = xTaskGetTickCount() + pdMS_TO_TICKS(TH_SCAN_MS);
    taskEXIT_CRITICAL(&s_mux);
    (void)modulus_wireless_th_refresh_devices();
    return true;
}

void modulus_wireless_thread_scan_stop(void)
{
    th_scan_finish();
}

bool modulus_wireless_thread_scan_done(void)
{
    return !s_th_scan_active && s_th_scan_done;
}

int modulus_wireless_thread_scan_count(void)
{
    return s_th_scan_n;
}

bool modulus_wireless_thread_scan_get(int idx, modulus_th_device_t *out)
{
    if (!out || idx < 0 || idx >= s_th_scan_n) {
        return false;
    }
    taskENTER_CRITICAL(&s_mux);
    *out = s_th_scan[idx];
    taskEXIT_CRITICAL(&s_mux);
    return true;
}

bool modulus_wireless_thread_scan_select(int idx)
{
    modulus_th_device_t d = {};
    if (!modulus_wireless_thread_scan_get(idx, &d)) {
        return false;
    }
    return modulus_wireless_thread_device_add(d.name, d.ext_addr);
}

int modulus_wireless_thread_device_count(void)
{
    return s_th_dev_n;
}

bool modulus_wireless_thread_device_get(int idx, modulus_th_device_t *out)
{
    if (!out || idx < 0 || idx >= s_th_dev_n) {
        return false;
    }
    *out = s_th_devs[idx];
    return true;
}

bool modulus_wireless_thread_device_add(const char *name, const char *ext_addr)
{
    if (!ext_addr || !ieee_valid(ext_addr) || s_th_dev_n >= MODULUS_TH_MAX_DEVICES) {
        return false;
    }
    char id[17];
    strncpy(id, ext_addr, sizeof(id) - 1);
    id[sizeof(id) - 1] = '\0'; /* same latent bug as the Zigbee twin */
    ieee_to_upper(id);
    if (th_find_idx(id)) {
        return false;
    }
    modulus_th_device_t *d = &s_th_devs[s_th_dev_n++];
    memset(d, 0, sizeof(*d));
    strncpy(d->ext_addr, id, sizeof(d->ext_addr) - 1);
    if (name && name[0]) {
        strncpy(d->name, name, sizeof(d->name) - 1);
    } else {
        snprintf(d->name, sizeof(d->name), "Node %.8s", id);
    }
    d->on = false;
    th_save_nvs();
    return true;
}

bool modulus_wireless_thread_device_toggle(int idx)
{
    if (idx < 0 || idx >= s_th_dev_n) {
        return false;
    }
    s_th_devs[idx].on = !s_th_devs[idx].on;
    th_save_nvs();
    if (!modulus_wireless_thread_can_control()) {
        ESP_LOGW(TAG, "Thread ON/OFF cached only (Matter/CoAP path open)");
    }
    return true;
}

bool modulus_wireless_thread_device_remove(int idx)
{
    if (idx < 0 || idx >= s_th_dev_n) {
        return false;
    }
    s_th_dev_n--;
    memmove(&s_th_devs[idx], &s_th_devs[idx + 1], (size_t)(s_th_dev_n - idx) * sizeof(s_th_devs[0]));
    th_save_nvs();
    return true;
}

void modulus_wireless_thread_devices_clear(void)
{
    s_th_dev_n = 0;
    modulus_nvs_set_u8("th_n", 0);
}

bool modulus_wireless_thread_can_control(void)
{
    return modulus_wireless_transport_up() && modulus_wireless_th_attached();
}
