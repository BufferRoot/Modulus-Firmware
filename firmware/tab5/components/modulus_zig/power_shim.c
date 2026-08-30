/*
 * Power shim — deep-sleep monitor + graceful PMIC shutdown (C++ hal_power parity).
 */
#include "power_shim.h"
#include "battery_shim.h"
#include "audio_shim.h"
#include "cnc_cmd_exports.h"
#include "display_shim.h"
#include "event_shim.h"
#include "ext_encoder_shim.h"
#include "estop_gpio_shim.h"
#include "nvs_shim.h"
#include "tab5_pi4ioe.h"
#include "touch_shim.h"
#include "wakeup_shim.h"
#include "wireless_shim.h"

#include <bsp/m5stack_tab5.h>
#include <esp_log.h>
#include <esp_lvgl_port.h>
#include <esp_system.h>
#include <esp_timer.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <lvgl.h>

static const char *TAG = "modulus_power";

extern void modulus_zig_enter_deep_sleep(void);
extern void modulus_zig_wake_from_deep_sleep(void);
extern void modulus_zig_transport_reinit(void);

static uint8_t s_sleep_mode = 0;
static uint16_t s_deep_sleep_to = 120;

static bool s_deep_sleeping = false;
static bool s_sleep_task_running = false;
static TaskHandle_t s_sleep_task = NULL;

static bool s_gate_wifi = true;
static bool s_gate_ext5v = true;
static bool s_gate_usb5v = false;
static uint8_t s_wake_sources = 0x01;
static uint16_t s_wake_timer_min = 0;

static bool s_power_action_running = false;
static bool s_reboot_after = false;

static void power_wake_from_deep_sleep(void);
static void deep_sleep_worker(void *arg);
static void deep_sleep_worker_impl(void);
static void power_down_worker(void *arg);

/* Called from the display_shim esp_timer with the authoritative inactivity
 * figure (LVGL's when LVGL owns the panel, the shim's monotonic counter when
 * the Zig engine does). Was an lv_timer reading lv_display_get_inactive_time,
 * which lvgl_port_stop() left frozen under the Zig UI engine. */
void modulus_power_poll_deep_sleep(uint32_t inactive_ms)
{
    if (!modulus_display_is_sleeping()) {
        return;
    }
    if (modulus_display_wake_hold_active()) {
        return;
    }
    if (s_sleep_mode != 1 || s_deep_sleep_to == 0) {
        return;
    }
    if (s_deep_sleeping || s_sleep_task_running) {
        return;
    }

    const uint32_t thresh_ms = (uint32_t)s_deep_sleep_to * 1000U;
    if (inactive_ms >= thresh_ms) {
        ESP_LOGI(TAG, "Display idle %lu ms >= %lu ms — deep sleep",
                 (unsigned long)inactive_ms, (unsigned long)thresh_ms);
        modulus_power_enter_deep_sleep();
    }
}

void modulus_power_set_ext5v(bool en)
{
    (void)tab5_pi4ioe_ensure_init();
    tab5_pi4ioe_set_ext_5v_en(en);
    modulus_nvs_set_u8("ext5v", en ? 1 : 0);
    modulus_ext_encoder_notify_ext5v(en);
}

void modulus_power_set_usb5v(bool en)
{
    (void)tab5_pi4ioe_ensure_init();
    tab5_pi4ioe_set_usb_5v_en(en);
    modulus_nvs_set_u8("usb5v", en ? 1 : 0);
}

void modulus_power_set_charge_en(bool en)
{
    (void)tab5_pi4ioe_ensure_init();
    tab5_pi4ioe_set_charge_en(en);
    modulus_battery_set_charge_en(en);
    modulus_nvs_set_u8("chg_en", en ? 1 : 0);
}

void modulus_power_set_quick_charge(bool en)
{
    (void)tab5_pi4ioe_ensure_init();
    tab5_pi4ioe_set_charge_qc_en(en);
    modulus_nvs_set_u8("qc", en ? 1 : 0);
    ESP_LOGI(TAG, "Quick charge QC -> %u", en ? 1U : 0U);
}

