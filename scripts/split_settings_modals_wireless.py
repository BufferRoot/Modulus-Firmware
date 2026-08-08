#!/usr/bin/env python3
"""Split ui_settings_modals.c and ui_settings_wireless.c into focused TUs."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "firmware/tab5/components/modulus_zig"

MODALS = ROOT / "ui_settings_modals.c"
WIRELESS = ROOT / "ui_settings_wireless.c"

MODAL_HDR = """#include "ui_settings_modals_priv.h"
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
"""

MODAL_KB_BODY = """
void settings_modal_kb_configure_text(lv_obj_t *kb)
{
    if (!kb) {
        return;
    }
    const bool full = modulus_nvs_get_u8("kb_full", 0) != 0;
    if (full) {
        lv_obj_set_size(kb, lv_pct(100), lv_pct(48));
        lv_obj_align(kb, LV_ALIGN_BOTTOM_MID, 0, 0);
    } else {
        lv_obj_set_size(kb, 560, 220);
        lv_obj_align(kb, LV_ALIGN_BOTTOM_MID, 0, -20);
    }
    modulus_ui_apply_keyboard_theme(kb);
}

void settings_modal_kb_configure_number(lv_obj_t *kb)
{
    if (!kb) {
        return;
    }
    lv_obj_set_size(kb, lv_pct(100), lv_pct(48));
    lv_obj_align(kb, LV_ALIGN_BOTTOM_MID, 0, 0);
    modulus_ui_apply_keyboard_theme(kb);
}
"""

THEME_ORCH = """
void settings_modals_theme_refresh(void)
{
    settings_transport_modal_theme_refresh();
    settings_pin_modal_theme_refresh();
    settings_incr_modal_theme_refresh();
    settings_macro_modal_theme_refresh();
    settings_mach_name_modal_theme_refresh();
    settings_qbtn_modal_theme_refresh();
    settings_grbl_dump_modal_theme_refresh();
}
"""

WL_PRIV_HEADER = """#pragma once

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

extern lv_timer_t *wl_timer;
extern lv_obj_t *wl_radio_lbl;
extern lv_obj_t *wl_ssid_lbl;
extern lv_obj_t *wl_ip_lbl;
extern lv_obj_t *wl_scan_lbl;
extern lv_obj_t *wl_bt_radio_lbl;
extern lv_obj_t *wl_bt_paired_lbl;
extern lv_obj_t *wl_154_radio_lbl;
extern lv_obj_t *wl_154_net_lbl;
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
void wl_espnow_mac_modal_hide(void);
void wl_zb_add_modal_hide(void);
void wl_th_add_modal_hide(void);
void wl_timer_maybe_start(void);
void wl_panel_scroll_hook(bool attach);

#ifdef __cplusplus
}
#endif
"""

WL_STATE_DEFS = """
int wl_page = WL_PG_MAIN;
int wl_hist[6];
int wl_hist_n = 0;
bool wl_main_ref_exp = false;

