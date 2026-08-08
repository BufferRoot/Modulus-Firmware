#include "ui_settings_modals_priv.h"
#include "ui_settings_common.h"
#include "ui_settings_priv.h"
#include "ui_internal.h"
#include "security_shim.h"
#include "display_shim.h"
#include "nvs_shim.h"

#include <stdint.h>

static lv_obj_t *s_idle_modal = NULL;
static const uint16_t k_pin_idle_tmo_secs[] = {0, 60, 300, 900, 1800, 3600};

void settings_idle_lock_modal_hide(void)
{
    if (!s_idle_modal) {
        return;
    }
    modulus_ui_dialog_scrim_hide_animated(&s_idle_modal);
}

static void close_cb(lv_event_t *e)
{
    (void)e;
    settings_idle_lock_modal_hide();
    modulus_ui_settings_build_security_tab();
}

static void idle_cb(lv_event_t *e)
{
    if (!modulus_security_has_pin()) {
        return;
    }
    const bool on = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
    if (on && modulus_nvs_get_u16("pin_idle_tmo", 0) == 0) {
        modulus_nvs_set_u16("pin_idle_tmo", 300);
    }
    modulus_nvs_set_u8("pin_idle", on ? 1 : 0);
    modulus_display_refresh_activity_monitor();
}

static void idle_tmo_cb(lv_event_t *e)
{
    if (!modulus_security_has_pin()) {
        return;
    }
    const uint8_t idx = (uint8_t)lv_dropdown_get_selected(lv_event_get_target(e));
    const uint16_t sec = k_pin_idle_tmo_secs[idx < 6 ? idx : 0];
    modulus_nvs_set_u16("pin_idle_tmo", sec);
    if (sec == 0) {
        modulus_nvs_set_u8("pin_idle", 0);
    }
    modulus_display_refresh_activity_monitor();
}

void settings_idle_lock_modal_show(void)
{
    settings_idle_lock_modal_hide();

    s_idle_modal = modulus_ui_dialog_scrim_create();
    lv_obj_t *card = modulus_ui_dialog_card_create(s_idle_modal, MOD_UI_DIALOG_W_STANDARD, 0);
    modulus_ui_motion_dialog_enter(card);

    modulus_ui_dialog_header(card, "Idle lock", close_cb, NULL);
    modulus_ui_dialog_supporting(card, "Lock when display stays on and idle.");
    modulus_ui_dialog_scrim_bind_dismiss(s_idle_modal, close_cb, NULL);

    lv_obj_t *body = lv_obj_create(card);
    lv_obj_remove_style_all(body);
    lv_obj_set_width(body, lv_pct(100));
    lv_obj_set_height(body, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(body, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(body, MOD_UI_SPACE_SM, 0);
    settings_no_scroll(body);

    const bool has_pin = modulus_security_has_pin();
    lv_obj_t *idle = settings_toggle_row(body, "Lock when idle",
                                         modulus_nvs_get_u8("pin_idle", 0) != 0);
    lv_obj_t *idle_row = lv_obj_get_parent(idle);
    lv_obj_add_event_cb(idle, idle_cb, LV_EVENT_VALUE_CHANGED, NULL);

    uint16_t cur = modulus_nvs_get_u16("pin_idle_tmo", 0);
    uint8_t idx = 0;
    for (uint8_t i = 0; i < 6; i++) {
        if (k_pin_idle_tmo_secs[i] == cur) {
            idx = i;
            break;
        }
    }
    lv_obj_t *idle_tmo = settings_dropdown_row(body, "Idle timeout",
        "Never\n1 min\n5 min\n15 min\n30 min\n1 hour", idx);
    lv_obj_t *idle_tmo_row = lv_obj_get_parent(idle_tmo);
    lv_obj_add_event_cb(idle_tmo, idle_tmo_cb, LV_EVENT_VALUE_CHANGED, NULL);

    if (!has_pin) {
        modulus_ui_settings_row_set_enabled(idle_row, idle, false);
        modulus_ui_settings_row_set_enabled(idle_tmo_row, idle_tmo, false);
        settings_note(body, "Set a PIN first to enable idle lock.");
    }

    lv_obj_t *row = modulus_ui_dialog_actions(card, true);
    modulus_ui_dialog_action_btn(row, "Done", MOD_UI_DIALOG_BTN_FILLED, close_cb, NULL);
}

void settings_idle_lock_modal_theme_refresh(void)
{
    modulus_ui_dialog_theme_refresh(s_idle_modal);
}
