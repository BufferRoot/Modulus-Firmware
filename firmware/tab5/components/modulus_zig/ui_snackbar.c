#include "ui_internal.h"

#include <string.h>

enum {
    SNACK_KIND_NONE = 0,
    SNACK_KIND_TRANSIENT,
    SNACK_KIND_STICKY,
};

typedef struct {
    char message[96];
    char action[24];
    uint32_t duration_ms;
    lv_event_cb_t action_cb;
    void *user_data;
    bool pending;
} snack_pending_t;

typedef struct {
    lv_event_cb_t cb;
    void *ud;
    bool sticky;
} snack_action_ud_t;

static lv_obj_t *s_snack = NULL;
static lv_timer_t *s_snack_tmr = NULL;
static uint8_t s_kind = SNACK_KIND_NONE;
static snack_pending_t s_pending = {};

static void snack_hide(void);
static void snack_timer_cb(lv_timer_t *t);
static void snack_action_wrap_free_cb(lv_event_t *e);
static void snack_action_wrap_cb(lv_event_t *e);

static void snack_show_inner(const char *message, const char *action_label, uint32_t duration_ms,
                             lv_event_cb_t action_cb, void *user_data)
{
    if (!message || !message[0]) {
        return;
    }

    const bool sticky = (duration_ms == 0);

    lv_display_t *disp = lv_display_get_default();
    const lv_coord_t scr_w = disp ? lv_display_get_horizontal_resolution(disp) : 1280;
    const lv_coord_t max_w = (lv_coord_t)((scr_w * 4) / 5);
    const lv_coord_t pad_h = MOD_UI_SPACE_MD;
    const lv_coord_t text_max = max_w - (pad_h * 2);

    s_snack = lv_obj_create(lv_layer_top());
    lv_obj_remove_style_all(s_snack);
    lv_obj_set_size(s_snack, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_style_max_width(s_snack, max_w, 0);
    lv_obj_set_style_bg_color(s_snack, modulus_ui_color_inverse_surface(), 0);
    lv_obj_set_style_bg_opa(s_snack, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(s_snack, MOD_UI_SHAPE_SM, 0);
    lv_obj_set_style_pad_hor(s_snack, pad_h, 0);
    lv_obj_set_style_pad_ver(s_snack, MOD_UI_SPACE_SM + 4, 0);
    lv_obj_set_style_shadow_width(s_snack, 0, 0);
    lv_obj_set_flex_flow(s_snack, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(s_snack, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(s_snack, MOD_UI_SPACE_MD, 0);
    lv_obj_remove_flag(s_snack, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(s_snack, LV_OBJ_FLAG_FLOATING);
    lv_obj_align(s_snack, LV_ALIGN_BOTTOM_MID, 0, -24);
    lv_obj_move_foreground(s_snack);

    lv_obj_t *lbl = lv_label_create(s_snack);
    lv_label_set_text(lbl, message);
    lv_label_set_long_mode(lbl, LV_LABEL_LONG_WRAP);
    lv_obj_set_width(lbl, LV_SIZE_CONTENT);
    lv_obj_set_style_max_width(lbl, text_max > 0 ? text_max : max_w, 0);
    lv_obj_set_style_text_align(lbl, LV_TEXT_ALIGN_LEFT, 0);
    lv_obj_set_style_text_color(lbl, modulus_ui_color_inverse_on_surface(), 0);
    lv_obj_set_style_text_opa(lbl, LV_OPA_COVER, 0);
    lv_obj_set_style_text_font(lbl, MOD_UI_FONT_BODY_M, 0);
    if (action_label && action_label[0]) {
        lv_obj_set_flex_grow(lbl, 1);
    }

    if (action_label && action_label[0] && action_cb) {
        lv_obj_t *btn = lv_button_create(s_snack);
        lv_obj_remove_style_all(btn);
        lv_obj_set_size(btn, LV_SIZE_CONTENT, MOD_UI_TOUCH_MIN);
        lv_obj_set_style_min_width(btn, 48, 0);
        lv_obj_set_style_pad_hor(btn, MOD_UI_SPACE_SM, 0);
        lv_obj_set_style_radius(btn, MOD_UI_SHAPE_FULL, 0);
        lv_obj_set_style_bg_opa(btn, LV_OPA_TRANSP, 0);
        modulus_ui_apply_pressed_state_layer_color(btn, modulus_ui_color_inverse_primary());
        lv_obj_add_event_cb(btn, action_cb, LV_EVENT_SHORT_CLICKED, user_data);

        lv_obj_t *act = lv_label_create(btn);
        lv_label_set_text(act, action_label);
        lv_obj_set_style_text_color(act, modulus_ui_color_inverse_primary(), 0);
        lv_obj_set_style_text_font(act, MOD_UI_FONT_LABEL_L, 0);
        lv_obj_center(act);
    }

    s_kind = sticky ? SNACK_KIND_STICKY : SNACK_KIND_TRANSIENT;
    if (!sticky) {
        const uint32_t ms = duration_ms ? duration_ms : 2500;
        s_snack_tmr = lv_timer_create(snack_timer_cb, ms, NULL);
        lv_timer_set_repeat_count(s_snack_tmr, 1);
    }

    lv_obj_set_style_translate_y(s_snack, 40, 0);
    modulus_ui_anim_translate_y(s_snack, 40, 0, MOD_UI_MOTION_UTIL_MS, true, NULL, NULL);
}

static void snack_timer_cb(lv_timer_t *t)
{
    (void)t;
    snack_hide();
}

static void snack_hide(void)
{
    if (s_snack_tmr) {
        lv_timer_delete(s_snack_tmr);
        s_snack_tmr = NULL;
    }
    if (s_snack) {
        lv_obj_delete(s_snack);
        s_snack = NULL;
    }
    s_kind = SNACK_KIND_NONE;

    if (s_pending.pending) {
        snack_pending_t next = s_pending;
        s_pending.pending = false;
        snack_show_inner(next.message, next.action[0] ? next.action : NULL, next.duration_ms,
                         next.action_cb, next.user_data);
    }
}

static void snack_action_wrap_cb(lv_event_t *e)
{
    snack_action_ud_t *w = lv_event_get_user_data(e);
    if (w && w->cb) {
        w->cb(e);
    }
    if (!w || !w->sticky) {
        modulus_ui_snackbar_hide();
    }
}

static void snack_action_wrap_free_cb(lv_event_t *e)
{
    snack_action_ud_t *w = lv_event_get_user_data(e);
    if (w) {
        lv_free(w);
    }
}

void modulus_ui_snackbar_hide(void)
{
    s_pending.pending = false;
    snack_hide();
}

bool modulus_ui_snackbar_is_sticky(void)
{
    return s_snack != NULL && s_kind == SNACK_KIND_STICKY;
}

void modulus_ui_snackbar_show_action(const char *message, const char *action_label,
                                     uint32_t duration_ms, lv_event_cb_t action_cb,
                                     void *user_data)
{
    if (!message || !message[0]) {
        return;
    }

    const bool sticky = (duration_ms == 0);
    if (s_snack && s_kind == SNACK_KIND_TRANSIENT && !sticky) {
        strncpy(s_pending.message, message, sizeof(s_pending.message) - 1);
        s_pending.message[sizeof(s_pending.message) - 1] = '\0';
        s_pending.action[0] = '\0';
        if (action_label) {
            strncpy(s_pending.action, action_label, sizeof(s_pending.action) - 1);
            s_pending.action[sizeof(s_pending.action) - 1] = '\0';
        }
        s_pending.duration_ms = duration_ms;
        s_pending.action_cb = action_cb;
        s_pending.user_data = user_data;
        s_pending.pending = true;
        return;
    }

    snack_hide();

    if (action_label && action_cb) {
        snack_action_ud_t *wrap = lv_malloc(sizeof(*wrap));
        if (!wrap) {
            snack_show_inner(message, NULL, duration_ms, NULL, NULL);
            return;
        }
        wrap->cb = action_cb;
        wrap->ud = user_data;
        wrap->sticky = sticky;
        snack_show_inner(message, action_label, duration_ms, snack_action_wrap_cb, wrap);
        lv_obj_add_event_cb(s_snack, snack_action_wrap_free_cb, LV_EVENT_DELETE, wrap);
        return;
    }

    snack_show_inner(message, NULL, duration_ms, NULL, NULL);
}

void modulus_ui_snackbar_show(const char *message, uint32_t duration_ms)
{
    modulus_ui_snackbar_show_action(message, NULL, duration_ms, NULL, NULL);
}