lv_timer_t *wl_timer = NULL;
lv_obj_t *wl_radio_lbl = NULL;
lv_obj_t *wl_ssid_lbl = NULL;
lv_obj_t *wl_ip_lbl = NULL;
lv_obj_t *wl_scan_lbl = NULL;
lv_obj_t *wl_bt_radio_lbl = NULL;
lv_obj_t *wl_bt_paired_lbl = NULL;
lv_obj_t *wl_154_radio_lbl = NULL;
lv_obj_t *wl_154_net_lbl = NULL;
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
"""

WL_RENAME = {
    "s_page": "wl_page",
    "s_hist": "wl_hist",
    "s_hist_n": "wl_hist_n",
    "s_main_ref_exp": "wl_main_ref_exp",
    "s_wl_timer": "wl_timer",
    "s_radio_lbl": "wl_radio_lbl",
    "s_ssid_lbl": "wl_ssid_lbl",
    "s_ip_lbl": "wl_ip_lbl",
    "s_scan_lbl": "wl_scan_lbl",
    "s_bt_radio_lbl": "wl_bt_radio_lbl",
    "s_bt_paired_lbl": "wl_bt_paired_lbl",
    "s_154_radio_lbl": "wl_154_radio_lbl",
    "s_154_net_lbl": "wl_154_net_lbl",
    "s_radio_cache": "wl_radio_cache",
    "s_ssid_cache": "wl_ssid_cache",
    "s_ip_cache": "wl_ip_cache",
    "s_scan_cache": "wl_scan_cache",
    "s_wifi_conn_cache": "wl_wifi_conn_cache",
    "s_bt_radio_cache": "wl_bt_radio_cache",
    "s_bt_paired_cache": "wl_bt_paired_cache",
    "s_154_radio_cache": "wl_154_radio_cache",
    "s_154_net_cache": "wl_154_net_cache",
    "s_scan_done_cache": "wl_scan_done_cache",
    "s_scan_n_cache": "wl_scan_n_cache",
    "s_bt_scan_done_cache": "wl_bt_scan_done_cache",
    "s_bt_scan_n_cache": "wl_bt_scan_n_cache",
    "s_bt_conn_cache": "wl_bt_conn_cache",
    "s_bt_pk_cache": "wl_bt_pk_cache",
    "s_en_bridge_lbl": "wl_en_bridge_lbl",
    "s_en_scan_lbl": "wl_en_scan_lbl",
    "s_en_traf_lbl": "wl_en_traf_lbl",
    "s_en_dbg_snap_lbl": "wl_en_dbg_snap_lbl",
    "s_en_dbg_last_lbl": "wl_en_dbg_last_lbl",
    "s_en_bridge_cache": "wl_en_bridge_cache",
    "s_en_scan_cache": "wl_en_scan_cache",
    "s_en_traf_cache": "wl_en_traf_cache",
    "s_en_dbg_snap_cache": "wl_en_dbg_snap_cache",
    "s_en_dbg_last_cache": "wl_en_dbg_last_cache",
    "s_en_scan_done_cache": "wl_en_scan_done_cache",
    "s_en_scan_n_cache": "wl_en_scan_n_cache",
    "s_en_scan_fail_cache": "wl_en_scan_fail_cache",
    "s_en_mac_modal": "wl_en_mac_modal",
    "s_en_mac_kb": "wl_en_mac_kb",
    "s_en_mac_ta": "wl_en_mac_ta",
    "s_zb_add_modal": "wl_zb_add_modal",
    "s_zb_add_kb": "wl_zb_add_kb",
    "s_zb_name_ta": "wl_zb_name_ta",
    "s_zb_ieee_ta": "wl_zb_ieee_ta",
    "s_zb_code_ta": "wl_zb_code_ta",
    "s_th_add_modal": "wl_th_add_modal",
    "s_th_add_kb": "wl_th_add_kb",
    "s_th_name_ta": "wl_th_name_ta",
    "s_th_ext_ta": "wl_th_ext_ta",
    "s_zb_scan_done_cache": "wl_zb_scan_done_cache",
    "s_zb_scan_n_cache": "wl_zb_scan_n_cache",
    "s_th_scan_done_cache": "wl_th_scan_done_cache",
    "s_th_scan_n_cache": "wl_th_scan_n_cache",
    "s_wl_scrolling": "wl_scrolling",
    "s_wl_rebuild_pending": "wl_rebuild_pending",
    "s_connect_modal": "wl_connect_modal",
    "s_connect_kb": "wl_connect_kb",
    "s_connect_ta": "wl_connect_ta",
    "s_connect_ssid": "wl_connect_ssid",
    "s_bt_pk_modal": "wl_bt_pk_modal",
    "s_bt_pk_kb": "wl_bt_pk_kb",
    "s_bt_pk_ta": "wl_bt_pk_ta",
    "s_bt_pk_hint": "wl_bt_pk_hint",
    "PG_MAIN": "WL_PG_MAIN",
    "PG_WIFI": "WL_PG_WIFI",
    "PG_WIFI_DETAILS": "WL_PG_WIFI_DETAILS",
    "PG_WIFI_ADVANCED": "WL_PG_WIFI_ADVANCED",
    "PG_WIFI_SAVED": "WL_PG_WIFI_SAVED",
    "PG_WIFI_CONNECT": "WL_PG_WIFI_CONNECT",
    "PG_BT": "WL_PG_BT",
    "PG_BT_ADVANCED": "WL_PG_BT_ADVANCED",
    "PG_ZIGBEE": "WL_PG_ZIGBEE",
    "PG_ZIGBEE_ADVANCED": "WL_PG_ZIGBEE_ADVANCED",
    "PG_THREAD": "WL_PG_THREAD",
    "PG_THREAD_ADVANCED": "WL_PG_THREAD_ADVANCED",
    "PG_ESPNOW": "WL_PG_ESPNOW",
    "PG_ESPNOW_ADVANCED": "WL_PG_ESPNOW_ADVANCED",
    "BLE_PK_NONE": "WL_BLE_PK_NONE",
    "BLE_PK_INPUT": "WL_BLE_PK_INPUT",
    "BLE_PK_DISPLAY": "WL_BLE_PK_DISPLAY",
    "BLE_PK_CONFIRM": "WL_BLE_PK_CONFIRM",
    "rebuild,": "wl_rebuild,",
    "rebuild)": "wl_rebuild)",
    "rebuild_now(": "wl_rebuild_now(",
    "connect_modal_hide(": "wl_connect_modal_hide(",
    "bt_passkey_modal_hide(": "wl_bt_passkey_modal_hide(",
    "espnow_mac_modal_hide(": "wl_espnow_mac_modal_hide(",
    "zb_add_modal_hide(": "wl_zb_add_modal_hide(",
    "th_add_modal_hide(": "wl_th_add_modal_hide(",
    "wl_timer_maybe_start(": "wl_timer_maybe_start(",
    "wl_panel_scroll_hook(": "wl_panel_scroll_hook(",
    "build_main(": "wl_build_main(",
    "build_wifi_hub(": "wl_build_wifi_hub(",
    "build_wifi_saved(": "wl_build_wifi_saved(",
    "build_wifi_sub(": "wl_build_wifi_sub(",
    "build_bt_hub(": "wl_build_bt_hub(",
    "build_bt_advanced(": "wl_build_bt_advanced(",
    "build_802154_hub(": "wl_build_802154_hub(",
    "build_802154_advanced(": "wl_build_802154_advanced(",
    "build_espnow_hub(": "wl_build_espnow_hub(",
    "build_espnow_adv(": "wl_build_espnow_adv(",
}


def wl_rename(text: str) -> str:
    for old, new in WL_RENAME.items():
        text = text.replace(old, new)
    return text


def slice_lines(lines, start, end):
    return lines[start - 1:end]


def split_modals():
    lines = MODALS.read_text(encoding="utf-8").splitlines()
    inc = ROOT / "include"

    (inc / "ui_settings_modal_kb.h").write_text(
        """#pragma once

