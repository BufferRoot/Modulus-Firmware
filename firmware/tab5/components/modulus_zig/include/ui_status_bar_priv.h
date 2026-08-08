#pragma once

#include "battery_shim.h"
#include "cnc_cmd_exports.h"
#include "ui_icons.h"

#include <stddef.h>
#include <stdint.h>

#include <lvgl.h>

typedef struct {
    lv_obj_t *bar;
    lv_obj_t *conn_dot;
    lv_obj_t *state_badge;
    lv_obj_t *alarm_badge;
    lv_obj_t *state_lbl;
    lv_obj_t *mpg_btn;
    lv_obj_t *mpg_lbl;
    lv_obj_t *wcs_val;
    lv_obj_t *tool_hdr;
    lv_obj_t *tool_val;
    lv_obj_t *feed_hdr;
    lv_obj_t *feed_val;
    lv_obj_t *feed_unit;
    lv_obj_t *spin_hdr;
    lv_obj_t *spin_val;
    lv_obj_t *spin_unit;
    lv_obj_t *clock_lbl;
    lv_obj_t *batt_row;
    lv_obj_t *batt_icon;
    lv_obj_t *batt_pct;
    lv_obj_t *wireless_row;
    lv_obj_t *wifi_icon;
    lv_obj_t *wifi_badge;
    lv_obj_t *ble_icon;
    lv_obj_t *espnow_icon;
    lv_obj_t *mpg_icon;
    lv_obj_t *settings_icon;
    lv_obj_t *power_icon;
} status_bar_t;

void bar_build(lv_obj_t *parent, status_bar_t *out);
void bar_no_scroll(lv_obj_t *obj);
lv_obj_t *bar_divider(lv_obj_t *parent);
lv_obj_t *bar_make_pill(lv_obj_t *parent, const char *text, lv_color_t bg, lv_color_t fg);
lv_obj_t *bar_stat_col(lv_obj_t *parent, const char *hdr, const char *val, const char *unit,
                       lv_obj_t **out_hdr, lv_obj_t **out_val, lv_obj_t **out_unit,
                       bool clickable, bool right_align, int val_row_min_width);
const char *bar_state_name(uint8_t st);
const char *bar_wcs_name(uint8_t wcs);
lv_color_t bar_conn_color(uint8_t session);
void bar_state_pill_style(uint8_t st, bool connected, lv_color_t *bg, lv_color_t *fg);
void bar_format_clock(char *buf, size_t len);
modulus_ui_icon_id_t bar_batt_icon(const modulus_battery_status_t *st);

/** Wi-Fi: 0=off, 1=idle, 2=connecting, 3=connected (STA). */
uint8_t bar_wireless_wifi_state(void);
lv_color_t bar_wireless_wifi_color(uint8_t st);
/** BLE: 0=hidden, 1=idle, 2=connecting, 3=connected. */
uint8_t bar_wireless_ble_state(void);
lv_color_t bar_wireless_ble_color(uint8_t st);
/** ESP-NOW: 0=hidden, 1=enabled, 2=transport active. */
uint8_t bar_wireless_espnow_state(void);
lv_color_t bar_wireless_espnow_color(uint8_t st);
void bar_update_wireless(status_bar_t *bar, uint8_t *wifi_st, uint8_t *ble_st, uint8_t *en_st,
                         uint32_t *wifi_color_u32, uint32_t *ble_color_u32, uint32_t *en_color_u32);
