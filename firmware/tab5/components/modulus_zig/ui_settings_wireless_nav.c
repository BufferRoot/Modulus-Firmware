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

void nav_push(int page)
{
    if (wl_hist_n < 6) {
        wl_hist[wl_hist_n++] = wl_page;
    }
    wl_page = page;
    wl_rebuild();
}

void nav_pop(lv_event_t *e)
{
    (void)e;
    wl_connect_modal_hide();
    if (wl_hist_n > 0) {
        wl_page = wl_hist[--wl_hist_n];
    } else {
        wl_page = WL_PG_MAIN;
    }
    wl_rebuild();
}

void nav_to(lv_event_t *e)
{
    nav_push((int)(intptr_t)lv_event_get_user_data(e));
}
void wl_rebuild_now(void)
{
    wl_timer_stop_core();
    lv_obj_t *panel = modulus_ui_settings_tab_panel(MOD_UI_SETTINGS_TAB_WIRELESS);
    if (!panel) {
        return;
    }
    /* Preserve scroll position across the clean/rebuild — otherwise every
     * scan press, toggle, or live-state refresh snaps the page to the top
     * and the user has to scroll back down (reported on WiFi/ESP-NOW/BLE/
     * Zigbee alike). Layout must be finalized before restoring, or the
     * scroll clamps to 0 because content height is still unknown. */
    const int32_t scroll_y = lv_obj_get_scroll_y(panel);
    static int s_last_built_page = -1;
    const bool same_page = (s_last_built_page == (int)wl_page);
    s_last_built_page = (int)wl_page;
    /* lv_obj_clean adjusts scroll and fires SCROLL_END through our hook,
     * which re-enters wl_timer_tick while children are half-freed. Detach
     * the hook for the duration of the rebuild. */
    wl_panel_scroll_hook(false);
    lv_obj_clean(panel);
    wl_wireless_build_page(panel);
    if (same_page && scroll_y > 0) {
        lv_obj_update_layout(panel);
        lv_obj_scroll_to_y(panel, scroll_y, LV_ANIM_OFF);
    }
    wl_panel_scroll_hook(true);
    wl_timer_maybe_start();
    modulus_ui_settings_note_tab_built(MOD_UI_SETTINGS_TAB_WIRELESS);
}

static lv_timer_t *s_wl_rebuild_debounce;

static void wl_rebuild_debounce_cb(lv_timer_t *t)
{
    (void)t;
    s_wl_rebuild_debounce = NULL;
    if (wl_scrolling) {
        wl_rebuild_pending = true;
        return;
    }
    wl_rebuild_pending = false;
    wl_rebuild_now();
}

void wl_rebuild(void)
{
    if (wl_scrolling) {
        wl_rebuild_pending = true;
        return;
    }
    /* Coalesce rapid toggles/scan taps — one rebuild per 120 ms. */
    wl_rebuild_pending = true;
    if (s_wl_rebuild_debounce) {
        lv_timer_reset(s_wl_rebuild_debounce);
        return;
    }
    s_wl_rebuild_debounce = lv_timer_create(wl_rebuild_debounce_cb, 120, NULL);
    lv_timer_set_repeat_count(s_wl_rebuild_debounce, 1);
}

static void wl_panel_scroll_cb(lv_event_t *e)
{
    const lv_event_code_t code = lv_event_get_code(e);
    if (code == LV_EVENT_SCROLL_BEGIN) {
        wl_scrolling = true;
        if (wl_timer) {
            lv_timer_pause(wl_timer);
        }
        modulus_wireless_ble_scan_stop();
        return;
    }
    if (code != LV_EVENT_SCROLL_END) {
        return;
    }
    wl_scrolling = false;
    wl_timer_maybe_start();
    if (wl_timer) {
        lv_timer_resume(wl_timer);
        wl_timer_tick();
    }
    if (wl_rebuild_pending) {
        wl_rebuild_pending = false;
        wl_rebuild_now();
    }
}

void wl_panel_scroll_hook(bool attach)
{
    lv_obj_t *panel = modulus_ui_settings_tab_panel(MOD_UI_SETTINGS_TAB_WIRELESS);
    if (!panel) {
        return;
    }
    lv_obj_remove_event_cb(panel, wl_panel_scroll_cb);
    if (attach) {
        lv_obj_add_event_cb(panel, wl_panel_scroll_cb, LV_EVENT_SCROLL_BEGIN, NULL);
        lv_obj_add_event_cb(panel, wl_panel_scroll_cb, LV_EVENT_SCROLL_END, NULL);
    }
}

void modulus_ui_settings_build_wireless_tab(void)
{
    wl_rebuild_pending = false;
    wl_rebuild();
}

void modulus_ui_settings_wireless_open_espnow(void)
{
    wl_page = WL_PG_ESPNOW;
    wl_hist_n = 0;
    wl_hist[wl_hist_n++] = WL_PG_MAIN;
    modulus_ui_settings_select_tab(4);
    /* select_tab no-ops when already on Wireless — rebuild for subpage nav. */
    if (modulus_ui_settings_visible()) {
        wl_rebuild();
    }
}
