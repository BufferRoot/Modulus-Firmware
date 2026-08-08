#include "ui_settings_priv.h"
#include "wireless_shim.h"
#include "transport_shim.h"
#include "wireless_shim.h"
#include "ui_settings_common.h"
#include "ui_settings_modals.h"
#include "ui_shim.h"
#include "display_shim.h"
#include "nvs_shim.h"
#include "cnc_cmd_exports.h"
#include "espnow_debug.h"
#include "ui_internal.h"
#include "ui_cnc_profiles.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern void modulus_ui_settings_wireless_open_espnow(void);

#define CNC_XPORT_DEFAULT SETTINGS_CNC_XPORT_DEFAULT
#define CNC_XPORT_OFF     SETTINGS_CNC_XPORT_OFF

static bool s_proto_ref_exp = false;

static void cnc_build_tab_now(void);
static void cnc_panel_scroll_hook(bool attach);

static lv_timer_t *s_cnc_timer = NULL;
static bool s_cnc_scrolling = false;
static bool s_cnc_rebuild_pending = false;
static lv_obj_t *s_session_lbl = NULL;
static lv_obj_t *s_disc_row = NULL;
static lv_obj_t *s_disc_detail = NULL;
static lv_obj_t *s_dbg_snap_lbl = NULL;
static lv_obj_t *s_dbg_last_lbl = NULL;
static lv_obj_t *s_masso_kb = NULL;
static char s_session_cache[24] = "";
static char s_dbg_snap_cache[128] = "";
static char s_dbg_last_cache[96] = "";
static int s_session_color = SETTINGS_STATUS_ERR;

static const char *const k_masso_host_chars =
    "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-";
static const char *const k_masso_sn_chars =
    "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-";

static void masso_kb_hide(void)
{
    if (s_masso_kb) {
        lv_obj_add_flag(s_masso_kb, LV_OBJ_FLAG_HIDDEN);
        lv_keyboard_set_textarea(s_masso_kb, NULL);
    }
}

static void masso_kb_ensure(void)
{
    if (s_masso_kb) {
        return;
    }
    s_masso_kb = lv_keyboard_create(lv_layer_top());
    lv_obj_set_size(s_masso_kb, LV_PCT(100), LV_PCT(40));
    lv_obj_align(s_masso_kb, LV_ALIGN_BOTTOM_MID, 0, 0);
    modulus_ui_apply_keyboard_theme(s_masso_kb);
    lv_obj_add_flag(s_masso_kb, LV_OBJ_FLAG_HIDDEN);
}

static void masso_ta_focus_cb(lv_event_t *e)
{
    masso_kb_ensure();
    lv_keyboard_set_textarea(s_masso_kb, lv_event_get_target(e));
    lv_obj_remove_flag(s_masso_kb, LV_OBJ_FLAG_HIDDEN);
}

static void masso_str_defocus_cb(lv_event_t *e)
{
    const char *key = lv_event_get_user_data(e);
    const char *txt = lv_textarea_get_text(lv_event_get_target(e));
    if (key && txt) {
        modulus_nvs_set_str(key, txt);
    }
    masso_kb_hide();
}

static void masso_port_defocus_cb(lv_event_t *e)
{
    const char *key = lv_event_get_user_data(e);
    const char *txt = lv_textarea_get_text(lv_event_get_target(e));
    int pval = (txt && txt[0]) ? atoi(txt) : 0;
    if (pval < 1) {
        pval = 1;
    }
    if (pval > 65535) {
        pval = 65535;
    }
    if (key) {
        modulus_nvs_set_u16(key, (uint16_t)pval);
    }
    masso_kb_hide();
}

static void wire_masso_ta(lv_obj_t *ta, const char *nvs_key, bool port)
{
    lv_obj_add_event_cb(ta, masso_ta_focus_cb, LV_EVENT_FOCUSED, NULL);
    lv_obj_add_event_cb(ta, port ? masso_port_defocus_cb : masso_str_defocus_cb,
                        LV_EVENT_DEFOCUSED, (void *)nvs_key);
}