void modulus_power_set_wake_sources(uint8_t wake)
{
    s_wake_sources = wake;
}

void modulus_power_set_wake_timer_min(uint16_t min)
{
    s_wake_timer_min = min;
}

void modulus_power_set_gate_wifi(bool en)
{
    s_gate_wifi = en;
}

void modulus_power_set_gate_ext5v(bool en)
{
    s_gate_ext5v = en;
}

void modulus_power_set_gate_usb5v(bool en)
{
    s_gate_usb5v = en;
}

void modulus_power_apply_rails(void)
{
    if (!tab5_pi4ioe_ensure_init()) {
        ESP_LOGW(TAG, "PI4IOE not ready — rail NVS deferred");
        return;
    }
    const bool ext5v = modulus_nvs_get_u8("ext5v", 1) != 0;
    const bool usb5v = modulus_nvs_get_u8("usb5v", 1) != 0;
    const bool chg = modulus_nvs_get_u8("chg_en", 1) != 0;
    const bool qc = modulus_nvs_get_u8("qc", 1) != 0;
    tab5_pi4ioe_set_ext_5v_en(ext5v);
    tab5_pi4ioe_set_usb_5v_en(usb5v);
    tab5_pi4ioe_set_charge_en(chg);
    tab5_pi4ioe_set_charge_qc_en(qc);
    modulus_battery_set_charge_en(chg);
    if (ext5v) {
        modulus_ext_encoder_notify_ext5v(true);
    }
    ESP_LOGI(TAG, "Rails applied ext5v=%u usb5v=%u chg_en=%u qc=%u",
             ext5v ? 1U : 0U, usb5v ? 1U : 0U, chg ? 1U : 0U, qc ? 1U : 0U);
}

void modulus_power_init(void)
{
    s_sleep_mode = modulus_nvs_get_u8("pwr_mode", 0);
    s_deep_sleep_to = modulus_nvs_get_u16("pwr_dsto", 120);
    s_wake_sources = modulus_nvs_get_u8("pwr_wake", 0x01);
    s_wake_timer_min = modulus_nvs_get_u16("pwr_wtmin", 0);
    s_gate_wifi = modulus_nvs_get_u8("pwr_gwifi", 1) != 0;
    s_gate_ext5v = modulus_nvs_get_u8("pwr_gext", 1) != 0;
    s_gate_usb5v = modulus_nvs_get_u8("pwr_gusb", 0) != 0;

    modulus_power_apply_rails();
    modulus_wakeup_init();

    /* No timer to create — display_shim's activity esp_timer polls us. */

    ESP_LOGI(TAG, "Power init mode=%u ds_to=%us", s_sleep_mode, s_deep_sleep_to);
}

bool modulus_power_is_deep_sleeping(void)
{
    return s_deep_sleeping;
}

void modulus_power_enter_deep_sleep(void)
{
    if (s_deep_sleeping || s_sleep_task_running) {
        return;
    }
    if (xTaskCreate(deep_sleep_worker, "pwr_sleep", 4096, NULL, 5, &s_sleep_task) != pdPASS) {
        ESP_LOGE(TAG, "Failed to spawn deep sleep worker task");
        s_sleep_task = NULL;
    }
}

static void deep_sleep_worker(void *arg)
{
    (void)arg;
    s_sleep_task_running = true;
    deep_sleep_worker_impl();
    s_sleep_task_running = false;
    s_sleep_task = NULL;
    vTaskDelete(NULL);
}

