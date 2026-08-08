/*
 * Global LVGL pointer-indev touch feedback — port of C++ ui_manager.cpp.
 */
#include "ui_touch_sound.h"
#include "audio_shim.h"

static lv_obj_t *s_touch_press_obj = NULL;
static const lv_obj_flag_t k_no_touch_tick = LV_OBJ_FLAG_USER_1;

static bool touch_tick_suppressed(const lv_obj_t *obj)
{
    for (int i = 0; obj && i < 12; i++) {
        if (lv_obj_has_flag(obj, k_no_touch_tick)) {
            return true;
        }
        obj = lv_obj_get_parent(obj);
    }
    return false;
}

static lv_obj_t *resolve_touch_target(lv_obj_t *obj)
{
    for (int i = 0; obj && i < 12; i++) {
        if (touch_tick_suppressed(obj)) {
            return NULL;
        }
        if (lv_obj_has_flag(obj, LV_OBJ_FLAG_CLICKABLE)) {
            return obj;
        }
        const lv_obj_class_t *cls = lv_obj_get_class(obj);
        if (cls == &lv_slider_class || cls == &lv_switch_class || cls == &lv_dropdown_class) {
            return obj;
        }
        obj = lv_obj_get_parent(obj);
    }
    return NULL;
}

static bool is_dropdown_list_surface(const lv_obj_t *obj)
{
    for (int i = 0; obj && i < 10; i++) {
        if (lv_obj_get_class(obj) == &lv_list_class) {
            return true;
        }
        obj = lv_obj_get_parent(obj);
    }
    return false;
}

static bool should_skip_touch_target(const lv_obj_t *obj)
{
    if (!obj) {
        return true;
    }
    const lv_obj_class_t *cls = lv_obj_get_class(obj);
    if (cls == &lv_textarea_class || cls == &lv_keyboard_class) {
        return true;
    }
    if (is_dropdown_list_surface(obj)) {
        return true;
    }
    /* Bare scroll surfaces only — lv_obj_create() is scrollable by default, but
     * clickable buttons/rows must still get UI_TICK (C++ ui_util::add_click_feedback). */
    if (cls == &lv_obj_class && lv_obj_has_flag(obj, LV_OBJ_FLAG_SCROLLABLE) &&
        !lv_obj_has_flag(obj, LV_OBJ_FLAG_CLICKABLE)) {
        return true;
    }
    return false;
}

static void play_touch_feedback(lv_obj_t *raw, lv_event_code_t code)
{
    if (!modulus_audio_is_output_ready()) {
        return;
    }

    lv_obj_t *obj = resolve_touch_target(raw);
    if (!obj || should_skip_touch_target(obj)) {
        return;
    }

    const lv_obj_class_t *cls = lv_obj_get_class(obj);

    if (cls == &lv_slider_class || cls == &lv_switch_class) {
        if (code != LV_EVENT_RELEASED) {
            return;
        }
        modulus_audio_play_ui(MODULUS_UI_SOUND_TICK);
        return;
    }

    if (cls == &lv_dropdown_class) {
        if (code == LV_EVENT_CLICKED) {
            modulus_audio_play_ui(MODULUS_UI_SOUND_TICK);
        }
        return;
    }

    if (code == LV_EVENT_RELEASED) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_TICK);
    }
}

static void touch_sound_cb(lv_event_t *e)
{
    const lv_event_code_t code = lv_event_get_code(e);
    if (code == LV_EVENT_PRESSED) {
        s_touch_press_obj = lv_indev_get_active_obj();
        return;
    }
    if (code != LV_EVENT_CLICKED && code != LV_EVENT_RELEASED) {
        return;
    }

    lv_obj_t *obj = lv_indev_get_active_obj();
    if (!obj) {
        obj = s_touch_press_obj;
    } else if (code == LV_EVENT_RELEASED && s_touch_press_obj) {
        obj = s_touch_press_obj;
    }
    play_touch_feedback(obj, code);
    if (code == LV_EVENT_RELEASED || code == LV_EVENT_CLICKED) {
        s_touch_press_obj = NULL;
    }
}

static void register_touch_sound_indev(lv_indev_t *indev)
{
    lv_indev_add_event_cb(indev, touch_sound_cb, LV_EVENT_PRESSED, NULL);
    lv_indev_add_event_cb(indev, touch_sound_cb, LV_EVENT_RELEASED, NULL);
    lv_indev_add_event_cb(indev, touch_sound_cb, LV_EVENT_CLICKED, NULL);
}

void modulus_ui_touch_sound_register(void)
{
    lv_indev_t *indev = lv_indev_get_next(NULL);
    while (indev) {
        if (lv_indev_get_type(indev) == LV_INDEV_TYPE_POINTER) {
            register_touch_sound_indev(indev);
        }
        indev = lv_indev_get_next(indev);
    }
}

void modulus_ui_suppress_touch_tick(lv_obj_t *obj)
{
    if (obj) {
        lv_obj_add_flag(obj, k_no_touch_tick);
    }
}

static void click_feedback_cb(lv_event_t *e)
{
    if (lv_event_get_code(e) == LV_EVENT_CLICKED) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_TICK);
    }
}

void modulus_ui_add_click_feedback(lv_obj_t *obj)
{
    if (!obj) {
        return;
    }
    lv_obj_add_event_cb(obj, click_feedback_cb, LV_EVENT_CLICKED, NULL);
}
