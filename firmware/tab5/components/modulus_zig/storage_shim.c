/*
 * SD card mount + memory/flash diagnostics — mirrors C++ hal_storage.cpp.
 * Tab5: SDMMC 4-bit @ /sdcard via m5stack_tab5 BSP.
 */
#include "storage_shim.h"
#include "i2c_scan_shim.h"
#include "mbus_shim.h"
#include "tab5_port_map.h"
#include "modulus_zig.h"
#include "nvs_shim.h"

#include <bsp/m5stack_tab5.h>
#include <esp_heap_caps.h>
#include <esp_log.h>
#include <esp_partition.h>
#include <esp_timer.h>
#include <esp_vfs_fat.h>
#include <lvgl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static const char *TAG = "modulus_storage";

static const char *const k_loglvl_names[] = {
    "None", "Error", "Warn", "Info", "Debug", "Verbose",
};

static bool s_sd_mounted = false;
static char s_mount_point[] = "/sdcard";

void modulus_storage_init(void)
{
    /* Restore log level from NVS (matches Storage tab + C++ hal_system::init). */
    {
        uint8_t lvl = modulus_nvs_get_u8("loglvl", 2);
        if (lvl > 5) {
            lvl = 2;
        }
        esp_log_level_set("*", (esp_log_level_t)lvl);
        ESP_LOGI(TAG, "Log level restored: %u", (unsigned)lvl);
    }

    modulus_mbus_init();
    /* Best-effort mount once at boot. Live get_sd_info must NOT remount —
     * otherwise Eject is undone by the 2 s Storage refresh timer. */
    (void)modulus_storage_mount();
    ESP_LOGI(TAG, "Storage HAL init (SD mount after wireless_restore — SDIO bus free)");
}

bool modulus_storage_mount(void)
{
    if (s_sd_mounted) {
        return true;
    }

    (void)s_mount_point;
    const esp_err_t ret = bsp_sdcard_mount();
    if (ret == ESP_OK) {
        s_sd_mounted = true;
        ESP_LOGI(TAG, "SD mounted at %s", s_mount_point);
        return true;
    }

    ESP_LOGW(TAG, "SD mount failed: %s", esp_err_to_name(ret));
    s_sd_mounted = false;
    return false;
}

void modulus_storage_unmount(void)
{
    if (!s_sd_mounted) {
        return;
    }
    const esp_err_t ret = bsp_sdcard_unmount();
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "SD unmount failed: %s", esp_err_to_name(ret));
    }
    s_sd_mounted = false;
    ESP_LOGI(TAG, "SD unmounted");
}

bool modulus_storage_is_mounted(void)
{
    return s_sd_mounted;
}

void modulus_storage_get_sd_info(modulus_sd_info_t *out)
{
    if (!out) {
        return;
    }
    memset(out, 0, sizeof(*out));
    out->state = MODULUS_SD_NOT_PRESENT;
    out->bus_width = 4;

    /* Never auto-mount here — Mount/Eject UI owns session lifetime. */
    if (!s_sd_mounted) {
        return;
    }

    uint64_t total_bytes = 0;
    uint64_t free_bytes = 0;
    if (esp_vfs_fat_info(s_mount_point, &total_bytes, &free_bytes) == ESP_OK) {
        out->state = MODULUS_SD_MOUNTED;
        out->total_bytes = total_bytes;
        out->free_bytes = free_bytes;
    } else {
        out->state = MODULUS_SD_ERROR;
    }
}

