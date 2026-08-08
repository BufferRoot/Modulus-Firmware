#include "ui_settings_wireless_priv.h"
#include "ui_settings_modals.h"
#include "zb_link_proto.h"
#include "wireless_rpc.h"
#include "wireless_shim_802154.h"
#include "zb_automation.h"
#include "ui_settings_common.h"
#include "ui_internal.h"
#include "ui_touch_sound.h"
#include "audio_shim.h"
#include "nvs_shim.h"
#include "wireless_shim.h"
#include "transport_shim.h"
#include "cnc_cmd_exports.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static lv_obj_t *wl_peer_list_row(lv_obj_t *parent, const char *primary, const char *supporting,
                                  lv_event_cb_t tap_cb, void *tap_ud, lv_event_cb_t overflow_cb,
                                  void *overflow_ud)
{
    lv_obj_t *row = modulus_ui_list_item_create(parent, MOD_UI_ICON_BROADCAST, primary, supporting,
                                                tap_cb, tap_ud);
    lv_obj_set_style_border_width(row, 1, 0);
    lv_obj_set_style_border_side(row, LV_BORDER_SIDE_BOTTOM, 0);
    lv_obj_set_style_border_color(row, modulus_ui_color_outline_variant(), 0);
    lv_obj_set_style_border_opa(row, LV_OPA_30, 0);

    lv_obj_t *more = lv_button_create(row);
    lv_obj_remove_style_all(more);
    lv_obj_set_size(more, MOD_UI_TOUCH_MIN, MOD_UI_TOUCH_MIN);
    lv_obj_set_style_radius(more, MOD_UI_SHAPE_FULL, 0);
    lv_obj_set_style_bg_opa(more, LV_OPA_TRANSP, 0);
    modulus_ui_apply_pressed_state_layer(more);
    lv_obj_t *dots = lv_label_create(more);
    lv_label_set_text(dots, "...");
    lv_obj_set_style_text_color(dots, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(dots, MOD_UI_FONT_BODY_L, 0);
    lv_obj_center(dots);
    lv_obj_add_event_cb(more, overflow_cb, LV_EVENT_SHORT_CLICKED, overflow_ud);
    modulus_ui_touch_ensure_min(more);
    return row;
}

static void espnow_saved_menu_cb(lv_event_t *e)
{
    const int peer_idx = (int)(intptr_t)lv_event_get_user_data(e);
    const int item_idx = (int)(intptr_t)lv_obj_get_user_data(lv_event_get_target(e));
    if (item_idx == 0) {
        if (!modulus_wireless_espnow_activate_saved(peer_idx)) {
            modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
            return;
        }
    } else {
        (void)modulus_wireless_espnow_delete_saved(peer_idx);
        wl_maybe_reinit_espnow_transport();
    }
    wl_rebuild();
}

static void espnow_saved_overflow_cb(lv_event_t *e)
{
    static const char *const k_saved_menu[] = { "Set as bridge", "Remove" };
    modulus_ui_menu_show(lv_event_get_target(e), k_saved_menu, 2, espnow_saved_menu_cb,
                         lv_event_get_user_data(e));
}

void wl_build_main(lv_obj_t *p)
{
    settings_section(p, "Wireless protocols", "ESP32-C6 co-processor via SDIO2.");
    lv_obj_t *w = settings_action_row(p, "Wi-Fi", modulus_wireless_wifi_is_connected() ? "On" : "");
    settings_bind_menu_click(w, nav_to, (void *)(intptr_t)WL_PG_WIFI);
    lv_obj_t *b = settings_action_row(p, "Bluetooth",
                                      modulus_wireless_ble_is_enabled() ? "On" : "");
    settings_bind_menu_click(b, nav_to, (void *)(intptr_t)WL_PG_BT);
    lv_obj_t *en = settings_action_row(p, "ESP-NOW", modulus_wireless_espnow_is_enabled() ? "On" : "");
    settings_bind_menu_click(en, nav_to, (void *)(intptr_t)WL_PG_ESPNOW);

    settings_section(p, "802.15.4 radios", NULL);
    lv_obj_t *z = settings_action_row(p, "Zigbee",
                                      modulus_nvs_get_u8("zigbee", 0) ? "On" : "");
    settings_bind_menu_click(z, nav_to, (void *)(intptr_t)WL_PG_ZIGBEE);
    lv_obj_t *t = settings_action_row(p, "Thread",
                                      modulus_nvs_get_u8("thread", 0) ? "On" : "");
    settings_bind_menu_click(t, nav_to, (void *)(intptr_t)WL_PG_THREAD);

    settings_section(p, "Antenna", NULL);
    settings_detail_row(p, "Active", modulus_nvs_get_u8("ant_ext", 0) ? "External MMCX" : "Internal PCB");
    lv_obj_t *ext = settings_toggle_row(p, "External MMCX", modulus_nvs_get_u8("ant_ext", 0) != 0);
    lv_obj_add_event_cb(ext, ant_ext_cb, LV_EVENT_VALUE_CHANGED, NULL);

    settings_expandable_link(p, "Show radio reference", "Hide radio reference",
                             &wl_main_ref_exp, wl_rebuild);
    if (wl_main_ref_exp) {
        settings_detail_row(p, "Module", "ESP32-C6-MINI-1U");
        settings_detail_row(p, "Transport", "ESP-Hosted SDIO2");
        settings_detail_row(p, "Channels", "ESP-NOW=8 Zigbee=9 Thread=10");
    }

    static settings_reset_ctx_t reset_ctx = {
        .title = "Reset network defaults?",
        .body = "Clears wireless NVS flags and disables radios.",
        .fn = wireless_reset_cb,
    };
    settings_reset_row(p, "Reset network defaults", &reset_ctx);
}

void wl_build_wifi_hub(lv_obj_t *p)
{
    settings_back_row(p, "Wireless", nav_pop);
    settings_section(p, "Status", NULL);
    wl_radio_lbl = settings_detail_row(p, "Radio", modulus_wireless_wifi_radio_text());
    wl_ssid_lbl = settings_detail_row(p, "SSID", modulus_wireless_wifi_ssid_text());
    wl_ip_lbl = settings_detail_row(p, "IP address", modulus_wireless_wifi_ip_text());
    strncpy(wl_radio_cache, modulus_wireless_wifi_radio_text(), sizeof(wl_radio_cache) - 1);
    strncpy(wl_ssid_cache, modulus_wireless_wifi_ssid_text(), sizeof(wl_ssid_cache) - 1);
    strncpy(wl_ip_cache, modulus_wireless_wifi_ip_text(), sizeof(wl_ip_cache) - 1);

    lv_obj_t *wf = settings_toggle_row(p, "Wi-Fi radio", modulus_wireless_wifi_is_enabled());
    lv_obj_add_event_cb(wf, wifi_radio_toggle_cb, LV_EVENT_VALUE_CHANGED, NULL);

    settings_section(p, "Networks", NULL);
    wl_scan_lbl = settings_detail_row(p, "Scan", modulus_wireless_wifi_scan_text());
    strncpy(wl_scan_cache, modulus_wireless_wifi_scan_text(), sizeof(wl_scan_cache) - 1);
    lv_obj_t *scan_btn = settings_action_row(p, "Scan for networks", "");
    settings_bind_menu_click(scan_btn, scan_cb, NULL);

    const bool scanning = modulus_wireless_wifi_is_enabled() &&
                          !modulus_wireless_wifi_scan_done();
    const bool connecting = modulus_wireless_wifi_is_connecting();
    if (modulus_wireless_wifi_scan_done() && modulus_wireless_wifi_scan_count() > 0 &&
        !connecting) {
        settings_section(p, "Results", "Tap to connect");
        const int n = modulus_wireless_wifi_scan_count();
        for (int i = 0; i < n && i < 8; i++) {
            modulus_wifi_ap_t ap = {};
            if (!modulus_wireless_wifi_scan_get(i, &ap)) {
                continue;
            }
            char row[64];
            snprintf(row, sizeof(row), "%.20s  %d dBm  %s", ap.ssid, (int)ap.rssi,
                     modulus_wireless_wifi_auth_text(ap.auth));
            lv_obj_t *r = settings_action_row(p, row, ">");
            settings_bind_menu_click(r, ap_row_click_cb, (void *)(intptr_t)i);
        }
    }

    if (modulus_wireless_wifi_is_connected()) {
        lv_obj_t *dc = settings_destructive_row(p, "Disconnect", "");
        settings_bind_menu_click(dc, disconnect_cb, NULL);
    }

    lv_obj_t *sv = settings_action_row(p, "Saved networks", "");
    settings_bind_menu_click(sv, nav_to, (void *)(intptr_t)WL_PG_WIFI_SAVED);
    settings_link_tab_row(p, "Time sync (NTP)", "System tab", 9);
    lv_obj_t *adv = settings_action_row(p, "Advanced", "");
    settings_bind_menu_click(adv, settings_wl_adv_modal_open_cb,
                             (void *)(intptr_t)WL_PG_WIFI_ADVANCED);

    wl_timer_maybe_start();
    wl_scan_done_cache = modulus_wireless_wifi_scan_done();
    wl_scan_n_cache = modulus_wireless_wifi_scan_count();
    wl_wifi_conn_cache = connecting ? 1 : (modulus_wireless_wifi_is_connected() ? 2 : 0);
    (void)scanning;
}

void wl_build_wifi_saved(lv_obj_t *p)
{
    settings_back_row(p, "Wi-Fi", nav_pop);
    settings_section(p, "Saved", NULL);
    char ssid[33] = {};
    char pass[65] = {};
    if (modulus_nvs_get_str("wf_ssid", ssid, sizeof(ssid)) && ssid[0]) {
        settings_detail_row(p, "SSID", ssid);
        settings_detail_row(p, "Auto-connect", modulus_nvs_get_u8("wf_auto", 1) ? "On" : "Off");
        lv_obj_t *conn = settings_action_row(p, "Connect now", "");
        settings_bind_menu_click(conn, connect_apply_saved_cb, NULL);
        (void)pass;
    } else {
        settings_detail_row(p, "Status", "No saved network");
    }
    if (modulus_wireless_wifi_is_connected()) {
        lv_obj_t *dc = settings_destructive_row(p, "Disconnect", "");
        settings_bind_menu_click(dc, disconnect_cb, NULL);
    }
    if (ssid[0]) {
        lv_obj_t *fg = settings_destructive_row(p, "Forget network", "");
        settings_bind_menu_click(fg, forget_saved_cb, NULL);
    }
}

void connect_apply_saved_cb(lv_event_t *e)
{
    (void)e;
    char ssid[33] = {};
    char pass[65] = {};
    if (modulus_nvs_get_str("wf_ssid", ssid, sizeof(ssid))) {
        modulus_nvs_get_str("wf_pass", pass, sizeof(pass));
        if (!modulus_wireless_wifi_connect(ssid, pass)) {
            modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
            return;
        }
        wl_wifi_conn_cache = 1;
        wl_rebuild();
    }
}

void disconnect_cb(lv_event_t *e)
{
    (void)e;
    modulus_wireless_wifi_disconnect();
    wl_wifi_conn_cache = 0;
    wl_rebuild();
}

void forget_saved_cb(lv_event_t *e)
{
    (void)e;
    modulus_wireless_wifi_disconnect();
    modulus_wireless_wifi_forget_saved();
    wl_wifi_conn_cache = 0;
    wl_rebuild();
}

void wl_build_wifi_sub(lv_obj_t *p, const char *name)
{
    if (!wl_build_skip_back) {
        settings_back_row(p, "Wi-Fi", nav_pop);
    }
    settings_section(p, name, NULL);
    if (wl_page == WL_PG_WIFI_ADVANCED) {
        settings_detail_row(p, "Auto-reconnect", modulus_nvs_get_u8("wf_arecon", 1) ? "On" : "Off");
        lv_obj_t *ar = settings_toggle_row(p, "Auto-reconnect", modulus_nvs_get_u8("wf_arecon", 1) != 0);
        lv_obj_add_event_cb(ar, toggle_nvs_u8_cb, LV_EVENT_VALUE_CHANGED, (void *)"wf_arecon");
        lv_obj_t *au = settings_toggle_row(p, "Auto-connect saved", modulus_nvs_get_u8("wf_auto", 1) != 0);
        lv_obj_add_event_cb(au, toggle_nvs_u8_cb, LV_EVENT_VALUE_CHANGED, (void *)"wf_auto");
        settings_section(p, "IP config", NULL);
        settings_detail_row(p, "Mode", modulus_nvs_get_u8("wf_dhcp", 1) ? "DHCP" : "Static");
        settings_coming_soon_row(p, "Static IP / DNS");
    } else {
        settings_detail_row(p, "Status", modulus_wireless_wifi_ssid_text());
    }
}

void wl_build_bt_hub(lv_obj_t *p)
{
    settings_back_row(p, "Wireless", nav_pop);
    settings_section(p, "Status", NULL);
    wl_bt_radio_lbl = settings_detail_row(p, "Radio", modulus_wireless_ble_status_text());
    wl_bt_paired_lbl = settings_detail_row(p, "Paired", modulus_wireless_ble_paired_text());
    strncpy(wl_bt_radio_cache, modulus_wireless_ble_status_text(), sizeof(wl_bt_radio_cache) - 1);
    strncpy(wl_bt_paired_cache, modulus_wireless_ble_paired_text(), sizeof(wl_bt_paired_cache) - 1);
    lv_obj_t *bt = settings_toggle_row(p, "Bluetooth radio", modulus_wireless_ble_is_enabled());
    lv_obj_add_event_cb(bt, bt_radio_toggle_cb, LV_EVENT_VALUE_CHANGED, NULL);

    if (!modulus_wireless_ble_is_enabled()) {
        settings_note(p, "Enable radio for BLE discovery and pairing.");
    } else {
        settings_section(p, "Paired devices", NULL);
        settings_detail_row(p, "Saved", modulus_wireless_ble_paired_text());
        if (modulus_wireless_ble_is_connected()) {
            lv_obj_t *dc = settings_destructive_row(p, "Disconnect", "");
            settings_bind_menu_click(dc, bt_disconnect_cb, NULL);
        }

        settings_section(p, "Discovery", "Tap device to connect");
        const bool scanning = !modulus_wireless_ble_scan_done() &&
                              !modulus_wireless_ble_is_connecting();
        const bool connecting = modulus_wireless_ble_is_connecting();
        if (connecting) {
            settings_detail_row(p, "Scan", "Connecting...");
        } else if (scanning) {
            settings_detail_row(p, "Scan", "Scanning...");
        } else if (modulus_wireless_ble_scan_done() && modulus_wireless_ble_scan_count() == 0) {
            settings_detail_row(p, "Scan", "No devices found");
        }
        const int bt_n = (scanning || connecting) ? 0 : modulus_wireless_ble_scan_count();
        for (int i = 0; i < bt_n && i < MODULUS_BLE_MAX_SCAN; i++) {
            char name[32];
            int8_t rssi = 0;
            if (!modulus_wireless_ble_scan_get(i, name, sizeof(name), &rssi, NULL, 0)) {
                continue;
            }
            char sup[16];
            snprintf(sup, sizeof(sup), "%d dBm", (int)rssi);
            modulus_ui_list_item_create(p, MOD_UI_ICON_BLUETOOTH, name, sup, bt_device_row_cb,
                                        (void *)(intptr_t)i);
        }
        lv_obj_t *scan_btn = settings_action_row(p, "Scan for devices",
                                                 (scanning || connecting) ? "..." : "");
        settings_bind_menu_click(scan_btn, bt_scan_cb, NULL);

        lv_obj_t *adv = settings_action_row(p, "Advanced", "");
        settings_bind_menu_click(adv, settings_wl_adv_modal_open_cb,
                                 (void *)(intptr_t)WL_PG_BT_ADVANCED);
    }
    wl_timer_maybe_start();
    wl_bt_scan_done_cache = modulus_wireless_ble_scan_done();
    wl_bt_scan_n_cache = modulus_wireless_ble_scan_count();
    wl_bt_conn_cache = modulus_wireless_ble_is_connecting() ? 1 :
                      (modulus_wireless_ble_is_connected() ? 2 : 0);
    wl_bt_pk_cache = modulus_wireless_ble_passkey_state();
    if (wl_bt_pk_cache != WL_BLE_PK_NONE && !wl_bt_pk_modal) {
        wl_bt_passkey_modal_show(wl_bt_pk_cache, modulus_wireless_ble_passkey_value());
    }
}

void wl_build_bt_advanced(lv_obj_t *p)
{
    if (!wl_build_skip_back) {
        settings_back_row(p, "Bluetooth", nav_pop);
    }
    settings_section(p, "Power", NULL);
    settings_coming_soon_row(p, "Turn off when idle");
    settings_coming_soon_row(p, "Background scanning");
    settings_section(p, "Security", NULL);
    settings_coming_soon_row(p, "Require pairing confirmation");
    settings_coming_soon_row(p, "Block unknown devices");
    settings_section(p, "Troubleshooting", NULL);
    lv_obj_t *clr = settings_action_row(p, "Clear paired devices", "");
    settings_bind_menu_click(clr, bt_clear_paired_cb, NULL);
}

void wl_build_802154_hub(lv_obj_t *p, const char *proto, const char *nvs_key, int adv_page)
{
    settings_back_row(p, "Wireless", nav_pop);
    settings_section(p, "Status", NULL);
    const bool is_zb = (strcmp(nvs_key, "zigbee") == 0);
    const bool radio_on = modulus_nvs_get_u8(nvs_key, 0) != 0;
    const char *st = is_zb ? modulus_wireless_zigbee_status_text()
                           : modulus_wireless_thread_status_text();
    const char *net = is_zb ? modulus_wireless_zigbee_network_text()
                            : modulus_wireless_thread_network_text();
    wl_154_radio_lbl = settings_detail_row(p, "Radio", st);
    wl_154_net_lbl = settings_detail_row(p, "Network", net);
    if (is_zb) {
        /* Pairing-window countdown; text driven by wl_refresh_154_labels
         * (settings_note returns void, so use a detail row). */
        wl_zb_permit_lbl = settings_detail_row(p, "Pairing", "Closed");
        if (modulus_wireless_zb_hub_offline()) {
            settings_note(p, "Zigbee hub offline - check wiring/power");
        }
    } else {
        wl_zb_permit_lbl = NULL;
    }
    strncpy(wl_154_radio_cache, st, sizeof(wl_154_radio_cache) - 1);
    strncpy(wl_154_net_cache, net, sizeof(wl_154_net_cache) - 1);
    lv_obj_t *sw = settings_toggle_row(p, "Radio enable", radio_on);
    lv_obj_add_event_cb(sw, generic_radio_toggle_cb, LV_EVENT_VALUE_CHANGED, (void *)nvs_key);

    if (!radio_on) {
        settings_note(p, "Enable radio for network and device control.");
    } else {
        settings_section(p, "Network control", NULL);
        if (is_zb) {
            lv_obj_t *join = settings_action_row(p, "Join network", "");
            settings_bind_menu_click(join, zb_join_cb, NULL);
            lv_obj_t *leave = settings_action_row(p, "Leave network", "");
            settings_bind_menu_click(leave, zb_leave_cb, NULL);
            if (!modulus_wireless_zb_joined()) {
                settings_note(p, "Join the network first, then pair devices.");
            } else if (!modulus_wireless_zigbee_can_control()) {
                settings_note(p, "Detach Thread before Zigbee scan/control.");
            }
        } else {
            lv_obj_t *attach = settings_action_row(p, "Attach network", "");
            settings_bind_menu_click(attach, th_attach_cb, NULL);
            lv_obj_t *detach = settings_action_row(p, "Detach network", "");
            settings_bind_menu_click(detach, th_detach_cb, NULL);
            if (!modulus_wireless_thread_can_control()) {
                settings_note(p, "Attach Thread network for device refresh.");
            }
        }

        settings_section(p, "Discovery",
                         is_zb ? (modulus_wireless_zb_joined()
                                      ? "Opens the network - put the device in pairing mode"
                                      : "Tap to save device")
                               : "Tap to save node");
        const char *scan_txt = is_zb ? modulus_wireless_zigbee_scan_text()
                                     : modulus_wireless_thread_scan_text();
        settings_detail_row(p, "Scan", scan_txt);
        const bool scanning = is_zb ? !modulus_wireless_zigbee_scan_done()
                                    : !modulus_wireless_thread_scan_done();
        /* Show Zigbee joiners as they arrive — "scan" is permit-join, not a
         * Wi-Fi-style list that only fills after the window closes. */
        const int scan_n = is_zb ? modulus_wireless_zigbee_scan_count()
                                 : (scanning ? 0 : modulus_wireless_thread_scan_count());
        for (int i = 0; i < scan_n; i++) {
            char row[56];
            if (is_zb) {
                modulus_zb_device_t d = {};
                if (!modulus_wireless_zigbee_scan_get(i, &d)) {
                    continue;
                }
                if (d.rssi != 0) {
                    snprintf(row, sizeof(row), "%.20s  %d dBm", d.name, (int)d.rssi);
                } else {
                    snprintf(row, sizeof(row), "%.20s", d.name);
                }
                lv_obj_t *r = settings_action_row(p, row, ">");
                settings_bind_menu_click(r, zb_scan_row_cb, (void *)(intptr_t)i);
            } else {
                modulus_th_device_t d = {};
                if (!modulus_wireless_thread_scan_get(i, &d)) {
                    continue;
                }
                snprintf(row, sizeof(row), "%.20s", d.name);
                lv_obj_t *r = settings_action_row(p, row, ">");
                settings_bind_menu_click(r, th_scan_row_cb, (void *)(intptr_t)i);
            }
        }
        lv_obj_t *scan_btn = settings_action_row(
            p,
            is_zb ? (modulus_wireless_zb_joined() ? "Pair devices (permit join)"
                                                         : "Scan for devices")
                  : "Refresh nodes",
            scanning ? "..." : "");
        settings_bind_menu_click(scan_btn, is_zb ? zb_scan_cb : th_scan_cb, NULL);
        lv_obj_t *add_btn = settings_action_row(p, is_zb ? "Add with install code" : "Add node manually",
                                                "");
        settings_bind_menu_click(add_btn, is_zb ? zb_add_modal_show : th_add_modal_show,
                            NULL);

        settings_section(p, "Saved devices", "Toggle on/off");
        const int dev_n = is_zb ? modulus_wireless_zigbee_device_count()
                                : modulus_wireless_thread_device_count();
        if (dev_n == 0) {
            settings_detail_row(p, "Status", "None saved");
        }
        for (int i = 0; i < dev_n; i++) {
            char row[48];
            if (is_zb) {
                modulus_zb_device_t d = {};
                if (!modulus_wireless_zigbee_device_get(i, &d)) {
                    continue;
                }
                snprintf(row, sizeof(row), "%.18s%s", d.name,
                         d.short_addr == 0 ? " (offline)" : "");
                /* Capability-gated controls (ZDO Simple Descriptor):
                 * caps==0 = unknown/legacy -> assume plain On/Off. */
                const bool has_onoff = d.caps == 0 || (d.caps & ZIGBEE_CAP_ONOFF);
                const bool reachable = d.short_addr != 0 && modulus_wireless_zigbee_can_control();
                if (has_onoff) {
                    lv_obj_t *tg = settings_toggle_row(p, row, d.on);
                    lv_obj_add_event_cb(tg, zb_device_toggle_cb, LV_EVENT_VALUE_CHANGED,
                                        (void *)(intptr_t)i);
                    if ((d.caps & ZIGBEE_CAP_LEVEL) && reachable) {
                        lv_obj_t *lv = settings_slider_row(p, "Brightness", d.level, 0, 254);
                        lv_obj_add_event_cb(lv, zb_device_level_cb, LV_EVENT_VALUE_CHANGED,
                                            (void *)(intptr_t)i);
                        lv_obj_add_event_cb(lv, zb_device_level_cb, LV_EVENT_RELEASED,
                                            (void *)(intptr_t)i);
                    }
                } else if (d.caps & ZIGBEE_CAP_COVER) {
                    lv_obj_t *op = settings_action_row(p, row, reachable ? "Open" : "offline");
                    if (reachable) {
                        settings_bind_menu_click(op, zb_cover_open_cb, (void *)(intptr_t)i);
                        lv_obj_t *cl = settings_action_row(p, "Close", "");
                        settings_bind_menu_click(cl, zb_cover_close_cb, (void *)(intptr_t)i);
                        lv_obj_t *st = settings_action_row(p, "Stop", "");
                        settings_bind_menu_click(st, zb_cover_stop_cb, (void *)(intptr_t)i);
                    }
                } else if (d.caps & ZIGBEE_CAP_THERMOSTAT) {
                    settings_detail_row(p, row, "Thermostat - control coming soon");
                } else {
                    settings_detail_row(p, row, "Sensor - reports only");
                }
                lv_obj_t *rn = settings_text_input_row(p, "Name", d.name,
                                                       (int)sizeof(d.name) - 1, NULL);
                lv_obj_add_event_cb(rn, zb_device_rename_cb, LV_EVENT_DEFOCUSED,
                                    (void *)(intptr_t)i);
                lv_obj_add_event_cb(rn, zb_rename_focus_cb, LV_EVENT_FOCUSED, NULL);
                /* Link + power telemetry (LQI from the hub's neighbor table,
                 * power via bound attribute reporting; Tuya scaling P/10 V/10). */
                if (d.short_addr != 0 && (d.lqi != 0 || d.rssi != 0)) {
                    char lk[40];
                    if (d.rssi != 0) {
                        snprintf(lk, sizeof(lk), "LQI %u | %d dBm", (unsigned)d.lqi, (int)d.rssi);
                    } else {
                        snprintf(lk, sizeof(lk), "LQI %u", (unsigned)d.lqi);
                    }
                    settings_detail_row(p, "Link", lk);
                }
                if ((d.caps & ZIGBEE_CAP_SENSOR) && d.zone_seen) {
                    settings_detail_row(p, "Zone",
                                        (d.zone_status & 0x0001u) ? "Alarm (open)" : "Clear");
                }
                if ((d.caps & (ZIGBEE_CAP_POWER | ZIGBEE_CAP_METER)) &&
                    (d.power_raw != 0 || d.volt_raw != 0)) {
                    char pw[44];
                    snprintf(pw, sizeof(pw), "%.1f W | %.1f V | %.2f kWh",
                             d.power_raw / 10.0, d.volt_raw / 10.0, d.energy_raw / 100.0);
                    settings_detail_row(p, "Power", pw);
                }
                if (d.short_addr != 0) {
                    lv_obj_t *idb = settings_action_row(p, "Identify", "blink 5s");
                    settings_bind_menu_click(idb, zb_identify_cb, (void *)(intptr_t)i);
                }
                /* CNC automation (only meaningful for switchable devices). */
                if (has_onoff) {
                    lv_obj_t *au = settings_action_row(p, "CNC automation",
                        modulus_zb_auto_mode_text(modulus_zb_auto_get(i)));
                    settings_bind_menu_click(au, zb_auto_cycle_cb, (void *)(intptr_t)i);
                }
                lv_obj_t *rm = settings_destructive_row(p, "Remove device", "");
                settings_bind_menu_click(rm, zb_device_remove_cb, (void *)(intptr_t)i);
            } else {
                modulus_th_device_t d = {};
                if (!modulus_wireless_thread_device_get(i, &d)) {
                    continue;
                }
                snprintf(row, sizeof(row), "%.18s", d.name);
                lv_obj_t *tg = settings_toggle_row(p, row, d.on);
                lv_obj_add_event_cb(tg, th_device_toggle_cb, LV_EVENT_VALUE_CHANGED,
                                    (void *)(intptr_t)i);
                lv_obj_t *rm = settings_destructive_row(p, "Remove device", "");
                settings_bind_menu_click(rm, th_device_remove_cb, (void *)(intptr_t)i);
            }
        }
    }

    lv_obj_t *adv = settings_action_row(p, "Advanced", "");
    settings_bind_menu_click(adv, settings_wl_adv_modal_open_cb, (void *)(intptr_t)adv_page);
    wl_timer_maybe_start();
    if (is_zb) {
        wl_zb_scan_done_cache = modulus_wireless_zigbee_scan_done();
        wl_zb_scan_n_cache = modulus_wireless_zigbee_scan_count();
    } else {
        wl_th_scan_done_cache = modulus_wireless_thread_scan_done();
        wl_th_scan_n_cache = modulus_wireless_thread_scan_count();
    }
}

void wl_build_802154_advanced(lv_obj_t *p, const char *proto)
{
    if (!wl_build_skip_back) {
        settings_back_row(p, proto, nav_pop);
    }
    const bool is_zb = (strcmp(proto, "Zigbee") == 0);
    settings_section(p, "Radio", NULL);
    if (is_zb) {
        settings_detail_row(p, "Control path",
                            modulus_wireless_zigbee_can_control() ? "NanoH2 hub (UART)"
                                                                  : "Cache only");
        settings_detail_row(p, "Energy scan", modulus_wireless_zigbee_energy_text());
        lv_obj_t *es = settings_action_row(p, "Scan channel energy", "");
        settings_bind_menu_click(es, zb_energy_scan_cb, NULL);
        settings_note(p, "Pick quietest 802.15.4 channel before (re)forming hub.");
        lv_obj_t *dil = settings_toggle_row(p, "Door blocks Cycle Start",
                                            modulus_nvs_get_u8("zb_door_il", 1) != 0);
        lv_obj_add_event_cb(dil, generic_radio_toggle_cb, LV_EVENT_VALUE_CHANGED,
                            (void *)"zb_door_il");
        settings_detail_row(p, "Vacuum off delay (s)", "NVS zb_off_s (default 10)");
    } else {
        settings_detail_row(p, "Control path", modulus_wireless_thread_can_control() ? "Attached"
                                                                                     : "Cache only");
        settings_note(p, "Matter/CoAP ON/OFF needs C6 border router RPC.");
    }
    settings_section(p, "Troubleshooting", NULL);
    lv_obj_t *clr = settings_destructive_row(p, "Clear saved devices", "");
    settings_bind_menu_click(clr, is_zb ? zb_devices_clear_cb : th_devices_clear_cb,
                        NULL);
}

void wl_build_espnow_hub(lv_obj_t *p)
{
    const bool on = modulus_wireless_espnow_is_enabled();

    settings_back_row(p, "Wireless", nav_pop);

    /* STATUS — single combined radio control + live bridge/channel state. */
    settings_section(p, "Status", NULL);
    wl_en_bridge_lbl = settings_detail_row(p, "Bridge peer", modulus_wireless_espnow_bridge_text());
    strncpy(wl_en_bridge_cache, modulus_wireless_espnow_bridge_text(), sizeof(wl_en_bridge_cache) - 1);
    char ch_txt[24];
    snprintf(ch_txt, sizeof(ch_txt), "%u (match bridge)", (unsigned)modulus_wireless_espnow_channel());
    settings_detail_row(p, "Channel", ch_txt);

    lv_obj_t *en = settings_toggle_row(p, "ESP-NOW radio", on);
    lv_obj_add_event_cb(en, espnow_toggle_cb, LV_EVENT_VALUE_CHANGED, NULL);

    if (!on) {
        settings_note(p, "Enable radio for peer discovery and bridge.");
    } else {
        /* Scan sits directly under the on/off toggle. */
        const bool scanning = !modulus_wireless_espnow_scan_done();
        wl_en_scan_lbl = settings_detail_row(p, "Scan", modulus_wireless_espnow_scan_text());
        strncpy(wl_en_scan_cache, modulus_wireless_espnow_scan_text(), sizeof(wl_en_scan_cache) - 1);
        lv_obj_t *scan_btn = settings_action_row(p, "Scan for peers", scanning ? "..." : "");
        settings_bind_menu_click(scan_btn, espnow_scan_cb, NULL);

        /* Discovered (not-yet-saved) peers — tap to save + make active. */
        const int en_n = scanning ? 0 : modulus_wireless_espnow_scan_count();
        bool printed_disc = false;
        for (int i = 0; i < en_n && i < MODULUS_ESPNOW_MAX_SCAN; i++) {
            modulus_espnow_peer_t peer = {};
            if (!modulus_wireless_espnow_scan_get(i, &peer)) {
                continue;
            }
            if (!printed_disc) {
                settings_section(p, "Discovered", "Tap to save + use");
                printed_disc = true;
            }
            char sup[16];
            const char *supporting = NULL;
            if (peer.rssi != 0) {
                snprintf(sup, sizeof(sup), "%d dBm", (int)peer.rssi);
                supporting = sup;
            }
            modulus_ui_list_item_create(p, MOD_UI_ICON_BROADCAST, peer.mac, supporting,
                                        espnow_peer_row_cb, (void *)(intptr_t)i);
        }

        /* Saved peers — tap to switch active target, Remove to delete. */
        settings_section(p, "Saved peers", "Tap to use; Active = bridge target");
        const int saved_n = modulus_wireless_espnow_saved_count();
        if (saved_n == 0) {
            settings_detail_row(p, "Status", "None saved");
        }
        for (int i = 0; i < saved_n && i < MODULUS_ESPNOW_MAX_PEERS; i++) {
            modulus_espnow_peer_t sp = {};
            if (!modulus_wireless_espnow_saved_get(i, &sp)) {
                continue;
            }
            const bool active = modulus_wireless_espnow_saved_is_active(i);
            wl_peer_list_row(p, sp.mac, active ? "Active" : NULL, espnow_saved_activate_cb,
                             (void *)(intptr_t)i, espnow_saved_overflow_cb,
                             (void *)(intptr_t)i);
        }
        lv_obj_t *add = settings_action_row(p, "Add MAC manually", "");
        settings_bind_menu_click(add, espnow_mac_modal_show, NULL);

        settings_section(p, "Traffic", NULL);
        char traf[32];
        snprintf(traf, sizeof(traf), "%lu / %lu",
                 (unsigned long)modulus_wireless_espnow_tx_count(),
                 (unsigned long)modulus_wireless_espnow_rx_count());
        wl_en_traf_lbl = settings_detail_row(p, "CNC TX / RX", traf);
        strncpy(wl_en_traf_cache, traf, sizeof(wl_en_traf_cache) - 1);
        if (!modulus_wireless_espnow_transport_active()) {
            settings_note(p,
                          "Counters track GrblHAL CNC traffic only. Set CNC transport "
                          "to ESP-NOW and tap Connect on the CNC tab.");
        }
    }

    settings_link_tab_row(p, "CNC Connection tab", "Configure", 0);
    if (modulus_wireless_espnow_debug_active()) {
        settings_section(p, "Debug state", "Live CNC + transport snapshot");
        const char *snap = modulus_wireless_espnow_debug_snapshot();
        const char *last = modulus_wireless_espnow_debug_last_event();
        wl_en_dbg_snap_lbl = settings_detail_row(p, "Snapshot", snap);
        strncpy(wl_en_dbg_snap_cache, snap, sizeof(wl_en_dbg_snap_cache) - 1);
        wl_en_dbg_last_lbl = settings_detail_row(p, "Last event", last);
        strncpy(wl_en_dbg_last_cache, last, sizeof(wl_en_dbg_last_cache) - 1);
        settings_note(p, "Serial: filter en_dbg wl_espnow espnow_tx");
    }
    lv_obj_t *adv = settings_action_row(p, "Advanced", "");
    settings_bind_menu_click(adv, settings_wl_adv_modal_open_cb,
                             (void *)(intptr_t)WL_PG_ESPNOW_ADVANCED);
    wl_timer_maybe_start();
    wl_en_scan_done_cache = modulus_wireless_espnow_scan_done();
    wl_en_scan_n_cache = modulus_wireless_espnow_scan_count();
}

void wl_build_espnow_adv(lv_obj_t *p)
{
    if (!wl_build_skip_back) {
        settings_back_row(p, "ESP-NOW", nav_pop);
    }
    settings_section(p, "Debug", "Serial monitor logging + UI snapshot");
    static const char *const k_wl_log[] = {"Off", "Debug", "Verbose"};
    lv_obj_t *log_dd = settings_segmented_row(p, "Log level", k_wl_log, 3,
                                              modulus_wireless_espnow_log_level(), 92);
    lv_obj_add_event_cb(log_dd, espnow_log_dd_cb, LV_EVENT_VALUE_CHANGED, NULL);
    settings_note(p, "Debug: key transitions. Verbose: SDIO events + TX/RX.");
    settings_section(p, "Radio", NULL);
    lv_obj_t *ch = settings_dropdown_row(p, "Channel", "1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n13",
                                         modulus_nvs_get_u8("en_chan", 0));
    lv_obj_add_event_cb(ch, dd_u8_cb, LV_EVENT_VALUE_CHANGED, (void *)"en_chan");
    /* Default 24 Mbps OFDM — adaptive fallback drops tiers on fail streaks. */
    lv_obj_t *rate = settings_dropdown_row(
        p, "PHY rate",
        "1 Mbps\n2 Mbps\n5.5 Mbps\n11 Mbps\n6 Mbps OFDM\n12 Mbps OFDM\n24 Mbps OFDM\nMCS0\nMCS3",
        modulus_nvs_get_u8("en_rate", 6));
    lv_obj_add_event_cb(rate, dd_u8_cb, LV_EVENT_VALUE_CHANGED, (void *)"en_rate");
    settings_note(p, "Adaptive: 3 send fails drop one tier; recovers after clean sends.");
    lv_obj_t *enc = settings_toggle_row(p, "PMK encryption", modulus_nvs_get_u8("en_enc", 0) != 0);
    lv_obj_add_event_cb(enc, toggle_nvs_u8_cb, LV_EVENT_VALUE_CHANGED, (void *)"en_enc");
    settings_detail_row(p, "PMK", "MODULUS_ENOW_PMK (fixed)");
    settings_section(p, "Peers", NULL);
    lv_obj_t *clr = settings_destructive_row(p, "Clear saved scan list", "");
    settings_bind_menu_click(clr, espnow_clear_peers_cb, NULL);
}

void wl_wireless_build_page(lv_obj_t *panel)
{
    switch (wl_page) {
    case WL_PG_MAIN:
        wl_build_main(panel);
        break;
    case WL_PG_WIFI:
        wl_build_wifi_hub(panel);
        break;
    case WL_PG_WIFI_SAVED:
        wl_build_wifi_saved(panel);
        break;
    case WL_PG_WIFI_DETAILS:
    case WL_PG_WIFI_CONNECT:
        wl_build_wifi_sub(panel, "Details");
        break;
    case WL_PG_BT:
        wl_build_bt_hub(panel);
        break;
    case WL_PG_ZIGBEE:
        wl_build_802154_hub(panel, "Zigbee", "zigbee", WL_PG_ZIGBEE_ADVANCED);
        break;
    case WL_PG_THREAD:
        wl_build_802154_hub(panel, "Thread", "thread", WL_PG_THREAD_ADVANCED);
        break;
    case WL_PG_ESPNOW:
        wl_build_espnow_hub(panel);
        break;
    default:
        wl_build_main(panel);
        break;
    }
}

