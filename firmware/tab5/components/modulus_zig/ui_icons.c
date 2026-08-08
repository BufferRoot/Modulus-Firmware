#include "ui_icons.h"

#include "assets/icons/generated/icon_decl.h"

static const lv_image_dsc_t *icon_dsc_24[MOD_UI_ICON_COUNT];
static const lv_image_dsc_t *icon_dsc_32[MOD_UI_ICON_COUNT];
static const lv_image_dsc_t *icon_dsc_40[3];

static void bind24(void)
{
    icon_dsc_24[MOD_UI_ICON_POWER] = &mod_icon_power_24;
    icon_dsc_24[MOD_UI_ICON_GEAR] = &mod_icon_gear_24;
    icon_dsc_24[MOD_UI_ICON_GEAR_SIX] = &mod_icon_gear_six_24;
    icon_dsc_24[MOD_UI_ICON_BATTERY_FULL] = &mod_icon_battery_full_24;
    icon_dsc_24[MOD_UI_ICON_BATTERY_HIGH] = &mod_icon_battery_high_24;
    icon_dsc_24[MOD_UI_ICON_BATTERY_MEDIUM] = &mod_icon_battery_medium_24;
    icon_dsc_24[MOD_UI_ICON_BATTERY_LOW] = &mod_icon_battery_low_24;
    icon_dsc_24[MOD_UI_ICON_BATTERY_EMPTY] = &mod_icon_battery_empty_24;
    icon_dsc_24[MOD_UI_ICON_BATTERY_CHARGING] = &mod_icon_battery_charging_24;
    icon_dsc_24[MOD_UI_ICON_BATTERY_WARNING] = &mod_icon_battery_warning_24;
    icon_dsc_24[MOD_UI_ICON_PLAY] = &mod_icon_play_24;
    icon_dsc_24[MOD_UI_ICON_PAUSE] = &mod_icon_pause_24;
    icon_dsc_24[MOD_UI_ICON_STOP] = &mod_icon_stop_24;
    icon_dsc_24[MOD_UI_ICON_SPINDLE] = &mod_icon_spindle_24;
    icon_dsc_24[MOD_UI_ICON_COOLANT] = &mod_icon_coolant_24;
    icon_dsc_24[MOD_UI_ICON_FAN] = &mod_icon_fan_24;
    icon_dsc_24[MOD_UI_ICON_SINGLE_STEP] = &mod_icon_single_step_24;
    icon_dsc_24[MOD_UI_ICON_HOUSE] = &mod_icon_house_24;
    icon_dsc_24[MOD_UI_ICON_HOUSE_FILL] = &mod_icon_house_fill_24;
    icon_dsc_24[MOD_UI_ICON_ARROW_UP] = &mod_icon_arrow_up_24;
    icon_dsc_24[MOD_UI_ICON_ARROW_DOWN] = &mod_icon_arrow_down_24;
    icon_dsc_24[MOD_UI_ICON_CARET_UP] = &mod_icon_caret_up_24;
    icon_dsc_24[MOD_UI_ICON_CARET_DOWN] = &mod_icon_caret_down_24;
    icon_dsc_24[MOD_UI_ICON_X] = &mod_icon_x_24;
    icon_dsc_24[MOD_UI_ICON_MPG] = &mod_icon_mpg_24;
    icon_dsc_24[MOD_UI_ICON_CNC] = &mod_icon_cnc_24;
    icon_dsc_24[MOD_UI_ICON_MONITOR] = &mod_icon_monitor_24;
    icon_dsc_24[MOD_UI_ICON_SPEAKER] = &mod_icon_speaker_24;
    icon_dsc_24[MOD_UI_ICON_WIFI] = &mod_icon_wifi_24;
    icon_dsc_24[MOD_UI_ICON_BLUETOOTH] = &mod_icon_bluetooth_24;
    icon_dsc_24[MOD_UI_ICON_BROADCAST] = &mod_icon_broadcast_24;
    icon_dsc_24[MOD_UI_ICON_EYE] = &mod_icon_eye_24;
    icon_dsc_24[MOD_UI_ICON_STORAGE] = &mod_icon_storage_24;
    icon_dsc_24[MOD_UI_ICON_LIGHTNING] = &mod_icon_lightning_24;
    icon_dsc_24[MOD_UI_ICON_BACKSPACE] = &mod_icon_backspace_24;
    icon_dsc_24[MOD_UI_ICON_CHECK] = &mod_icon_check_24;
    icon_dsc_24[MOD_UI_ICON_ZERO] = &mod_icon_zero_24;
    icon_dsc_24[MOD_UI_ICON_CLOUD_FOG] = &mod_icon_cloud_fog_24;
    icon_dsc_24[MOD_UI_ICON_SCROLL] = &mod_icon_scroll_24;
    icon_dsc_24[MOD_UI_ICON_CROSSHAIR] = &mod_icon_crosshair_24;
    icon_dsc_24[MOD_UI_ICON_SPINDLE_CCW] = &mod_icon_spindle_ccw_24;
}

