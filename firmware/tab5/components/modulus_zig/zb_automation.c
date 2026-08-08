/* CNC-linked Zigbee automation + scenes. See zb_automation.h.
 * Gate/vacuum order: COVER(follow)=blast gate, ONOFF(follow)=vacuum.
 * Cut: gate open -> 500 ms -> vacuum ON. Stop: vacuum off-delay -> 500 ms -> gate close. */
#include "zb_automation.h"

#include "audio_shim.h"
#include "zb_link_proto.h"
#include "nvs_shim.h"
#include "shop_recipe.h"
#include "ui_shim.h"
#include "ui_internal.h"
#include "wireless_rpc.h"
#include "wireless_shim_802154.h"

#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include <stdio.h>
#include <string.h>

static const char *TAG = "zb_auto";

#define AUTO_POLL_US (1000LL * 1000)
#define GATE_LEAD_US (500LL * 1000)
#define K_STATE_RUN   2
#define K_STATE_HOLD  3
#define K_STATE_ALARM 5
#define K_STATE_DOOR  6

#define LVL_CUT   80
#define LVL_CLEAN 160
#define LVL_IDLE  254
#define CCT_CUT   370
#define CCT_IDLE  250

#define DRIVE_COVER  1
#define DRIVE_SWITCH 2
#define DRIVE_ALL    3

static char s_pwr_warn[48];
static int s_clog_idx = -1;
static int16_t s_pwr_base[MODULUS_ZB_MAX_DEVICES];
static uint8_t s_sensor_tick;
static int64_t s_vac_arm_us = -1;   /* Cut: when to turn vacuums on */
static int64_t s_gate_close_us = -1; /* Stop: when to close gates after vacuum off */

static void auto_key(char *buf, size_t n, int idx)
{
    snprintf(buf, n, "zb%d_auto", idx);
}

uint8_t modulus_zb_auto_get(int idx)
{
    char k[16];
    auto_key(k, sizeof(k), idx);
    uint8_t v = modulus_nvs_get_u8(k, MODULUS_ZB_AUTO_OFF);
    return v > MODULUS_ZB_AUTO_INVERSE ? MODULUS_ZB_AUTO_OFF : v;
}

void modulus_zb_auto_set(int idx, uint8_t mode)
{
    char k[16];
    auto_key(k, sizeof(k), idx);
    modulus_nvs_set_u8(k, mode > MODULUS_ZB_AUTO_INVERSE ? MODULUS_ZB_AUTO_OFF : mode);
}

const char *modulus_zb_auto_mode_text(uint8_t mode)
{
    switch (mode) {
    case MODULUS_ZB_AUTO_FOLLOW:
        return "On while CNC runs";
    case MODULUS_ZB_AUTO_INVERSE:
        return "Off while CNC runs";
    default:
        return "Manual";
    }
}

static int64_t off_delay_us(void)
{
    uint8_t s = modulus_nvs_get_u8("zb_off_s", 10);
    if (s > 120) {
        s = 120;
    }
    return (int64_t)s * 1000LL * 1000LL;
}

static void drive_device(int i, bool cnc_active, uint8_t lvl_on, uint16_t cct_on, int which)
{
    const uint8_t mode = modulus_zb_auto_get(i);
    if (mode == MODULUS_ZB_AUTO_OFF) {
        return;
    }
    modulus_zb_device_t d = {};
    if (!modulus_wireless_zigbee_device_get(i, &d) || d.short_addr == 0) {
        return;
    }
    if ((d.caps & ZIGBEE_CAP_SENSOR) && !(d.caps & (ZIGBEE_CAP_ONOFF | ZIGBEE_CAP_COVER))) {
        return;
    }
    const bool want_on = (mode == MODULUS_ZB_AUTO_FOLLOW) ? cnc_active : !cnc_active;
    const bool is_cover = (d.caps & ZIGBEE_CAP_COVER) != 0;

    if (is_cover) {
        if (which == DRIVE_SWITCH) {
            return;
        }
        (void)modulus_wireless_zb_cover(&d, want_on ? 0 : 1);
        return;
    }
    if (which == DRIVE_COVER) {
        return;
    }
    if (d.on != want_on) {
        if (modulus_wireless_zb_set_onoff(&d, want_on)) {
            ESP_LOGI(TAG, "auto: %s -> %s", d.name, want_on ? "ON" : "OFF");
        }
    }
    if (want_on && (d.caps & ZIGBEE_CAP_LEVEL)) {
        (void)modulus_wireless_zb_set_level(&d, lvl_on);
    }
    if (want_on && (d.caps & ZIGBEE_CAP_COLOR)) {
        (void)modulus_wireless_zb_color(&d, 0, cct_on, 5);
    }
}

