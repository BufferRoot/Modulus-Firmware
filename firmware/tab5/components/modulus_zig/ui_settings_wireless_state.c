#include "ui_settings_wireless_priv.h"


int wl_page = WL_PG_MAIN;
int wl_hist[6];
int wl_hist_n = 0;
bool wl_main_ref_exp = false;
bool wl_build_skip_back = false;

lv_timer_t *wl_timer = NULL;
lv_obj_t *wl_radio_lbl = NULL;
lv_obj_t *wl_ssid_lbl = NULL;
lv_obj_t *wl_ip_lbl = NULL;
lv_obj_t *wl_scan_lbl = NULL;
lv_obj_t *wl_bt_radio_lbl = NULL;
lv_obj_t *wl_bt_paired_lbl = NULL;
lv_obj_t *wl_154_radio_lbl = NULL;
lv_obj_t *wl_154_net_lbl = NULL;
lv_obj_t *wl_zb_permit_lbl = NULL;
char wl_radio_cache[32] = "";
char wl_ssid_cache[48] = "";
char wl_ip_cache[20] = "";
char wl_scan_cache[32] = "";
uint8_t wl_wifi_conn_cache = 255;
char wl_bt_radio_cache[32] = "";
char wl_bt_paired_cache[32] = "";
char wl_154_radio_cache[40] = "";
char wl_154_net_cache[48] = "";
bool wl_scan_done_cache = false;
int wl_scan_n_cache = -1;
bool wl_bt_scan_done_cache = false;
int wl_bt_scan_n_cache = -1;
uint8_t wl_bt_conn_cache = 255;
uint8_t wl_bt_pk_cache = 255;

lv_obj_t *wl_en_bridge_lbl = NULL;
lv_obj_t *wl_en_scan_lbl = NULL;
lv_obj_t *wl_en_traf_lbl = NULL;
lv_obj_t *wl_en_dbg_snap_lbl = NULL;
lv_obj_t *wl_en_dbg_last_lbl = NULL;
char wl_en_bridge_cache[40] = "";
char wl_en_scan_cache[32] = "";
char wl_en_traf_cache[32] = "";
char wl_en_dbg_snap_cache[128] = "";
char wl_en_dbg_last_cache[96] = "";
bool wl_en_scan_done_cache = false;
int wl_en_scan_n_cache = -1;
bool wl_en_scan_fail_cache = false;

lv_obj_t *wl_en_mac_modal = NULL;
lv_obj_t *wl_en_mac_kb = NULL;
lv_obj_t *wl_en_mac_ta = NULL;

lv_obj_t *wl_zb_add_modal = NULL;
lv_obj_t *wl_zb_add_kb = NULL;
lv_obj_t *wl_zb_name_ta = NULL;
lv_obj_t *wl_zb_ieee_ta = NULL;
lv_obj_t *wl_zb_code_ta = NULL;

lv_obj_t *wl_th_add_modal = NULL;
lv_obj_t *wl_th_add_kb = NULL;
lv_obj_t *wl_th_name_ta = NULL;
lv_obj_t *wl_th_ext_ta = NULL;

bool wl_zb_scan_done_cache = false;
int wl_zb_scan_n_cache = -1;
uint32_t wl_zb_state_gen_cache = 0;
bool wl_th_scan_done_cache = false;
int wl_th_scan_n_cache = -1;

bool wl_scrolling = false;
bool wl_rebuild_pending = false;

lv_obj_t *wl_connect_modal = NULL;
lv_obj_t *wl_connect_kb = NULL;
lv_obj_t *wl_connect_ta = NULL;
char wl_connect_ssid[33] = "";

lv_obj_t *wl_bt_pk_modal = NULL;
lv_obj_t *wl_bt_pk_kb = NULL;
lv_obj_t *wl_bt_pk_ta = NULL;
lv_obj_t *wl_bt_pk_hint = NULL;

