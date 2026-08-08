#include "ui_settings_wireless_priv.h"
#include "ui_settings_wireless_kb.h"
#include "ui_settings_common.h"
#include "ui_touch_sound.h"
#include "audio_shim.h"
#include "nvs_shim.h"
#include "wireless_shim.h"
#include "transport_shim.h"
#include "cnc_cmd_exports.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void generic_radio_toggle_cb(lv_event_t *e)
{
    const char *key = lv_event_get_user_data(e);
    const bool on = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
    modulus_nvs_set_u8(key, on ? 1 : 0);
    if (strcmp(key, "zigbee") == 0) {
        if (on) {
            if (!modulus_wireless_zigbee_enable()) {
                lv_obj_remove_state(lv_event_get_target(e), LV_STATE_CHECKED);
            }
        } else {
            modulus_wireless_zigbee_disable();
        }
    } else if (strcmp(key, "thread") == 0) {
        if (on) {
            modulus_wireless_thread_enable();
        } else {
            modulus_wireless_thread_disable();
        }
    }
    wl_rebuild();
}
void wireless_reset_cb(void)
{
    modulus_wireless_wifi_forget_saved();
    modulus_wireless_wifi_disable();
    modulus_wireless_espnow_disable();
    modulus_wireless_zigbee_disable();
    modulus_wireless_thread_disable();
    modulus_wireless_zigbee_devices_clear();
    modulus_wireless_thread_devices_clear();
    modulus_wireless_ble_disable();
    wl_page = WL_PG_MAIN;
    wl_hist_n = 0;
    wl_rebuild();
}

void ant_ext_cb(lv_event_t *e)
{
    const bool on = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
    modulus_wireless_set_antenna_external(on);
}

void toggle_nvs_u8_cb(lv_event_t *e)
{
    const char *key = lv_event_get_user_data(e);
    modulus_nvs_set_u8(key, lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED) ? 1 : 0);
    if (key && strcmp(key, "en_enc") == 0) {
        wl_maybe_reinit_espnow_transport();
    }
}