static void bind32(void)
{
    icon_dsc_32[MOD_UI_ICON_POWER] = &mod_icon_power_32;
    icon_dsc_32[MOD_UI_ICON_GEAR] = &mod_icon_gear_32;
    icon_dsc_32[MOD_UI_ICON_GEAR_SIX] = &mod_icon_gear_six_32;
    icon_dsc_32[MOD_UI_ICON_BATTERY_FULL] = &mod_icon_battery_full_32;
    icon_dsc_32[MOD_UI_ICON_BATTERY_HIGH] = &mod_icon_battery_high_32;
    icon_dsc_32[MOD_UI_ICON_BATTERY_MEDIUM] = &mod_icon_battery_medium_32;
    icon_dsc_32[MOD_UI_ICON_BATTERY_LOW] = &mod_icon_battery_low_32;
    icon_dsc_32[MOD_UI_ICON_BATTERY_EMPTY] = &mod_icon_battery_empty_32;
    icon_dsc_32[MOD_UI_ICON_BATTERY_CHARGING] = &mod_icon_battery_charging_32;
    icon_dsc_32[MOD_UI_ICON_BATTERY_WARNING] = &mod_icon_battery_warning_32;
    icon_dsc_32[MOD_UI_ICON_PLAY] = &mod_icon_play_32;
    icon_dsc_32[MOD_UI_ICON_PAUSE] = &mod_icon_pause_32;
    icon_dsc_32[MOD_UI_ICON_STOP] = &mod_icon_stop_32;
    icon_dsc_32[MOD_UI_ICON_SPINDLE] = &mod_icon_spindle_32;
    icon_dsc_32[MOD_UI_ICON_COOLANT] = &mod_icon_coolant_32;
    icon_dsc_32[MOD_UI_ICON_FAN] = &mod_icon_fan_32;
    icon_dsc_32[MOD_UI_ICON_SINGLE_STEP] = &mod_icon_single_step_32;
    icon_dsc_32[MOD_UI_ICON_HOUSE] = &mod_icon_house_32;
    icon_dsc_32[MOD_UI_ICON_HOUSE_FILL] = &mod_icon_house_fill_32;
    icon_dsc_32[MOD_UI_ICON_ARROW_UP] = &mod_icon_arrow_up_32;
    icon_dsc_32[MOD_UI_ICON_ARROW_DOWN] = &mod_icon_arrow_down_32;
    icon_dsc_32[MOD_UI_ICON_CARET_UP] = &mod_icon_caret_up_32;
    icon_dsc_32[MOD_UI_ICON_CARET_DOWN] = &mod_icon_caret_down_32;
    icon_dsc_32[MOD_UI_ICON_X] = &mod_icon_x_32;
    icon_dsc_32[MOD_UI_ICON_MPG] = &mod_icon_mpg_32;
    icon_dsc_32[MOD_UI_ICON_CNC] = &mod_icon_cnc_32;
    icon_dsc_32[MOD_UI_ICON_MONITOR] = &mod_icon_monitor_32;
    icon_dsc_32[MOD_UI_ICON_SPEAKER] = &mod_icon_speaker_32;
    icon_dsc_32[MOD_UI_ICON_WIFI] = &mod_icon_wifi_32;
    icon_dsc_32[MOD_UI_ICON_BLUETOOTH] = &mod_icon_bluetooth_32;
    icon_dsc_32[MOD_UI_ICON_BROADCAST] = &mod_icon_broadcast_32;
    icon_dsc_32[MOD_UI_ICON_EYE] = &mod_icon_eye_32;
    icon_dsc_32[MOD_UI_ICON_STORAGE] = &mod_icon_storage_32;
    icon_dsc_32[MOD_UI_ICON_LIGHTNING] = &mod_icon_lightning_32;
    icon_dsc_32[MOD_UI_ICON_BACKSPACE] = &mod_icon_backspace_32;
    icon_dsc_32[MOD_UI_ICON_CHECK] = &mod_icon_check_32;
    icon_dsc_32[MOD_UI_ICON_ZERO] = &mod_icon_zero_32;
    icon_dsc_32[MOD_UI_ICON_CLOUD_FOG] = &mod_icon_cloud_fog_32;
    icon_dsc_32[MOD_UI_ICON_SCROLL] = &mod_icon_scroll_32;
    icon_dsc_32[MOD_UI_ICON_CROSSHAIR] = &mod_icon_crosshair_32;
    icon_dsc_32[MOD_UI_ICON_SPINDLE_CCW] = &mod_icon_spindle_ccw_32;
}