static void format_session_status(char *buf, size_t len, int *color_kind)
{
    const uint8_t nvs_conn = modulus_nvs_get_u8("cnc_conn", CNC_XPORT_DEFAULT);
    const uint8_t active = modulus_zig_active_transport();

    if (nvs_conn >= CNC_XPORT_OFF || active >= CNC_XPORT_OFF) {
        snprintf(buf, len, "Transport off");
        *color_kind = SETTINGS_STATUS_DIM;
        return;
    }
    if (active != nvs_conn) {
        snprintf(buf, len, "Starting...");
        *color_kind = SETTINGS_STATUS_WARN;
        return;
    }
    modulus_cnc_status_t st = {};
    modulus_zig_fill_cnc_status(&st);
    if (!st.connected) {
        if (st.session != 0) {
            snprintf(buf, len, "Connecting...");
            *color_kind = SETTINGS_STATUS_WARN;
            return;
        }
        snprintf(buf, len, "Disconnected");
        *color_kind = SETTINGS_STATUS_ERR;
        return;
    }
    snprintf(buf, len, "Connected");
    *color_kind = SETTINGS_STATUS_OK;
}

static bool cnc_session_up(void)
{
    const uint8_t nvs_conn = modulus_nvs_get_u8("cnc_conn", CNC_XPORT_DEFAULT);
    if (nvs_conn >= CNC_XPORT_OFF) {
        return false;
    }
    if (modulus_zig_active_transport() != nvs_conn) {
        return false;
    }
    modulus_cnc_status_t st = {};
    modulus_zig_fill_cnc_status(&st);
    return st.connected != 0;
}

static void cnc_refresh_disconnect_row(void)
{
    if (!s_disc_row) {
        return;
    }
    const bool up = cnc_session_up();
    const char *detail = up ? "Stop session" : "Already off";
    if (s_disc_detail) {
        modulus_ui_label_set_text_if_changed(s_disc_detail, detail);
    }
    if (up) {
        modulus_ui_obj_set_disabled_style(s_disc_row, true);
    } else {
        modulus_ui_obj_set_disabled_style(s_disc_row, false);
    }
}

static void cnc_set_session_lbl_if_changed(const char *text, int color_kind)
{
    if (!s_session_lbl || !text) {
        return;
    }
    if (s_session_cache[0] != '\0' && strcmp(s_session_cache, text) == 0 &&
        s_session_color == color_kind) {
        return;
    }
    lv_label_set_text(s_session_lbl, text);
    lv_obj_set_style_text_color(s_session_lbl, modulus_settings_status_color(color_kind), 0);
    strncpy(s_session_cache, text, sizeof(s_session_cache) - 1);
    s_session_cache[sizeof(s_session_cache) - 1] = '\0';
    s_session_color = color_kind;
}

static void cnc_refresh_debug(void)
{
    if (!modulus_wireless_espnow_debug_active()) {
        return;
    }
    const char *snap = modulus_wireless_espnow_debug_snapshot();
    const char *last = modulus_wireless_espnow_debug_last_event();
    if (s_dbg_snap_lbl && strcmp(s_dbg_snap_cache, snap) != 0) {
        strncpy(s_dbg_snap_cache, snap, sizeof(s_dbg_snap_cache) - 1);
        lv_label_set_text(s_dbg_snap_lbl, s_dbg_snap_cache);
    }
    if (s_dbg_last_lbl && strcmp(s_dbg_last_cache, last) != 0) {
        strncpy(s_dbg_last_cache, last, sizeof(s_dbg_last_cache) - 1);
        lv_label_set_text(s_dbg_last_lbl, s_dbg_last_cache);
    }
}

static void cnc_refresh_session(void)
{
    char buf[24];
    int color = SETTINGS_STATUS_ERR;
    format_session_status(buf, sizeof(buf), &color);
    cnc_set_session_lbl_if_changed(buf, color);
    cnc_refresh_disconnect_row();
    cnc_refresh_debug();
}

static void cnc_timer_cb(lv_timer_t *t)
{
    (void)t;
    cnc_refresh_session();
}

void modulus_ui_settings_cnc_tab_stop_timer(void)
{
    cnc_panel_scroll_hook(false);
    s_cnc_scrolling = false;
    s_cnc_rebuild_pending = false;
    masso_kb_hide();
    if (s_masso_kb) {
        lv_obj_delete(s_masso_kb);
        s_masso_kb = NULL;
    }
    if (s_cnc_timer) {
        lv_timer_delete(s_cnc_timer);
        s_cnc_timer = NULL;
    }
    s_session_lbl = NULL;
    s_disc_row = NULL;
    s_disc_detail = NULL;
    s_dbg_snap_lbl = NULL;
    s_dbg_last_lbl = NULL;
    s_session_cache[0] = '\0';
    s_dbg_snap_cache[0] = '\0';
    s_dbg_last_cache[0] = '\0';
}

