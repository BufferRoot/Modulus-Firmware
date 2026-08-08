#include "ui_internal.h"
#include "security_shim.h"
#include "display_shim.h"

#include <esp_log.h>
#include <stdint.h>

static const char *TAG = "ui_pin";

static lv_obj_t *s_overlay = NULL;
static lv_obj_t *s_pin_ta = NULL;
static lv_obj_t *s_status = NULL;
static lv_obj_t *s_key_pad = NULL;

typedef enum {
    PIN_KEY_DIGIT = 0,
    PIN_KEY_BACKSPACE,
    PIN_KEY_OK,
} pin_key_kind_t;

typedef struct {
    pin_key_kind_t kind;
    char digit;
} pin_key_t;

static void key_cb(lv_event_t *e)
{
    const pin_key_t *key = lv_event_get_user_data(e);
    if (!key || !s_pin_ta) {
        return;
    }
    if (key->kind == PIN_KEY_BACKSPACE) {
        lv_textarea_delete_char(s_pin_ta);
    } else if (key->kind == PIN_KEY_OK) {
        const char *entered = lv_textarea_get_text(s_pin_ta);
        if (modulus_security_verify_pin(entered)) {
            modulus_security_unlock();
            modulus_ui_pin_hide();
            modulus_display_note_user_activity();
            ESP_LOGI(TAG, "PIN accepted");
        } else {
            lv_textarea_set_text(s_pin_ta, "");
            if (s_status) {
                lv_label_set_text(s_status, "Incorrect PIN");
                lv_obj_set_style_text_color(s_status, modulus_ui_color_error(), 0);
            }
        }
    } else {
        char buf[2] = {key->digit, '\0'};
        lv_textarea_add_text(s_pin_ta, buf);
    }
}

static void apply_pin_key_theme(lv_obj_t *btn, const pin_key_t *key)
{
    if (key->kind == PIN_KEY_OK) {
        lv_obj_set_style_bg_color(btn, modulus_ui_color_primary(), 0);
        lv_obj_t *ico = lv_obj_get_child(btn, 0);
        if (ico) {
            modulus_ui_icon_recolor(ico, modulus_ui_color_on_primary());
        }
        return;
    }

    lv_obj_set_style_bg_color(btn, modulus_ui_color_surface_container_high(), 0);
    if (key->kind == PIN_KEY_BACKSPACE) {
        lv_obj_t *ico = lv_obj_get_child(btn, 0);
        if (ico) {
            modulus_ui_icon_recolor(ico, modulus_ui_color_on_surface());
        }
        return;
    }

    lv_obj_t *lbl = lv_obj_get_child(btn, 0);
    if (lbl) {
        lv_obj_set_style_text_color(lbl, modulus_ui_color_on_surface(), 0);
    }
}

static lv_obj_t *make_key(lv_obj_t *parent, const pin_key_t *key, int w, int h)
{
    lv_obj_t *btn = lv_button_create(parent);
    lv_obj_set_size(btn, w, h);
    lv_obj_set_style_radius(btn, MOD_UI_SHAPE_MD, 0);
    if (key->kind == PIN_KEY_BACKSPACE) {
        lv_obj_t *ico = modulus_ui_icon_create(btn, MOD_UI_ICON_BACKSPACE, MOD_UI_ICON_SZ_24);
        lv_obj_center(ico);
    } else if (key->kind == PIN_KEY_OK) {
        lv_obj_t *ico = modulus_ui_icon_create(btn, MOD_UI_ICON_CHECK, MOD_UI_ICON_SZ_24);
        lv_obj_center(ico);
    } else {
        char buf[2] = {key->digit, '\0'};
        lv_obj_t *lbl = lv_label_create(btn);
        lv_label_set_text(lbl, buf);
        lv_obj_center(lbl);
    }
    apply_pin_key_theme(btn, key);
    modulus_ui_apply_pressed_state_layer(btn);
    lv_obj_add_event_cb(btn, key_cb, LV_EVENT_CLICKED, (void *)key);
    return btn;
}

