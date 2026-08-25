#include "nvs_shim.h"
#include "cnc_cmd_exports.h"
#include "audio_shim.h"
#include "shop_recipe.h"
#include "wireless_shim.h"
#include "sdkconfig.h"
#include "ui_internal.h"
#include "ui_cnc_profiles.h"

#if !CONFIG_MODULUS_ZIG_UI_ENGINE
#include "ui_settings_priv.h"
#include "ui_settings_common.h"
#include "ui_settings_modal_kb.h"
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { k_prof_slots = 4, k_blob_max = 220, k_name_max = 24 };

static const char *const k_prof_keys[k_prof_slots] = {
    "cnc_p0", "cnc_p1", "cnc_p2", "cnc_p3",
};

static void copy_field(char *dst, size_t dst_len, const char *src)
{
    if (!dst || dst_len == 0) {
        return;
    }
    dst[0] = '\0';
    if (!src) {
        return;
    }
    strncpy(dst, src, dst_len - 1);
    dst[dst_len - 1] = '\0';
}

static void pack_live(char *out, size_t out_len, const char *name)
{
    char ws_host[64] = "";
    char tn_host[64] = "";
    char masso_ip[32] = "";
    char masso_sn[16] = "";
    char en_mac[24] = "";
    (void)modulus_nvs_get_str("ws_host", ws_host, sizeof(ws_host));
    (void)modulus_nvs_get_str("tn_host", tn_host, sizeof(tn_host));
    (void)modulus_nvs_get_str("masso_ip", masso_ip, sizeof(masso_ip));
    (void)modulus_nvs_get_str("masso_sn", masso_sn, sizeof(masso_sn));
    (void)modulus_nvs_get_str("en_mac", en_mac, sizeof(en_mac));
    snprintf(out, out_len, "%s|%u|%u|%s|%u|%s|%u|%s|%s|%s|%u", name ? name : "Profile",
             (unsigned)modulus_nvs_get_u8("cnc_proto", 0),
             (unsigned)modulus_nvs_get_u8("cnc_conn", 4), ws_host,
             (unsigned)modulus_nvs_get_u16("ws_port", 81), tn_host,
             (unsigned)modulus_nvs_get_u16("tn_port", 23), masso_ip, masso_sn, en_mac,
             (unsigned)modulus_nvs_get_u8("en_chan", 1));
}

static bool parse_field(char *blob, int idx, char *out, size_t out_len)
{
    char *p = blob;
    int i = 0;
    while (p && *p) {
        char *bar = strchr(p, '|');
        if (bar) {
            *bar = '\0';
        }
        if (i == idx) {
            copy_field(out, out_len, p);
            if (bar) {
                *bar = '|';
            }
            return true;
        }
        if (!bar) {
            break;
        }
        *bar = '|';
        p = bar + 1;
        i++;
    }
    return false;
}

static void apply_blob(char *blob)
{
    char tmp[48];
    if (parse_field(blob, 1, tmp, sizeof(tmp))) {
        modulus_nvs_set_u8("cnc_proto", (uint8_t)atoi(tmp));
    }
    if (parse_field(blob, 2, tmp, sizeof(tmp))) {
        modulus_nvs_set_u8("cnc_conn", (uint8_t)atoi(tmp));
    }
    if (parse_field(blob, 3, tmp, sizeof(tmp))) {
        modulus_nvs_set_str("ws_host", tmp);
    }
    if (parse_field(blob, 4, tmp, sizeof(tmp))) {
        modulus_nvs_set_u16("ws_port", (uint16_t)atoi(tmp));
    }
    if (parse_field(blob, 5, tmp, sizeof(tmp))) {
        modulus_nvs_set_str("tn_host", tmp);
    }
    if (parse_field(blob, 6, tmp, sizeof(tmp))) {
        modulus_nvs_set_u16("tn_port", (uint16_t)atoi(tmp));
    }
    if (parse_field(blob, 7, tmp, sizeof(tmp))) {
        modulus_nvs_set_str("masso_ip", tmp);
    }
    if (parse_field(blob, 8, tmp, sizeof(tmp))) {
        modulus_nvs_set_str("masso_sn", tmp);
    }
    if (parse_field(blob, 9, tmp, sizeof(tmp))) {
        modulus_nvs_set_str("en_mac", tmp);
    }
    if (parse_field(blob, 10, tmp, sizeof(tmp)) && tmp[0]) {
        modulus_nvs_set_u8("en_chan", (uint8_t)atoi(tmp));
    }
}

