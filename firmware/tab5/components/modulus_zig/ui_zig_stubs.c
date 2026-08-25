//! Stubs for LVGL UI entry points when CONFIG_MODULUS_ZIG_UI_ENGINE=y.
//! Keeps HAL / zb_automation / main linking without the LVGL widget tree.

#include "sdkconfig.h"

#if CONFIG_MODULUS_ZIG_UI_ENGINE

#include "ui_cnc_profiles.h"
#include "ui_internal.h"
#include "ui_touch_sound.h"

#include <esp_log.h>

static const char *TAG = "ui_zig_stub";

void modulus_ui_theme_apply(void) {}

void modulus_ui_touch_sound_register(void) {}

void modulus_ui_snackbar_show(const char *message, uint32_t duration_ms)
{
    (void)duration_ms;
    if (message && message[0]) {
        ESP_LOGI(TAG, "snack: %s", message);
    }
}

void modulus_ui_snackbar_show_action(const char *message, const char *action_label,
                                     uint32_t duration_ms, lv_event_cb_t action_cb, void *user_data)
{
    (void)action_label;
    (void)duration_ms;
    (void)action_cb;
    (void)user_data;
    modulus_ui_snackbar_show(message, 0);
}

void modulus_ui_snackbar_hide(void) {}

bool modulus_ui_snackbar_is_sticky(void)
{
    return false;
}

void modulus_ui_settings_cnc_on_status_event(void) {}

void modulus_ui_cnc_profiles_modal_show(void) {}

void modulus_ui_cnc_profiles_modal_hide(void) {}

void modulus_ui_cnc_profile_rename_show(uint8_t slot)
{
    (void)slot;
}

void modulus_ui_cnc_profiles_kb_theme_refresh(void) {}

#endif /* CONFIG_MODULUS_ZIG_UI_ENGINE */
