#include "ui_settings_modals_priv.h"
#include "ui_settings_common.h"
#include "ui_settings_priv.h"
#include "ui_internal.h"
#include "nvs_shim.h"
#include "ui_quick_grid.h"

#include <stdio.h>
#include <string.h>

/* MD3 list-based slot assignment. Never lv_obj_clean from inside a click
 * handler on the object being deleted — defer rebuild one tick. */

#define QBTN_PREVIEW_H 220
#define QBTN_FILTER_ALL 0
#define QBTN_FILTER_BUILTIN 1
#define QBTN_FILTER_CUSTOM 2

static lv_obj_t *s_qbtn_modal = NULL;
static lv_obj_t *s_qbtn_preview = NULL;
static lv_obj_t *s_qbtn_body = NULL;
static int s_pick_slot = -1;
static uint8_t s_filter = QBTN_FILTER_ALL;
static lv_timer_t *s_rebuild_tmr = NULL;

static void qbtn_rebuild_body(void);

static void qbtn_rebuild_cancel(void)
{
    if (s_rebuild_tmr) {
        lv_timer_delete(s_rebuild_tmr);
        s_rebuild_tmr = NULL;
    }
}

static void qbtn_rebuild_timer_cb(lv_timer_t *t)
{
    (void)t;
    s_rebuild_tmr = NULL;
    qbtn_rebuild_body();
}

static void qbtn_rebuild_deferred(void)
{
    if (!s_qbtn_body) {
        return;
    }
    if (s_rebuild_tmr) {
        return;
    }
    s_rebuild_tmr = lv_timer_create(qbtn_rebuild_timer_cb, 1, NULL);
    lv_timer_set_repeat_count(s_rebuild_tmr, 1);
}

static void qbtn_exit_ready(lv_anim_t *a)
{
    lv_obj_t *dlg = lv_anim_get_user_data(a);
    if (dlg) {
        lv_obj_delete(dlg);
    }
    s_qbtn_preview = NULL;
    s_qbtn_body = NULL;
    s_pick_slot = -1;
}

void settings_qbtn_modal_hide(void)
{
    qbtn_rebuild_cancel();
    if (!s_qbtn_modal) {
        s_qbtn_preview = NULL;
        s_qbtn_body = NULL;
        s_pick_slot = -1;
        return;
    }
    lv_obj_t *dlg = s_qbtn_modal;
    s_qbtn_modal = NULL;
    s_qbtn_preview = NULL;
    s_qbtn_body = NULL;
    s_pick_slot = -1;
    lv_obj_t *card = lv_obj_get_child(dlg, 0);
    if (card && modulus_ui_motion_smooth()) {
        modulus_ui_motion_dialog_exit(card, qbtn_exit_ready, dlg);
        return;
    }
    lv_obj_delete(dlg);
}

static void qbtn_close_cb(lv_event_t *e)
{
    (void)e;
    settings_qbtn_modal_hide();
}

static void refresh_qbtn_preview(void)
{
    if (s_qbtn_preview) {
        ui_qbtn_build_preview(s_qbtn_preview, QBTN_PREVIEW_H);
    }
}

static void qbtn_pick_cb(lv_event_t *e)
{
    const uint8_t assign = (uint8_t)(uintptr_t)lv_event_get_user_data(e);
    if (s_pick_slot < 0 || s_pick_slot >= UI_QBTN_MAX_SLOTS) {
        return;
    }
    if (assign >= UI_QBTN_ASSIGN_COUNT) {
        return;
    }
    char key[12];
    snprintf(key, sizeof(key), "cnc_qbtn%d", s_pick_slot);
    modulus_nvs_set_u8(key, assign);
    s_pick_slot = -1;
    qbtn_rebuild_deferred();
    modulus_ui_dashboard_config_changed();
}