void modulus_ui_cnc_profile_save_slot(uint8_t slot, const char *name)
{
    if (slot >= k_prof_slots) {
        return;
    }
    char blob[k_blob_max];
    pack_live(blob, sizeof(blob), name && name[0] ? name : "Profile");
    modulus_nvs_set_str(k_prof_keys[slot], blob);
    modulus_nvs_set_u8("cnc_prof", slot);
    modulus_audio_play_ui(1);
    modulus_ui_snackbar_show("Profile saved", 2500);
}

void modulus_ui_cnc_profile_activate(uint8_t slot)
{
    if (slot >= k_prof_slots) {
        return;
    }
    char blob[k_blob_max];
    if (!modulus_nvs_get_str(k_prof_keys[slot], blob, sizeof(blob)) || blob[0] == '\0') {
        modulus_audio_play_ui(2);
        return;
    }
    apply_blob(blob);
    modulus_nvs_set_u8("cnc_prof", slot);
    modulus_zig_transport_reinit();
    modulus_recipe_maybe_wifi_off_for_espnow();
    if (modulus_nvs_get_u8("cnc_conn", 4) == 0) {
        modulus_wireless_espnow_transport_reinit();
    }
    modulus_audio_play_ui(1);
    modulus_ui_snackbar_show("Profile activated", 2500);
}

void modulus_ui_cnc_profile_clear(uint8_t slot)
{
    if (slot >= k_prof_slots) {
        return;
    }
    modulus_nvs_set_str(k_prof_keys[slot], "");
}

static void sanitize_name(char *dst, size_t dst_len, const char *src)
{
    size_t j = 0;
    const size_t limit = (k_name_max < dst_len) ? (size_t)(k_name_max - 1) : dst_len - 1;
    for (size_t i = 0; src && src[i] && j < limit; i++) {
        const unsigned char c = (unsigned char)src[i];
        if (c >= 0x20 && c <= 0x7E && c != '|') {
            dst[j++] = (char)c;
        }
    }
    dst[j] = '\0';
    if (j == 0) {
        copy_field(dst, dst_len, "Profile");
    }
}

void modulus_ui_cnc_profile_rename(uint8_t slot, const char *name)
{
    if (slot >= k_prof_slots) {
        return;
    }
    char clean[k_name_max];
    sanitize_name(clean, sizeof(clean), name);

    char blob[k_blob_max];
    if (!modulus_nvs_get_str(k_prof_keys[slot], blob, sizeof(blob)) || blob[0] == '\0') {
        pack_live(blob, sizeof(blob), clean);
        modulus_nvs_set_str(k_prof_keys[slot], blob);
        modulus_audio_play_ui(1);
        modulus_ui_snackbar_show("Profile renamed", 2500);
        return;
    }
    char *bar = strchr(blob, '|');
    char out[k_blob_max];
    if (bar) {
        snprintf(out, sizeof(out), "%s%s", clean, bar);
    } else {
        snprintf(out, sizeof(out), "%s", clean);
    }
    modulus_nvs_set_str(k_prof_keys[slot], out);
    modulus_audio_play_ui(1);
    modulus_ui_snackbar_show("Profile renamed", 2500);
}

bool modulus_ui_cnc_profile_name(uint8_t slot, char *out, size_t out_len)
{
    if (!out || out_len == 0 || slot >= k_prof_slots) {
        return false;
    }
    out[0] = '\0';
    char blob[k_blob_max];
    if (!modulus_nvs_get_str(k_prof_keys[slot], blob, sizeof(blob)) || blob[0] == '\0') {
        return false;
    }
    return parse_field(blob, 0, out, out_len);
}

void modulus_ui_cnc_profile_boot_apply(void)
{
    if (modulus_nvs_get_u8("cnc_autocon", 0) == 0) {
        return;
    }
    const uint8_t slot = modulus_nvs_get_u8("cnc_prof", 0);
    char blob[k_blob_max];
    if (slot < k_prof_slots &&
        modulus_nvs_get_str(k_prof_keys[slot], blob, sizeof(blob)) && blob[0] != '\0') {
        apply_blob(blob);
    }
}

#if !CONFIG_MODULUS_ZIG_UI_ENGINE

/* ── Manager modal + rename keyboard ─────────────────────────────── */

static lv_obj_t *s_mgr_modal = NULL;
static lv_obj_t *s_mgr_body = NULL;
static lv_obj_t *s_rename_modal = NULL;
static lv_obj_t *s_rename_ta = NULL;
static lv_obj_t *s_rename_kb = NULL;
static uint8_t s_rename_slot = 0;

static void mgr_rebuild_body(void);
void modulus_ui_cnc_profiles_modal_hide(void);

