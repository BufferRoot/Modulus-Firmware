#include <stdint.h>
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_system.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "wireless_shim.h"
#include "ui_cnc_profiles.h"
#include "modulus_zig.h"

static const char *TAG = "modulus_tab5";

/* Radio work reboots the P4 while the C6 keeps running, so the C6 log only ever
 * shows a fresh SDIO handshake. This names the cause on the very next boot. */
static void log_reset_reason(void)
{
    const esp_reset_reason_t reason = esp_reset_reason();
    const char *name;
    bool abnormal = true;
    switch (reason) {
    case ESP_RST_POWERON:   name = "power-on";              abnormal = false; break;
    case ESP_RST_EXT:       name = "external reset pin";    abnormal = false; break;
    case ESP_RST_SW:        name = "esp_restart()";         abnormal = false; break;
    case ESP_RST_DEEPSLEEP: name = "deep-sleep wake";       abnormal = false; break;
    case ESP_RST_PANIC:     name = "PANIC / CPU exception"; break;
    case ESP_RST_INT_WDT:   name = "INTERRUPT watchdog";    break;
    case ESP_RST_TASK_WDT:  name = "TASK watchdog";         break;
    case ESP_RST_WDT:       name = "other watchdog";        break;
    case ESP_RST_BROWNOUT:  name = "BROWNOUT (power rail sag)"; break;
    case ESP_RST_SDIO:      name = "SDIO reset";            break;
    case ESP_RST_USB:       name = "USB serial (monitor)";  abnormal = false; break;
    case ESP_RST_JTAG:      name = "JTAG";                  abnormal = false; break;
    default:                name = "unknown";               break;
    }
    if (abnormal) {
        ESP_LOGE(TAG, "Reset reason: %s (%d) — last boot ended abnormally; "
                      "run 'idf.py coredump-info' for the backtrace",
                 name, (int)reason);
    } else {
        ESP_LOGI(TAG, "Reset reason: %s (%d)", name, (int)reason);
    }
}

void app_main(void)
{
    log_reset_reason();
    ESP_LOGI(TAG, "Modulus Zig %s (ABI epoch %lu)", modulus_zig_version(),
             (unsigned long)modulus_zig_abi_epoch());
    modulus_zig_boot();
    if (!modulus_zig_boot_ok()) {
        ESP_LOGE(TAG, "Zig runtime boot failed — restarting in 2 s");
        vTaskDelay(pdMS_TO_TICKS(2000));
        esp_restart();
    }
    /* Last-used connection profile (F5) — apply before transport settles. */
    modulus_ui_cnc_profile_boot_apply();
    modulus_zig_transport_reinit();
    if (!modulus_zig_event_dispatch_spawned()) {
        ESP_LOGE(TAG, "Core 0 evt_dispatch spawn failed — restarting in 2 s");
        vTaskDelay(pdMS_TO_TICKS(2000));
        esp_restart();
    }
    if (!modulus_zig_system_task_spawned()) {
        ESP_LOGE(TAG, "Core 1 sys_task spawn failed — restarting in 2 s");
        vTaskDelay(pdMS_TO_TICKS(2000));
        esp_restart();
    }
    if (!modulus_wireless_ready()) {
        ESP_LOGW(TAG, "Wireless not ready — reflash C6 slave on COM18 if SDIO fails");
    }
    ESP_LOGI(TAG, "Core 0 evt_dispatch + Core 1 sys_task running");

    /* Return: ESP-IDF deletes the main task on app_main exit, reclaiming its
     * stack (~4 KiB internal RAM) and its 1 Hz wakeup. Core 0 UI runs on
     * taskLVGL; sys_task owns CNC poll on Core 1. */
}
