/*
 * RX8130 RTC + system time — boot sync, manual set, timezone, NTP status (WiFi deferred).
 */
#include "rtc_shim.h"
#include "rx8130.h"
#include "i2c_coex_shim.h"
#include "nvs_shim.h"
#include "flash_walltime.h"

#include <bsp/m5stack_tab5.h>
#include "tab5_hw.h"
#include <driver/i2c_master.h>
#include <esp_log.h>
#include <esp_timer.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <esp_sntp.h>
#include <sys/time.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include "wireless_shim.h"

static const char *TAG = "modulus_rtc";

static const uint8_t k_rtc_addr = TAB5_I2C_ADDR_RX8130;
static bool s_ready = false;

static const char *const k_ntp_servers[] = {
    "pool.ntp.org",
    "time.google.com",
    "time.cloudflare.com",
};

typedef enum {
    NTP_DISABLED = 0,
    NTP_NO_NET,
    NTP_SYNCING,
    NTP_SYNCED,
    NTP_NOT_SYNCED,
} ntp_status_t;

static bool s_ntp_synced = false;
static ntp_status_t s_ntp_status = NTP_NOT_SYNCED;

static void ntp_sync_cb(struct timeval *tv)
{
    (void)tv;
    s_ntp_synced = true;
    s_ntp_status = NTP_SYNCED;
    ESP_LOGI(TAG, "NTP synchronized");
    if (s_ready) {
        (void)modulus_rtc_write_hw_from_system();
    }
}

static void configure_sntp_servers(void)
{
    esp_sntp_setoperatingmode(ESP_SNTP_OPMODE_POLL);
    for (int i = 0; i < 3; i++) {
        esp_sntp_setservername(i, k_ntp_servers[i]);
    }
}

static void ntp_start_internal(void)
{
    if (modulus_nvs_get_u8("ntp", 1) == 0) {
        s_ntp_status = NTP_DISABLED;
        return;
    }
    if (!modulus_wireless_wifi_is_connected()) {
        s_ntp_status = NTP_NO_NET;
        return;
    }
    if (esp_sntp_enabled()) {
        return;
    }
    configure_sntp_servers();
    esp_sntp_set_time_sync_notification_cb(ntp_sync_cb);
    s_ntp_synced = false;
    s_ntp_status = NTP_SYNCING;
    esp_sntp_init();
    ESP_LOGI(TAG, "SNTP started");
}

typedef struct {
    const char *label;
    const char *posix;
} tz_entry_t;

static const tz_entry_t k_tz[] = {
    {"UTC", "UTC0"},
    {"UTC-8 Pacific", "PST8"},
    {"UTC-5 Eastern", "EST5"},
    {"UTC+0 London", "GMT0"},
    {"UTC+1 Berlin", "CET-1"},
    {"UTC+8 China", "CST-8"},
};

static const int k_tz_count = (int)(sizeof(k_tz) / sizeof(k_tz[0]));

static void apply_tz_index(uint8_t idx)
{
    if (idx >= (uint8_t)k_tz_count) {
        idx = 0;
    }
    setenv("TZ", k_tz[idx].posix, 1);
    tzset();
    ESP_LOGI(TAG, "Timezone: %s (%s)", k_tz[idx].label, k_tz[idx].posix);
}

static bool tm_plausible(const struct tm *t)
{
    if (!t) {
        return false;
    }
    const int year = t->tm_year + 1900;
    return year >= 2020 && year <= 2099 && t->tm_mon >= 0 && t->tm_mon <= 11 && t->tm_mday >= 1 &&
           t->tm_mday <= 31 && t->tm_hour >= 0 && t->tm_hour <= 23 && t->tm_min >= 0 && t->tm_min <= 59 &&
           t->tm_sec >= 0 && t->tm_sec <= 59;
}

static bool sync_system_from_rtc(void)
{
    struct tm rtc = {};
    if (!rx8130_get_time(&rtc)) {
        ESP_LOGW(TAG, "RTC read failed");
        return false;
    }

    if (rx8130_voltage_low()) {
        ESP_LOGW(TAG, "RTC VLF set — time may be invalid");
    }

    if (!tm_plausible(&rtc)) {
        ESP_LOGW(TAG, "RTC time out of range — skip system sync");
        return false;
    }

    const time_t epoch = mktime(&rtc);
    if (epoch == (time_t)-1) {
        ESP_LOGW(TAG, "mktime failed for RTC wall time");
        return false;
    }

    const struct timeval tv = {.tv_sec = epoch, .tv_usec = 0};
    if (settimeofday(&tv, NULL) != 0) {
        ESP_LOGW(TAG, "settimeofday failed");
        return false;
    }

    ESP_LOGI(TAG, "System time from RTC: %04d-%02d-%02d %02d:%02d:%02d", rtc.tm_year + 1900,
             rtc.tm_mon + 1, rtc.tm_mday, rtc.tm_hour, rtc.tm_min, rtc.tm_sec);
    return true;
}