static void deep_sleep_worker_impl(void)
{
    if (s_deep_sleeping) {
        return;
    }
    s_deep_sleeping = true;
    ESP_LOGI(TAG, ">>> Entering deep sleep (worker)");

    const uint8_t wake = modulus_nvs_get_u8("pwr_wake", 0x01);
    s_wake_sources = wake;
    s_wake_timer_min = modulus_nvs_get_u16("pwr_wtmin", 0);
    s_gate_wifi = modulus_nvs_get_u8("pwr_gwifi", 1) != 0;
    s_gate_ext5v = modulus_nvs_get_u8("pwr_gext", 1) != 0;
    s_gate_usb5v = modulus_nvs_get_u8("pwr_gusb", 0) != 0;
    const bool rtc_timer = (wake & 0x02) != 0 && s_wake_timer_min > 0;
    const bool motion_wake = modulus_nvs_get_u8("wake_motion", 0) != 0;
    const bool usb_was_charging = tab5_pi4ioe_get_charge_status();
    /* Soft sleep: touch/USB/timer polled below. BMI270 E_TRG uses Display→Wake on motion. */
    modulus_wakeup_arm(motion_wake, rtc_timer);
    modulus_audio_stop();
    modulus_display_backlight_off();

    modulus_zig_enter_deep_sleep();
    vTaskDelay(pdMS_TO_TICKS(50));

    modulus_battery_set_poll_paused(true);

    if (s_gate_wifi && modulus_wireless_ready()) {
        modulus_wireless_prepare_for_sleep();
    }

    const bool ext5v_was_on = modulus_nvs_get_u8("ext5v", 1) != 0;
    const bool usb5v_was_on = modulus_nvs_get_u8("usb5v", 1) != 0;
    if (s_gate_ext5v && ext5v_was_on) {
        tab5_pi4ioe_set_ext_5v_en(false);
    }
    if (s_gate_usb5v && usb5v_was_on) {
        tab5_pi4ioe_set_usb_5v_en(false);
    }

    if (s_gate_wifi) {
        vTaskDelay(pdMS_TO_TICKS(400));
        tab5_pi4ioe_set_wifi_power_en(false);
    }

    ESP_LOGI(TAG, "Peripherals gated, entering sleep loop");

    const uint32_t poll_ms = 100;
    uint32_t elapsed_ms = 0;
    const uint32_t wake_timer_ms = (uint32_t)s_wake_timer_min * 60U * 1000U;

    while (s_deep_sleeping) {
        if ((s_wake_sources & 0x01) != 0 && modulus_touch_poll_pressed()) {
            ESP_LOGI(TAG, "Touch wake detected");
            break;
        }

        if ((s_wake_sources & 0x02) != 0 && wake_timer_ms > 0 && elapsed_ms >= wake_timer_ms) {
            ESP_LOGI(TAG, "Timer wake (%u min)", s_wake_timer_min);
            break;
        }

        if ((s_wake_sources & 0x04) != 0) {
            const bool charging = tab5_pi4ioe_get_charge_status();
            if (charging && !usb_was_charging) {
                ESP_LOGI(TAG, "USB/charge wake detected");
                break;
            }
        }

        vTaskDelay(pdMS_TO_TICKS(poll_ms));
        elapsed_ms += poll_ms;
    }

    power_wake_from_deep_sleep();
}

static void power_wake_from_deep_sleep(void)
{
    if (!s_deep_sleeping) {
        return;
    }
    s_deep_sleeping = false;
    ESP_LOGI(TAG, "<<< Waking from deep sleep");

    modulus_wakeup_disarm();
    modulus_battery_set_poll_paused(false);

    const bool ext5v_was_on = modulus_nvs_get_u8("ext5v", 1) != 0;
    const bool usb5v_was_on = modulus_nvs_get_u8("usb5v", 1) != 0;
    if (s_gate_ext5v && ext5v_was_on) {
        tab5_pi4ioe_set_ext_5v_en(true);
    }
    if (s_gate_usb5v && usb5v_was_on) {
        tab5_pi4ioe_set_usb_5v_en(true);
    }

    bool wifi_wake_ok = true;
    if (s_gate_wifi) {
        tab5_pi4ioe_set_wifi_power_en(true);
        vTaskDelay(pdMS_TO_TICKS(300));
        wifi_wake_ok = modulus_wireless_wake_coprocessor();
        if (!wifi_wake_ok) {
            ESP_LOGE(TAG, "C6 wake failed — skipping transport reinit");
        }
    }

    const uint8_t bright = modulus_nvs_get_u8("bright", 100);
    modulus_display_set_brightness(bright > 0 ? bright : 50);

    if (!s_gate_wifi || wifi_wake_ok) {
        modulus_zig_transport_reinit();
        if (s_gate_wifi) {
            modulus_wireless_restore_settings();
        }
    }

    modulus_ext_encoder_hw_init();
    modulus_estop_gpio_init();
    modulus_zig_wake_from_deep_sleep();
    (void)modulus_event_publish(EVT_SYSTEM_WAKE, NULL, 0);

    ESP_LOGI(TAG, "Peripherals restored, system active");
}