void modulus_ui_settings_cnc_tab_pause_activity(void)
{
    cnc_panel_scroll_hook(false);
    if (s_cnc_timer) {
        lv_timer_pause(s_cnc_timer);
    }
}

void modulus_ui_settings_cnc_tab_resume_activity(void)
{
    if (s_cnc_timer) {
        cnc_panel_scroll_hook(true);
        lv_timer_resume(s_cnc_timer);
        cnc_refresh_session();
    }
}

void modulus_ui_settings_cnc_on_status_event(void)
{
    if (!s_cnc_timer || s_cnc_scrolling) {
        return;
    }
    modulus_display_lock();
    cnc_refresh_session();
    modulus_display_unlock();
}

static void cnc_panel_scroll_cb(lv_event_t *e)
{
    if (!s_cnc_timer) {
        return;
    }
    const lv_event_code_t code = lv_event_get_code(e);
    if (code == LV_EVENT_SCROLL_BEGIN) {
        s_cnc_scrolling = true;
        lv_timer_pause(s_cnc_timer);
        return;
    }
    if (code != LV_EVENT_SCROLL_END) {
        return;
    }
    s_cnc_scrolling = false;
    lv_timer_resume(s_cnc_timer);
    cnc_refresh_session();
    if (s_cnc_rebuild_pending) {
        s_cnc_rebuild_pending = false;
        cnc_build_tab_now();
    }
}

static void cnc_panel_scroll_hook(bool attach)
{
    lv_obj_t *panel = modulus_ui_settings_tab_panel(MOD_UI_SETTINGS_TAB_CNC);
    if (!panel) {
        return;
    }
    lv_obj_remove_event_cb(panel, cnc_panel_scroll_cb);
    if (attach) {
        lv_obj_add_event_cb(panel, cnc_panel_scroll_cb, LV_EVENT_SCROLL_BEGIN, NULL);
        lv_obj_add_event_cb(panel, cnc_panel_scroll_cb, LV_EVENT_SCROLL_END, NULL);
    }
}

static void cnc_request_rebuild(void)
{
    if (s_cnc_scrolling) {
        s_cnc_rebuild_pending = true;
        return;
    }
    s_cnc_rebuild_pending = false;
    cnc_build_tab_now();
}

static void cnc_profiles_edit_cb(lv_event_t *e)
{
    (void)e;
    modulus_ui_cnc_profiles_modal_show();
}

static void transport_changed_cb(lv_event_t *e)
{
    const uint8_t idx = (uint8_t)lv_dropdown_get_selected(lv_event_get_target(e));
    modulus_espnow_debug_event("cnc_ui", "transport dropdown -> %u", (unsigned)idx);
    modulus_nvs_set_u8("cnc_conn", idx);
    modulus_zig_transport_reinit();
    cnc_request_rebuild();
}

static void protocol_changed_cb(lv_event_t *e)
{
    const uint8_t idx = (uint8_t)lv_dropdown_get_selected(lv_event_get_target(e));
    modulus_espnow_debug_event("cnc_ui", "mcs dropdown -> %u", (unsigned)idx);
    modulus_nvs_set_u8("cnc_proto", idx);
    /* Soft-default transport to MCS preferred link so dashboard reconnects on the
     * right path (user can still override Transport afterward). */
    const uint8_t pref = settings_cnc_protocol_preferred_transport(idx);
    if (pref < SETTINGS_CNC_TRANSPORT_COUNT) {
        modulus_nvs_set_u8("cnc_conn", pref);
    }
    /* Seed Telnet port to MCS defaults when picking LinuxCNC / Mach3. */
    if (idx == SETTINGS_CNC_PROTO_LINUXCNC) {
        modulus_nvs_set_u16("tn_port", 5007);
    } else if (idx == SETTINGS_CNC_PROTO_MACH3) {
        modulus_nvs_set_u16("tn_port", 7878);
    }
    modulus_zig_transport_reinit();
    modulus_zig_cmd_reset();
    cnc_request_rebuild();
}