static bool write_rtc_from_local_tm(struct tm *local)
{
    if (!s_ready || !local) {
        return false;
    }
    local->tm_isdst = -1;
    if (!modulus_i2c_coex_lock(2000)) {
        return false;
    }
    rx8130_set_time(local);
    modulus_i2c_coex_unlock();
    return true;
}

/** One-shot: host PC time stamped at flash build → RX8130 + system clock. */
static void apply_flash_walltime_once(void)
{
    if (MODULUS_FLASH_WALL_ID == 0u || !s_ready) {
        return;
    }

    char prev[16] = {};
    if (modulus_nvs_get_str("fw_wall", prev, sizeof(prev))) {
        const unsigned long seen = strtoul(prev, NULL, 10);
        if (seen == (unsigned long)MODULUS_FLASH_WALL_ID) {
            return;
        }
    }

    if (!modulus_rtc_set_local_time(MODULUS_FLASH_WALL_YEAR, MODULUS_FLASH_WALL_MON, MODULUS_FLASH_WALL_DAY,
                                    MODULUS_FLASH_WALL_HOUR, MODULUS_FLASH_WALL_MIN, MODULUS_FLASH_WALL_SEC)) {
        ESP_LOGW(TAG, "flash walltime apply failed");
        return;
    }

    char idbuf[16];
    snprintf(idbuf, sizeof(idbuf), "%lu", (unsigned long)MODULUS_FLASH_WALL_ID);
    (void)modulus_nvs_set_str("fw_wall", idbuf);
    ESP_LOGI(TAG, "RTC set from flash host time id=%s", idbuf);
}

void modulus_rtc_apply_timezone(void)
{
    apply_tz_index(modulus_nvs_get_u8("tz_idx", 0));
}

void modulus_rtc_tz_changed(uint8_t tz_idx)
{
    struct tm wall = {};
    modulus_rtc_get_local_time(&wall);

    apply_tz_index(tz_idx);
    modulus_nvs_set_u8("tz_idx", tz_idx);

    wall.tm_isdst = -1;
    const time_t epoch = mktime(&wall);
    if (epoch != (time_t)-1) {
        const struct timeval tv = {.tv_sec = epoch, .tv_usec = 0};
        settimeofday(&tv, NULL);
    }
}

void modulus_rtc_init(void)
{
    modulus_rtc_apply_timezone();

    i2c_master_bus_handle_t bus = bsp_i2c_get_handle();
    if (!bus) {
        ESP_LOGW(TAG, "M-Bus I2C missing — RTC skipped");
        return;
    }

    if (!modulus_i2c_coex_lock(8000)) {
        ESP_LOGW(TAG, "RTC init skipped — M-Bus busy");
        return;
    }

    if (!rx8130_begin(bus, k_rtc_addr)) {
        ESP_LOGW(TAG, "RX8130 not detected at 0x%02X", k_rtc_addr);
        modulus_i2c_coex_unlock();
        return;
    }

    rx8130_init_bat();
    rx8130_clear_irq_flags();
    rx8130_disable_irq();
    s_ready = true;
    modulus_i2c_coex_unlock();

    (void)sync_system_from_rtc();
    apply_flash_walltime_once();
    ESP_LOGI(TAG, "RX8130 ready");
}

bool modulus_rtc_is_ready(void)
{
    return s_ready;
}

void modulus_rtc_get_local_time(struct tm *out)
{
    if (!out) {
        return;
    }
    const time_t now = time(NULL);
    localtime_r(&now, out);
}

void modulus_rtc_format_time(char *buf, size_t len)
{
    if (!buf || len == 0) {
        return;
    }
    struct tm t = {};
    modulus_rtc_get_local_time(&t);
    const bool h24 = modulus_nvs_get_u8("t_24h", 1) != 0;
    /* Status bar (Zig mirrorBatteryClock) — no seconds. */
    strftime(buf, len, h24 ? "%H:%M" : "%I:%M %p", &t);
}

void modulus_rtc_format_date(char *buf, size_t len)
{
    if (!buf || len == 0) {
        return;
    }
    struct tm t = {};
    modulus_rtc_get_local_time(&t);
    switch (modulus_nvs_get_u8("datefmt", 0)) {
    case 1:
        strftime(buf, len, "%m/%d/%Y", &t);
        break;
    case 2:
        strftime(buf, len, "%d/%m/%Y", &t);
        break;
    default:
        strftime(buf, len, "%Y-%m-%d", &t);
        break;
    }
}