static void auto_apply_which(bool cnc_active, uint8_t lvl_on, uint16_t cct_on, int which)
{
    if (!modulus_wireless_zigbee_can_control()) {
        return;
    }
    const int n = modulus_wireless_zigbee_device_count();
    for (int i = 0; i < n; i++) {
        drive_device(i, cnc_active, lvl_on, cct_on, which);
    }
}

static void auto_apply(bool cnc_active, uint8_t lvl_on, uint16_t cct_on)
{
    auto_apply_which(cnc_active, lvl_on, cct_on, DRIVE_ALL);
}

static void force_all_off(void)
{
    s_vac_arm_us = -1;
    s_gate_close_us = -1;
    if (!modulus_wireless_zigbee_can_control()) {
        return;
    }
    const int n = modulus_wireless_zigbee_device_count();
    for (int i = 0; i < n; i++) {
        modulus_zb_device_t d = {};
        if (!modulus_wireless_zigbee_device_get(i, &d) || d.short_addr == 0) {
            continue;
        }
        if (d.caps & ZIGBEE_CAP_COVER) {
            (void)modulus_wireless_zb_cover(&d, 1);
        } else if (d.caps == 0 || (d.caps & ZIGBEE_CAP_ONOFF)) {
            (void)modulus_wireless_zb_set_onoff(&d, false);
        }
    }
    ESP_LOGW(TAG, "hard-off");
}

void modulus_zb_scene_apply(uint8_t scene)
{
    const int64_t now = esp_timer_get_time();
    switch (scene) {
    case MODULUS_ZB_SCENE_EMERGENCY:
        force_all_off();
        s_pwr_warn[0] = '\0';
        s_clog_idx = -1;
        break;
    case MODULUS_ZB_SCENE_CUT:
        /* Gate first, vacuum after GATE_LEAD_US (poll + scene path). */
        auto_apply_which(true, LVL_CUT, CCT_CUT, DRIVE_COVER);
        s_vac_arm_us = now + GATE_LEAD_US;
        s_gate_close_us = -1;
        break;
    case MODULUS_ZB_SCENE_CLEANUP:
        auto_apply(true, LVL_CLEAN, CCT_IDLE);
        s_vac_arm_us = -1;
        break;
    case MODULUS_ZB_SCENE_IDLE:
    default:
        auto_apply_which(false, LVL_IDLE, CCT_IDLE, DRIVE_SWITCH);
        s_vac_arm_us = -1;
        s_gate_close_us = now + GATE_LEAD_US;
        if (modulus_wireless_zigbee_can_control()) {
            const int n = modulus_wireless_zigbee_device_count();
            for (int i = 0; i < n; i++) {
                modulus_zb_device_t d = {};
                if (!modulus_wireless_zigbee_device_get(i, &d) || d.short_addr == 0) {
                    continue;
                }
                if ((d.caps & ZIGBEE_CAP_LEVEL) && modulus_zb_auto_get(i) == MODULUS_ZB_AUTO_OFF) {
                    (void)modulus_wireless_zb_set_onoff(&d, true);
                    (void)modulus_wireless_zb_set_level(&d, LVL_IDLE);
                }
            }
        }
        break;
    }
}