#include <lvgl.h>

#ifdef __cplusplus
extern "C" {
#endif

void settings_modal_kb_configure_text(lv_obj_t *kb);
void settings_modal_kb_configure_number(lv_obj_t *kb);

#ifdef __cplusplus
}
#endif
""",
        encoding="utf-8",
    )

    priv_parts = [
        "void settings_transport_modal_theme_refresh(void);",
        "void settings_pin_modal_theme_refresh(void);",
        "void settings_incr_modal_theme_refresh(void);",
        "void settings_macro_modal_theme_refresh(void);",
        "void settings_mach_name_modal_theme_refresh(void);",
        "void settings_qbtn_modal_theme_refresh(void);",
        "void settings_grbl_dump_modal_theme_refresh(void);",
    ]
    (inc / "ui_settings_modals_priv.h").write_text(
        "#pragma once\n\n#ifdef __cplusplus\nextern \"C\" {\n#endif\n\n"
        + "\n".join(priv_parts)
        + "\n\n#ifdef __cplusplus\n}\n#endif\n",
        encoding="utf-8",
    )

    chunks = {
        "ui_settings_modal_transport.c": (16, 374),
        "ui_settings_modal_pin.c": (375, 575),
        "ui_settings_modal_incr.c": (576, 648),
        "ui_settings_modal_macro.c": (649, 776),
        "ui_settings_modal_mach_name.c": (777, 922),
        "ui_settings_modal_qbtn.c": (923, 1038),
        "ui_settings_modal_grbl_dump.c": (1039, 1149),
    }

    for fname, (start, end) in chunks.items():
        body = slice_lines(lines, start, end)
        # drop duplicate keyboard defs in mach_name chunk tail
        out = MODAL_HDR + "\n" + "\n".join(body) + "\n"
        out = out.replace("configure_text_keyboard", "settings_modal_kb_configure_text")
        out = out.replace("configure_number_keyboard", "settings_modal_kb_configure_number")
        (ROOT / fname).write_text(out, encoding="utf-8")

    # Add theme refresh to each modal file
    add_modal_theme_refreshers()

    (ROOT / "ui_settings_modal_kb.c").write_text(
        '#include "ui_settings_modal_kb.h"\n#include "ui_internal.h"\n#include "nvs_shim.h"\n'
        + MODAL_KB_BODY
        + "\n",
        encoding="utf-8",
    )

    (ROOT / "ui_settings_modals.c").write_text(
        '#include "ui_settings_modals_priv.h"\n\n' + THEME_ORCH + "\n", encoding="utf-8"
    )

    MODALS.unlink()


def add_modal_theme_refreshers():
    """Append per-modal theme_refresh after hide/show in each file."""
    patches = {
        "ui_settings_modal_transport.c": (
            "s_xport_modal",
            "settings_transport_modal_theme_refresh",
            """void settings_transport_modal_theme_refresh(void)
{
    if (s_xport_kb) {
        modulus_ui_apply_keyboard_theme(s_xport_kb);
    }
    if (s_xport_modal) {
        modulus_ui_apply_overlay_scrim(s_xport_modal);
    }
}
""",
        ),
        "ui_settings_modal_pin.c": (
            "s_pin_modal",
            "settings_pin_modal_theme_refresh",
            """void settings_pin_modal_theme_refresh(void)
{
    if (s_pin_kb) {
        modulus_ui_apply_keyboard_theme(s_pin_kb);
    }
    if (!s_pin_modal) {
        return;
    }
    modulus_ui_apply_overlay_scrim(s_pin_modal);
    lv_obj_t *card = lv_obj_get_child(s_pin_modal, 0);
    if (card) {
        lv_obj_set_style_bg_color(card, modulus_ui_color_surface_container_highest(), 0);
        lv_obj_set_style_border_color(card, modulus_ui_color_outline_variant(), 0);
    }
    if (s_pin_status) {
        const char *txt = lv_label_get_text(s_pin_status);
        const bool err = txt && txt[0] != '\0' &&
                         (strstr(txt, "Incorrect") != NULL || strstr(txt, "must") != NULL ||
                          strstr(txt, "match") != NULL || strstr(txt, "Could not") != NULL);
        lv_obj_set_style_text_color(s_pin_status,
                                    err ? modulus_ui_color_error()
                                        : modulus_ui_color_on_surface_variant(),
                                    0);
    }
}
""",
        ),
        "ui_settings_modal_incr.c": (
            "s_incr_modal",
            "settings_incr_modal_theme_refresh",
            """void settings_incr_modal_theme_refresh(void)
{
    if (s_incr_modal) {
        modulus_ui_apply_overlay_scrim(s_incr_modal);
    }
}
""",
        ),
        "ui_settings_modal_macro.c": (
            "s_macro_modal",
            "settings_macro_modal_theme_refresh",
            """void settings_macro_modal_theme_refresh(void)
{
    if (s_macro_modal) {
        modulus_ui_apply_overlay_scrim(s_macro_modal);
    }
    if (s_macro_kb) {
        modulus_ui_apply_keyboard_theme(s_macro_kb);
    }
}
""",
        ),
        "ui_settings_modal_mach_name.c": (
            "s_mach_name_modal",
            "settings_mach_name_modal_theme_refresh",
            """void settings_mach_name_modal_theme_refresh(void)
{
    if (s_mach_name_kb) {
        modulus_ui_apply_keyboard_theme(s_mach_name_kb);
    }
    if (s_mach_name_modal) {
        modulus_ui_apply_overlay_scrim(s_mach_name_modal);
    }
}
""",
        ),
        "ui_settings_modal_qbtn.c": (
            "s_qbtn_modal",
            "settings_qbtn_modal_theme_refresh",
            """void settings_qbtn_modal_theme_refresh(void)
{
    if (s_qbtn_modal) {
        modulus_ui_apply_overlay_scrim(s_qbtn_modal);
    }
}
""",
        ),
        "ui_settings_modal_grbl_dump.c": (
            "s_grbl_dump_modal",
            "settings_grbl_dump_modal_theme_refresh",
            """void settings_grbl_dump_modal_theme_refresh(void)
{
    if (s_grbl_dump_modal) {
        modulus_ui_apply_overlay_scrim(s_grbl_dump_modal);
    }
}
""",
        ),
    }
    for fname, (_, _, fn_body) in patches.items():
        path = ROOT / fname
        text = path.read_text(encoding="utf-8")
        if "settings_" in fn_body.split("(")[0].split("void ")[1] and fn_body.split("(")[0].split("void ")[1] in text:
            continue
        path.write_text(text.rstrip() + "\n\n" + fn_body + "\n", encoding="utf-8")


def split_wireless():
    lines = WIRELESS.read_text(encoding="utf-8").splitlines()
    (ROOT / "include" / "ui_settings_wireless_priv.h").write_text(WL_PRIV_HEADER, encoding="utf-8")

    wl_hdr = """#include "ui_settings_wireless_priv.h"
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
"""

    # core: timer, handlers, modals, shell (not build_*)
    core_parts = (
        slice_lines(lines, 161, 845)
        + slice_lines(lines, 1363, 1556)
        + slice_lines(lines, 1557, 1958)
        + slice_lines(lines, 1960, 2126)
    )
    core_body = wl_rename("\n".join(core_parts))
    # fix rebuild_now switch to call wl_wireless_build_page
    core_body = core_body.replace(
        "static void wl_rebuild_now(void)",
        "void wl_rebuild_now(void)",
    )
    core_body = core_body.replace("static void rebuild(void)", "void wl_rebuild(void)")
    core_body = core_body.replace("static void wl_timer_stop_core", "void wl_timer_stop_core")
    core_body = core_body.replace("static void wl_timer_maybe_start", "void wl_timer_maybe_start")
    core_body = core_body.replace("static void wl_panel_scroll_hook", "void wl_panel_scroll_hook")
    core_body = core_body.replace("static void wl_connect_modal_hide", "void wl_connect_modal_hide")
    core_body = core_body.replace("static void wl_bt_passkey_modal_hide", "void wl_bt_passkey_modal_hide")
    core_body = core_body.replace("static void wl_espnow_mac_modal_hide", "void wl_espnow_mac_modal_hide")
    core_body = core_body.replace("static void wl_zb_add_modal_hide", "void wl_zb_add_modal_hide")
    core_body = core_body.replace("static void wl_th_add_modal_hide", "void wl_th_add_modal_hide")
    # replace rebuild_now body switch with build_page call
    switch_start = core_body.find("switch (wl_page)")
    if switch_start != -1:
        brace = core_body.find("{", switch_start)
        # find matching close of switch - use simple replace of whole rebuild_now
        old_rebuild_now = core_body[core_body.find("void wl_rebuild_now"):core_body.find("void wl_rebuild(")]
        new_rebuild_now = """void wl_rebuild_now(void)
{
    wl_timer_stop_core();
    lv_obj_t *panel = modulus_ui_settings_tab_panel(MOD_UI_SETTINGS_TAB_WIRELESS);
    if (!panel) {
        return;
    }
    lv_obj_clean(panel);
    wl_wireless_build_page(panel);
    wl_panel_scroll_hook(true);
    wl_timer_maybe_start();
    modulus_ui_settings_note_tab_built(MOD_UI_SETTINGS_TAB_WIRELESS);
}

