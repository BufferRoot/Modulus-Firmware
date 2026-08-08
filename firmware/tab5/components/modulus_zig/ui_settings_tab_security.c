#include "ui_settings_priv.h"
#include "ui_settings_common.h"
#include "ui_settings_modals.h"
#include "ui_internal.h"
#include "security_shim.h"
#include "display_shim.h"
#include "nvs_shim.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

static void pin_edit_cb(lv_event_t *e)
{
    (void)e;
    if (modulus_security_has_pin()) {
        settings_pin_modal_show_change();
    } else {
        settings_pin_modal_show_set();
    }
}

static void pin_clear_confirmed(void)
{
    settings_pin_modal_show_clear();
}

static void pin_clear_cb(lv_event_t *e)
{
    (void)e;
    if (!modulus_security_has_pin()) {
        return;
    }
    settings_confirm_show(
        "Clear PIN",
        "Removes PIN and disables boot and wake lock.",
        "Clear",
        true,
        pin_clear_confirmed,
        NULL);
}

static const uint16_t k_pin_tmo_secs[] = {0, 60, 300, 900, 1800, 3600, 65535};

static void sec_set_control_enabled(lv_obj_t *ctrl, lv_obj_t *row, bool enabled)
{
    if (!ctrl && row) {
        modulus_ui_row_set_content_enabled(row, enabled);
        return;
    }
    if (ctrl && row) {
        modulus_ui_settings_row_set_enabled(row, ctrl, enabled);
        return;
    }
    if (row) {
        modulus_ui_row_set_content_enabled(row, enabled);
    }
}

static void sec_sync_policy_controls(lv_obj_t *boot_sw, lv_obj_t *boot_row,
                                     lv_obj_t *slp_sw, lv_obj_t *slp_row,
                                     lv_obj_t *tmo_dd, lv_obj_t *tmo_row,
                                     lv_obj_t *idle_sw, lv_obj_t *idle_row,
                                     lv_obj_t *idle_tmo_dd, lv_obj_t *idle_tmo_row,
                                     lv_obj_t *clear_row, bool has_pin)
{
    sec_set_control_enabled(boot_sw, boot_row, has_pin);
    sec_set_control_enabled(slp_sw, slp_row, has_pin);
    sec_set_control_enabled(tmo_dd, tmo_row, has_pin);
    sec_set_control_enabled(idle_sw, idle_row, has_pin);
    sec_set_control_enabled(idle_tmo_dd, idle_tmo_row, has_pin);
    if (clear_row) {
        modulus_ui_obj_set_disabled_style(clear_row, has_pin);
    }
}

static void pin_tmo_cb(lv_event_t *e)
{
    const uint8_t idx = (uint8_t)lv_dropdown_get_selected(lv_event_get_target(e));
    const uint16_t sec = k_pin_tmo_secs[idx < 7 ? idx : 0];
    modulus_nvs_set_u16("pin_tmo", sec);
    if (sec == 0) {
        modulus_nvs_set_u8("pin_slp", 0);
    }
    modulus_ui_settings_build_security_tab();
}

static void pin_boot_cb(lv_event_t *e)
{
    if (!modulus_security_has_pin()) {
        return;
    }
    const char *key = lv_event_get_user_data(e);
    modulus_nvs_set_u8(key, lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED) ? 1 : 0);
}

static void pin_slp_cb(lv_event_t *e)
{
    if (!modulus_security_has_pin()) {
        return;
    }
    const bool on = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
    bool reb = false;
    if (on && modulus_nvs_get_u16("pin_tmo", 0) == 0) {
        modulus_nvs_set_u16("pin_tmo", 65535);
        reb = true;
    }
    modulus_nvs_set_u8("pin_slp", on ? 1 : 0);
    if (reb) {
        modulus_ui_settings_build_security_tab();
    }
}

static void idle_lock_cfg_cb(lv_event_t *e)
{
    (void)e;
    settings_idle_lock_modal_show();
}

