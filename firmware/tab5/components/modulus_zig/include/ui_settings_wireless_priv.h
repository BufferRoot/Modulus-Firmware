#pragma once

#include "ui_settings_priv.h"
#include <lvgl.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    WL_PG_MAIN = 0,
    WL_PG_WIFI,
    WL_PG_WIFI_DETAILS,
    WL_PG_WIFI_ADVANCED,
    WL_PG_WIFI_SAVED,
    WL_PG_WIFI_CONNECT,
    WL_PG_BT,
    WL_PG_BT_ADVANCED,
    WL_PG_ZIGBEE,
    WL_PG_ZIGBEE_ADVANCED,
    WL_PG_THREAD,
    WL_PG_THREAD_ADVANCED,
    WL_PG_ESPNOW,
    WL_PG_ESPNOW_ADVANCED,
};

#define WL_BLE_PK_NONE    0
#define WL_BLE_PK_INPUT   1
#define WL_BLE_PK_DISPLAY 2
#define WL_BLE_PK_CONFIRM 3

extern int wl_page;
extern int wl_hist[6];
extern int wl_hist_n;
extern bool wl_main_ref_exp;
extern bool wl_build_skip_back;

extern lv_timer_t *wl_timer;
extern lv_obj_t *wl_radio_lbl;
extern lv_obj_t *wl_ssid_lbl;
extern lv_obj_t *wl_ip_lbl;
extern lv_obj_t *wl_scan_lbl;
extern lv_obj_t *wl_bt_radio_lbl;
extern lv_obj_t *wl_bt_paired_lbl;
extern lv_obj_t *wl_154_radio_lbl;
extern lv_obj_t *wl_154_net_lbl;
extern lv_obj_t *wl_zb_permit_lbl;
extern char wl_radio_cache[32];
extern char wl_ssid_cache[48];
extern char wl_ip_cache[20];
extern char wl_scan_cache[32];
extern uint8_t wl_wifi_conn_cache;
extern char wl_bt_radio_cache[32];
extern char wl_bt_paired_cache[32];
extern char wl_154_radio_cache[40];
extern char wl_154_net_cache[48];
extern bool wl_scan_done_cache;
extern int wl_scan_n_cache;
extern bool wl_bt_scan_done_cache;
extern int wl_bt_scan_n_cache;
extern uint8_t wl_bt_conn_cache;
extern uint8_t wl_bt_pk_cache;

extern lv_obj_t *wl_en_bridge_lbl;
extern lv_obj_t *wl_en_scan_lbl;
extern lv_obj_t *wl_en_traf_lbl;
extern lv_obj_t *wl_en_dbg_snap_lbl;
extern lv_obj_t *wl_en_dbg_last_lbl;
extern char wl_en_bridge_cache[40];
extern char wl_en_scan_cache[32];
extern char wl_en_traf_cache[32];
extern char wl_en_dbg_snap_cache[128];
extern char wl_en_dbg_last_cache[96];
extern bool wl_en_scan_done_cache;
extern int wl_en_scan_n_cache;
extern bool wl_en_scan_fail_cache;

extern lv_obj_t *wl_en_mac_modal;
extern lv_obj_t *wl_en_mac_kb;
extern lv_obj_t *wl_en_mac_ta;

extern lv_obj_t *wl_zb_add_modal;
extern lv_obj_t *wl_zb_add_kb;
extern lv_obj_t *wl_zb_name_ta;
extern lv_obj_t *wl_zb_ieee_ta;
extern lv_obj_t *wl_zb_code_ta;

extern lv_obj_t *wl_th_add_modal;
extern lv_obj_t *wl_th_add_kb;
extern lv_obj_t *wl_th_name_ta;
extern lv_obj_t *wl_th_ext_ta;

extern bool wl_zb_scan_done_cache;
extern int wl_zb_scan_n_cache;
extern uint32_t wl_zb_state_gen_cache;
extern bool wl_th_scan_done_cache;
extern int wl_th_scan_n_cache;

extern bool wl_scrolling;
extern bool wl_rebuild_pending;

extern lv_obj_t *wl_connect_modal;
extern lv_obj_t *wl_connect_kb;
extern lv_obj_t *wl_connect_ta;
extern char wl_connect_ssid[33];