void modulus_storage_get_mem_info(modulus_mem_info_t *out)
{
    if (!out) {
        return;
    }
    memset(out, 0, sizeof(*out));
    out->internal_free = heap_caps_get_free_size(MALLOC_CAP_INTERNAL);
    out->internal_total = heap_caps_get_total_size(MALLOC_CAP_INTERNAL);
    out->internal_min_free = heap_caps_get_minimum_free_size(MALLOC_CAP_INTERNAL);
    out->psram_free = heap_caps_get_free_size(MALLOC_CAP_SPIRAM);
    out->psram_total = heap_caps_get_total_size(MALLOC_CAP_SPIRAM);

    /* CONFIG_LV_USE_CLIB_MALLOC: lv_mem_monitor_core is a no-op (no LVGL TLSF pool).
     * LVGL widgets/layers use malloc -> PSRAM via CONFIG_SPIRAM_USE_MALLOC. Largest
     * contiguous PSRAM block is the practical headroom for layer draw buffers. */
    out->lvgl_free = heap_caps_get_largest_free_block(MALLOC_CAP_SPIRAM);
    if (out->psram_total > 0) {
        const size_t psram_used = out->psram_total - out->psram_free;
        out->lvgl_used_pct = (uint8_t)((psram_used * 100U) / out->psram_total);
        if (out->lvgl_used_pct > 100) {
            out->lvgl_used_pct = 100;
        }
    }
}

static const char *partition_type_str(esp_partition_type_t t)
{
    return (t == ESP_PARTITION_TYPE_APP) ? "app" : "data";
}

static const char *partition_subtype_str(esp_partition_type_t type, esp_partition_subtype_t sub)
{
    if (type == ESP_PARTITION_TYPE_APP) {
        switch (sub) {
        case ESP_PARTITION_SUBTYPE_APP_FACTORY:
            return "factory";
        case ESP_PARTITION_SUBTYPE_APP_OTA_0:
            return "ota_0";
        case ESP_PARTITION_SUBTYPE_APP_OTA_1:
            return "ota_1";
        default:
            return "app";
        }
    }
    switch (sub) {
    case ESP_PARTITION_SUBTYPE_DATA_NVS:
        return "nvs";
    case ESP_PARTITION_SUBTYPE_DATA_PHY:
        return "phy";
    case ESP_PARTITION_SUBTYPE_DATA_FAT:
        return "fat";
    case ESP_PARTITION_SUBTYPE_DATA_SPIFFS:
        return "spiffs";
    default:
        return "data";
    }
}