bool modulus_zb_door_blocks_cycle(void)
{
    if (modulus_nvs_get_u8("zb_door_il", 1) == 0) {
        return false;
    }
    const int n = modulus_wireless_zigbee_device_count();
    for (int i = 0; i < n; i++) {
        modulus_zb_device_t d = {};
        if (!modulus_wireless_zigbee_device_get(i, &d)) {
            continue;
        }
        if ((d.caps & ZIGBEE_CAP_SENSOR) && d.zone_seen && (d.zone_status & 0x0001u)) {
            return true;
        }
    }
    return false;
}

const char *modulus_zb_power_warn_text(void)
{
    return s_pwr_warn[0] ? s_pwr_warn : NULL;
}

int modulus_zb_clog_device_idx(void)
{
    return s_clog_idx;
}

void modulus_zb_job_complete(void)
{
    modulus_audio_play_ui(MODULUS_UI_SOUND_CHIRP);
    modulus_zb_scene_apply(MODULUS_ZB_SCENE_IDLE);
    modulus_ui_snackbar_show("Job complete", 2800);
    ESP_LOGI(TAG, "job complete -> Idle scene");
}

static void pwr_sample_run(void)
{
    const int16_t recipe_base = modulus_recipe_clog_base_raw();
    const int n = modulus_wireless_zigbee_device_count();
    for (int i = 0; i < n && i < MODULUS_ZB_MAX_DEVICES; i++) {
        if (modulus_zb_auto_get(i) != MODULUS_ZB_AUTO_FOLLOW) {
            continue;
        }
        modulus_zb_device_t d = {};
        if (!modulus_wireless_zigbee_device_get(i, &d)) {
            continue;
        }
        if ((d.caps & ZIGBEE_CAP_COVER) || !(d.caps & (ZIGBEE_CAP_POWER | ZIGBEE_CAP_METER)) ||
            !(d.sensors_seen & 0x04)) {
            continue;
        }
        if (s_pwr_base[i] < d.power_raw) {
            s_pwr_base[i] = d.power_raw;
        }
        /* Prefer recipe baseline; else peak seen this RUN. */
        int16_t base = recipe_base > 0 ? recipe_base : s_pwr_base[i];
        if (s_pwr_base[i] > base) {
            base = s_pwr_base[i];
        }
        if (base >= 50 && d.power_raw < (base * 3) / 10) {
            snprintf(s_pwr_warn, sizeof(s_pwr_warn), "Vacuum weak? %s (%.0fW)", d.name,
                     d.power_raw / 10.0);
            s_clog_idx = i;
            ESP_LOGW(TAG, "%s", s_pwr_warn);
        }
    }
    if (++s_sensor_tick >= 5) {
        s_sensor_tick = 0;
        for (int i = 0; i < n; i++) {
            modulus_zb_device_t d = {};
            if (!modulus_wireless_zigbee_device_get(i, &d)) {
                continue;
            }
            if (d.caps & (ZIGBEE_CAP_POWER | ZIGBEE_CAP_METER)) {
                (void)modulus_wireless_zigbee_device_read_sensors(i);
            }
        }
    }
}

