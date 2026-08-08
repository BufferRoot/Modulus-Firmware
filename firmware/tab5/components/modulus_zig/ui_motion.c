#include "ui_internal.h"
#include "nvs_shim.h"

#include <stdint.h>

typedef struct {
    lv_coord_t rest;
    lv_coord_t press;
} press_morph_t;

static void anim_y_exec(void *obj, int32_t v)
{
    lv_obj_set_style_translate_y((lv_obj_t *)obj, (lv_coord_t)v, 0);
}

static void anim_radius_exec(void *obj, int32_t v)
{
    lv_obj_set_style_radius((lv_obj_t *)obj, (lv_coord_t)v, 0);
}

bool modulus_ui_motion_smooth(void)
{
    return modulus_nvs_get_u8("smooth_anim", 1) != 0;
}

bool modulus_ui_motion_expressive(void)
{
    return modulus_ui_motion_smooth() && modulus_nvs_get_u8("motion_scheme", 0) != 0;
}

uint32_t modulus_ui_motion_spatial_ms(bool enter)
{
    if (!modulus_ui_motion_smooth()) {
        return 0;
    }
    if (modulus_ui_motion_expressive()) {
        return enter ? 480 : 240;
    }
    return enter ? MOD_UI_MOTION_ENTER_MS : MOD_UI_MOTION_EXIT_MS;
}

static lv_anim_path_cb_t spatial_path(bool decelerate)
{
    if (modulus_ui_motion_expressive()) {
        /* Spring-ish: overshoot on enter, ease-in on exit. */
        return decelerate ? lv_anim_path_overshoot : lv_anim_path_ease_in;
    }
    return decelerate ? lv_anim_path_ease_out : lv_anim_path_ease_in;
}

void modulus_ui_anim_translate_y(lv_obj_t *obj, lv_coord_t from, lv_coord_t to, uint32_t duration_ms,
                                bool decelerate, lv_anim_ready_cb_t ready_cb, void *user_data)
{
    if (!obj) {
        return;
    }
    if (!modulus_ui_motion_smooth() || duration_ms == 0) {
        lv_obj_set_style_translate_y(obj, to, 0);
        if (ready_cb) {
            lv_anim_t dummy;
            lv_anim_init(&dummy);
            lv_anim_set_user_data(&dummy, user_data);
            ready_cb(&dummy);
        }
        return;
    }

    lv_anim_delete(obj, anim_y_exec);
    lv_anim_t anim;
    lv_anim_init(&anim);
    lv_anim_set_var(&anim, obj);
    lv_anim_set_exec_cb(&anim, anim_y_exec);
    lv_anim_set_values(&anim, (int32_t)from, (int32_t)to);
    lv_anim_set_duration(&anim, duration_ms);
    lv_anim_set_path_cb(&anim, spatial_path(decelerate));
    if (ready_cb) {
        lv_anim_set_user_data(&anim, user_data);
        lv_anim_set_ready_cb(&anim, ready_cb);
    }
    lv_anim_start(&anim);
}

void modulus_ui_morph_radius(lv_obj_t *obj, lv_coord_t to_radius, uint32_t duration_ms)
{
    if (!obj) {
        return;
    }
    const lv_coord_t from = (lv_coord_t)lv_obj_get_style_radius(obj, 0);
    if (from == to_radius) {
        return;
    }
    if (!modulus_ui_motion_smooth() || duration_ms == 0) {
        lv_obj_set_style_radius(obj, to_radius, 0);
        return;
    }
    lv_anim_delete(obj, anim_radius_exec);
    lv_anim_t anim;
    lv_anim_init(&anim);
    lv_anim_set_var(&anim, obj);
    lv_anim_set_exec_cb(&anim, anim_radius_exec);
    lv_anim_set_values(&anim, (int32_t)from, (int32_t)to_radius);
    lv_anim_set_duration(&anim, duration_ms);
    lv_anim_set_path_cb(&anim, spatial_path(true));
    lv_anim_start(&anim);
}