bool modulus_storage_export_diagnostics(const char *path)
{
    if (!path || path[0] == '\0') {
        return false;
    }
    if (!s_sd_mounted && !modulus_storage_mount()) {
        ESP_LOGW(TAG, "Diagnostics export requires mounted SD");
        return false;
    }

    FILE *f = fopen(path, "w");
    if (!f) {
        ESP_LOGW(TAG, "Cannot open %s", path);
        return false;
    }

    const time_t now = time(NULL);
    struct tm tm_now = {};
    if (now > 0) {
        localtime_r(&now, &tm_now);
    }

    fprintf(f, "Modulus Diagnostics Export\n");
    fprintf(f, "OS: Modulus v%s\n", modulus_zig_version());
    fprintf(f, "ABI epoch: %lu\n", (unsigned long)modulus_zig_abi_epoch());
    fprintf(f, "Framework: ESP-IDF 6.0\n");
    if (now > 0) {
        fprintf(f, "Timestamp: %04d-%02d-%02d %02d:%02d:%02d\n", tm_now.tm_year + 1900,
                tm_now.tm_mon + 1, tm_now.tm_mday, tm_now.tm_hour, tm_now.tm_min, tm_now.tm_sec);
    }

    const uint32_t sec = (uint32_t)(esp_timer_get_time() / 1000000ULL);
    fprintf(f, "Uptime: %lu s\n", (unsigned long)sec);

    const uint8_t log_lvl = modulus_nvs_get_u8("loglvl", 2);
    const char *log_name = (log_lvl <= 5) ? k_loglvl_names[log_lvl] : "Unknown";
    fprintf(f, "Log Level: %s (%u)\n", log_name, (unsigned)log_lvl);

    modulus_mem_info_t mem = {};
    modulus_storage_get_mem_info(&mem);
    fprintf(f, "Internal SRAM: %u free / %u total (min ever %u)\n",
            (unsigned)mem.internal_free, (unsigned)mem.internal_total,
            (unsigned)mem.internal_min_free);
    fprintf(f, "PSRAM: %u free / %u total\n", (unsigned)mem.psram_free,
            (unsigned)mem.psram_total);
    fprintf(f, "UI allocator: CLIB + PSRAM (<=4 KiB internal)\n");
    fprintf(f, "PSRAM largest block: %u bytes (%u%% PSRAM used)\n",
            (unsigned)mem.lvgl_free, (unsigned)mem.lvgl_used_pct);

    modulus_sd_info_t sd = {};
    modulus_storage_get_sd_info(&sd);
    const char *sd_str = (sd.state == MODULUS_SD_MOUNTED) ? "mounted"
                         : (sd.state == MODULUS_SD_ERROR) ? "error"
                                                          : "absent";
    fprintf(f, "SD Card: %s", sd_str);
    if (sd.state == MODULUS_SD_MOUNTED) {
        fprintf(f, " - %llu bytes total, %llu free", (unsigned long long)sd.total_bytes,
                (unsigned long long)sd.free_bytes);
    }
    fprintf(f, "\n");

    typedef struct {
        const char *label;
        uint32_t size;
        const char *type_str;
        const char *subtype_str;
    } flash_part_t;

    flash_part_t parts[12];
    int count = 0;
    esp_partition_iterator_t it =
        esp_partition_find(ESP_PARTITION_TYPE_ANY, ESP_PARTITION_SUBTYPE_ANY, NULL);
    while (it && count < 12) {
        const esp_partition_t *p = esp_partition_get(it);
        if (p) {
            parts[count].label = p->label;
            parts[count].size = p->size;
            parts[count].type_str = partition_type_str(p->type);
            parts[count].subtype_str = partition_subtype_str(p->type, p->subtype);
            count++;
        }
        it = esp_partition_next(it);
    }
    if (it) {
        esp_partition_iterator_release(it);
    }

    fprintf(f, "Flash partitions (%d):\n", count);
    for (int i = 0; i < count; i++) {
        fprintf(f, "  %s: %lu bytes (%s/%s)\n", parts[i].label, (unsigned long)parts[i].size,
                parts[i].type_str, parts[i].subtype_str);
    }

    fprintf(f, "USB Type-A host: %s\n", modulus_storage_usb_host_status_text());
    fprintf(f, "USB Type-A VBUS: %s\n",
            modulus_nvs_get_u8("usb5v", 0) ? "ON (Power tab)" : "OFF");

    fprintf(f, "I2C Scanner: %s\n", modulus_i2c_scan_status_text());
    fprintf(f, "Port A Grove: %s\n", modulus_i2c_scan_port_a_text());
    fprintf(f, "M-Bus system: %s\n", modulus_i2c_scan_mbus_text());
    fprintf(f, "EXP1 PI4IOE1: %s\n", modulus_i2c_scan_exp1_text());
    fprintf(f, "EXP2 PI4IOE2: %s\n", modulus_i2c_scan_exp2_text());
    tab5_port_map_write_diag(f);

    fclose(f);
    ESP_LOGI(TAG, "Diagnostics exported to %s", path);
    return true;
}

