#include "ui_power_menu_priv.h"
#include "cnc_cmd_exports.h"
#include "power_shim.h"

#include <esp_system.h>

static lv_obj_t *s_confirm = NULL;
static pwr_confirm_kind_t s_confirm_kind = PWR_CONFIRM_RESTART;

static void confirm_exit_ready(lv_anim_t *a)
{
    lv_obj_t *dlg = lv_anim_get_user_data(a);
    if (dlg) {
        lv_obj_delete(dlg);
    }
}

void modulus_pwr_hide_confirm(void)
{
    if (!s_confirm) {
        return;
    }
    lv_obj_t *dlg = s_confirm;
    s_confirm = NULL;
    lv_obj_t *card = lv_obj_get_child(dlg, 0);
    if (card && modulus_ui_motion_smooth()) {
        modulus_ui_motion_dialog_exit(card, confirm_exit_ready, dlg);
        return;
    }
    lv_obj_delete(dlg);
}

static void confirm_cancel_cb(lv_event_t *e)
{
    (void)e;
    modulus_pwr_hide_confirm();
}

static void confirm_yes_cb(lv_event_t *e)
{
    (void)e;
    const pwr_confirm_kind_t kind = s_confirm_kind;
    modulus_pwr_hide_confirm();
    modulus_ui_hide_power_menu();
    switch (kind) {
        case PWR_CONFIRM_RESTART:  modulus_power_request(true);  break;
        case PWR_CONFIRM_SHUTDOWN: modulus_power_request(false); break;
    }
}

void modulus_pwr_show_confirm(pwr_confirm_kind_t kind, const char *title,
                              const char *body, const char *confirm_label,
                              bool destructive)
{
    modulus_pwr_hide_confirm();
    s_confirm_kind = kind;

    s_confirm = modulus_ui_dialog_scrim_create();

    lv_obj_t *card = modulus_ui_dialog_card_create(s_confirm, MOD_UI_DIALOG_W_COMPACT, 0);
    lv_obj_center(card);
    lv_obj_set_flex_align(card, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);

    lv_obj_t *icon = modulus_ui_icon_create(card, MOD_UI_ICON_POWER, MOD_UI_ICON_SZ_24);
    modulus_ui_icon_recolor(icon, destructive ? modulus_ui_color_error()
                                              : modulus_ui_color_primary());

    modulus_ui_dialog_header(card, title, confirm_cancel_cb, NULL);
    lv_obj_t *msg = modulus_ui_dialog_supporting(card, body);
    lv_obj_set_style_text_align(msg, LV_TEXT_ALIGN_CENTER, 0);

    lv_obj_t *row = modulus_ui_dialog_actions(card, false);
    modulus_ui_dialog_action_btn(row, "Cancel", MOD_UI_DIALOG_BTN_TONAL, confirm_cancel_cb, NULL);
    modulus_ui_dialog_action_btn(row, confirm_label,
                                 destructive ? MOD_UI_DIALOG_BTN_DESTRUCTIVE
                                             : MOD_UI_DIALOG_BTN_FILLED,
                                 confirm_yes_cb, NULL);

    modulus_ui_dialog_scrim_bind_dismiss(s_confirm, confirm_cancel_cb, NULL);
    modulus_ui_motion_dialog_enter(card);
}