static void qbtn_slot_open_cb(lv_event_t *e)
{
    s_pick_slot = (int)(intptr_t)lv_event_get_user_data(e);
    qbtn_rebuild_deferred();
}

static void qbtn_back_cb(lv_event_t *e)
{
    (void)e;
    s_pick_slot = -1;
    qbtn_rebuild_deferred();
}

static void qbtn_filter_cb(lv_event_t *e)
{
    s_filter = (uint8_t)(uintptr_t)lv_event_get_user_data(e);
    qbtn_rebuild_deferred();
}

static void qbtn_swap_slots(int a, int b)
{
    if (a < 0 || b < 0 || a >= UI_QBTN_MAX_SLOTS || b >= UI_QBTN_MAX_SLOTS || a == b) {
        return;
    }
    char ka[12], kb[12];
    snprintf(ka, sizeof(ka), "cnc_qbtn%d", a);
    snprintf(kb, sizeof(kb), "cnc_qbtn%d", b);
    const uint8_t va = ui_qbtn_slot_assign(a);
    const uint8_t vb = ui_qbtn_slot_assign(b);
    modulus_nvs_set_u8(ka, vb);
    modulus_nvs_set_u8(kb, va);
    qbtn_rebuild_deferred();
    modulus_ui_dashboard_config_changed();
}

static void qbtn_move_up_cb(lv_event_t *e)
{
    const int slot = (int)(intptr_t)lv_event_get_user_data(e);
    if (slot > 0) {
        qbtn_swap_slots(slot, slot - 1);
    }
}

static void qbtn_move_down_cb(lv_event_t *e)
{
    const int slot = (int)(intptr_t)lv_event_get_user_data(e);
    if (slot + 1 < UI_QBTN_MAX_SLOTS) {
        qbtn_swap_slots(slot, slot + 1);
    }
}

