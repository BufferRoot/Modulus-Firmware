#include "ui_icons.h"
#include "ui_internal.h"


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
    if (pct >= 76) {
        return MOD_UI_ICON_BATTERY_FULL;
    }
    if (pct >= 51) {
        return MOD_UI_ICON_BATTERY_HIGH;
    }
    if (pct >= 26) {
        return MOD_UI_ICON_BATTERY_MEDIUM;
    }
    if (pct >= 5) {
        return MOD_UI_ICON_BATTERY_LOW;
    }
    return MOD_UI_ICON_BATTERY_EMPTY;
}

/* Battery icon recolor tiers (status bar):
 *   charging          -> green  #24D391
 *   warn (low/no-pack)-> amber  #FFB800
 *   full  76-100%     -> green  #24D391
 *   high  51-75%      -> white  #E8EAED
 *   medium 26-50%     -> white  #E8EAED
 *   low    5-25%      -> amber  #FFB800
 *   empty  0-4%       -> red    #FF4D4D
 */
lv_color_t modulus_ui_icon_battery_color_for_state(uint8_t charge_state, uint8_t pct, bool warn)
{
    if (charge_state == 1 || charge_state == 2) {
        return modulus_ui_color_success();
    }
    if (charge_state == 3 || warn) {
        return modulus_ui_color_warning();
    }
    if (pct >= 76) {
        return modulus_ui_color_success();
    }
    if (pct >= 26) {
        return modulus_ui_color_icon_chrome();
    }
    if (pct >= 5) {
        return modulus_ui_color_warning();
    }
    return modulus_ui_color_error();
}