void modulus_ui_settings_build_security_tab(void)
{
    lv_obj_t *p = modulus_ui_settings_tab_panel(MOD_UI_SETTINGS_TAB_SECURITY);
    if (!p) {
        return;
    }
    lv_obj_clean(p);

    const bool has_pin = modulus_security_has_pin();
    const bool locked = modulus_security_is_locked();

    settings_section(p, "Device lock", NULL);
    {
        lv_obj_t *row = settings_row_base(p, 56, false);
        lv_obj_t *left = lv_obj_create(row);
        lv_obj_remove_style_all(left);
        lv_obj_set_size(left, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
        lv_obj_set_flex_flow(left, LV_FLEX_FLOW_COLUMN);
        lv_obj_set_style_pad_row(left, 2, 0);
        settings_no_scroll(left);
        lv_obj_t *cap = lv_label_create(left);
        lv_label_set_text(cap, "Lock status");
        lv_obj_set_style_text_color(cap, modulus_ui_color_on_surface_variant(), 0);
        lv_obj_set_style_text_font(cap, MOD_UI_FONT_BODY_M, 0);
        lv_obj_t *state = lv_label_create(left);
        lv_label_set_text(state, locked ? "Locked" : "Unlocked");
        lv_obj_set_style_text_color(state,
            locked ? modulus_ui_color_warning() : modulus_ui_color_success(), 0);
        lv_obj_set_style_text_font(state, MOD_UI_FONT_BODY_L, 0);

        lv_obj_t *right = lv_obj_create(row);
        lv_obj_remove_style_all(right);
        lv_obj_set_size(right, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
        lv_obj_set_flex_flow(right, LV_FLEX_FLOW_COLUMN);
        lv_obj_set_flex_align(right, LV_FLEX_ALIGN_END, LV_FLEX_ALIGN_CENTER,
                              LV_FLEX_ALIGN_CENTER);
        lv_obj_set_style_pad_row(right, 2, 0);
        settings_no_scroll(right);
        lv_obj_t *pcap = lv_label_create(right);
        lv_label_set_text(pcap, "PIN");
        lv_obj_set_style_text_color(pcap, modulus_ui_color_on_surface_variant(), 0);
        lv_obj_set_style_text_font(pcap, MOD_UI_FONT_BODY_M, 0);
        lv_obj_t *pval = lv_label_create(right);
        lv_label_set_text(pval, has_pin ? "Configured" : "Not set");
        lv_obj_set_style_text_color(pval,
            has_pin ? modulus_ui_color_on_surface() : modulus_ui_color_error(), 0);
        lv_obj_set_style_text_font(pval, MOD_UI_FONT_BODY_L, 0);
    }

    lv_obj_t *pin_row = settings_action_row(p, has_pin ? "Change PIN" : "Set PIN",
                                            has_pin ? "Update" : "Create");
    settings_bind_menu_click(pin_row, pin_edit_cb, NULL);

    lv_obj_t *clr_row = settings_destructive_row(p, "Clear PIN",
                                                 has_pin ? "Remove" : "Not set");
    settings_bind_menu_click(clr_row, pin_clear_cb, NULL);

    settings_section(p, "Auto lock", "After display sleep. Never disables wake lock.");
    uint16_t cur_tmo = modulus_nvs_get_u16("pin_tmo", 0);
    uint8_t tmo_idx = 0;
    for (uint8_t i = 0; i < 7; i++) {
        if (k_pin_tmo_secs[i] == cur_tmo) {
            tmo_idx = i;
            break;
        }
    }
    lv_obj_t *tmo = settings_dropdown_row(p,
        "Lock after sleep",
        "Never\n1 min\n5 min\n15 min\n30 min\n1 hour\nOn sleep",
        tmo_idx);
    lv_obj_t *tmo_row = lv_obj_get_parent(tmo);
    lv_obj_add_event_cb(tmo, pin_tmo_cb, LV_EVENT_VALUE_CHANGED, NULL);

    settings_section(p, "Session policy", NULL);
    lv_obj_t *boot = settings_toggle_row(p, "PIN on boot", modulus_security_lock_on_boot());
    lv_obj_t *boot_row = lv_obj_get_parent(boot);
    lv_obj_add_event_cb(boot, pin_boot_cb, LV_EVENT_VALUE_CHANGED, (void *)"pin_boot");

    lv_obj_t *slp = settings_toggle_row(p, "PIN on wake", modulus_security_lock_on_sleep());
    lv_obj_t *slp_row = lv_obj_get_parent(slp);
    lv_obj_add_event_cb(slp, pin_slp_cb, LV_EVENT_VALUE_CHANGED, (void *)"pin_slp");

    settings_section(p, "Idle lock", "While display stays on.");
    {
        const bool on = modulus_nvs_get_u8("pin_idle", 0) != 0;
        const uint16_t idle_sec = modulus_nvs_get_u16("pin_idle_tmo", 0);
        char detail[40];
        if (!on || idle_sec == 0) {
            snprintf(detail, sizeof(detail), "Off");
        } else if (idle_sec < 60) {
            snprintf(detail, sizeof(detail), "On / %u s", (unsigned)idle_sec);
        } else if (idle_sec < 3600) {
            snprintf(detail, sizeof(detail), "On / %u min", (unsigned)(idle_sec / 60));
        } else {
            snprintf(detail, sizeof(detail), "On / %u h", (unsigned)(idle_sec / 3600));
        }
        lv_obj_t *cfg = settings_action_row(p, "Configure idle lock", detail);
        settings_bind_menu_click(cfg, idle_lock_cfg_cb, NULL);
        if (!has_pin) {
            modulus_ui_obj_set_disabled_style(cfg, false);
        }
    }

    /* Keep session/auto-lock controls enabled via helper (idle moved to modal). */
    sec_sync_policy_controls(boot, boot_row, slp, slp_row, tmo, tmo_row,
                             NULL, NULL, NULL, NULL, clr_row, has_pin);

    modulus_ui_settings_note_tab_built(MOD_UI_SETTINGS_TAB_SECURITY);
}