bool modulus_storage_export_settings(const char *path, bool include_secrets)
{
    if (!path || path[0] == '\0') {
        return false;
    }
    if (!s_sd_mounted && !modulus_storage_mount()) {
        return false;
    }
    FILE *f = fopen(path, "w");
    if (!f) {
        return false;
    }
    fprintf(f, "{\n  \"modulus_settings\": 1");

    static const char *const u8_keys[] = {
        "cnc_proto", "cnc_conn", "cnc_autocon", "cnc_prof", "cnc_wcs", "cnc_unit",
        "cnc_jmode", "cnc_axes", "cnc_encdiv", "cnc_contpct", "cnc_stepacc", "cnc_mpgpol",
        "cnf_cycle", "cnf_spin", "cnf_zero", "cnf_home", "cnf_mac", "jog_coal_ms",
        "jog_pend_max", "wcs_lock", "bright", "darkmode", "lefty", "flip",
    };
    for (unsigned i = 0; i < sizeof(u8_keys) / sizeof(u8_keys[0]); i++) {
        fprintf(f, ",\n  \"%s\": %u", u8_keys[i], (unsigned)modulus_nvs_get_u8(u8_keys[i], 0));
    }
    static const char *const u16_keys[] = {
        "cnc_jogspd", "ws_port", "tn_port", "ser_baud", "r4_baud", "masso_tx", "masso_rx",
    };
    for (unsigned i = 0; i < sizeof(u16_keys) / sizeof(u16_keys[0]); i++) {
        fprintf(f, ",\n  \"%s\": %u", u16_keys[i], (unsigned)modulus_nvs_get_u16(u16_keys[i], 0));
    }
    static const char *const str_keys[] = {
        "ws_host", "ws_path", "tn_host", "mach_name", "cnc_incr", "cnc_macro",
        "cnc_mac0", "cnc_mac1", "cnc_mac2", "cnc_mac3", "cnc_p0", "cnc_p1", "cnc_p2", "cnc_p3",
        "wcs_n0", "wcs_n1", "wcs_n2", "wcs_n3", "wcs_n4", "wcs_n5", "masso_ip", "masso_sn",
    };
    for (unsigned i = 0; i < sizeof(str_keys) / sizeof(str_keys[0]); i++) {
        char buf[192];
        if (!modulus_nvs_get_str(str_keys[i], buf, sizeof(buf))) {
            buf[0] = '\0';
        }
        fprintf(f, ",\n  \"%s\": \"", str_keys[i]);
        for (const char *c = buf; *c; c++) {
            if (*c == '"' || *c == '\\') {
                fputc('\\', f);
            }
            fputc(*c, f);
        }
        fputc('"', f);
    }
    if (include_secrets) {
        char buf[128];
        if (modulus_nvs_get_str("wf_pass", buf, sizeof(buf))) {
            fprintf(f, ",\n  \"wf_pass\": \"%s\"", buf);
        }
        if (modulus_nvs_get_str("wf_ssid", buf, sizeof(buf))) {
            fprintf(f, ",\n  \"wf_ssid\": \"%s\"", buf);
        }
    }
    fprintf(f, "\n}\n");
    fclose(f);
    ESP_LOGI(TAG, "Settings exported to %s (secrets=%d)", path, (int)include_secrets);
    return true;
}

static bool json_get_u_number(const char *json, const char *key, unsigned *out)
{
    char pat[48];
    snprintf(pat, sizeof(pat), "\"%s\":", key);
    const char *p = strstr(json, pat);
    if (!p) {
        return false;
    }
    p += strlen(pat);
    while (*p == ' ' || *p == '\t') {
        p++;
    }
    *out = (unsigned)strtoul(p, NULL, 10);
    return true;
}

static bool json_get_string(const char *json, const char *key, char *out, size_t out_len)
{
    char pat[48];
    snprintf(pat, sizeof(pat), "\"%s\":", key);
    const char *p = strstr(json, pat);
    if (!p || out_len == 0) {
        return false;
    }
    p += strlen(pat);
    while (*p == ' ' || *p == '\t') {
        p++;
    }
    if (*p != '"') {
        return false;
    }
    p++;
    size_t i = 0;
    while (*p && *p != '"' && i + 1 < out_len) {
        if (*p == '\\' && p[1]) {
            p++;
        }
        out[i++] = *p++;
    }
    out[i] = '\0';
    return true;
}

