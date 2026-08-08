#include "ui_settings_modals_priv.h"
#include "ui_settings_modals.h"
#include "ui_settings_common.h"
#include "ui_settings_wireless_priv.h"
#include "ui_internal.h"

static lv_obj_t *s_wl_adv_modal = NULL;

void wl_build_wifi_sub(lv_obj_t *p, const char *name);
void wl_build_bt_advanced(lv_obj_t *p);
void wl_build_802154_advanced(lv_obj_t *p, const char *proto);
void wl_build_espnow_adv(lv_obj_t *p);

void settings_wl_adv_modal_hide(void)
{
    if (!s_wl_adv_modal) {
        wl_build_skip_back = false;
        return;
    }
    wl_build_skip_back = false;
    modulus_ui_dialog_scrim_hide_animated(&s_wl_adv_modal);
}

static void close_cb(lv_event_t *e)
{
    (void)e;
    settings_wl_adv_modal_hide();
}

void settings_wl_adv_modal_show(int kind)
{
    settings_wl_adv_modal_hide();

    const char *title = "Advanced";
    switch (kind) {
    case WL_PG_WIFI_ADVANCED:
        title = "Wi-Fi advanced";
        break;
    case WL_PG_BT_ADVANCED:
        title = "Bluetooth advanced";
        break;
    case WL_PG_ZIGBEE_ADVANCED:
        title = "Zigbee advanced";
        break;
    case WL_PG_THREAD_ADVANCED:
        title = "Thread advanced";
        break;
    case WL_PG_ESPNOW_ADVANCED:
        title = "ESP-NOW advanced";
        break;
    default:
        break;
    }

    s_wl_adv_modal = modulus_ui_dialog_scrim_create();
    lv_obj_t *card = modulus_ui_dialog_card_create(s_wl_adv_modal, MOD_UI_DIALOG_W_WIDE, 0);
    modulus_ui_motion_dialog_enter(card);
    modulus_ui_dialog_header(card, title, close_cb, NULL);
    modulus_ui_dialog_scrim_bind_dismiss(s_wl_adv_modal, close_cb, NULL);

    lv_obj_t *body = lv_obj_create(card);
    lv_obj_remove_style_all(body);
    lv_obj_set_width(body, lv_pct(100));
    lv_obj_set_height(body, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(body, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(body, MOD_UI_SPACE_SM, 0);
    lv_obj_set_style_max_height(body, 440, 0);
    lv_obj_add_flag(body, LV_OBJ_FLAG_SCROLLABLE);

    wl_build_skip_back = true;
    const int saved_page = wl_page;
    switch (kind) {
    case WL_PG_WIFI_ADVANCED:
        wl_page = WL_PG_WIFI_ADVANCED;
        wl_build_wifi_sub(body, "Advanced");
        break;
    case WL_PG_BT_ADVANCED:
        wl_build_bt_advanced(body);
        break;
    case WL_PG_ZIGBEE_ADVANCED:
        wl_build_802154_advanced(body, "Zigbee");
        break;
    case WL_PG_THREAD_ADVANCED:
        wl_build_802154_advanced(body, "Thread");
        break;
    case WL_PG_ESPNOW_ADVANCED:
        wl_build_espnow_adv(body);
        break;
    default:
        break;
    }
    wl_page = saved_page;
    wl_build_skip_back = false;

    lv_obj_t *row = modulus_ui_dialog_actions(card, true);
    modulus_ui_dialog_action_btn(row, "Done", MOD_UI_DIALOG_BTN_FILLED, close_cb, NULL);
}

void settings_wl_adv_modal_theme_refresh(void)
{
    modulus_ui_dialog_theme_refresh(s_wl_adv_modal);
}

void settings_wl_adv_modal_open_cb(lv_event_t *e)
{
    const int kind = (int)(intptr_t)lv_event_get_user_data(e);
    settings_wl_adv_modal_show(kind);
}