static void rename_exit_ready(lv_anim_t *a)
{
    lv_obj_t *dlg = lv_anim_get_user_data(a);
    if (dlg) {
        lv_obj_delete(dlg);
    }
    s_rename_ta = NULL;
    s_rename_kb = NULL;
}

static void rename_hide(void)
{
    if (!s_rename_modal) {
        s_rename_ta = NULL;
        s_rename_kb = NULL;
        return;
    }
    lv_obj_t *dlg = s_rename_modal;
    s_rename_modal = NULL;
    s_rename_ta = NULL;
    s_rename_kb = NULL;
    lv_obj_t *card = lv_obj_get_child(dlg, 0);
    if (card && modulus_ui_motion_smooth()) {
        modulus_ui_motion_dialog_exit(card, rename_exit_ready, dlg);
        return;
    }
    lv_obj_delete(dlg);
}

static void rename_close_cb(lv_event_t *e)
{
    (void)e;
    rename_hide();
}

static void rename_save_cb(lv_event_t *e)
{
    (void)e;
    if (!s_rename_ta) {
        return;
    }
    modulus_ui_cnc_profile_rename(s_rename_slot, lv_textarea_get_text(s_rename_ta));
    rename_hide();
    mgr_rebuild_body();
    modulus_ui_settings_build_cnc_tab();
}

static void rename_ta_focus_cb(lv_event_t *e)
{
    if (s_rename_kb) {
        lv_keyboard_set_textarea(s_rename_kb, lv_event_get_target(e));
    }
}

void modulus_ui_cnc_profile_rename_show(uint8_t slot)
{
    if (slot >= k_prof_slots) {
        return;
    }
    rename_hide();
    s_rename_slot = slot;

    char cur[k_name_max];
    if (!modulus_ui_cnc_profile_name(slot, cur, sizeof(cur)) || cur[0] == '\0') {
        snprintf(cur, sizeof(cur), "Profile %u", (unsigned)(slot + 1));
    }

    s_rename_modal = modulus_ui_dialog_scrim_create();

    lv_obj_t *card = modulus_ui_dialog_card_create(s_rename_modal, MOD_UI_DIALOG_W_STANDARD, 0);
    lv_obj_align(card, LV_ALIGN_TOP_MID, 0, 40);
    modulus_ui_motion_dialog_enter(card);

    modulus_ui_dialog_header(card, "Rename profile", rename_close_cb, NULL);
    modulus_ui_dialog_scrim_bind_dismiss(s_rename_modal, rename_close_cb, NULL);
    modulus_ui_dialog_supporting(card, "ASCII only, up to 23 characters.");

    s_rename_ta = lv_textarea_create(card);
    lv_textarea_set_text(s_rename_ta, cur);
    lv_textarea_set_one_line(s_rename_ta, true);
    lv_textarea_set_max_length(s_rename_ta, k_name_max - 1);
    lv_obj_set_width(s_rename_ta, lv_pct(100));
    modulus_ui_apply_textarea_theme(s_rename_ta, false);
    lv_obj_add_event_cb(s_rename_ta, rename_ta_focus_cb, LV_EVENT_FOCUSED, NULL);

    lv_obj_t *row = modulus_ui_dialog_actions(card, true);
    modulus_ui_dialog_action_btn(row, "Cancel", MOD_UI_DIALOG_BTN_TONAL, rename_close_cb, NULL);
    modulus_ui_dialog_action_btn(row, "Save", MOD_UI_DIALOG_BTN_FILLED, rename_save_cb, NULL);

    s_rename_kb = lv_keyboard_create(s_rename_modal);
    lv_keyboard_set_mode(s_rename_kb, LV_KEYBOARD_MODE_TEXT_LOWER);
    settings_modal_kb_configure_text(s_rename_kb);
    lv_keyboard_set_textarea(s_rename_kb, s_rename_ta);
}

static void mgr_activate_cb(lv_event_t *e)
{
    const uint8_t slot = (uint8_t)(intptr_t)lv_event_get_user_data(e);
    modulus_ui_cnc_profile_activate(slot);
    mgr_rebuild_body();
    modulus_ui_settings_build_cnc_tab();
}

static void mgr_rename_cb(lv_event_t *e)
{
    const uint8_t slot = (uint8_t)(intptr_t)lv_event_get_user_data(e);
    modulus_ui_cnc_profile_rename_show(slot);
}