static void init_registry(void)
{
    static bool ready;
    if (ready) {
        return;
    }
    bind24();
    bind32();
    icon_dsc_40[MOD_UI_ICON_POWER] = &mod_icon_power_40;
    icon_dsc_40[MOD_UI_ICON_GEAR_SIX] = &mod_icon_gear_six_40;
    ready = true;
}

const lv_image_dsc_t *modulus_ui_icon_dsc(modulus_ui_icon_id_t id, modulus_ui_icon_size_t sz)
{
    init_registry();
    if (id >= MOD_UI_ICON_COUNT) {
        return NULL;
    }
    if (sz == MOD_UI_ICON_SZ_40 && (id == MOD_UI_ICON_POWER || id == MOD_UI_ICON_GEAR_SIX)) {
        return icon_dsc_40[id];
    }
    return (sz == MOD_UI_ICON_SZ_32) ? icon_dsc_32[id] : icon_dsc_24[id];
}

lv_obj_t *modulus_ui_icon_create(lv_obj_t *parent, modulus_ui_icon_id_t id, modulus_ui_icon_size_t sz)
{
    const lv_image_dsc_t *dsc = modulus_ui_icon_dsc(id, sz);
    if (!dsc) {
        return NULL;
    }
    lv_obj_t *img = lv_image_create(parent);
    lv_image_set_src(img, dsc);
    return img;
}

void modulus_ui_icon_set(lv_obj_t *img, modulus_ui_icon_id_t id, modulus_ui_icon_size_t sz)
{
    const lv_image_dsc_t *dsc = modulus_ui_icon_dsc(id, sz);
    if (!img || !dsc) {
        return;
    }
    if (lv_image_get_src(img) == dsc) {
        return;
    }
    lv_image_set_src(img, dsc);
}

void modulus_ui_icon_recolor(lv_obj_t *img, lv_color_t color)
{
    if (!img) {
        return;
    }
    lv_obj_set_style_image_recolor(img, color, 0);
    lv_obj_set_style_image_recolor_opa(img, LV_OPA_COVER, 0);
}
