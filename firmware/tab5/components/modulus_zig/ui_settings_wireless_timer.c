#include "ui_settings_wireless_priv.h"
#include "ui_settings_wireless_kb.h"
#include "ui_settings_modals.h"
#include "ui_settings_common.h"
#include "ui_touch_sound.h"
#include "audio_shim.h"
#include "nvs_shim.h"
#include "wireless_shim.h"
#include "wireless_rpc.h"
#include "transport_shim.h"
#include "cnc_cmd_exports.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void wl_timer_cb(lv_timer_t *t);

void wl_timer_stop_core(void)
{
    if (wl_timer) {
        lv_timer_delete(wl_timer);
        wl_timer = NULL;
    }
    modulus_wireless_ble_scan_stop();
    wl_radio_lbl = NULL;
    wl_ssid_lbl = NULL;
    wl_ip_lbl = NULL;
    wl_scan_lbl = NULL;
    wl_bt_radio_lbl = NULL;
    wl_bt_paired_lbl = NULL;
    wl_154_radio_lbl = NULL;
    wl_154_net_lbl = NULL;
    wl_zb_permit_lbl = NULL; /* missing here = dangling label -> LVGL load fault */
    wl_scan_done_cache = false;
    wl_scan_n_cache = -1;
    wl_bt_scan_done_cache = false;
    wl_bt_scan_n_cache = -1;
    wl_bt_conn_cache = 255;
    wl_bt_pk_cache = 255;
    wl_en_bridge_lbl = NULL;
    wl_en_scan_lbl = NULL;
    wl_en_traf_lbl = NULL;
    wl_en_dbg_snap_lbl = NULL;
    wl_en_dbg_last_lbl = NULL;
    wl_en_scan_done_cache = false;
    wl_en_scan_n_cache = -1;
    wl_en_scan_fail_cache = false;
    wl_zb_scan_done_cache = false;
    wl_zb_scan_n_cache = -1;
    wl_th_scan_done_cache = false;
    wl_th_scan_n_cache = -1;
    wl_wifi_conn_cache = 255;
}

void wl_timer_stop_activity(void)
{
    wl_timer_stop_core();
    wl_scrolling = false;
    wl_rebuild_pending = false;
    modulus_wireless_zigbee_scan_stop();
    modulus_wireless_thread_scan_stop();
    wl_connect_modal_hide();
    wl_bt_passkey_modal_hide();
    wl_espnow_mac_modal_hide();
    wl_zb_add_modal_hide();
    wl_th_add_modal_hide();
    settings_wl_adv_modal_hide();
}

static bool wl_page_needs_timer(void)
{
    return wl_page == WL_PG_WIFI || wl_page == WL_PG_BT || wl_page == WL_PG_ZIGBEE || wl_page == WL_PG_THREAD ||
           wl_page == WL_PG_ESPNOW;
}

void wl_timer_maybe_start(void)
{
    if (!wl_timer && wl_page_needs_timer()) {
        wl_timer = lv_timer_create(wl_timer_cb, 1000, NULL);
    }
}

void modulus_ui_settings_wireless_tab_stop_timer(void)
{
    wl_timer_stop_activity();
}

void modulus_ui_settings_wireless_tab_pause_activity(void)
{
    if (wl_timer) {
        lv_timer_pause(wl_timer);
    }
    modulus_wireless_ble_scan_stop();
    modulus_wireless_zigbee_scan_stop();
    modulus_wireless_thread_scan_stop();
    wl_connect_modal_hide();
    wl_bt_passkey_modal_hide();
    wl_espnow_mac_modal_hide();
    wl_zb_add_modal_hide();
    wl_th_add_modal_hide();
    settings_wl_adv_modal_hide();
}

void modulus_ui_settings_wireless_tab_resume_activity(void)
{
    wl_timer_maybe_start();
    if (wl_timer) {
        lv_timer_resume(wl_timer);
        wl_timer_tick();
    }
}

void wl_refresh_wifi_labels(void)
{
    const char *r = modulus_wireless_wifi_radio_text();
    const char *s = modulus_wireless_wifi_ssid_text();
    const char *ip = modulus_wireless_wifi_ip_text();
    const char *sc = modulus_wireless_wifi_scan_text();
    if (wl_radio_lbl && strcmp(wl_radio_cache, r) != 0) {
        strncpy(wl_radio_cache, r, sizeof(wl_radio_cache) - 1);
        lv_label_set_text(wl_radio_lbl, wl_radio_cache);
    }
    if (wl_ssid_lbl && strcmp(wl_ssid_cache, s) != 0) {
        strncpy(wl_ssid_cache, s, sizeof(wl_ssid_cache) - 1);
        lv_label_set_text(wl_ssid_lbl, wl_ssid_cache);
    }
    if (wl_ip_lbl && strcmp(wl_ip_cache, ip) != 0) {
        strncpy(wl_ip_cache, ip, sizeof(wl_ip_cache) - 1);
        lv_label_set_text(wl_ip_lbl, wl_ip_cache);
    }
    if (wl_scan_lbl && strcmp(wl_scan_cache, sc) != 0) {
        strncpy(wl_scan_cache, sc, sizeof(wl_scan_cache) - 1);
        lv_label_set_text(wl_scan_lbl, wl_scan_cache);
    }
}