bool modulus_storage_import_settings(const char *path, bool include_secrets)
{
    if (!path || path[0] == '\0') {
        return false;
    }
    if (!s_sd_mounted && !modulus_storage_mount()) {
        return false;
    }
    FILE *f = fopen(path, "r");
    if (!f) {
        return false;
    }
    char *json = calloc(1, 16384);
    if (!json) {
        fclose(f);
        return false;
    }
    const size_t n = fread(json, 1, 16383, f);
    fclose(f);
    json[n] = '\0';
    if (!strstr(json, "\"modulus_settings\"")) {
        free(json);
        return false;
    }

    static const char *const u8_keys[] = {
        "cnc_proto", "cnc_conn", "cnc_autocon", "cnc_prof", "cnc_wcs", "cnc_unit",
        "cnc_jmode", "cnc_axes", "cnc_encdiv", "cnc_contpct", "cnc_stepacc", "cnc_mpgpol",
        "cnf_cycle", "cnf_spin", "cnf_zero", "cnf_home", "cnf_mac", "jog_coal_ms",
        "jog_pend_max", "wcs_lock", "bright", "darkmode", "lefty", "flip",
    };
    for (unsigned i = 0; i < sizeof(u8_keys) / sizeof(u8_keys[0]); i++) {
        unsigned v = 0;
        if (json_get_u_number(json, u8_keys[i], &v)) {
            modulus_nvs_set_u8(u8_keys[i], (uint8_t)v);
        }
    }
    static const char *const u16_keys[] = {
        "cnc_jogspd", "ws_port", "tn_port", "ser_baud", "r4_baud", "masso_tx", "masso_rx",
    };
    for (unsigned i = 0; i < sizeof(u16_keys) / sizeof(u16_keys[0]); i++) {
        unsigned v = 0;
        if (json_get_u_number(json, u16_keys[i], &v)) {
            modulus_nvs_set_u16(u16_keys[i], (uint16_t)v);
        }
    }
    static const char *const str_keys[] = {
        "ws_host", "ws_path", "tn_host", "mach_name", "cnc_incr", "cnc_macro",
        "cnc_mac0", "cnc_mac1", "cnc_mac2", "cnc_mac3", "cnc_p0", "cnc_p1", "cnc_p2", "cnc_p3",
        "wcs_n0", "wcs_n1", "wcs_n2", "wcs_n3", "wcs_n4", "wcs_n5", "masso_ip", "masso_sn",
    };
    for (unsigned i = 0; i < sizeof(str_keys) / sizeof(str_keys[0]); i++) {
        char buf[192];
        if (json_get_string(json, str_keys[i], buf, sizeof(buf))) {
            modulus_nvs_set_str(str_keys[i], buf);
        }
    }
    if (include_secrets) {
        char buf[128];
        if (json_get_string(json, "wf_pass", buf, sizeof(buf))) {
            modulus_nvs_set_str("wf_pass", buf);
        }
        if (json_get_string(json, "wf_ssid", buf, sizeof(buf))) {
            modulus_nvs_set_str("wf_ssid", buf);
        }
    }
    free(json);
    ESP_LOGI(TAG, "Settings imported from %s", path);
    return true;
}

void modulus_storage_clear_ui_cache(void)
{
    lv_obj_t *scr = lv_screen_active();
    if (scr) {
        lv_obj_invalidate(scr);
    }
    /* Let LVGL refr timer flush — lv_refr_now pins taskLVGL on 1280x720 sw_rotate. */
    ESP_LOGI(TAG, "UI cache cleared");
}

bool modulus_storage_is_usb_host_enabled(void)
{
    /* Type-A VBUS rail is Power tab `usb5v` (PI4IOE). Host-data detect is not
     * exposed by m5stack_tab5 BSP yet — do not pretend the port is dead when
     * power is on. Callers should use modulus_nvs usb5v for rail status. */
    return false;
}

/** ponytail: host-link detect not in BSP; Type-A VBUS uses Power `usb5v`. */
const char *modulus_storage_usb_host_status_text(void)
{
    return "Host detect N/A";
}