extern lv_obj_t *wl_bt_pk_modal;
extern lv_obj_t *wl_bt_pk_kb;
extern lv_obj_t *wl_bt_pk_ta;
extern lv_obj_t *wl_bt_pk_hint;

void wl_rebuild(void);
void wl_rebuild_now(void);
void wl_wireless_build_page(lv_obj_t *panel);
void wl_connect_modal_hide(void);
void wl_bt_passkey_modal_hide(void);
void wl_bt_passkey_modal_show(uint8_t mode, uint32_t value);
void wl_espnow_mac_modal_hide(void);
void wl_zb_add_modal_hide(void);
void wl_th_add_modal_hide(void);
/** Cancel + primary action row for wireless dialogs (MD3 dialog buttons). */
lv_obj_t *wl_modal_action_row(lv_obj_t *card, const char *ok_label,
                              lv_event_cb_t cancel_cb, lv_event_cb_t ok_cb);
void wl_timer_stop_core(void);
void wl_timer_stop_activity(void);
void wl_timer_tick(void);
void wl_timer_maybe_start(void);
void wl_refresh_wifi_labels(void);
void wl_refresh_bt_labels(void);
void wl_maybe_reinit_espnow_transport(void);
void wl_panel_scroll_hook(bool attach);

void nav_push(int page);
void nav_pop(lv_event_t *e);
void nav_to(lv_event_t *e);
void wifi_radio_toggle_cb(lv_event_t *e);
void scan_cb(lv_event_t *e);
void ap_row_click_cb(lv_event_t *e);
void disconnect_cb(lv_event_t *e);
void connect_apply_saved_cb(lv_event_t *e);
void forget_saved_cb(lv_event_t *e);
void bt_radio_toggle_cb(lv_event_t *e);
void bt_disconnect_cb(lv_event_t *e);
void bt_device_row_cb(lv_event_t *e);
void bt_scan_cb(lv_event_t *e);
void bt_clear_paired_cb(lv_event_t *e);
void generic_radio_toggle_cb(lv_event_t *e);
void zb_join_cb(lv_event_t *e);
void zb_leave_cb(lv_event_t *e);
void th_attach_cb(lv_event_t *e);
void th_detach_cb(lv_event_t *e);
void zb_scan_cb(lv_event_t *e);
void th_scan_cb(lv_event_t *e);
void zb_scan_row_cb(lv_event_t *e);
void th_scan_row_cb(lv_event_t *e);
void zb_device_toggle_cb(lv_event_t *e);
void zb_device_rename_cb(lv_event_t *e);
void zb_rename_focus_cb(lv_event_t *e);
void zb_device_level_cb(lv_event_t *e);
void zb_cover_open_cb(lv_event_t *e);
void zb_cover_close_cb(lv_event_t *e);
void zb_cover_stop_cb(lv_event_t *e);
void zb_identify_cb(lv_event_t *e);
void th_device_toggle_cb(lv_event_t *e);
void zb_device_remove_cb(lv_event_t *e);
void zb_auto_cycle_cb(lv_event_t *e); /* cycles CNC automation mode */
void zb_energy_scan_cb(lv_event_t *e);
void th_device_remove_cb(lv_event_t *e);
void zb_devices_clear_cb(lv_event_t *e);
void th_devices_clear_cb(lv_event_t *e);
void espnow_toggle_cb(lv_event_t *e);
void espnow_scan_cb(lv_event_t *e);
void espnow_peer_row_cb(lv_event_t *e);
void espnow_saved_activate_cb(lv_event_t *e);
void espnow_saved_delete_cb(lv_event_t *e);
void espnow_mac_modal_show(lv_event_t *e);
void espnow_log_dd_cb(lv_event_t *e);
void espnow_clear_peers_cb(lv_event_t *e);
void ant_ext_cb(lv_event_t *e);
void toggle_nvs_u8_cb(lv_event_t *e);
void dd_u8_cb(lv_event_t *e);
void wireless_reset_cb(void);
void zb_add_modal_show(lv_event_t *e);
void th_add_modal_show(lv_event_t *e);

#ifdef __cplusplus
}
#endif