void wl_refresh_bt_labels(void)
{
    const char *r = modulus_wireless_ble_status_text();
    const char *p = modulus_wireless_ble_paired_text();
    if (wl_bt_radio_lbl && strcmp(wl_bt_radio_cache, r) != 0) {
        strncpy(wl_bt_radio_cache, r, sizeof(wl_bt_radio_cache) - 1);
        lv_label_set_text(wl_bt_radio_lbl, wl_bt_radio_cache);
    }
    if (wl_bt_paired_lbl && strcmp(wl_bt_paired_cache, p) != 0) {
        strncpy(wl_bt_paired_cache, p, sizeof(wl_bt_paired_cache) - 1);
        lv_label_set_text(wl_bt_paired_lbl, wl_bt_paired_cache);
    }
}

void wl_refresh_154_labels(bool zigbee)
{
    const char *r = zigbee ? modulus_wireless_zigbee_status_text()
                           : modulus_wireless_thread_status_text();
    const char *n = zigbee ? modulus_wireless_zigbee_network_text()
                           : modulus_wireless_thread_network_text();
    if (wl_154_radio_lbl && strcmp(wl_154_radio_cache, r) != 0) {
        strncpy(wl_154_radio_cache, r, sizeof(wl_154_radio_cache) - 1);
        lv_label_set_text(wl_154_radio_lbl, wl_154_radio_cache);
    }
    if (wl_154_net_lbl && strcmp(wl_154_net_cache, n) != 0) {
        strncpy(wl_154_net_cache, n, sizeof(wl_154_net_cache) - 1);
        lv_label_set_text(wl_154_net_lbl, wl_154_net_cache);
    }
    if (zigbee && wl_zb_permit_lbl) {
        /* Pairing countdown: the C6 only reports permit changes on open/close
         * signals, so tick a local shadow between events and resync whenever
         * the reported value moves. */
        static uint8_t s_evt_val;
        static int s_shadow;
        const uint8_t evt = modulus_wireless_zb_permit_remaining();
        if (evt != s_evt_val) {
            s_evt_val = evt;
            s_shadow = evt;
        } else if (s_shadow > 0) {
            s_shadow--;
        }
        char buf[36];
        if (s_shadow > 0) {
            snprintf(buf, sizeof(buf), "Open - %ds left", s_shadow);
        } else {
            snprintf(buf, sizeof(buf), "Closed");
        }
        modulus_ui_label_set_text_if_changed(wl_zb_permit_lbl, buf);
    }
}

void wl_refresh_espnow_labels(void)
{
    const char *b = modulus_wireless_espnow_bridge_text();
    const char *sc = modulus_wireless_espnow_scan_text();
    char traf[32];
    snprintf(traf, sizeof(traf), "%lu / %lu",
             (unsigned long)modulus_wireless_espnow_tx_count(),
             (unsigned long)modulus_wireless_espnow_rx_count());
    if (wl_en_bridge_lbl && strcmp(wl_en_bridge_cache, b) != 0) {
        strncpy(wl_en_bridge_cache, b, sizeof(wl_en_bridge_cache) - 1);
        lv_label_set_text(wl_en_bridge_lbl, wl_en_bridge_cache);
    }
    if (wl_en_scan_lbl && strcmp(wl_en_scan_cache, sc) != 0) {
        strncpy(wl_en_scan_cache, sc, sizeof(wl_en_scan_cache) - 1);
        lv_label_set_text(wl_en_scan_lbl, wl_en_scan_cache);
    }
    if (wl_en_traf_lbl && strcmp(wl_en_traf_cache, traf) != 0) {
        strncpy(wl_en_traf_cache, traf, sizeof(wl_en_traf_cache) - 1);
        lv_label_set_text(wl_en_traf_lbl, wl_en_traf_cache);
    }
    if (modulus_wireless_espnow_debug_active()) {
        const char *snap = modulus_wireless_espnow_debug_snapshot();
        const char *last = modulus_wireless_espnow_debug_last_event();
        if (wl_en_dbg_snap_lbl && strcmp(wl_en_dbg_snap_cache, snap) != 0) {
            strncpy(wl_en_dbg_snap_cache, snap, sizeof(wl_en_dbg_snap_cache) - 1);
            lv_label_set_text(wl_en_dbg_snap_lbl, wl_en_dbg_snap_cache);
        }
        if (wl_en_dbg_last_lbl && strcmp(wl_en_dbg_last_cache, last) != 0) {
            strncpy(wl_en_dbg_last_cache, last, sizeof(wl_en_dbg_last_cache) - 1);
            lv_label_set_text(wl_en_dbg_last_lbl, wl_en_dbg_last_cache);
        }
    }
}