static void press_morph_cb(lv_event_t *e)
{
    const press_morph_t *m = lv_event_get_user_data(e);
    lv_obj_t *obj = lv_event_get_target(e);
    if (!m || !obj) {
        return;
    }
    const lv_event_code_t code = lv_event_get_code(e);
    const uint32_t ms = modulus_ui_motion_expressive() ? MOD_UI_MOTION_MORPH_MS : 80;
    if (code == LV_EVENT_PRESSED) {
        modulus_ui_morph_radius(obj, m->press, ms);
    } else if (code == LV_EVENT_RELEASED || code == LV_EVENT_PRESS_LOST) {
        modulus_ui_morph_radius(obj, m->rest, ms);
    } else if (code == LV_EVENT_DELETE) {
        lv_free((void *)m);
    }
}

void modulus_ui_bind_press_morph(lv_obj_t *obj, lv_coord_t rest_r, lv_coord_t press_r)
{
    if (!obj) {
        return;
    }
    press_morph_t *m = lv_malloc(sizeof(*m));
    if (!m) {
        lv_obj_set_style_radius(obj, rest_r, 0);
        return;
    }
    m->rest = rest_r;
    m->press = press_r;
    lv_obj_set_style_radius(obj, rest_r, 0);
    lv_obj_add_event_cb(obj, press_morph_cb, LV_EVENT_PRESSED, m);
    lv_obj_add_event_cb(obj, press_morph_cb, LV_EVENT_RELEASED, m);
    lv_obj_add_event_cb(obj, press_morph_cb, LV_EVENT_PRESS_LOST, m);
    lv_obj_add_event_cb(obj, press_morph_cb, LV_EVENT_DELETE, m);
}

void modulus_ui_motion_sheet_enter(lv_obj_t *panel, lv_coord_t slide_px)
{
    if (!panel) {
        return;
    }
    lv_obj_set_style_translate_y(panel, slide_px, 0);
    modulus_ui_anim_translate_y(panel, slide_px, 0, modulus_ui_motion_spatial_ms(true), true, NULL,
                                NULL);
}

void modulus_ui_motion_sheet_exit(lv_obj_t *panel, lv_coord_t slide_px, lv_anim_ready_cb_t ready_cb,
                                  void *user_data)
{
    if (!panel) {
        return;
    }
    modulus_ui_anim_translate_y(panel, 0, slide_px, modulus_ui_motion_spatial_ms(false), false,
                                ready_cb, user_data);
}

void modulus_ui_motion_dialog_enter(lv_obj_t *card)
{
    if (!card) {
        return;
    }
    const uint32_t ms = modulus_ui_motion_expressive() ? MOD_UI_MOTION_UTIL_MS + 80
                                                       : MOD_UI_MOTION_UTIL_MS;
    lv_obj_set_style_translate_y(card, MOD_UI_MOTION_DIALOG_OFFSET, 0);
    modulus_ui_anim_translate_y(card, MOD_UI_MOTION_DIALOG_OFFSET, 0, ms, true, NULL, NULL);
}

void modulus_ui_motion_dialog_exit(lv_obj_t *card, lv_anim_ready_cb_t ready_cb, void *user_data)
{
    if (!card) {
        if (ready_cb) {
            lv_anim_t dummy;
            lv_anim_init(&dummy);
            lv_anim_set_user_data(&dummy, user_data);
            ready_cb(&dummy);
        }
        return;
    }
    const uint32_t ms = modulus_ui_motion_spatial_ms(false);
    if (ms == 0) {
        if (ready_cb) {
            lv_anim_t dummy;
            lv_anim_init(&dummy);
            lv_anim_set_user_data(&dummy, user_data);
            ready_cb(&dummy);
        }
        return;
    }
    modulus_ui_anim_translate_y(card, 0, MOD_UI_MOTION_DIALOG_OFFSET, ms, false, ready_cb,
                                user_data);
}

void modulus_ui_motion_settings_enter(lv_obj_t *card)
{
    if (!card) {
        return;
    }
    /* No slide-in: settings shell builds tab content after show; Y translate
     * looked like a layout jump while content settled. */
    lv_anim_delete(card, anim_y_exec);
    lv_obj_set_style_translate_y(card, 0, 0);
}
