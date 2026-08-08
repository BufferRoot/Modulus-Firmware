#include "ui_settings_modals_priv.h"
#include "ui_settings_modal_kb.h"
#include "ui_settings_common.h"
#include "ui_settings_priv.h"
#include "ui_internal.h"
#include "ui_touch_sound.h"
#include "nvs_shim.h"
#include "security_shim.h"
#include "audio_shim.h"
#include "cnc_cmd_exports.h"
#include "ui_quick_grid.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MACH_NAME_MAX_LEN 31

static lv_obj_t *s_mach_name_modal = NULL;
static lv_obj_t *s_mach_name_ta = NULL;
static lv_obj_t *s_mach_name_kb = NULL;

void settings_mach_name_modal_hide(void)
{
    if (!s_mach_name_modal) {
        s_mach_name_ta = NULL;
        s_mach_name_kb = NULL;
        return;
    }
    s_mach_name_ta = NULL;
    s_mach_name_kb = NULL;
    modulus_ui_dialog_scrim_hide_animated(&s_mach_name_modal);
}

static void mach_name_close_cb(lv_event_t *e)
{
    (void)e;
    settings_mach_name_modal_hide();
}

static void mach_name_sanitize(char *dst, size_t dst_len, const char *src)
{
    size_t j = 0;
    const size_t limit = (MACH_NAME_MAX_LEN < dst_len - 1) ? MACH_NAME_MAX_LEN : dst_len - 1;
    for (size_t i = 0; src[i] && j < limit; i++) {
        const unsigned char c = (unsigned char)src[i];
        if (c >= 0x20 && c <= 0x7E) {
            dst[j++] = (char)c;
        }
    }
    dst[j] = '\0';
}

static void mach_name_save_cb(lv_event_t *e)
{
    (void)e;
    if (!s_mach_name_ta) {
        return;
    }
    char buf[32];
    mach_name_sanitize(buf, sizeof(buf), lv_textarea_get_text(s_mach_name_ta));
    modulus_nvs_set_str("mach_name", buf);
    settings_mach_name_modal_hide();
    modulus_ui_snackbar_show("Machine name saved", 2000);
    modulus_ui_settings_build_machine_tab();
}

static void mach_name_ta_focus_cb(lv_event_t *e)
{
    if (s_mach_name_kb) {
        lv_keyboard_set_textarea(s_mach_name_kb, lv_event_get_target(e));
    }
}

void settings_mach_name_modal_show(void)
{
    settings_mach_name_modal_hide();

    char buf[32];
    if (!modulus_nvs_get_str("mach_name", buf, sizeof(buf))) {
        strncpy(buf, "My CNC", sizeof(buf) - 1);
        buf[sizeof(buf) - 1] = '\0';
    }

    s_mach_name_modal = modulus_ui_dialog_scrim_create();

    lv_obj_t *card = modulus_ui_dialog_card_create(s_mach_name_modal, MOD_UI_DIALOG_W_STANDARD, 0);
    lv_obj_align(card, LV_ALIGN_TOP_MID, 0, 40);
    modulus_ui_motion_dialog_enter(card);

    modulus_ui_dialog_header(card, "Machine name", mach_name_close_cb, NULL);
    modulus_ui_dialog_supporting(card, "ASCII only, up to 31 characters.");
    modulus_ui_dialog_scrim_bind_dismiss(s_mach_name_modal, mach_name_close_cb, NULL);

    s_mach_name_ta = lv_textarea_create(card);
    lv_textarea_set_text(s_mach_name_ta, buf);
    lv_textarea_set_one_line(s_mach_name_ta, true);
    lv_textarea_set_max_length(s_mach_name_ta, MACH_NAME_MAX_LEN);
    lv_obj_set_width(s_mach_name_ta, lv_pct(100));
    modulus_ui_apply_textarea_theme(s_mach_name_ta, false);
    lv_obj_add_event_cb(s_mach_name_ta, mach_name_ta_focus_cb, LV_EVENT_FOCUSED, NULL);

    lv_obj_t *row = modulus_ui_dialog_actions(card, true);
    modulus_ui_dialog_action_btn(row, "Cancel", MOD_UI_DIALOG_BTN_TONAL, mach_name_close_cb, NULL);
    modulus_ui_dialog_action_btn(row, "Save", MOD_UI_DIALOG_BTN_FILLED, mach_name_save_cb, NULL);

    s_mach_name_kb = lv_keyboard_create(s_mach_name_modal);
    lv_keyboard_set_mode(s_mach_name_kb, LV_KEYBOARD_MODE_TEXT_LOWER);
    settings_modal_kb_configure_text(s_mach_name_kb);
    lv_keyboard_set_textarea(s_mach_name_kb, s_mach_name_ta);
}

void settings_mach_name_modal_theme_refresh(void)
{
    if (s_mach_name_kb) {
        modulus_ui_apply_keyboard_theme(s_mach_name_kb);
    }
    if (s_mach_name_ta) {
        modulus_ui_apply_textarea_theme(s_mach_name_ta, false);
    }
    modulus_ui_dialog_theme_refresh(s_mach_name_modal);
}