static void reconnect_cb(lv_event_t *e)
{
    (void)e;
    modulus_espnow_debug_event("cnc_ui", "reconnect pressed");
    modulus_ui_snackbar_show("Reconnecting...", 2200);
    modulus_zig_transport_reinit();
    modulus_zig_cmd_reset();
    cnc_request_rebuild();
}

static void espnow_connect_cb(lv_event_t *e)
{
    (void)e;
    modulus_espnow_debug_event("cnc_ui", "connect pressed (cnc_conn=espnow)");
    modulus_nvs_set_u8("cnc_conn", 0);
    /* Radio already up: open/refresh transport without full zig reinit stop/start
     * (blocks Core 1 sys_task in SDIO/UART setup → IDLE1 WDT ~5 s). */
    if (modulus_wireless_espnow_is_enabled()) {
        if (modulus_espnow_transport_is_open()) {
            modulus_espnow_debug_event("cnc_ui", "espnow refresh (skip full reinit)");
            modulus_wireless_espnow_transport_reinit();
            modulus_zig_transport_espnow_attach();
            modulus_zig_transport_on_connect();
        } else {
            char mac[20];
            modulus_wireless_espnow_peer_mac_str(mac, sizeof(mac));
            const uint8_t ch = modulus_wireless_espnow_channel();
            modulus_espnow_debug_event("cnc_ui", "espnow light start (skip full reinit)");
            if (modulus_espnow_transport_start(mac, ch, false)) {
                modulus_zig_transport_espnow_attach();
                cnc_request_rebuild();
                return;
            }
            modulus_espnow_debug_event("cnc_ui", "light start failed - full reinit");
            modulus_zig_transport_reinit();
        }
        cnc_request_rebuild();
        return;
    }
    modulus_zig_transport_reinit();
    cnc_request_rebuild();
}

static void configure_cb(lv_event_t *e)
{
    (void)e;
    settings_transport_modal_show(modulus_nvs_get_u8("cnc_conn", CNC_XPORT_DEFAULT));
}

static void cnc_grbl_dump_cb(lv_event_t *e)
{
    (void)e;
    settings_grbl_dump_modal_show();
}

static void disconnect_cb(lv_event_t *e)
{
    (void)e;
    modulus_espnow_debug_event("cnc_ui", "disconnect pressed (cnc_conn=off)");
    modulus_nvs_set_u8("cnc_conn", CNC_XPORT_OFF);
    modulus_zig_transport_reinit();
    modulus_zig_cmd_reset();
    cnc_request_rebuild();
}

static void cnc_reset_cb(void)
{
    modulus_nvs_set_u8("cnc_conn", CNC_XPORT_DEFAULT);
    modulus_nvs_set_u8("r4_baud", 4);
    modulus_zig_transport_reinit();
    cnc_request_rebuild();
}

static void open_wireless_espnow_cb(lv_event_t *e)
{
    (void)e;
    modulus_ui_settings_wireless_open_espnow();
}

