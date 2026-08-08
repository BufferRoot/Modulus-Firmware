#include "ui_settings_modals_priv.h"
#include "ui_settings_modal_kb.h"
#include "ui_settings_common.h"
#include "ui_settings_priv.h"
#include "ui_internal.h"
#include "ui_touch_sound.h"
#include "nvs_shim.h"
#include "security_shim.h"
#include "audio_shim.h"
#include "cnc_cmd_exports.h"
#include "ui_quick_grid.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ── Transport config modal ───────────────────────────────────────── */

static lv_obj_t *s_xport_modal = NULL;
static lv_obj_t *s_xport_kb = NULL;
static uint8_t s_xport_conn = 4;

#define XPORT_HOST_MAX 63
#define XPORT_PATH_MAX 31
#define XPORT_PORT_MAX 5

static const char *const k_host_chars =
    "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-";
static const char *const k_path_chars =
    "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ/-_.";

void settings_transport_modal_hide(void)
{
    if (!s_xport_modal) {
        s_xport_kb = NULL;
        return;
    }
    s_xport_kb = NULL;
    modulus_ui_dialog_scrim_hide_animated(&s_xport_modal);
}

static void xport_close_cb(lv_event_t *e)
{
    (void)e;
    settings_transport_modal_hide();
}

static void xport_connect_cb(lv_event_t *e)
{
    const uint8_t idx = (uint8_t)(uintptr_t)lv_event_get_user_data(e);
    modulus_nvs_set_u8("cnc_conn", idx);
    modulus_zig_transport_reinit();
    settings_transport_modal_hide();
    modulus_ui_settings_build_cnc_tab();
}

static void xport_maybe_reinit(void)
{
    const uint8_t active = modulus_nvs_get_u8("cnc_conn", 4);
    if (active == s_xport_conn) {
        modulus_zig_transport_reinit();
    }
}

static void xport_kb_hide_cb(lv_event_t *e)
{
    (void)e;
    if (s_xport_kb) {
        lv_obj_add_flag(s_xport_kb, LV_OBJ_FLAG_HIDDEN);
    }
}

static void xport_ta_focus_cb(lv_event_t *e)
{
    if (s_xport_kb) {
        lv_keyboard_set_textarea(s_xport_kb, lv_event_get_target(e));
        lv_obj_remove_flag(s_xport_kb, LV_OBJ_FLAG_HIDDEN);
    }
}

static void xport_ta_defocus_cb(lv_event_t *e)
{
    const char *key = lv_event_get_user_data(e);
    const char *txt = lv_textarea_get_text(lv_event_get_target(e));
    if (key && txt) {
        modulus_nvs_set_str(key, txt);
    }
    xport_kb_hide_cb(e);
    xport_maybe_reinit();
}

static void xport_port_defocus_cb(lv_event_t *e)
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
    xport_kb_hide_cb(e);
    xport_maybe_reinit();
}

static void xport_u8_ta_defocus_cb(lv_event_t *e)
{
    const char *key = lv_event_get_user_data(e);
    const char *txt = lv_textarea_get_text(lv_event_get_target(e));
    uint8_t val = (uint8_t)((txt && txt[0]) ? atoi(txt) : 1);
    if (key) {
        modulus_nvs_set_u8(key, val);
    }
    xport_kb_hide_cb(e);
    xport_maybe_reinit();
}

static void xport_i2c_addr_defocus_cb(lv_event_t *e)
{
    const char *txt = lv_textarea_get_text(lv_event_get_target(e));
    uint8_t addr = (uint8_t)strtol(txt ? txt : "50", NULL, 0);
    if (addr < 0x03) {
        addr = 0x03;
    }
    if (addr > 0x77) {
        addr = 0x77;
    }
    modulus_nvs_set_u8("i2c_addr", addr);
    xport_kb_hide_cb(e);
    xport_maybe_reinit();
}

static void xport_serial_reconnect_cb(lv_event_t *e)
{
    (void)e;
    modulus_zig_transport_reinit();
}

static void xport_dd_u8_cb(lv_event_t *e)
{
    const char *key = lv_event_get_user_data(e);
    modulus_nvs_set_u8(key, (uint8_t)lv_dropdown_get_selected(lv_event_get_target(e)));
    xport_maybe_reinit();
}

/* Segmented twin of xport_dd_u8_cb — small option sets use MD3 segmented
 * buttons (all options visible, one tap) instead of dropdowns. */
static void xport_seg_u8_cb(lv_event_t *e)
{
    const char *key = lv_event_get_user_data(e);
    modulus_nvs_set_u8(key, modulus_ui_segmented_get_selected(lv_event_get_target(e)));
    xport_maybe_reinit();
}