void modulus_zb_auto_poll(void)
{
    static int64_t s_next_us;
    static bool s_last_active;
    static int64_t s_stop_seen_us = -1;
    static bool s_job_armed;
    static float s_job_peak_pct;

    const int64_t now = esp_timer_get_time();
    if (now < s_next_us) {
        return;
    }
    s_next_us = now + AUTO_POLL_US;

    /* Deferred vacuum ON after gate open. */
    if (s_vac_arm_us >= 0 && now >= s_vac_arm_us) {
        s_vac_arm_us = -1;
        auto_apply_which(true, LVL_CUT, CCT_CUT, DRIVE_SWITCH);
    }
    /* Deferred gate close after vacuum off. */
    if (s_gate_close_us >= 0 && now >= s_gate_close_us) {
        s_gate_close_us = -1;
        auto_apply_which(false, LVL_IDLE, CCT_IDLE, DRIVE_COVER);
    }

    modulus_cnc_status_t st = {};
    modulus_zig_fill_cnc_status(&st);

    if (!st.connected || st.state == K_STATE_ALARM || st.state == K_STATE_DOOR) {
        if (s_last_active || s_stop_seen_us >= 0) {
            s_last_active = false;
            s_stop_seen_us = -1;
            s_job_armed = false;
            force_all_off();
            memset(s_pwr_base, 0, sizeof(s_pwr_base));
            s_pwr_warn[0] = '\0';
            s_clog_idx = -1;
        }
        return;
    }

    const bool run_now = st.state == K_STATE_RUN;
    const bool hold_now = st.state == K_STATE_HOLD;

    if (run_now || hold_now) {
        s_stop_seen_us = -1;
        if (st.sd_percent > 1.f || st.sd_streaming || st.sd_file[0]) {
            s_job_armed = true;
            if (st.sd_percent > s_job_peak_pct) {
                s_job_peak_pct = st.sd_percent;
            }
        }
        if (!s_last_active) {
            s_last_active = true;
            memset(s_pwr_base, 0, sizeof(s_pwr_base));
            s_pwr_warn[0] = '\0';
            s_clog_idx = -1;
            /* Ordered Cut: gates now, vacuums after 500 ms. */
            auto_apply_which(true, LVL_CUT, CCT_CUT, DRIVE_COVER);
            s_vac_arm_us = now + GATE_LEAD_US;
            s_gate_close_us = -1;
        }
        if (run_now) {
            pwr_sample_run();
        }
        return;
    }

    if (!s_last_active) {
        return;
    }
    if (s_stop_seen_us < 0) {
        s_stop_seen_us = now;
        if (s_job_armed && s_job_peak_pct >= 99.0f) {
            modulus_zb_job_complete();
            s_job_armed = false;
            s_job_peak_pct = 0.f;
            s_last_active = false;
            s_stop_seen_us = -1;
            memset(s_pwr_base, 0, sizeof(s_pwr_base));
            s_pwr_warn[0] = '\0';
            s_clog_idx = -1;
        }
        return;
    }
    if (now - s_stop_seen_us >= off_delay_us()) {
        s_last_active = false;
        s_stop_seen_us = -1;
        /* Vacuum/switches off first; gate closes GATE_LEAD later. */
        auto_apply_which(false, LVL_IDLE, CCT_IDLE, DRIVE_SWITCH);
        s_vac_arm_us = -1;
        s_gate_close_us = now + GATE_LEAD_US;
        memset(s_pwr_base, 0, sizeof(s_pwr_base));
        if (s_job_armed) {
            /* Incomplete % still gets Idle when run-on ends. */
            modulus_zb_scene_apply(MODULUS_ZB_SCENE_IDLE);
            s_job_armed = false;
            s_job_peak_pct = 0.f;
        }
        s_pwr_warn[0] = '\0';
        s_clog_idx = -1;
    }
}

void modulus_zb_auto_on_remove(int removed_idx, int new_count)
{
    for (int i = removed_idx; i < new_count; i++) {
        modulus_zb_auto_set(i, modulus_zb_auto_get(i + 1));
    }
    modulus_zb_auto_set(new_count, MODULUS_ZB_AUTO_OFF);
    if (s_clog_idx == removed_idx) {
        s_clog_idx = -1;
    } else if (s_clog_idx > removed_idx) {
        s_clog_idx--;
    }
}

void modulus_zb_auto_clear_all(int old_count)
{
    for (int i = 0; i < old_count; i++) {
        modulus_zb_auto_set(i, MODULUS_ZB_AUTO_OFF);
    }
    s_clog_idx = -1;
}

static void zb_auto_task(void *arg)
{
    (void)arg;
    for (;;) {
        modulus_zb_auto_poll();
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}

void modulus_zb_auto_start_task(void)
{
    static bool started;
    if (started) {
        return;
    }
    started = true;
    /* Core 0, low priority — UART ACK waits on zb_uart_cmd (Core 1), not here. */
    (void)xTaskCreatePinnedToCore(zb_auto_task, "zb_auto", 4096, NULL, 2, NULL, 0);
    ESP_LOGI(TAG, "always-on automation task started");
}