void modulus_ui_pin_show(void)
{
    if (s_overlay) {
        return;
    }
    ESP_LOGI(TAG, "PIN lock overlay");
    modulus_ui_pause_dashboard_refresh();

    s_overlay = lv_obj_create(lv_layer_top());
    lv_obj_set_size(s_overlay, lv_pct(100), lv_pct(100));
    lv_obj_set_style_bg_color(s_overlay, modulus_ui_color_surface(), 0);
    lv_obj_set_style_bg_opa(s_overlay, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(s_overlay, 0, 0);
    lv_obj_set_style_border_width(s_overlay, 0, 0);

    lv_obj_t *card = lv_obj_create(s_overlay);
    lv_obj_set_size(card, 360, 520);
    lv_obj_center(card);
    lv_obj_set_style_bg_color(card, modulus_ui_color_surface_container_low(), 0);
    lv_obj_set_style_radius(card, MOD_UI_SHAPE_DIALOG, 0);

    lv_obj_t *title = lv_label_create(card);
    lv_label_set_text(title, "Enter PIN");
    lv_obj_set_style_text_font(title, MOD_UI_FONT_TITLE_L, 0);
    lv_obj_set_style_text_color(title, modulus_ui_color_on_surface(), 0);
    lv_obj_align(title, LV_ALIGN_TOP_MID, 0, 16);

    s_pin_ta = lv_textarea_create(card);
    lv_obj_set_width(s_pin_ta, 280);
    lv_obj_align(s_pin_ta, LV_ALIGN_TOP_MID, 0, 56);
    lv_textarea_set_password_mode(s_pin_ta, true);
    lv_textarea_set_one_line(s_pin_ta, true);
    lv_textarea_set_max_length(s_pin_ta, 8);
    /* Display only — digits come from on-screen keypad, not LVGL keyboard. */
    lv_obj_remove_flag(s_pin_ta, LV_OBJ_FLAG_CLICK_FOCUSABLE);
    modulus_ui_apply_textarea_theme(s_pin_ta, false);

    s_status = lv_label_create(card);
    lv_label_set_text(s_status, "");
    lv_obj_align(s_status, LV_ALIGN_TOP_MID, 0, 100);

    s_key_pad = lv_obj_create(card);
    lv_obj_remove_style_all(s_key_pad);
    lv_obj_set_size(s_key_pad, 300, 300);
    lv_obj_align(s_key_pad, LV_ALIGN_BOTTOM_MID, 0, -16);
    lv_obj_set_flex_flow(s_key_pad, LV_FLEX_FLOW_ROW_WRAP);
    lv_obj_set_style_pad_row(s_key_pad, MOD_UI_SPACE_SM, 0);
    lv_obj_set_style_pad_column(s_key_pad, MOD_UI_SPACE_SM, 0);
    lv_obj_set_flex_align(s_key_pad, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);

    static pin_key_t keys[] = {
        {PIN_KEY_DIGIT, '1'}, {PIN_KEY_DIGIT, '2'}, {PIN_KEY_DIGIT, '3'},
        {PIN_KEY_DIGIT, '4'}, {PIN_KEY_DIGIT, '5'}, {PIN_KEY_DIGIT, '6'},
        {PIN_KEY_DIGIT, '7'}, {PIN_KEY_DIGIT, '8'}, {PIN_KEY_DIGIT, '9'},
        {PIN_KEY_BACKSPACE, '\0'}, {PIN_KEY_DIGIT, '0'}, {PIN_KEY_OK, '\0'},
    };
    for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
        make_key(s_key_pad, &keys[i], 88, 64);
    }
}

void modulus_ui_pin_hide(void)
{
    if (!s_overlay) {
        return;
    }
    lv_obj_delete(s_overlay);
    s_overlay = NULL;
    s_pin_ta = NULL;
    s_status = NULL;
    s_key_pad = NULL;
    modulus_ui_resume_dashboard_refresh();
}

bool modulus_ui_pin_visible(void)
{
    return s_overlay != NULL;
}

void modulus_ui_pin_theme_refresh(void)
{
    if (!s_overlay) {
        return;
    }
    lv_obj_set_style_bg_color(s_overlay, modulus_ui_color_surface(), 0);
    lv_obj_t *card = lv_obj_get_child(s_overlay, 0);
    if (card) {
        lv_obj_set_style_bg_color(card, modulus_ui_color_surface_container_low(), 0);
        lv_obj_t *title = lv_obj_get_child(card, 0);
        if (title) {
            lv_obj_set_style_text_color(title, modulus_ui_color_on_surface(), 0);
        }
    }
    if (s_pin_ta) {
        modulus_ui_apply_textarea_theme(s_pin_ta, false);
    }
    if (s_status) {
        const char *txt = lv_label_get_text(s_status);
        if (txt && txt[0] != '\0') {
            lv_obj_set_style_text_color(s_status, modulus_ui_color_error(), 0);
        }
    }
    if (!s_key_pad) {
        return;
    }
    static const pin_key_t keys[] = {
        {PIN_KEY_DIGIT, '1'}, {PIN_KEY_DIGIT, '2'}, {PIN_KEY_DIGIT, '3'},
        {PIN_KEY_DIGIT, '4'}, {PIN_KEY_DIGIT, '5'}, {PIN_KEY_DIGIT, '6'},
        {PIN_KEY_DIGIT, '7'}, {PIN_KEY_DIGIT, '8'}, {PIN_KEY_DIGIT, '9'},
        {PIN_KEY_BACKSPACE, '\0'}, {PIN_KEY_DIGIT, '0'}, {PIN_KEY_OK, '\0'},
    };
    const uint32_t n = (uint32_t)(sizeof(keys) / sizeof(keys[0]));
    for (uint32_t i = 0; i < n; i++) {
        lv_obj_t *btn = lv_obj_get_child(s_key_pad, i);
        if (btn) {
            apply_pin_key_theme(btn, &keys[i]);
        }
    }
}
