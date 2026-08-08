#pragma once

#include <lvgl.h>
#include <stdbool.h>
#include <stdint.h>

/* Phosphor Light mapping (LV_SYMBOL_* -> IconId):
 * POWER          -> MOD_UI_ICON_POWER
 * SETTINGS       -> MOD_UI_ICON_GEAR (tabs) / MOD_UI_ICON_GEAR_SIX (status bar)
 * BATTERY_*      -> MOD_UI_ICON_BATTERY_* (vertical stems in status bar)
 * PLAY           -> MOD_UI_ICON_PLAY (fill)
 * PAUSE          -> MOD_UI_ICON_PAUSE (fill)
 * STOP           -> MOD_UI_ICON_STOP (fill)
 * REFRESH        -> MOD_UI_ICON_SPINDLE (ArrowsClockwise)
 * TINT           -> MOD_UI_ICON_COOLANT (Drop)
 * LOOP (fan)     -> MOD_UI_ICON_FAN
 * STEPS          -> MOD_UI_ICON_SINGLE_STEP (Steps)
 * HOME           -> MOD_UI_ICON_HOUSE (light) / MOD_UI_ICON_HOUSE_FILL (dashboard)
 * OVR UP/DOWN    -> MOD_UI_ICON_ARROW_UP/DOWN (regular)
 * UP/DOWN        -> MOD_UI_ICON_CARET_UP/DOWN (legacy light)
 * CLOSE          -> MOD_UI_ICON_X
 * DRIVE (MPG)    -> MOD_UI_ICON_MPG (Joystick)
 * LOOP (CNC tab) -> MOD_UI_ICON_CNC (Cpu)
 * IMAGE          -> MOD_UI_ICON_MONITOR
 * VOLUME_MAX     -> MOD_UI_ICON_SPEAKER
 * WIFI           -> MOD_UI_ICON_WIFI
 * BLUETOOTH      -> MOD_UI_ICON_BLUETOOTH
 * BROADCAST      -> MOD_UI_ICON_BROADCAST (ESP-NOW)
 * EYE_OPEN       -> MOD_UI_ICON_EYE
 * DRIVE (store)  -> MOD_UI_ICON_STORAGE
 * CHARGE         -> MOD_UI_ICON_LIGHTNING
 * BACKSPACE      -> MOD_UI_ICON_BACKSPACE
 * OK             -> MOD_UI_ICON_CHECK
 * ZERO           -> MOD_UI_ICON_ZERO (regular)
 * MIST           -> MOD_UI_ICON_CLOUD_FOG (CloudFog)
 * MACRO          -> MOD_UI_ICON_SCROLL (Scroll)
 * ZERO ALL       -> MOD_UI_ICON_CROSSHAIR (Crosshair)
 * SPINDLE CCW    -> MOD_UI_ICON_SPINDLE_CCW (ArrowsCounterClockwise)
 */

typedef enum {
    MOD_UI_ICON_POWER = 0,
    MOD_UI_ICON_GEAR,
    MOD_UI_ICON_GEAR_SIX,
    MOD_UI_ICON_BATTERY_FULL,
    MOD_UI_ICON_BATTERY_HIGH,
    MOD_UI_ICON_BATTERY_MEDIUM,
    MOD_UI_ICON_BATTERY_LOW,
    MOD_UI_ICON_BATTERY_EMPTY,
    MOD_UI_ICON_BATTERY_CHARGING,
    MOD_UI_ICON_BATTERY_WARNING,
    MOD_UI_ICON_PLAY,
    MOD_UI_ICON_PAUSE,
    MOD_UI_ICON_STOP,
    MOD_UI_ICON_SPINDLE,
    MOD_UI_ICON_COOLANT,
    MOD_UI_ICON_FAN,
    MOD_UI_ICON_SINGLE_STEP,
    MOD_UI_ICON_HOUSE,
    MOD_UI_ICON_HOUSE_FILL,
    MOD_UI_ICON_ARROW_UP,
    MOD_UI_ICON_ARROW_DOWN,
    MOD_UI_ICON_CARET_UP,
    MOD_UI_ICON_CARET_DOWN,
    MOD_UI_ICON_X,
    MOD_UI_ICON_MPG,
    MOD_UI_ICON_CNC,
    MOD_UI_ICON_MONITOR,
    MOD_UI_ICON_SPEAKER,
    MOD_UI_ICON_WIFI,
    MOD_UI_ICON_BLUETOOTH,
    MOD_UI_ICON_BROADCAST,
    MOD_UI_ICON_EYE,
    MOD_UI_ICON_STORAGE,
    MOD_UI_ICON_LIGHTNING,
    MOD_UI_ICON_BACKSPACE,
    MOD_UI_ICON_CHECK,
    MOD_UI_ICON_ZERO,
    MOD_UI_ICON_CLOUD_FOG,
    MOD_UI_ICON_SCROLL,
    MOD_UI_ICON_CROSSHAIR,
    MOD_UI_ICON_SPINDLE_CCW,
    MOD_UI_ICON_COUNT
} modulus_ui_icon_id_t;

typedef enum {
    MOD_UI_ICON_SZ_24 = 24,
    MOD_UI_ICON_SZ_32 = 32,
    MOD_UI_ICON_SZ_40 = 40,
} modulus_ui_icon_size_t;

/* Prefer modulus_ui_icon_recolor(..., modulus_ui_color_*()) — no hardcoded hex. */

const lv_image_dsc_t *modulus_ui_icon_dsc(modulus_ui_icon_id_t id, modulus_ui_icon_size_t sz);
modulus_ui_icon_id_t modulus_ui_icon_battery_for_state(uint8_t charge_state, uint8_t pct, bool warn);
lv_color_t modulus_ui_icon_battery_color_for_state(uint8_t charge_state, uint8_t pct, bool warn);

lv_obj_t *modulus_ui_icon_create(lv_obj_t *parent, modulus_ui_icon_id_t id, modulus_ui_icon_size_t sz);
void modulus_ui_icon_set(lv_obj_t *img, modulus_ui_icon_id_t id, modulus_ui_icon_size_t sz);
void modulus_ui_icon_recolor(lv_obj_t *img, lv_color_t color);