static void wire_xport_ta(lv_obj_t *ta, const char *nvs_key)
{
    lv_obj_add_event_cb(ta, xport_ta_focus_cb, LV_EVENT_FOCUSED, NULL);
    lv_obj_add_event_cb(ta, xport_ta_defocus_cb, LV_EVENT_DEFOCUSED, (void *)nvs_key);
}

static void wire_xport_port(lv_obj_t *ta, const char *nvs_key)
{
    lv_obj_add_event_cb(ta, xport_ta_focus_cb, LV_EVENT_FOCUSED, NULL);
    lv_obj_add_event_cb(ta, xport_port_defocus_cb, LV_EVENT_DEFOCUSED, (void *)nvs_key);
}

static void xport_init_keyboard(lv_obj_t *modal)
{
    s_xport_kb = lv_keyboard_create(modal);
    lv_keyboard_set_mode(s_xport_kb, LV_KEYBOARD_MODE_TEXT_LOWER);
    settings_modal_kb_configure_text(s_xport_kb);
    lv_obj_add_flag(s_xport_kb, LV_OBJ_FLAG_HIDDEN);
    lv_obj_add_event_cb(s_xport_kb, xport_kb_hide_cb, LV_EVENT_READY, NULL);
    lv_obj_add_event_cb(s_xport_kb, xport_kb_hide_cb, LV_EVENT_CANCEL, NULL);
}

static void add_serial_params(lv_obj_t *card, const char *baud_key,
                              const char *dbit_key, const char *par_key,
                              const char *sbit_key)
{
    lv_obj_t *b = settings_dropdown_row(card, "Baud rate",
        "9600\n19200\n38400\n57600\n115200\n250000\n1000000",
        modulus_nvs_get_u8(baud_key, 4));
    lv_obj_add_event_cb(b, xport_dd_u8_cb, LV_EVENT_VALUE_CHANGED, (void *)baud_key);
    static const char *const k_dbits[] = {"7", "8"};
    lv_obj_t *d = settings_segmented_row(card, "Data bits", k_dbits, 2,
                                         modulus_nvs_get_u8(dbit_key, 1), 64);
    lv_obj_add_event_cb(d, xport_seg_u8_cb, LV_EVENT_VALUE_CHANGED, (void *)dbit_key);
    static const char *const k_parity[] = {"None", "Even", "Odd"};
    lv_obj_t *p = settings_segmented_row(card, "Parity", k_parity, 3,
                                         modulus_nvs_get_u8(par_key, 0), 76);
    lv_obj_add_event_cb(p, xport_seg_u8_cb, LV_EVENT_VALUE_CHANGED, (void *)par_key);
    static const char *const k_sbits[] = {"1", "2"};
    lv_obj_t *s = settings_segmented_row(card, "Stop bits", k_sbits, 2,
                                         modulus_nvs_get_u8(sbit_key, 0), 64);
    lv_obj_add_event_cb(s, xport_seg_u8_cb, LV_EVENT_VALUE_CHANGED, (void *)sbit_key);
}