static void wl_timer_cb(lv_timer_t *t)
{
    (void)t;
    modulus_wireless_poll();
    if (wl_page == WL_PG_WIFI) {
        const bool scan_done = modulus_wireless_wifi_scan_done();
        const int scan_n = modulus_wireless_wifi_scan_count();
        uint8_t conn_st = 0;
        if (modulus_wireless_wifi_is_connecting()) {
            conn_st = 1;
        } else if (modulus_wireless_wifi_is_connected()) {
            conn_st = 2;
        }
        if (scan_done != wl_scan_done_cache ||
            (scan_done && scan_n != wl_scan_n_cache) ||
            conn_st != wl_wifi_conn_cache) {
            wl_scan_done_cache = scan_done;
            wl_scan_n_cache = scan_n;
            wl_wifi_conn_cache = conn_st;
            wl_rebuild();
            return;
        }
        wl_refresh_wifi_labels();
        return;
    }
    if (wl_page == WL_PG_BT) {
        const bool scan_done = modulus_wireless_ble_scan_done();
        const int scan_n = modulus_wireless_ble_scan_count();
        uint8_t conn_st = 0;
        if (modulus_wireless_ble_is_connecting()) {
            conn_st = 1;
        } else if (modulus_wireless_ble_is_connected()) {
            conn_st = 2;
        }
        const uint8_t pk_st = modulus_wireless_ble_passkey_state();
        if (scan_done != wl_bt_scan_done_cache ||
            (scan_done && scan_n != wl_bt_scan_n_cache) ||
            conn_st != wl_bt_conn_cache || pk_st != wl_bt_pk_cache) {
            wl_bt_scan_done_cache = scan_done;
            wl_bt_scan_n_cache = scan_n;
            wl_bt_conn_cache = conn_st;
            wl_bt_pk_cache = pk_st;
            wl_rebuild();
            return;
        }
        if (pk_st != WL_BLE_PK_NONE && !wl_bt_pk_modal) {
            wl_bt_passkey_modal_show(pk_st, modulus_wireless_ble_passkey_value());
        }
        wl_refresh_bt_labels();
        return;
    }
    if (wl_page == WL_PG_ESPNOW) {
        const bool scan_done = modulus_wireless_espnow_scan_done();
        const int scan_n = modulus_wireless_espnow_scan_count();
        const bool scan_fail = scan_done && modulus_wireless_espnow_scan_failed();
        if (modulus_wireless_espnow_debug_active()) {
            const char *snap = modulus_wireless_espnow_debug_snapshot();
            const char *last = modulus_wireless_espnow_debug_last_event();
            if (strcmp(snap, wl_en_dbg_snap_cache) != 0 || strcmp(last, wl_en_dbg_last_cache) != 0) {
                wl_refresh_espnow_labels();
            }
        }
        if (scan_done != wl_en_scan_done_cache ||
            (scan_done && scan_n != wl_en_scan_n_cache) ||
            scan_fail != wl_en_scan_fail_cache) {
            if (scan_done && scan_fail && !wl_en_scan_fail_cache) {
                modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
            }
            wl_en_scan_done_cache = scan_done;
            wl_en_scan_n_cache = scan_n;
            wl_en_scan_fail_cache = scan_fail;
            wl_rebuild();
            return;
        }
        wl_refresh_espnow_labels();
        return;
    }
    if (wl_page == WL_PG_ZIGBEE) {
        const bool scan_done = modulus_wireless_zigbee_scan_done();
        const int scan_n = modulus_wireless_zigbee_scan_count();
        const uint32_t state_gen = modulus_wireless_zigbee_state_gen();
        if (scan_done != wl_zb_scan_done_cache ||
            scan_n != wl_zb_scan_n_cache ||
            state_gen != wl_zb_state_gen_cache) {
            wl_zb_scan_done_cache = scan_done;
            wl_zb_scan_n_cache = scan_n;
            wl_zb_state_gen_cache = state_gen;
            wl_rebuild();
            return;
        }
        wl_refresh_154_labels(true);
        return;
    }
    if (wl_page == WL_PG_THREAD) {
        const bool scan_done = modulus_wireless_thread_scan_done();
        const int scan_n = modulus_wireless_thread_scan_count();
        if (scan_done != wl_th_scan_done_cache ||
            (scan_done && scan_n != wl_th_scan_n_cache)) {
            wl_th_scan_done_cache = scan_done;
            wl_th_scan_n_cache = scan_n;
            wl_rebuild();
            return;
        }
        wl_refresh_154_labels(false);
    }
}

void wl_timer_tick(void)
{
    wl_timer_cb(NULL);
}