/* Graceful power-down sequencer. Runs on its own task (NOT the LVGL event
 * thread) so the ~5 s of audio-fade + settle delays never block the UI or trip
 * the task WDT. Shared by Restart (reboot=true) and Shutdown (reboot=false). */
static void power_down_worker(void *arg)
{
    (void)arg;
    const bool reboot = s_reboot_after;
    ESP_LOGW(TAG, "%s requested", reboot ? "Restart" : "Shutdown");

    /* Halt machine motion before tearing anything down. */
    modulus_zig_cmd_feed_hold();

    /* Let subsystems quiesce (NVS already commits per-write, nothing to flush). */
    (void)modulus_event_publish(EVT_SYSTEM_SHUTDOWN, NULL, 0);

    if (modulus_nvs_get_u8("snd_dn", 1) != 0) {
        modulus_audio_play_shutdown();
    }
    modulus_display_set_brightness(0);

    int wait = 0;
    while (modulus_audio_is_playing() && wait < 30) {
        vTaskDelay(pdMS_TO_TICKS(100));
        wait++;
    }
    modulus_audio_stop();

    /* Bring the C6/wireless link down cleanly so the next boot does not start
     * mid-SDIO-transaction (avoids H_SDIO_DRV RX-resync / GPIO15 retries). This
     * is the step the old esp_restart() restart path skipped entirely. */
    if (modulus_wireless_ready()) {
        modulus_wireless_prepare_for_sleep();
        vTaskDelay(pdMS_TO_TICKS(50));
    }

    if (reboot) {
        esp_restart();   /* never returns */
    }

    /* True power-off path — arm PMIC E_TRG (motion = Display wake_motion; timer = Power). */
    {
        const uint8_t wake = modulus_nvs_get_u8("pwr_wake", 0x01);
        const bool rtc_timer = (wake & 0x02) != 0 && modulus_nvs_get_u16("pwr_wtmin", 0) > 0;
        const bool motion_wake = modulus_nvs_get_u8("wake_motion", 0) != 0;
        modulus_wakeup_arm(motion_wake, rtc_timer);
    }

    (void)tab5_pi4ioe_ensure_init();
    tab5_pi4ioe_set_ext_5v_en(false);
    tab5_pi4ioe_set_usb_5v_en(false);
    vTaskDelay(pdMS_TO_TICKS(100));

    tab5_pi4ioe_generate_poweroff_signal();

    /* Still alive => external power cannot latch off (USB/bench). Reboot rather
     * than leave the device in a half-gated state. */
    ESP_LOGE(TAG, "Power-off signal sent but still running (external power?) - rebooting");
    vTaskDelay(pdMS_TO_TICKS(2000));
    esp_restart();
}

void modulus_power_request(bool reboot)
{
    if (s_power_action_running) {
        return;   /* debounce double-tap on the confirm dialog */
    }
    s_power_action_running = true;
    s_reboot_after = reboot;
    if (xTaskCreate(power_down_worker, "pwr_down", 4096, NULL, 5, NULL) != pdPASS) {
        ESP_LOGE(TAG, "Failed to spawn power-down worker");
        s_power_action_running = false;
    }
}

void modulus_power_shutdown(void)
{
    modulus_power_request(false);
}

void modulus_power_set_sleep_policy(uint8_t mode, uint16_t dsto_sec)
{
    s_sleep_mode = mode;
    s_deep_sleep_to = dsto_sec;
    /* `mode` is read by modulus_power_poll_deep_sleep on the display timer;
     * nothing to start or stop. */
}