"""
        core_body = core_body.replace(old_rebuild_now, new_rebuild_now)

    (ROOT / "ui_settings_wireless_core.c").write_text(
        wl_hdr + "\n" + core_body + "\n", encoding="utf-8"
    )

    build_parts = slice_lines(lines, 846, 1361)
    build_body = wl_rename("\n".join(build_parts))
    build_body = build_body.replace("static void wl_build_", "void wl_build_")
    build_router = """
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
    case WL_PG_WIFI_ADVANCED:
        wl_build_wifi_sub(panel, "Advanced");
        break;
    case WL_PG_BT:
        wl_build_bt_hub(panel);
        break;
    case WL_PG_BT_ADVANCED:
        wl_build_bt_advanced(panel);
        break;
    case WL_PG_ZIGBEE:
        wl_build_802154_hub(panel, "Zigbee", "zigbee", WL_PG_ZIGBEE_ADVANCED);
        break;
    case WL_PG_ZIGBEE_ADVANCED:
        wl_build_802154_advanced(panel, "Zigbee");
        break;
    case WL_PG_THREAD:
        wl_build_802154_hub(panel, "Thread", "thread", WL_PG_THREAD_ADVANCED);
        break;
    case WL_PG_THREAD_ADVANCED:
        wl_build_802154_advanced(panel, "Thread");
        break;
    case WL_PG_ESPNOW:
        wl_build_espnow_hub(panel);
        break;
    case WL_PG_ESPNOW_ADVANCED:
        wl_build_espnow_adv(panel);
        break;
    default:
        wl_build_main(panel);
        break;
    }
}
"""
    (ROOT / "ui_settings_wireless_build.c").write_text(
        wl_hdr + "\n" + build_body + "\n" + build_router + "\n", encoding="utf-8"
    )

    (ROOT / "ui_settings_wireless_state.c").write_text(
        '#include "ui_settings_wireless_priv.h"\n\n' + WL_STATE_DEFS + "\n", encoding="utf-8"
    )

    theme_fn = slice_lines(lines, 2086, 2126)
    theme_body = wl_rename("\n".join(theme_fn))
    theme_body = theme_body.replace(
        "void modulus_ui_wireless_theme_refresh(void)",
        "void modulus_ui_wireless_theme_refresh(void)",
    )
    (ROOT / "ui_settings_wireless_theme.c").write_text(
        wl_hdr + "\n" + theme_body + "\n", encoding="utf-8"
    )

    # Remove theme from core if duplicated
    core_path = ROOT / "ui_settings_wireless_core.c"
    core_text = core_path.read_text(encoding="utf-8")
    idx = core_text.find("void modulus_ui_wireless_theme_refresh")
    if idx != -1:
        core_path.write_text(core_text[:idx].rstrip() + "\n", encoding="utf-8")

    WIRELESS.unlink()


def update_cmake():
    cmake = ROOT / "CMakeLists.txt"
    text = cmake.read_text(encoding="utf-8")
    text = text.replace('"ui_settings_modals.c"\n', "")
    text = text.replace('"ui_settings_wireless.c"\n', "")
    insert = """        "ui_settings_modal_kb.c"
        "ui_settings_modal_transport.c"
        "ui_settings_modal_pin.c"
        "ui_settings_modal_incr.c"
        "ui_settings_modal_macro.c"
        "ui_settings_modal_mach_name.c"
        "ui_settings_modal_qbtn.c"
        "ui_settings_modal_grbl_dump.c"
        "ui_settings_modals.c"
        "ui_settings_wireless_state.c"
        "ui_settings_wireless_core.c"
        "ui_settings_wireless_build.c"
        "ui_settings_wireless_theme.c"
"""
    if "ui_settings_modal_kb.c" not in text:
        anchor = '        "ui_settings_common.c"\n'
        if anchor in text:
            text = text.replace(anchor, anchor + insert)
        else:
            text = text.replace(
                '        "ui_settings_modals.c"\n        "ui_settings_wireless.c"\n',
                insert,
            )
    cmake.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    split_modals()
    split_wireless()
    update_cmake()
    print("split complete")