static void mgr_save_cb(lv_event_t *e)
{
    (void)e;
    const uint8_t slot = modulus_nvs_get_u8("cnc_prof", 0);
    char name[24];
    if (!modulus_ui_cnc_profile_name(slot, name, sizeof(name)) || name[0] == '\0') {
        snprintf(name, sizeof(name), "Profile %u", (unsigned)(slot + 1));
    }
    modulus_ui_cnc_profile_save_slot(slot, name);
    mgr_rebuild_body();
    modulus_ui_settings_build_cnc_tab();
}

static void mgr_close_cb(lv_event_t *e)
{
    (void)e;
    modulus_ui_cnc_profiles_modal_hide();
}

static void mgr_rebuild_body(void)
{
    if (!s_mgr_body) {
        return;
    }
    lv_obj_clean(s_mgr_body);

    settings_note(s_mgr_body, "Activate applies proto/transport/hosts then reconnects.");

    const uint8_t active = modulus_nvs_get_u8("cnc_prof", 0);
    for (uint8_t i = 0; i < k_prof_slots; i++) {
        char name[24];
        char label[40];
        char value[48];
        if (modulus_ui_cnc_profile_name(i, name, sizeof(name))) {
            snprintf(label, sizeof(label), "Slot %u: %s", (unsigned)(i + 1), name);
        } else {
            snprintf(label, sizeof(label), "Slot %u: (empty)", (unsigned)(i + 1));
        }
        if (i == active) {
            snprintf(value, sizeof(value), "Active");
        } else {
            value[0] = '\0';
        }
        modulus_ui_list_item_create(s_mgr_body, MOD_UI_ICON_CNC, label, value[0] ? value : NULL,
                                    mgr_activate_cb, (void *)(intptr_t)i);

        char rlbl[32];
        snprintf(rlbl, sizeof(rlbl), "Rename slot %u", (unsigned)(i + 1));
        lv_obj_t *ren = settings_action_row(s_mgr_body, rlbl, "Keyboard");
        settings_bind_menu_click(ren, mgr_rename_cb, (void *)(intptr_t)i);
    }

    lv_obj_t *save = settings_action_row(s_mgr_body, "Save current to active slot", "");
    settings_bind_menu_click(save, mgr_save_cb, NULL);
}

static void mgr_exit_ready(lv_anim_t *a)
{
    lv_obj_t *dlg = lv_anim_get_user_data(a);
    if (dlg) {
        lv_obj_delete(dlg);
    }
    s_mgr_body = NULL;
}

void modulus_ui_cnc_profiles_modal_hide(void)
{
    rename_hide();
    if (!s_mgr_modal) {
        s_mgr_body = NULL;
        return;
    }
    lv_obj_t *dlg = s_mgr_modal;
    s_mgr_modal = NULL;
    s_mgr_body = NULL;
    lv_obj_t *card = lv_obj_get_child(dlg, 0);
    if (card && modulus_ui_motion_smooth()) {
        modulus_ui_motion_dialog_exit(card, mgr_exit_ready, dlg);
        return;
    }
    lv_obj_delete(dlg);
}

void modulus_ui_cnc_profiles_modal_show(void)
{
    modulus_ui_cnc_profiles_modal_hide();

    s_mgr_modal = modulus_ui_dialog_scrim_create();

    lv_obj_t *card = modulus_ui_dialog_card_create(s_mgr_modal, MOD_UI_DIALOG_W_WIDE, 560);
    lv_obj_center(card);
    settings_tune_scroll_container(card);
    modulus_ui_motion_dialog_enter(card);

    modulus_ui_dialog_header(card, "Connection profiles", mgr_close_cb, NULL);
    modulus_ui_dialog_scrim_bind_dismiss(s_mgr_modal, mgr_close_cb, NULL);
    modulus_ui_dialog_supporting(card, "Save/activate up to 4 machine setups.");

    s_mgr_body = lv_obj_create(card);
    lv_obj_remove_style_all(s_mgr_body);
    lv_obj_set_width(s_mgr_body, lv_pct(100));
    lv_obj_set_flex_grow(s_mgr_body, 1);
    lv_obj_set_flex_flow(s_mgr_body, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(s_mgr_body, MOD_UI_SPACE_SM, 0);
    settings_tune_scroll_container(s_mgr_body);

    mgr_rebuild_body();
}

void modulus_ui_cnc_profiles_kb_theme_refresh(void)
{
    if (s_rename_kb) {
        modulus_ui_apply_keyboard_theme(s_rename_kb);
    }
    if (s_rename_ta) {
        modulus_ui_apply_textarea_theme(s_rename_ta, false);
    }
    modulus_ui_dialog_theme_refresh(s_rename_modal);
    modulus_ui_dialog_theme_refresh(s_mgr_modal);
}

#endif /* !CONFIG_MODULUS_ZIG_UI_ENGINE */