static void build_status_hero(lv_obj_t *p, const char *xport, uint8_t xidx)
{
    char stat_buf[24];
    int stat_color = SETTINGS_STATUS_ERR;
    format_session_status(stat_buf, sizeof(stat_buf), &stat_color);

    lv_obj_t *row = settings_row_base(p, 60, false);
    lv_obj_t *left = lv_obj_create(row);
    lv_obj_remove_style_all(left);
    lv_obj_set_size(left, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(left, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(left, 2, 0);
    lv_obj_t *cap = lv_label_create(left);
    lv_label_set_text(cap, "Session");
    lv_obj_set_style_text_color(cap, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(cap, MOD_UI_FONT_LABEL_M, 0);
    s_session_lbl = lv_label_create(left);
    lv_label_set_text(s_session_lbl, stat_buf);
    lv_obj_set_style_text_color(s_session_lbl, modulus_settings_status_color(stat_color), 0);
    lv_obj_set_style_text_font(s_session_lbl, MOD_UI_FONT_TITLE_L, 0);
    strncpy(s_session_cache, stat_buf, sizeof(s_session_cache) - 1);
    s_session_cache[sizeof(s_session_cache) - 1] = '\0';
    s_session_color = stat_color;

    lv_obj_t *right = lv_obj_create(row);
    lv_obj_remove_style_all(right);
    lv_obj_set_size(right, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(right, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(right, LV_FLEX_ALIGN_END, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_row(right, 2, 0);
    lv_obj_t *tcap = lv_label_create(right);
    lv_label_set_text(tcap, "Transport");
    lv_obj_set_style_text_color(tcap, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(tcap, MOD_UI_FONT_LABEL_M, 0);
    lv_obj_t *tval = lv_label_create(right);
    lv_label_set_text(tval, xport);
    lv_obj_set_style_text_font(tval, MOD_UI_FONT_BODY_L, 0);
    lv_obj_set_style_text_color(
        tval, modulus_settings_cnc_transport_color(xidx, xidx < CNC_XPORT_OFF), 0);
}

static void build_transport_summary(lv_obj_t *p, uint8_t xidx)
{
    if (xidx == 0) {
        char mac[20];
        modulus_wireless_espnow_peer_mac_str(mac, sizeof(mac));
        settings_detail_row(p, "Peer MAC", mac);
        char ch[12];
        snprintf(ch, sizeof(ch), "Ch %u", (unsigned)(modulus_nvs_get_u8("en_chan", 0) + 1));
        settings_detail_row(p, "Channel", ch);
        settings_detail_row(p, "Radio",
                            modulus_wireless_espnow_is_enabled() ? "On" : "Off");
        lv_obj_t *lnk = settings_action_row(p, "Wireless ESP-NOW", "");
        settings_bind_menu_click(lnk, open_wireless_espnow_cb, NULL);
        return;
    }
    if (xidx == 4 || xidx == 3) {
        const char *bk = (xidx == 4) ? "r4_baud" : "ser_baud";
        char baud[24];
        snprintf(baud, sizeof(baud), "%s baud", settings_baud_str(modulus_nvs_get_u8(bk, 4)));
        settings_detail_row(p, "Serial", baud);
        settings_detail_row(p, "Interface", xidx == 4 ? "UART1 RS-485 (DE pin)" : "USB CDC");
        return;
    }
    if (xidx == 1) {
        char host[64];
        if (!modulus_nvs_get_str("ws_host", host, sizeof(host))) {
            strncpy(host, "192.168.1.100", sizeof(host) - 1);
            host[sizeof(host) - 1] = '\0';
        }
        char ep[96];
        snprintf(ep, sizeof(ep), "%s:%u%s", host,
                 (unsigned)modulus_nvs_get_u16("ws_port", 81),
                 modulus_nvs_get_u8("ws_tls", 0) ? " (TLS)" : "");
        settings_detail_row(p, "Endpoint", ep);
        return;
    }
    if (xidx == 2) {
        char host[64];
        if (!modulus_nvs_get_str("tn_host", host, sizeof(host))) {
            strncpy(host, "192.168.1.100", sizeof(host) - 1);
            host[sizeof(host) - 1] = '\0';
        }
        char ep[80];
        snprintf(ep, sizeof(ep), "%s:%u", host,
                 (unsigned)modulus_nvs_get_u16("tn_port",
                     modulus_nvs_get_u8("cnc_proto", 0) == SETTINGS_CNC_PROTO_LINUXCNC ? 5007 :
                     modulus_nvs_get_u8("cnc_proto", 0) == SETTINGS_CNC_PROTO_MACH3 ? 7878 : 23));
        settings_detail_row(p, "Endpoint", ep);
        return;
    }
    if (xidx == 5) {
        char nm[32];
        if (!modulus_nvs_get_str("ble_name", nm, sizeof(nm)) || nm[0] == '\0') {
            strncpy(nm, "(not set)", sizeof(nm) - 1);
            nm[sizeof(nm) - 1] = '\0';
        }
        settings_detail_row(p, "Device name", nm);
        return;
    }
    if (xidx == 6) {
        char addr[12];
        snprintf(addr, sizeof(addr), "0x%02X", modulus_nvs_get_u8("i2c_addr", 0x50));
        settings_detail_row(p, "Slave address", addr);
        static const char *const k_i2c_spd[] = {"100 kHz", "400 kHz"};
        uint8_t spd = modulus_nvs_get_u8("i2c_spd", 1);
        if (spd > 1) {
            spd = 1;
        }
        settings_detail_row(p, "Speed", k_i2c_spd[spd]);
        return;
    }
    if (xidx == 7) {
        static const char *const k_can_rates[] = {
            "125 Kbps", "250 Kbps", "500 Kbps", "1 Mbps",
        };
        uint8_t br = modulus_nvs_get_u8("can_brate", 2);
        if (br >= 4) {
            br = 2;
        }
        settings_detail_row(p, "Bitrate", k_can_rates[br]);
        char nid[8];
        snprintf(nid, sizeof(nid), "%u", (unsigned)modulus_nvs_get_u8("can_nid", 1));
        settings_detail_row(p, "Node ID", nid);
        return;
    }
    settings_detail_row(p, "Parameters", "Open configure");
}

static void cnc_build_tab_now(void)
{
    lv_obj_t *p = modulus_ui_settings_tab_panel(MOD_UI_SETTINGS_TAB_CNC);
    if (!p) {
        return;
    }
    modulus_ui_settings_cnc_tab_stop_timer();
    lv_obj_clean(p);

    const uint8_t xidx = modulus_nvs_get_u8("cnc_conn", CNC_XPORT_DEFAULT);
    const char *xport = settings_cnc_transport_name(xidx);
    const bool session_up = cnc_session_up();
    uint8_t proto_idx = modulus_nvs_get_u8("cnc_proto", SETTINGS_CNC_PROTO_DEFAULT);
    if (proto_idx >= SETTINGS_CNC_PROTOCOL_COUNT) {
        proto_idx = SETTINGS_CNC_PROTO_DEFAULT;
    }
    const char *proto = settings_cnc_protocol_name(proto_idx);
    const bool proto_ok = settings_cnc_protocol_implemented(proto_idx);

    settings_section(p, "Connection status", NULL);
    build_status_hero(p, xport, xidx);
    settings_detail_row(p, "Motion control", proto);

    settings_section(p, "Motion control systems", NULL);
    lv_obj_t *proto_dd = settings_dropdown_row(p, "System",
                                               settings_cnc_protocol_dropdown_opts(),
                                               proto_idx);
    lv_obj_add_event_cb(proto_dd, protocol_changed_cb, LV_EVENT_VALUE_CHANGED, NULL);
    if (!proto_ok) {
        settings_not_implemented_row(p, "Client support", "Coming soon");
    } else if (proto_idx == SETTINGS_CNC_PROTO_MASSO) {
        settings_note(p, "Masso Link UDP - status/keepalive only. No jog/gcode in RE'd Link protocol.");
        settings_note(p, "DRO XYZ not in Link packets (shows --). Handwheel MPG disabled for Masso.");
        settings_note(p, "Do not run official Masso Link PC app at the same time (shared UDP 65535).");
        settings_section(p, "Masso Link", "Wi-Fi via C6. UDP opens automatically for this MCS.");
        {
            char ip[64];
            if (!modulus_nvs_get_str("masso_ip", ip, sizeof(ip)) || ip[0] == '\0') {
                strncpy(ip, "192.168.1.100", sizeof(ip) - 1);
                ip[sizeof(ip) - 1] = '\0';
            }
            lv_obj_t *ta_ip = settings_text_input_row(p, "Controller IP", ip, 63, k_masso_host_chars);
            wire_masso_ta(ta_ip, "masso_ip", false);
        }
        {
            char sn[32];
            if (!modulus_nvs_get_str("masso_sn", sn, sizeof(sn))) {
                sn[0] = '\0';
            }
            lv_obj_t *ta_sn = settings_text_input_row(p, "Serial (optional)", sn, 24, k_masso_sn_chars);
            wire_masso_ta(ta_sn, "masso_sn", false);
            settings_note(p, "Digits must match controller (e.g. G3-12345 -> 12345). Mismatch disconnects.");
        }
        {
            char tx[8], rx[8];
            snprintf(tx, sizeof(tx), "%u", (unsigned)modulus_nvs_get_u16("masso_tx", 11000));
            snprintf(rx, sizeof(rx), "%u", (unsigned)modulus_nvs_get_u16("masso_rx", 65535));
            lv_obj_t *ta_tx = settings_text_input_row(p, "UDP send port", tx, 5, "0123456789");
            wire_masso_ta(ta_tx, "masso_tx", true);
            lv_obj_t *ta_rx = settings_text_input_row(p, "UDP recv port", rx, 5, "0123456789");
            wire_masso_ta(ta_rx, "masso_rx", true);
            settings_note(p, "Docs: send 11000-11050, recv 65535. Transport opens UDP automatically for Masso MCS.");
        }
    } else if (proto_idx == SETTINGS_CNC_PROTO_GRBL) {
        settings_note(p, "Grbl 1.1: status ? handshake only. No $I+ or MPG/FAN RT.");
    } else if (proto_idx == SETTINGS_CNC_PROTO_FLUIDNC) {
        settings_note(p, "FluidNC: classic Grbl dialect. Prefer WebSocket to FluidNC IP.");
    } else if (proto_idx == SETTINGS_CNC_PROTO_LINUXCNC) {
        settings_note(p, "linuxcncrsh over Telnet. Default port 5007.");
        settings_note(p, "Use Transport Telnet to LinuxCNC PC IP. Enable linuxcncrsh in INI.");
        {
            char cpw[17] = "EMC";
            char epw[17] = "EMCTOO";
            if (!modulus_nvs_get_str("lcnc_cpw", cpw, sizeof(cpw))) {
                strncpy(cpw, "EMC", sizeof(cpw) - 1);
            }
            if (!modulus_nvs_get_str("lcnc_epw", epw, sizeof(epw))) {
                strncpy(epw, "EMCTOO", sizeof(epw) - 1);
            }
            lv_obj_t *ta_c = settings_text_input_row(p, "Connect password", cpw, 15,
                "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ");
            wire_masso_ta(ta_c, "lcnc_cpw", false);
            lv_obj_t *ta_e = settings_text_input_row(p, "Enable password", epw, 15,
                "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ");
            wire_masso_ta(ta_e, "lcnc_epw", false);
        }
    } else if (proto_idx == SETTINGS_CNC_PROTO_MACH3) {
        settings_note(p, "MMBP text bridge: tools/mmbp_bridge on PC. Default Telnet port 7878.");
        settings_note(p, "Mach3/Mach4 have no native network API - run Modulus bridge on PC.");
    }

    settings_section(p, "Active transport", NULL);
    uint8_t dd_idx = (xidx < 8) ? xidx : CNC_XPORT_DEFAULT;
    lv_obj_t *dd = settings_dropdown_row(p, "Transport", settings_cnc_transport_dropdown_opts(),
                                         dd_idx);
    lv_obj_add_event_cb(dd, transport_changed_cb, LV_EVENT_VALUE_CHANGED, NULL);

    settings_section(p, "Actions", NULL);
    if (xidx == 0) {
        /* ESP-NOW is configured on the Wireless page — no overlay here.
         * Connect directly from the action area. */
        lv_obj_t *cn = settings_action_row(p, "Connect",
            session_up ? "Connected" : "Apply & connect");
        settings_bind_menu_click(cn, espnow_connect_cb, NULL);
    } else {
        lv_obj_t *rc = settings_action_row(p, "Reconnect / test", "Apply & connect");
        settings_bind_menu_click(rc, reconnect_cb, NULL);
        char cfg[40];
        snprintf(cfg, sizeof(cfg), "Configure %s", xport);
        lv_obj_t *cf = settings_action_row(p, cfg, "");
        settings_bind_menu_click(cf, configure_cb, NULL);
    }
    s_disc_row = settings_destructive_row(p, "Disconnect",
        session_up ? "Stop session" : "Already off");
    {
        lv_obj_t *rg = lv_obj_get_child(s_disc_row, 1);
        s_disc_detail = rg ? lv_obj_get_child(rg, 0) : NULL;
    }
    if (!session_up) {
        modulus_ui_obj_set_disabled_style(s_disc_row, false);
    }
    settings_bind_menu_click(s_disc_row, disconnect_cb, NULL);

    if (xidx == 0) {
        settings_section(p, "ESP-NOW peer", "Read-only bridge peer summary.");
        char mac[20];
        modulus_wireless_espnow_peer_mac_str(mac, sizeof(mac));
        settings_detail_row(p, "MAC", mac);
        settings_detail_row(p, "Encryption", modulus_nvs_get_u8("en_enc", 0) ? "On" : "Off");
        settings_detail_row(p, "Radio",
                            modulus_wireless_espnow_is_enabled() ? "On" : "Off");
        settings_detail_row(p, "CNC transport",
                            modulus_wireless_espnow_transport_active() ? "Live"
                                                                       : "Idle (bridge only)");
        if (modulus_wireless_espnow_debug_active()) {
            settings_section(p, "ESP-NOW debug", "Enable in Wireless > ESP-NOW > Advanced");
            const char *snap = modulus_wireless_espnow_debug_snapshot();
            const char *last = modulus_wireless_espnow_debug_last_event();
            s_dbg_snap_lbl = settings_detail_row(p, "State", snap);
            strncpy(s_dbg_snap_cache, snap, sizeof(s_dbg_snap_cache) - 1);
            s_dbg_last_lbl = settings_detail_row(p, "Last event", last);
            strncpy(s_dbg_last_cache, last, sizeof(s_dbg_last_cache) - 1);
        }
        lv_obj_t *wl = settings_action_row(p, "Open wireless ESP-NOW", "");
        settings_bind_menu_click(wl, open_wireless_espnow_cb, NULL);
    }

    if (xidx != 0 && xidx < CNC_XPORT_OFF) {
        settings_section(p, "Transport parameters", NULL);
        build_transport_summary(p, xidx);
    }

    settings_section(p, "Related settings", NULL);
    settings_link_tab_row(p, "Machine", "", 7);
    settings_link_tab_row(p, "Dashboard & handwheel", "", 1);
    settings_link_tab_row(p, "Wireless", "", 4);

    settings_expandable_link(p, "Show motion control reference", "Hide motion control reference",
                             &s_proto_ref_exp, modulus_ui_settings_build_cnc_tab);
    if (s_proto_ref_exp) {
        settings_detail_row(p, "GrblHAL", "$I+ info, ENUMS, MPG/FAN RT, bracket reports");
        settings_detail_row(p, "Grbl", "Grbl 1.1f banner, ? status poll, $J= jog");
        settings_detail_row(p, "FluidNC", "Classic Grbl dialect; WebSocket preferred");
        settings_detail_row(p, "LinuxCNC", "linuxcncrsh: hello/enable, get poll, set jog/mdi");
        settings_detail_row(p, "LinuxCNC port", "Telnet default 5007 (linuxcncrsh)");
        settings_detail_row(p, "Masso", "Link UDP status (XYZ DRO not in Link packets)");
        settings_detail_row(p, "Mach3/Mach4", "MMBP: tools/mmbp_bridge Telnet 7878");
        settings_detail_row(p, "Grbl transport", "RS-485, Serial USB, Telnet, WebSocket");
    }

    settings_section(p, "Advanced", NULL);
    if (settings_cnc_protocol_supports_dump(proto_idx)) {
        lv_obj_t *dump_row = settings_action_row(p, "Settings browser ($$)", "Read controller");
        settings_bind_menu_click(dump_row, cnc_grbl_dump_cb, NULL);
    } else {
        settings_note(p, "Settings browser ($$) is Grbl-family only (GrblHAL / Grbl / FluidNC).");
    }

    settings_section(p, "Connection profiles", "Save/activate up to 4 machine setups.");
    {
        const uint8_t active = modulus_nvs_get_u8("cnc_prof", 0);
        char name[24];
        char detail[48];
        if (modulus_ui_cnc_profile_name(active, name, sizeof(name)) && name[0]) {
            snprintf(detail, sizeof(detail), "Active: %s", name);
        } else {
            snprintf(detail, sizeof(detail), "Slot %u", (unsigned)(active + 1));
        }
        lv_obj_t *row = settings_action_row(p, "Manage profiles", detail);
        settings_bind_menu_click(row, cnc_profiles_edit_cb, NULL);
    }

    settings_section(p, "Planned features", NULL);
    settings_coming_soon_row(p, "USB HID / Gamepad transport");

    static settings_reset_ctx_t reset_ctx = {
        .title = "Reset CNC connection?",
        .body = "Restores RS-485 defaults and reconnects transport.",
        .fn = cnc_reset_cb,
    };
    settings_reset_row(p, "Reset CNC connection", &reset_ctx);

    s_cnc_timer = lv_timer_create(cnc_timer_cb, 1000, NULL);
    cnc_panel_scroll_hook(true);
    modulus_ui_settings_note_tab_built(MOD_UI_SETTINGS_TAB_CNC);
}

void modulus_ui_settings_build_cnc_tab(void)
{
    cnc_request_rebuild();
}

void settings_cnc_masso_kb_theme_refresh(void)
{
    if (s_masso_kb) {
        modulus_ui_apply_keyboard_theme(s_masso_kb);
    }
}
