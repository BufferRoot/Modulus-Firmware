#include "ui_icons.h"
#include "ui_internal.h"

/* SoC tiers (status bar vertical Phosphor):
 *   charging          -> charging icon, green
 *   fast charge       -> plus icon, blue (rate via Zig path; C keeps charging)
 *   error / no pack   -> warning icon, red
 *   full   90-100%    -> full, green
 *   high   71-89%     -> high, chrome
 *   medium 41-70%     -> medium, chrome
 *   low    11-40%     -> low, amber
 *   empty   0-10%     -> empty, red
 */

modulus_ui_icon_id_t modulus_ui_icon_battery_for_state(uint8_t charge_state, uint8_t pct, bool warn)
{
    if (charge_state == 3) {
        return MOD_UI_ICON_BATTERY_WARNING;
    }
    if (charge_state == 1) {
        return MOD_UI_ICON_BATTERY_CHARGING;
    }
    if (warn) {
        return MOD_UI_ICON_BATTERY_WARNING;
    }
    if (charge_state == 2 || pct >= 90) {
        return MOD_UI_ICON_BATTERY_FULL;
    }
    if (pct >= 71) {
        return MOD_UI_ICON_BATTERY_HIGH;
    }
    if (pct >= 41) {
        return MOD_UI_ICON_BATTERY_MEDIUM;
    }
    if (pct >= 11) {
        return MOD_UI_ICON_BATTERY_LOW;
    }
    return MOD_UI_ICON_BATTERY_EMPTY;
}

lv_color_t modulus_ui_icon_battery_color_for_state(uint8_t charge_state, uint8_t pct, bool warn)
{
    if (charge_state == 1 || charge_state == 2) {
        return modulus_ui_color_success();
    }
    if (charge_state == 3 || warn) {
        return modulus_ui_color_error();
    }
    if (pct >= 90) {
        return modulus_ui_color_success();
    }
    if (pct >= 41) {
        return modulus_ui_color_icon_chrome();
    }
    if (pct >= 11) {
        return modulus_ui_color_warning();
    }
    return modulus_ui_color_error();
}