void settings_transport_modal_show(uint8_t conn_idx)
{
    if (conn_idx > 7) {
        return;
    }
    /* ESP-NOW has no configuration overlay — it is set up on the Wireless page
     * and connected from the CNC tab's action area. */
    if (conn_idx == 0) {
        return;
    }
    settings_transport_modal_hide();
    s_xport_conn = conn_idx;

    s_xport_modal = lv_obj_create(lv_layer_top());
    lv_obj_remove_style_all(s_xport_modal);
    lv_obj_set_size(s_xport_modal, lv_pct(100), lv_pct(100));
    modulus_ui_apply_overlay_scrim(s_xport_modal);
    lv_obj_add_flag(s_xport_modal, LV_OBJ_FLAG_CLICKABLE);

    lv_obj_t *card = lv_obj_create(s_xport_modal);
    lv_obj_remove_style_all(card);
    lv_obj_set_size(card, 520, 440);
    lv_obj_center(card);
    lv_obj_set_style_bg_color(card, modulus_ui_color_surface_container_low(), 0);
    lv_obj_set_style_bg_opa(card, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(card, MOD_UI_SHAPE_XL, 0);
    lv_obj_set_style_border_color(card, modulus_ui_color_outline_variant(), 0);
    lv_obj_set_style_border_width(card, 1, 0);
    lv_obj_set_style_pad_all(card, 20, 0);
    lv_obj_set_flex_flow(card, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(card, MOD_UI_SPACE_SM, 0);
    settings_tune_scroll_container(card);
    modulus_ui_motion_dialog_enter(card);

    lv_obj_t *hdr = lv_obj_create(card);
    lv_obj_remove_style_all(hdr);
    lv_obj_set_width(hdr, lv_pct(100));
    lv_obj_set_height(hdr, 40);
    lv_obj_set_flex_flow(hdr, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(hdr, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);
    settings_no_scroll(hdr);
    char title[48];
    snprintf(title, sizeof(title), "%s Configuration",
             settings_cnc_transport_name(conn_idx < SETTINGS_CNC_TRANSPORT_COUNT ? conn_idx : 0));
    lv_obj_t *ttl = lv_label_create(hdr);
    lv_label_set_text(ttl, title);
    lv_obj_set_style_text_font(ttl, MOD_UI_FONT_TITLE_M, 0);
    lv_obj_t *xb = lv_button_create(hdr);
    lv_obj_remove_style_all(xb);
    lv_obj_set_size(xb, 48, 48);
    lv_obj_set_style_radius(xb, MOD_UI_SHAPE_FULL, 0);
    modulus_ui_apply_pressed_state_layer(xb);
    lv_obj_t *xl = lv_label_create(xb);
    lv_label_set_text(xl, "X");
    lv_obj_center(xl);
    settings_bind_menu_click(xb, xport_close_cb, NULL);

    settings_section(card, "Status", NULL);
    const uint8_t active = modulus_nvs_get_u8("cnc_conn", 4);
    const bool is_active = active == conn_idx;
    lv_obj_t *act_lbl = settings_detail_row(
        card, "Active transport", is_active ? "Currently active" : "Inactive");
    lv_obj_set_style_text_color(
        act_lbl, modulus_settings_cnc_transport_color(conn_idx, is_active), 0);

    lv_obj_t *conn_btn = settings_action_row(card, "Set as active & connect", "");
    settings_bind_menu_click(conn_btn, xport_connect_cb,
                        (void *)(uintptr_t)conn_idx);

    settings_section(card, "Parameters", NULL);
    if (conn_idx == 1 || conn_idx == 2 || conn_idx == 5 || conn_idx == 6 || conn_idx == 7) {
        xport_init_keyboard(s_xport_modal);
    }
    switch (conn_idx) {
    case 4: {
        add_serial_params(card, "r4_baud", "r4_dbit", "r4_par", "r4_sbit");
        static const char *const k_dir[] = {"Auto", "TX only", "RX only"};
        lv_obj_t *dir = settings_segmented_row(card, "Direction", k_dir, 3,
                                               modulus_nvs_get_u8("r4_dir", 0), 88);
        lv_obj_add_event_cb(dir, xport_seg_u8_cb, LV_EVENT_VALUE_CHANGED, (void *)"r4_dir");
        break;
    }
    case 3: {
        add_serial_params(card, "ser_baud", "ser_dbit", "ser_par", "ser_sbit");
        static const char *const k_flow[] = {"None", "RTS/CTS"};
        lv_obj_t *flow = settings_segmented_row(card, "Flow control", k_flow, 2,
                                                modulus_nvs_get_u8("ser_flow", 0), 96);
        lv_obj_add_event_cb(flow, xport_seg_u8_cb, LV_EVENT_VALUE_CHANGED, (void *)"ser_flow");
        break;
    }
    case 1: {
        static char host[XPORT_HOST_MAX + 1];
        if (!modulus_nvs_get_str("ws_host", host, sizeof(host))) {
            strncpy(host, "192.168.1.100", sizeof(host) - 1);
            host[sizeof(host) - 1] = '\0';
        }
        lv_obj_t *ta_host = settings_text_input_row(card, "Host", host, XPORT_HOST_MAX,
                                                  k_host_chars);
        wire_xport_ta(ta_host, "ws_host");

        static char port[XPORT_PORT_MAX + 1];
        snprintf(port, sizeof(port), "%u", modulus_nvs_get_u16("ws_port", 81));
        lv_obj_t *ta_port = settings_text_input_row(card, "Port", port, XPORT_PORT_MAX,
                                                    "0123456789");
        wire_xport_port(ta_port, "ws_port");

        static char path[XPORT_PATH_MAX + 1];
        if (!modulus_nvs_get_str("ws_path", path, sizeof(path))) {
            strncpy(path, "/", sizeof(path) - 1);
            path[sizeof(path) - 1] = '\0';
        }
        lv_obj_t *ta_path = settings_text_input_row(card, "Path", path, XPORT_PATH_MAX,
                                                    k_path_chars);
        wire_xport_ta(ta_path, "ws_path");

        static const char *const k_ws_sec[] = {"ws:// (plain)", "wss:// (TLS)"};
        lv_obj_t *sec = settings_segmented_row(card, "Security", k_ws_sec, 2,
                                               modulus_nvs_get_u8("ws_tls", 0), 118);
        lv_obj_add_event_cb(sec, xport_seg_u8_cb, LV_EVENT_VALUE_CHANGED, (void *)"ws_tls");
        break;
    }
    case 2: {
        static char host[XPORT_HOST_MAX + 1];
        if (!modulus_nvs_get_str("tn_host", host, sizeof(host))) {
            strncpy(host, "192.168.1.100", sizeof(host) - 1);
            host[sizeof(host) - 1] = '\0';
        }
        lv_obj_t *ta_host = settings_text_input_row(card, "Host", host, XPORT_HOST_MAX,
                                                  k_host_chars);
        wire_xport_ta(ta_host, "tn_host");

        static char port[XPORT_PORT_MAX + 1];
        snprintf(port, sizeof(port), "%u", modulus_nvs_get_u16("tn_port", 23));
        lv_obj_t *ta_port = settings_text_input_row(card, "Port", port, XPORT_PORT_MAX,
                                                    "0123456789");
        wire_xport_port(ta_port, "tn_port");
        break;
    }
    case 5: {
        char nm[32];
        if (!modulus_nvs_get_str("ble_name", nm, sizeof(nm))) {
            nm[0] = '\0';
        }
        lv_obj_t *ta_name = settings_text_input_row(
            card, "Device name", nm[0] ? nm : "Scan to find", 31, NULL);
        wire_xport_ta(ta_name, "ble_name");
        settings_note(card, "BLE HID pairing uses the C6 wireless stack.");
        break;
    }
    case 6: {
        char addr[12];
        snprintf(addr, sizeof(addr), "0x%02X", modulus_nvs_get_u8("i2c_addr", 0x50));
        lv_obj_t *ta_addr = settings_text_input_row(
            card, "Slave address", addr, 6, "0123456789ABCDEFabcdefxX");
        lv_obj_add_event_cb(ta_addr, xport_ta_focus_cb, LV_EVENT_FOCUSED, NULL);
        lv_obj_add_event_cb(ta_addr, xport_i2c_addr_defocus_cb, LV_EVENT_DEFOCUSED, NULL);
        static const char *const k_i2c_spd[] = {"100 kHz", "400 kHz"};
        lv_obj_t *spd = settings_segmented_row(card, "Speed", k_i2c_spd, 2,
                                               modulus_nvs_get_u8("i2c_spd", 1), 96);
        lv_obj_add_event_cb(spd, xport_seg_u8_cb, LV_EVENT_VALUE_CHANGED, (void *)"i2c_spd");
        break;
    }
    case 7: {
        static const char *const k_can_br[] = {"125K", "250K", "500K", "1M"};
        lv_obj_t *br = settings_segmented_row(card, "Bitrate", k_can_br, 4,
                                              modulus_nvs_get_u8("can_brate", 2), 72);
        lv_obj_add_event_cb(br, xport_seg_u8_cb, LV_EVENT_VALUE_CHANGED, (void *)"can_brate");
        char nid[8];
        snprintf(nid, sizeof(nid), "%u", (unsigned)modulus_nvs_get_u8("can_nid", 1));
        lv_obj_t *ta_nid = settings_text_input_row(card, "Node ID", nid, 3, "0123456789");
        lv_obj_add_event_cb(ta_nid, xport_ta_focus_cb, LV_EVENT_FOCUSED, NULL);
        lv_obj_add_event_cb(ta_nid, xport_u8_ta_defocus_cb, LV_EVENT_DEFOCUSED,
                            (void *)"can_nid");
        static const char *const k_can_mode[] = {"Normal", "Listen", "Loopback"};
        lv_obj_t *mode = settings_segmented_row(card, "Mode", k_can_mode, 3,
                                                modulus_nvs_get_u8("can_mode", 0), 92);
        lv_obj_add_event_cb(mode, xport_seg_u8_cb, LV_EVENT_VALUE_CHANGED, (void *)"can_mode");
        settings_note(card, "TWAI on Port A G53/G54 - verify with grblHAL CAN peer.");
        break;
    }
    default:
        break;
    }
    if (conn_idx == 3 || conn_idx == 4) {
        lv_obj_t *rc = settings_action_row(card, "Reconnect", "Apply serial params");
        settings_bind_menu_click(rc, xport_serial_reconnect_cb, NULL);
    }
}

void settings_transport_modal_theme_refresh(void)
{
    if (s_xport_kb) {
        modulus_ui_apply_keyboard_theme(s_xport_kb);
    }
    if (s_xport_modal) {
        modulus_ui_apply_overlay_scrim(s_xport_modal);
    }
}

