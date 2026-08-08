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


static lv_obj_t *s_grbl_dump_modal = NULL;
static lv_obj_t *s_grbl_dump_ta = NULL;
static lv_obj_t *s_grbl_dump_status = NULL;
static lv_obj_t *s_grbl_dump_prog = NULL;
static lv_timer_t *s_grbl_dump_timer = NULL;
static uint8_t s_grbl_dump_ticks = 0;

void settings_grbl_dump_modal_hide(void);

static void grbl_dump_timer_cb(lv_timer_t *timer)
{
    (void)timer;
    if (!s_grbl_dump_modal || !s_grbl_dump_status) {
        return;
    }
    if (s_grbl_dump_prog && s_grbl_dump_ticks < 95) {
        s_grbl_dump_ticks = (uint8_t)(s_grbl_dump_ticks + 5);
        modulus_ui_linear_progress_set(s_grbl_dump_prog, s_grbl_dump_ticks);
    }
    if (modulus_zig_settings_dump_ready()) {
        /* Heap (CLIB/PSRAM via lv_malloc), NOT stack: an 8 KiB local here on
         * the 16 KiB taskLVGL stack (plus render internals) overflows it. */
        char *buf = (char *)lv_malloc(8192);
        if (!buf) {
            lv_label_set_text(s_grbl_dump_status, "Out of memory");
            return; /* keep timer alive; retry next tick */
        }
        const size_t n = modulus_zig_settings_dump_copy(buf, 8192U - 1U);
        buf[n] = '\0';
        if (s_grbl_dump_ta) {
            lv_textarea_set_text(s_grbl_dump_ta, buf);
            lv_obj_remove_state(s_grbl_dump_ta, LV_STATE_DISABLED);
        }
        lv_free(buf);
        lv_label_set_text(s_grbl_dump_status, n > 0 ? "Controller settings loaded" : "Empty response");
        if (s_grbl_dump_prog) {
            modulus_ui_linear_progress_set(s_grbl_dump_prog, 100);
        }
        if (s_grbl_dump_timer) {
            lv_timer_delete(s_grbl_dump_timer);
            s_grbl_dump_timer = NULL;
        }
    } else if (modulus_zig_settings_dump_failed()) {
        lv_label_set_text(s_grbl_dump_status, "Failed - connect in Idle or buffer full");
        if (s_grbl_dump_timer) {
            lv_timer_delete(s_grbl_dump_timer);
            s_grbl_dump_timer = NULL;
        }
    }
}

static void grbl_dump_close_cb(lv_event_t *e)
{
    (void)e;
    settings_grbl_dump_modal_hide();
}

void settings_grbl_dump_modal_hide(void)
{
    if (s_grbl_dump_timer) {
        lv_timer_delete(s_grbl_dump_timer);
        s_grbl_dump_timer = NULL;
    }
    modulus_zig_settings_dump_cancel();
    if (!s_grbl_dump_modal) {
        s_grbl_dump_ta = NULL;
        s_grbl_dump_status = NULL;
        s_grbl_dump_prog = NULL;
        s_grbl_dump_ticks = 0;
        return;
    }
    s_grbl_dump_ta = NULL;
    s_grbl_dump_status = NULL;
    s_grbl_dump_prog = NULL;
    s_grbl_dump_ticks = 0;
    modulus_ui_dialog_scrim_hide_animated(&s_grbl_dump_modal);
}

void settings_grbl_dump_modal_show(void)
{
    settings_grbl_dump_modal_hide();

    s_grbl_dump_modal = modulus_ui_dialog_scrim_create();

    lv_obj_t *card = modulus_ui_dialog_card_create(s_grbl_dump_modal, MOD_UI_DIALOG_W_XWIDE, 520);
    lv_obj_align(card, LV_ALIGN_CENTER, 0, 0);
    modulus_ui_motion_dialog_enter(card);
    modulus_ui_dialog_scrim_bind_dismiss(s_grbl_dump_modal, grbl_dump_close_cb, NULL);

    modulus_ui_dialog_header(card, "Controller settings ($$)", grbl_dump_close_cb, NULL);

    s_grbl_dump_status = lv_label_create(card);
    lv_label_set_text(s_grbl_dump_status, "Requesting $$ from controller...");
    lv_obj_set_style_text_color(s_grbl_dump_status, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(s_grbl_dump_status, MOD_UI_FONT_BODY_M, 0);

    s_grbl_dump_prog = modulus_ui_linear_progress_create(card);
    s_grbl_dump_ticks = 0;

    s_grbl_dump_ta = lv_textarea_create(card);
    lv_textarea_set_one_line(s_grbl_dump_ta, false);
    lv_obj_set_width(s_grbl_dump_ta, lv_pct(100));
    lv_obj_set_flex_grow(s_grbl_dump_ta, 1);
    lv_textarea_set_text(s_grbl_dump_ta, "");
    modulus_ui_apply_textarea_theme(s_grbl_dump_ta, true);
    lv_obj_add_state(s_grbl_dump_ta, LV_STATE_DISABLED);

    lv_obj_t *row = modulus_ui_dialog_actions(card, true);
    modulus_ui_dialog_action_btn(row, "Close", MOD_UI_DIALOG_BTN_TEXT, grbl_dump_close_cb, NULL);

    modulus_zig_settings_dump_begin();
    s_grbl_dump_timer = lv_timer_create(grbl_dump_timer_cb, 250, NULL);
}

void settings_grbl_dump_modal_theme_refresh(void)
{
    if (s_grbl_dump_ta) {
        modulus_ui_apply_textarea_theme(s_grbl_dump_ta, true);
    }
    if (s_grbl_dump_status) {
        lv_obj_set_style_text_color(s_grbl_dump_status, modulus_ui_color_on_surface_variant(), 0);
    }
    modulus_ui_dialog_theme_refresh(s_grbl_dump_modal);
}