/** MD3 list item: headline + supporting + trailing check when selected. */
static void qbtn_list_item(lv_obj_t *parent, const char *headline, const char *support,
                           bool selected, lv_event_cb_t cb, void *ud)
{
    lv_obj_t *row = lv_obj_create(parent);
    lv_obj_remove_style_all(row);
    lv_obj_set_size(row, lv_pct(100), LV_SIZE_CONTENT);
    lv_obj_set_style_min_height(row, 56, 0);
    lv_obj_set_style_pad_ver(row, MOD_UI_SPACE_SM, 0);
    lv_obj_set_style_pad_hor(row, MOD_UI_SPACE_SM + MOD_UI_SPACE_XS, 0);
    lv_obj_set_style_radius(row, MOD_UI_SHAPE_MD, 0);
    lv_obj_set_style_bg_color(row, selected ? modulus_ui_color_secondary_container()
                                            : modulus_ui_color_surface_container_high(),
                              0);
    lv_obj_set_style_bg_opa(row, LV_OPA_COVER, 0);
    lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(row, MOD_UI_SPACE_SM + MOD_UI_SPACE_XS, 0);
    lv_obj_add_flag(row, LV_OBJ_FLAG_CLICKABLE);
    modulus_ui_apply_pressed_state_layer(row);
    if (cb) {
        settings_bind_menu_click(row, cb, ud);
    }

    lv_obj_t *col = lv_obj_create(row);
    lv_obj_remove_style_all(col);
    lv_obj_set_flex_grow(col, 1);
    lv_obj_set_height(col, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(col, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(col, 2, 0);

    lv_obj_t *h = lv_label_create(col);
    lv_label_set_text(h, headline);
    lv_obj_set_style_text_font(h, MOD_UI_FONT_BODY_L, 0);
    lv_obj_set_style_text_color(h, selected ? modulus_ui_color_on_secondary_container()
                                            : modulus_ui_color_on_surface(),
                                0);

    if (support && support[0]) {
        lv_obj_t *s = lv_label_create(col);
        lv_label_set_text(s, support);
        lv_obj_set_style_text_font(s, MOD_UI_FONT_LABEL_M, 0);
        lv_obj_set_style_text_color(s, selected ? modulus_ui_color_on_secondary_container()
                                                : modulus_ui_color_on_surface_variant(),
                                    0);
        lv_label_set_long_mode(s, LV_LABEL_LONG_DOT);
        lv_obj_set_width(s, lv_pct(100));
    }

    if (selected) {
        lv_obj_t *chk = modulus_ui_icon_create(row, MOD_UI_ICON_CHECK, MOD_UI_ICON_SZ_24);
        if (chk) {
            modulus_ui_icon_recolor(chk, modulus_ui_color_on_secondary_container());
        }
    }
}

static void qbtn_filter_chip(lv_obj_t *row, const char *label, uint8_t filt)
{
    const bool on = (s_filter == filt);
    lv_obj_t *btn = lv_button_create(row);
    lv_obj_set_height(btn, 36);
    lv_obj_set_style_radius(btn, MOD_UI_SHAPE_FULL, 0);
    lv_obj_set_style_bg_color(btn, on ? modulus_ui_color_secondary_container()
                                      : modulus_ui_color_surface_container_high(),
                              0);
    lv_obj_set_style_pad_hor(btn, 14, 0);
    lv_obj_t *lb = lv_label_create(btn);
    lv_label_set_text(lb, label);
    lv_obj_set_style_text_font(lb, MOD_UI_FONT_LABEL_M, 0);
    lv_obj_set_style_text_color(lb, on ? modulus_ui_color_on_secondary_container()
                                       : modulus_ui_color_on_surface(),
                                0);
    lv_obj_center(lb);
    settings_bind_menu_click(btn, qbtn_filter_cb, (void *)(uintptr_t)filt);
}

static void qbtn_slot_row(lv_obj_t *parent, int slot)
{
    const uint8_t cur = ui_qbtn_slot_assign(slot);
    char headline[24];
    char support[40];
    snprintf(headline, sizeof(headline), "Slot %d", slot + 1);
    ui_qbtn_assign_label(cur, support, sizeof(support));

    lv_obj_t *row = lv_obj_create(parent);
    lv_obj_remove_style_all(row);
    lv_obj_set_size(row, lv_pct(100), LV_SIZE_CONTENT);
    lv_obj_set_style_min_height(row, 56, 0);
    lv_obj_set_style_pad_ver(row, MOD_UI_SPACE_SM, 0);
    lv_obj_set_style_pad_hor(row, MOD_UI_SPACE_SM, 0);
    lv_obj_set_style_radius(row, MOD_UI_SHAPE_MD, 0);
    lv_obj_set_style_bg_color(row, modulus_ui_color_surface_container_high(), 0);
    lv_obj_set_style_bg_opa(row, LV_OPA_COVER, 0);
    lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(row, MOD_UI_SPACE_SM, 0);

    lv_obj_t *main = lv_obj_create(row);
    lv_obj_remove_style_all(main);
    lv_obj_set_flex_grow(main, 1);
    lv_obj_set_height(main, LV_SIZE_CONTENT);
    lv_obj_set_style_min_height(main, 48, 0);
    lv_obj_set_flex_flow(main, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(main, 2, 0);
    lv_obj_set_style_pad_hor(main, MOD_UI_SPACE_SM, 0);
    lv_obj_add_flag(main, LV_OBJ_FLAG_CLICKABLE);
    modulus_ui_apply_pressed_state_layer(main);
    settings_bind_menu_click(main, qbtn_slot_open_cb, (void *)(intptr_t)slot);

    lv_obj_t *h = lv_label_create(main);
    lv_label_set_text(h, headline);
    lv_obj_set_style_text_font(h, MOD_UI_FONT_BODY_L, 0);
    lv_obj_t *s = lv_label_create(main);
    lv_label_set_text(s, support);
    lv_obj_set_style_text_font(s, MOD_UI_FONT_LABEL_M, 0);
    lv_obj_set_style_text_color(s, modulus_ui_color_on_surface_variant(), 0);

    lv_obj_t *up = lv_button_create(row);
    lv_obj_set_size(up, 44, 44);
    lv_obj_set_style_radius(up, MOD_UI_SHAPE_FULL, 0);
    lv_obj_set_style_bg_color(up, modulus_ui_color_surface_container_highest(), 0);
    if (slot == 0) {
        modulus_ui_obj_set_disabled_style(up, false);
    } else {
        settings_bind_menu_click(up, qbtn_move_up_cb, (void *)(intptr_t)slot);
    }
    lv_obj_t *ul = modulus_ui_icon_create(up, MOD_UI_ICON_ARROW_UP, MOD_UI_ICON_SZ_24);
    if (ul) {
        modulus_ui_icon_recolor(ul, modulus_ui_color_on_surface());
        lv_obj_center(ul);
    }

    lv_obj_t *dn = lv_button_create(row);
    lv_obj_set_size(dn, 44, 44);
    lv_obj_set_style_radius(dn, MOD_UI_SHAPE_FULL, 0);
    lv_obj_set_style_bg_color(dn, modulus_ui_color_surface_container_highest(), 0);
    if (slot + 1 >= UI_QBTN_MAX_SLOTS) {
        modulus_ui_obj_set_disabled_style(dn, false);
    } else {
        settings_bind_menu_click(dn, qbtn_move_down_cb, (void *)(intptr_t)slot);
    }
    lv_obj_t *dl = modulus_ui_icon_create(dn, MOD_UI_ICON_ARROW_DOWN, MOD_UI_ICON_SZ_24);
    if (dl) {
        modulus_ui_icon_recolor(dl, modulus_ui_color_on_surface());
        lv_obj_center(dl);
    }
}

static void qbtn_rebuild_body(void)
{
    if (!s_qbtn_body) {
        return;
    }
    lv_obj_clean(s_qbtn_body);
    s_qbtn_preview = NULL;

    if (s_pick_slot >= 0) {
        char ttl[40];
        snprintf(ttl, sizeof(ttl), "Choose action for slot %d", s_pick_slot + 1);
        settings_section(s_qbtn_body, ttl, NULL);
        settings_note(s_qbtn_body, "Custom buttons appear after you create them.");

        lv_obj_t *filt = lv_obj_create(s_qbtn_body);
        lv_obj_remove_style_all(filt);
        lv_obj_set_width(filt, lv_pct(100));
        lv_obj_set_height(filt, LV_SIZE_CONTENT);
        lv_obj_set_flex_flow(filt, LV_FLEX_FLOW_ROW);
        lv_obj_set_style_pad_column(filt, MOD_UI_SPACE_SM, 0);
        settings_no_scroll(filt);
        qbtn_filter_chip(filt, "All", QBTN_FILTER_ALL);
        qbtn_filter_chip(filt, "Built-in", QBTN_FILTER_BUILTIN);
        qbtn_filter_chip(filt, "Custom", QBTN_FILTER_CUSTOM);

        const uint8_t cur = ui_qbtn_slot_assign(s_pick_slot);
        /* Macro (legacy) retired from picker — cnc_macro still runs if NVS has assign=5. */
        static const uint8_t k_builtin[] = {
            UI_QBTN_SPINDLE_CW, UI_QBTN_SPINDLE_CCW, UI_QBTN_COOLANT, UI_QBTN_FAN,
            UI_QBTN_ZERO_ALL,   UI_QBTN_MIST,        UI_QBTN_SINGLE_STEP, UI_QBTN_OFF,
        };
        if (s_filter != QBTN_FILTER_CUSTOM) {
            for (unsigned i = 0; i < sizeof(k_builtin) / sizeof(k_builtin[0]); i++) {
                char lbl[32];
                ui_qbtn_assign_label(k_builtin[i], lbl, sizeof(lbl));
                const char *sup = (k_builtin[i] == UI_QBTN_OFF) ? "Hide this dashboard slot" : "";
                qbtn_list_item(s_qbtn_body, lbl, sup, cur == k_builtin[i], qbtn_pick_cb,
                               (void *)(uintptr_t)k_builtin[i]);
            }
        }

        if (s_filter != QBTN_FILTER_BUILTIN) {
            settings_section(s_qbtn_body, "Your custom buttons", NULL);
            bool any = false;
            for (uint8_t mac = 0; mac < SETTINGS_MACRO_SLOTS; mac++) {
                char name[16], on[64], off[64];
                if (!settings_macro_slot_load(mac, name, sizeof(name), on, sizeof(on), off,
                                              sizeof(off), NULL)) {
                    continue;
                }
                any = true;
                const uint8_t assign = (uint8_t)(UI_QBTN_USER0 + mac);
                char support[80];
                if (off[0]) {
                    snprintf(support, sizeof(support), "Toggle: %.24s / %.24s", on, off);
                } else {
                    snprintf(support, sizeof(support), "Press: %.48s", on);
                }
                qbtn_list_item(s_qbtn_body, name, support, cur == assign, qbtn_pick_cb,
                               (void *)(uintptr_t)assign);
            }
            if (!any) {
                settings_note(s_qbtn_body, "None yet. Close and use Add quick button.");
            }
        }

        lv_obj_t *back = settings_action_row(s_qbtn_body, "Back to slots", "");
        settings_bind_menu_click(back, qbtn_back_cb, NULL);
        return;
    }

    settings_note(s_qbtn_body,
                  "Pick what each dashboard slot shows. 1 fills, 2 side-by-side, 3+ grid.");
    settings_section(s_qbtn_body, "Layout preview", NULL);
    s_qbtn_preview = lv_obj_create(s_qbtn_body);
    lv_obj_remove_style_all(s_qbtn_preview);
    lv_obj_set_width(s_qbtn_preview, lv_pct(100));
    lv_obj_set_height(s_qbtn_preview, QBTN_PREVIEW_H);
    lv_obj_clear_flag(s_qbtn_preview, LV_OBJ_FLAG_SCROLLABLE);
    refresh_qbtn_preview();

    settings_section(s_qbtn_body, "Dashboard slots", NULL);
    for (int slot = 0; slot < UI_QBTN_MAX_SLOTS; slot++) {
        qbtn_slot_row(s_qbtn_body, slot);
    }
}

void settings_qbtn_modal_show(void)
{
    settings_qbtn_modal_hide();
    s_filter = QBTN_FILTER_ALL;

    s_qbtn_modal = modulus_ui_dialog_scrim_create();

    lv_obj_t *card = modulus_ui_dialog_card_create(s_qbtn_modal, MOD_UI_DIALOG_W_WIDE, 600);
    lv_obj_center(card);
    settings_tune_scroll_container(card);
    modulus_ui_motion_dialog_enter(card);

    modulus_ui_dialog_header(card, "Arrange quick buttons", qbtn_close_cb, NULL);
    modulus_ui_dialog_scrim_bind_dismiss(s_qbtn_modal, qbtn_close_cb, NULL);

    s_qbtn_body = lv_obj_create(card);
    lv_obj_remove_style_all(s_qbtn_body);
    lv_obj_set_width(s_qbtn_body, lv_pct(100));
    lv_obj_set_flex_grow(s_qbtn_body, 1);
    lv_obj_set_flex_flow(s_qbtn_body, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(s_qbtn_body, MOD_UI_SPACE_SM, 0);
    settings_tune_scroll_container(s_qbtn_body);

    qbtn_rebuild_body();
}

void settings_qbtn_modal_theme_refresh(void)
{
    modulus_ui_dialog_theme_refresh(s_qbtn_modal);
}