bool modulus_rtc_set_local_time(int year, int month, int day, int hour, int min, int sec)
{
    struct tm t = {};
    t.tm_year = year - 1900;
    t.tm_mon = month - 1;
    t.tm_mday = day;
    t.tm_hour = hour;
    t.tm_min = min;
    t.tm_sec = sec;
    t.tm_isdst = -1;

    const time_t epoch = mktime(&t);
    if (epoch == (time_t)-1) {
        ESP_LOGW(TAG, "manual time mktime failed");
        return false;
    }

    const struct timeval tv = {.tv_sec = epoch, .tv_usec = 0};
    if (settimeofday(&tv, NULL) != 0) {
        return false;
    }

    localtime_r(&epoch, &t);
    if (s_ready) {
        write_rtc_from_local_tm(&t);
    }

    ESP_LOGI(TAG, "Manual time set: %04d-%02d-%02d %02d:%02d:%02d", year, month, day, hour, min, sec);
    return true;
}

bool modulus_rtc_write_hw_from_system(void)
{
    if (!s_ready) {
        return false;
    }
    struct tm t = {};
    modulus_rtc_get_local_time(&t);
    return write_rtc_from_local_tm(&t);
}

void modulus_rtc_ntp_poll(void)
{
    if (modulus_nvs_get_u8("ntp", 1) == 0) {
        if (esp_sntp_enabled()) {
            esp_sntp_stop();
        }
        s_ntp_status = NTP_DISABLED;
        return;
    }
    if (!modulus_wireless_wifi_is_connected()) {
        s_ntp_status = NTP_NO_NET;
        return;
    }
    if (!esp_sntp_enabled()) {
        s_ntp_status = s_ntp_synced ? NTP_SYNCED : NTP_NOT_SYNCED;
        return;
    }
    switch (esp_sntp_get_sync_status()) {
    case SNTP_SYNC_STATUS_COMPLETED:
        s_ntp_synced = true;
        s_ntp_status = NTP_SYNCED;
        break;
    case SNTP_SYNC_STATUS_IN_PROGRESS:
        s_ntp_status = NTP_SYNCING;
        break;
    default:
        s_ntp_status = s_ntp_synced ? NTP_SYNCED : NTP_SYNCING;
        break;
    }
}

const char *modulus_rtc_ntp_status_text(void)
{
    modulus_rtc_ntp_poll();
    switch (s_ntp_status) {
    case NTP_DISABLED:
        return "Disabled";
    case NTP_NO_NET:
        return "No network";
    case NTP_SYNCING:
        return "Syncing...";
    case NTP_SYNCED:
        return "Synced";
    default:
        return "Not synced";
    }
}

void modulus_rtc_ntp_on_wifi_connected(void)
{
    ntp_start_internal();
}

void modulus_rtc_ntp_set_enabled(bool enabled)
{
    modulus_nvs_set_u8("ntp", enabled ? 1 : 0);
    if (!enabled) {
        if (esp_sntp_enabled()) {
            esp_sntp_stop();
            ESP_LOGI(TAG, "SNTP stopped (NTP disabled)");
        }
        s_ntp_synced = false;
        s_ntp_status = NTP_DISABLED;
        return;
    }
    s_ntp_synced = false;
    s_ntp_status = NTP_NOT_SYNCED;
    ntp_start_internal();
}

bool modulus_rtc_ntp_sync_now(void)
{
    if (modulus_nvs_get_u8("ntp", 1) == 0) {
        s_ntp_status = NTP_DISABLED;
        return false;
    }
    if (!modulus_wireless_wifi_is_connected()) {
        s_ntp_status = NTP_NO_NET;
        ESP_LOGW(TAG, "NTP sync blocked — WiFi not connected");
        return false;
    }
    s_ntp_synced = false;
    s_ntp_status = NTP_SYNCING;
    if (!esp_sntp_enabled()) {
        ntp_start_internal();
        return true;
    }
    esp_sntp_stop();
    configure_sntp_servers();
    esp_sntp_set_time_sync_notification_cb(ntp_sync_cb);
    esp_sntp_init();
    ESP_LOGI(TAG, "SNTP forced re-sync");
    return true;
}

void modulus_rtc_format_uptime(char *buf, size_t len)
{
    if (!buf || len == 0) {
        return;
    }
    const uint32_t sec = (uint32_t)(esp_timer_get_time() / 1000000ULL);
    const uint32_t h = sec / 3600;
    const uint32_t m = (sec % 3600) / 60;
    const uint32_t s = sec % 60;
    snprintf(buf, len, "%luh %lum %lus", (unsigned long)h, (unsigned long)m, (unsigned long)s);
}
