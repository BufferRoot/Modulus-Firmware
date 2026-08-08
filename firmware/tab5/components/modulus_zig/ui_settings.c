#include "ui_settings_priv.h"

#include "ui_settings_common.h"

#include "ui_settings_modals.h"

#include "ui_settings_modal_kb.h"

#include "ui_cnc_profiles.h"



#include <stdint.h>

#include <stdbool.h>

#include <string.h>



#define SETTINGS_TAB_COUNT MOD_UI_SETTINGS_TAB_COUNT

/* C++ ref: sidebar 280px, tab icon title_medium (~16), label body_large (16). */
#define SETTINGS_SIDEBAR_W        300
#define SETTINGS_TAB_ICON_DISPLAY 40



typedef void (*tab_builder_fn)(void);



typedef struct {

    modulus_ui_icon_id_t icon;

    const char *label;

    tab_builder_fn build;

} settings_tab_t;



static lv_obj_t *s_overlay = NULL;

static lv_obj_t *s_shell_card = NULL;

static bool s_settings_hiding = false;

static lv_obj_t *s_shell_hdr = NULL;

static lv_obj_t *s_shell_sidebar = NULL;

static lv_obj_t *s_content = NULL;

static lv_obj_t *s_tab_panels[SETTINGS_TAB_COUNT] = {};

static bool s_tab_built[SETTINGS_TAB_COUNT] = {};

static lv_obj_t *s_tab_btns[SETTINGS_TAB_COUNT] = {};

static int s_active_tab = 0;

static char s_tab_filter[33] = "";



static const settings_tab_t k_tabs[SETTINGS_TAB_COUNT] = {

    {MOD_UI_ICON_CNC, "CNC &\nconnection", modulus_ui_settings_build_cnc_tab},

    {MOD_UI_ICON_HOUSE, "Dashboard &\nhandwheel", modulus_ui_settings_build_dashboard_tab},

    {MOD_UI_ICON_MONITOR, "Display &\ntheme", modulus_ui_settings_build_display_tab},

    {MOD_UI_ICON_SPEAKER, "Audio &\nhaptics", modulus_ui_settings_build_audio_tab},

    {MOD_UI_ICON_WIFI, "Wireless", modulus_ui_settings_build_wireless_tab},

    {MOD_UI_ICON_BATTERY_FULL, "Power", modulus_ui_settings_build_power_tab},

    {MOD_UI_ICON_EYE, "Security", modulus_ui_settings_build_security_tab},

    {MOD_UI_ICON_GEAR, "Machine", modulus_ui_settings_build_machine_tab},

    {MOD_UI_ICON_STORAGE, "Storage &\ndiagnostics", modulus_ui_settings_build_storage_tab},

    {MOD_UI_ICON_LIGHTNING, "System &\nabout", modulus_ui_settings_build_system_tab},

};



static void pause_tab_activity(int idx)

{

    switch (idx) {

    case 0:

        modulus_ui_settings_cnc_tab_pause_activity();

        break;

    case 1:

        modulus_ui_settings_dashboard_tab_stop();

        break;

    case 3:

        modulus_ui_settings_audio_tab_pause_activity();

        s_tab_built[MOD_UI_SETTINGS_TAB_AUDIO] = false;

        if (s_tab_panels[MOD_UI_SETTINGS_TAB_AUDIO]) {

            lv_obj_clean(s_tab_panels[MOD_UI_SETTINGS_TAB_AUDIO]);

        }

        break;

    case 4:

        modulus_ui_settings_wireless_tab_pause_activity();

        break;

    case 5:

        modulus_ui_settings_power_tab_pause_activity();

        break;

    case 7:

        modulus_ui_settings_machine_tab_pause_activity();

        break;

    case 8:

        modulus_ui_settings_storage_tab_pause_activity();

        break;

    case 9:

        modulus_ui_settings_system_tab_pause_activity();

        break;

    default:

        break;

    }

}



static void resume_tab_activity(int idx)

{

    switch (idx) {

    case 0:

        modulus_ui_settings_cnc_tab_resume_activity();

        break;

    case 4:

        modulus_ui_settings_wireless_tab_resume_activity();

        break;

    case 5:

        modulus_ui_settings_power_tab_resume_activity();

        break;

    case 8:

        modulus_ui_settings_storage_tab_resume_activity();

        break;

    case 9:

        modulus_ui_settings_system_tab_resume_activity();

        break;

    default:

        break;

    }

}



static void destroy_tab_activity(int idx)

{

    switch (idx) {

    case 0:

        modulus_ui_settings_cnc_tab_stop_timer();

        break;

    case 1:

        modulus_ui_settings_dashboard_tab_stop();

        break;

    case 4:

        modulus_ui_settings_wireless_tab_stop_timer();

        break;

    case 5:

        modulus_ui_settings_power_tab_stop_timer();

        break;

    case 7:

        modulus_ui_settings_machine_tab_stop_timer();

        break;

    case 8:

        modulus_ui_settings_storage_tab_stop_timer();

        break;

    case 9:

        modulus_ui_settings_system_tab_stop_timer();

        break;

    default:

        break;

    }

}



static void hide_modals(void)

{

    settings_incr_modal_hide();

    settings_mach_name_modal_hide();

    settings_macro_modal_hide();

    settings_qbtn_modal_hide();

    settings_transport_modal_hide();

    settings_pin_modal_hide();

    settings_wcs_modal_hide();

    settings_mpg_modal_hide();

    settings_maint_modal_hide();

    settings_wl_adv_modal_hide();

    settings_idle_lock_modal_hide();

    settings_probe_modal_hide();

    modulus_ui_cnc_profiles_modal_hide();

}



static lv_obj_t *ensure_tab_panel(int idx)

{

    if (s_tab_panels[idx]) {

        return s_tab_panels[idx];

    }

    lv_obj_t *panel = lv_obj_create(s_content);

    s_tab_panels[idx] = panel;

    lv_obj_remove_style_all(panel);

    lv_obj_set_size(panel, lv_pct(100), lv_pct(100));

    lv_obj_set_flex_flow(panel, LV_FLEX_FLOW_COLUMN);

    lv_obj_set_style_pad_row(panel, MOD_UI_SPACE_SM, 0);

    lv_obj_set_style_bg_opa(panel, LV_OPA_TRANSP, 0);

    lv_obj_set_style_max_width(panel, MOD_UI_CONTENT_MAX_W, 0);

    settings_tune_scroll_container(panel);

    lv_obj_add_flag(panel, LV_OBJ_FLAG_HIDDEN);
    lv_obj_add_flag(panel, LV_OBJ_FLAG_IGNORE_LAYOUT);
    lv_obj_set_pos(panel, 0, 0);

    return panel;

}



lv_obj_t *modulus_ui_settings_tab_panel(int idx)

{

    if (idx < 0 || idx >= SETTINGS_TAB_COUNT || !s_content) {

        return NULL;

    }

    return ensure_tab_panel(idx);

}



void modulus_ui_settings_note_tab_built(int idx)

{

    if (idx >= 0 && idx < SETTINGS_TAB_COUNT) {

        s_tab_built[idx] = true;

    }

}



static void set_tab_panel_visible(int idx, bool visible)

{

    lv_obj_t *panel = s_tab_panels[idx];

    if (!panel) {

        return;

    }

    if (visible) {

        lv_obj_remove_flag(panel, LV_OBJ_FLAG_HIDDEN);

    } else {

        lv_obj_add_flag(panel, LV_OBJ_FLAG_HIDDEN);

    }

}



static void highlight_tabs(void)

{

    for (int i = 0; i < SETTINGS_TAB_COUNT; i++) {

        if (!s_tab_btns[i]) {

            continue;

        }

        const bool active = (i == s_active_tab);

        lv_obj_set_style_bg_opa(s_tab_btns[i], active ? LV_OPA_COVER : LV_OPA_TRANSP, 0);

        lv_obj_set_style_bg_color(s_tab_btns[i], active ? modulus_ui_color_secondary_container()
                                                        : modulus_ui_color_surface_container_high(), 0);

        const lv_color_t tc = active ? modulus_ui_color_on_secondary_container()

                                     : modulus_ui_color_on_surface_variant();

        modulus_ui_icon_recolor(lv_obj_get_child(s_tab_btns[i], 0), tc);

        lv_obj_set_style_text_color(lv_obj_get_child(s_tab_btns[i], 1), tc, 0);

    }

}



static void select_tab(int idx)

{

    if (idx < 0 || idx >= SETTINGS_TAB_COUNT || !s_content) {

        return;

    }

    if (idx == s_active_tab && s_tab_built[idx]) {

        return;

    }



    pause_tab_activity(s_active_tab);

    hide_modals();



    set_tab_panel_visible(s_active_tab, false);



    s_active_tab = idx;

    lv_obj_t *panel = ensure_tab_panel(idx);

    modulus_ui_settings_set_content_panel(panel);



    if (!s_tab_built[idx]) {

        k_tabs[idx].build();

        s_tab_built[idx] = true;

    }



    set_tab_panel_visible(idx, true);

    lv_obj_scroll_to_y(panel, 0, LV_ANIM_OFF);

    if (modulus_ui_motion_smooth()) {
        lv_obj_set_style_translate_y(panel, 16, 0);
        modulus_ui_anim_translate_y(panel, 16, 0, MOD_UI_MOTION_SETTINGS_MS, true, NULL, NULL);
    }

    highlight_tabs();

    resume_tab_activity(idx);

}



static void tab_click_cb(lv_event_t *e)

{

    const int idx = (int)(intptr_t)lv_event_get_user_data(e);

    if (idx != s_active_tab) {

        select_tab(idx);

    }

}



static void close_click_cb(lv_event_t *e)

{

    (void)e;

    modulus_ui_hide_settings();

}



static bool tab_label_matches_filter(int idx)
{
    if (s_tab_filter[0] == '\0') {
        return true;
    }
    const char *label = k_tabs[idx].label;
    if (!label) {
        return false;
    }
    char norm[64];
    size_t j = 0;
    for (size_t i = 0; label[i] && j + 1 < sizeof(norm); i++) {
        char c = label[i];
        if (c == '\n') {
            c = ' ';
        }
        if (c >= 'A' && c <= 'Z') {
            c = (char)(c - 'A' + 'a');
        }
        norm[j++] = c;
    }
    norm[j] = '\0';

    char filt[33];
    for (j = 0; s_tab_filter[j] && j + 1 < sizeof(filt); j++) {
        char c = s_tab_filter[j];
        if (c >= 'A' && c <= 'Z') {
            c = (char)(c - 'A' + 'a');
        }
        filt[j] = c;
    }
    filt[j] = '\0';
    return strstr(norm, filt) != NULL;
}

static void tab_filter_apply(void)
{
    for (int i = 0; i < SETTINGS_TAB_COUNT; i++) {
        if (!s_tab_btns[i]) {
            continue;
        }
        if (tab_label_matches_filter(i)) {
            lv_obj_remove_flag(s_tab_btns[i], LV_OBJ_FLAG_HIDDEN);
        } else {
            lv_obj_add_flag(s_tab_btns[i], LV_OBJ_FLAG_HIDDEN);
        }
    }
}

static void tab_filter_cb(lv_event_t *e)
{
    lv_obj_t *ta = lv_event_get_target(e);
    const char *txt = lv_textarea_get_text(ta);
    size_t n = 0;
    if (txt) {
        for (size_t i = 0; txt[i] && n < sizeof(s_tab_filter) - 1; i++) {
            const unsigned char c = (unsigned char)txt[i];
            if (c >= 0x20 && c <= 0x7E) {
                s_tab_filter[n++] = (char)c;
            }
        }
    }
    s_tab_filter[n] = '\0';
    tab_filter_apply();
}

static void build_sidebar(lv_obj_t *body)

{

    lv_obj_t *sidebar = lv_obj_create(body);

    s_shell_sidebar = sidebar;

    lv_obj_remove_style_all(sidebar);

    lv_obj_set_size(sidebar, SETTINGS_SIDEBAR_W, lv_pct(100));

    lv_obj_set_flex_flow(sidebar, LV_FLEX_FLOW_COLUMN);

    lv_obj_set_style_pad_all(sidebar, MOD_UI_SPACE_SM + MOD_UI_SPACE_XS, 0);

    lv_obj_set_style_pad_row(sidebar, MOD_UI_SPACE_SM, 0);

    lv_obj_set_style_bg_color(sidebar, modulus_ui_color_surface_container_lowest(), 0);

    lv_obj_set_style_bg_opa(sidebar, LV_OPA_COVER, 0);

    lv_obj_set_style_border_width(sidebar, 1, 0);

    lv_obj_set_style_border_side(sidebar, LV_BORDER_SIDE_RIGHT, 0);

    lv_obj_set_style_border_color(sidebar, modulus_ui_color_outline_variant(), 0);

    settings_tune_sidebar_scroll(sidebar);

    lv_obj_t *search = lv_textarea_create(sidebar);
    lv_textarea_set_one_line(search, true);
    lv_textarea_set_max_length(search, 32);
    lv_textarea_set_placeholder_text(search, "Search tabs");
    lv_obj_set_width(search, lv_pct(100));
    lv_obj_set_height(search, MOD_UI_TOUCH_MIN);
    modulus_ui_apply_textarea_theme(search, false);
    lv_obj_add_event_cb(search, tab_filter_cb, LV_EVENT_VALUE_CHANGED, NULL);
    settings_shell_kb_bind_textarea(search);

    for (int i = 0; i < SETTINGS_TAB_COUNT; i++) {

        lv_obj_t *btn = lv_obj_create(sidebar);

        lv_obj_remove_style_all(btn);

        lv_obj_set_width(btn, lv_pct(100));

        lv_obj_set_height(btn, LV_SIZE_CONTENT);

        lv_obj_set_style_min_height(btn, 60, 0);

        lv_obj_set_flex_flow(btn, LV_FLEX_FLOW_ROW);

        lv_obj_set_flex_align(btn, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER,

                              LV_FLEX_ALIGN_CENTER);

        lv_obj_set_style_pad_hor(btn, MOD_UI_SPACE_LG, 0);

        lv_obj_set_style_pad_ver(btn, MOD_UI_SPACE_SM + MOD_UI_SPACE_XS, 0);

        lv_obj_set_style_pad_column(btn, MOD_UI_SPACE_MD, 0);

        lv_obj_set_style_radius(btn, MOD_UI_SHAPE_MD, 0);

        lv_obj_add_flag(btn, LV_OBJ_FLAG_CLICKABLE);

        settings_bind_menu_click(btn, tab_click_cb, (void *)(intptr_t)i);
        modulus_ui_touch_expand(btn, 8);

        lv_obj_t *icon = modulus_ui_icon_create(btn, k_tabs[i].icon, MOD_UI_ICON_SZ_32);

        if (icon) {
            lv_obj_set_size(icon, SETTINGS_TAB_ICON_DISPLAY, SETTINGS_TAB_ICON_DISPLAY);
        }

        lv_obj_t *lbl = lv_label_create(btn);

        lv_label_set_text(lbl, k_tabs[i].label);

        /* Larger tab labels — montserrat_18 is compiled in (sdkconfig) and was
         * previously unused; caption (14) was hard to read at arm's length. */
        lv_obj_set_style_text_font(lbl, &lv_font_montserrat_18, 0);

        lv_obj_set_flex_grow(lbl, 1);

        lv_label_set_long_mode(lbl, LV_LABEL_LONG_WRAP);

        settings_no_scroll(btn);

        s_tab_btns[i] = btn;

    }

    tab_filter_apply();

}



static void build_shell(void)

{

    s_overlay = lv_obj_create(lv_layer_top());

    lv_obj_remove_style_all(s_overlay);

    lv_obj_set_size(s_overlay, lv_pct(100), lv_pct(100));

    /* Opaque theme scrim — no full-screen alpha compositing under sw_rotate (F-S1). */
    modulus_ui_apply_overlay_scrim(s_overlay);

    lv_obj_add_flag(s_overlay, LV_OBJ_FLAG_CLICKABLE);

    settings_no_scroll(s_overlay);

    lv_obj_t *card = lv_obj_create(s_overlay);

    s_shell_card = card;

    lv_obj_remove_style_all(card);

    lv_obj_set_size(card, lv_pct(94), lv_pct(92));

    lv_obj_center(card);

    lv_obj_set_style_bg_color(card, modulus_ui_color_surface_container_low(), 0);

    lv_obj_set_style_bg_opa(card, LV_OPA_COVER, 0);

    lv_obj_set_style_radius(card, MOD_UI_SHAPE_XL, 0);

    lv_obj_set_style_clip_corner(card, true, 0);

    lv_obj_set_style_border_color(card, modulus_ui_color_outline_variant(), 0);

    lv_obj_set_style_border_width(card, 1, 0);

    lv_obj_set_flex_flow(card, LV_FLEX_FLOW_COLUMN);

    lv_obj_set_scrollbar_mode(card, LV_SCROLLBAR_MODE_OFF);

    settings_no_scroll(card);

    lv_obj_t *hdr = lv_obj_create(card);

    s_shell_hdr = hdr;

    lv_obj_remove_style_all(hdr);

    lv_obj_set_size(hdr, lv_pct(100), 64);

    lv_obj_set_style_bg_color(hdr, modulus_ui_color_surface_container_high(), 0);

    lv_obj_set_style_bg_opa(hdr, LV_OPA_COVER, 0);

    lv_obj_set_style_pad_hor(hdr, MOD_UI_SPACE_LG, 0);

    lv_obj_set_flex_flow(hdr, LV_FLEX_FLOW_ROW);

    lv_obj_set_flex_align(hdr, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER,

                          LV_FLEX_ALIGN_CENTER);

    lv_obj_set_style_border_width(hdr, 1, 0);

    lv_obj_set_style_border_side(hdr, LV_BORDER_SIDE_BOTTOM, 0);

    lv_obj_set_style_border_color(hdr, modulus_ui_color_outline_variant(), 0);

    lv_obj_set_style_border_opa(hdr, LV_OPA_30, 0);

    settings_no_scroll(hdr);

    lv_obj_t *tg = lv_obj_create(hdr);

    lv_obj_remove_style_all(tg);

    lv_obj_set_size(tg, LV_SIZE_CONTENT, LV_SIZE_CONTENT);

    lv_obj_set_flex_flow(tg, LV_FLEX_FLOW_ROW);

    lv_obj_set_flex_align(tg, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER,

                          LV_FLEX_ALIGN_CENTER);

    lv_obj_set_style_pad_column(tg, 14, 0);

    settings_no_scroll(tg);

    lv_obj_t *gi = modulus_ui_icon_create(tg, MOD_UI_ICON_GEAR, MOD_UI_ICON_SZ_24);

    modulus_ui_icon_recolor(gi, modulus_ui_color_primary());

    lv_obj_t *title = lv_label_create(tg);

    lv_label_set_text(title, "System settings");

    lv_obj_set_style_text_color(title, modulus_ui_color_on_surface(), 0);

    lv_obj_set_style_text_font(title, MOD_UI_FONT_TITLE_L, 0);



    lv_obj_t *close = lv_button_create(hdr);

    lv_obj_remove_style_all(close);

    lv_obj_set_size(close, 48, 48);

    lv_obj_set_style_radius(close, MOD_UI_SHAPE_FULL, 0);

    modulus_ui_apply_pressed_state_layer(close);

    lv_obj_add_flag(close, LV_OBJ_FLAG_CLICKABLE);

    lv_obj_t *xl = modulus_ui_icon_create(close, MOD_UI_ICON_X, MOD_UI_ICON_SZ_24);

    modulus_ui_icon_recolor(xl, modulus_ui_color_on_surface_variant());

    lv_obj_center(xl);

    settings_bind_menu_click(close, close_click_cb, NULL);



    lv_obj_t *body = lv_obj_create(card);

    lv_obj_remove_style_all(body);

    lv_obj_set_width(body, lv_pct(100));

    lv_obj_set_flex_grow(body, 1);

    lv_obj_set_flex_flow(body, LV_FLEX_FLOW_ROW);

    /* Bottom corners: sidebar/content paint square opaque backgrounds into the
     * card's rounded bottom corners. Clip on the body itself — its top edge
     * sits flush under the square-bottomed header, so only the bottom rounding
     * is visible, which is exactly the card's XL radius. */
    lv_obj_set_style_radius(body, MOD_UI_SHAPE_XL, 0);
    lv_obj_set_style_clip_corner(body, true, 0);

    lv_obj_set_scrollbar_mode(body, LV_SCROLLBAR_MODE_OFF);

    settings_no_scroll(body);

    build_sidebar(body);



    s_content = lv_obj_create(body);

    lv_obj_remove_style_all(s_content);

    lv_obj_set_flex_grow(s_content, 1);

    lv_obj_set_height(s_content, lv_pct(100));

    lv_obj_set_flex_flow(s_content, LV_FLEX_FLOW_COLUMN);

    lv_obj_set_style_pad_all(s_content, MOD_UI_SPACE_MD, 0);

    lv_obj_set_style_max_width(s_content, MOD_UI_CONTENT_MAX_W, 0);

    lv_obj_set_style_bg_color(s_content, modulus_ui_color_surface_container_low(), 0);

    lv_obj_set_style_bg_opa(s_content, LV_OPA_COVER, 0);

    lv_obj_set_scrollbar_mode(s_content, LV_SCROLLBAR_MODE_OFF);

    lv_obj_remove_flag(s_content, LV_OBJ_FLAG_SCROLLABLE);

    settings_no_scroll(s_content);

}



void modulus_ui_settings_show(void)

{

    if (!s_overlay) {

        build_shell();

    }

    /* Build active tab before reveal so card size is stable (no open jump). */
    lv_obj_t *panel = ensure_tab_panel(s_active_tab);

    modulus_ui_settings_set_content_panel(panel);

    if (!s_tab_built[s_active_tab]) {

        k_tabs[s_active_tab].build();

        s_tab_built[s_active_tab] = true;

    }

    if (s_shell_card) {
        lv_obj_set_style_translate_y(s_shell_card, 0, 0);
    }

    s_settings_hiding = false;
    lv_obj_remove_flag(s_overlay, LV_OBJ_FLAG_HIDDEN);

    lv_obj_move_foreground(s_overlay);

    if (s_shell_card) {
        modulus_ui_motion_settings_enter(s_shell_card);
    }



    for (int i = 0; i < SETTINGS_TAB_COUNT; i++) {

        set_tab_panel_visible(i, i == s_active_tab);

    }

    highlight_tabs();

    resume_tab_activity(s_active_tab);

}



void modulus_ui_settings_select_tab(int idx)

{

    if (!s_overlay || lv_obj_has_flag(s_overlay, LV_OBJ_FLAG_HIDDEN)) {

        return;

    }

    select_tab(idx);

}

static void settings_exit_ready(lv_anim_t *a)
{
    (void)a;
    s_settings_hiding = false;
    settings_shell_kb_hide();
    if (s_overlay) {
        lv_obj_add_flag(s_overlay, LV_OBJ_FLAG_HIDDEN);
    }
    if (s_shell_card) {
        lv_obj_set_style_translate_y(s_shell_card, 0, 0);
    }
    /* Resume only after overlay hidden — premature resume no-ops while visible. */
    modulus_ui_resume_dashboard_refresh();
}

void modulus_ui_settings_hide(void)
{
    if (s_settings_hiding) {
        return;
    }
    pause_tab_activity(s_active_tab);
    hide_modals();
    settings_shell_kb_hide();
    if (!s_overlay || lv_obj_has_flag(s_overlay, LV_OBJ_FLAG_HIDDEN)) {
        return;
    }
    if (s_shell_card && modulus_ui_motion_smooth()) {
        s_settings_hiding = true;
        modulus_ui_motion_dialog_exit(s_shell_card, settings_exit_ready, NULL);
        return;
    }
    lv_obj_add_flag(s_overlay, LV_OBJ_FLAG_HIDDEN);
    modulus_ui_resume_dashboard_refresh();
}



bool modulus_ui_settings_visible(void)

{

    return s_overlay && !lv_obj_has_flag(s_overlay, LV_OBJ_FLAG_HIDDEN);

}



void modulus_ui_settings_theme_refresh(void)

{

    if (!s_overlay) {

        return;

    }

    modulus_ui_apply_overlay_scrim(s_overlay);

    if (s_shell_card) {

        lv_obj_set_style_bg_color(s_shell_card, modulus_ui_color_surface_container_low(), 0);

        lv_obj_set_style_border_color(s_shell_card, modulus_ui_color_outline_variant(), 0);

    }

    if (s_shell_hdr) {

        lv_obj_set_style_bg_color(s_shell_hdr, modulus_ui_color_surface_container_high(), 0);

        lv_obj_set_style_border_color(s_shell_hdr, modulus_ui_color_outline_variant(), 0);

    }

    if (s_shell_sidebar) {

        lv_obj_set_style_bg_color(s_shell_sidebar, modulus_ui_color_surface_container_lowest(), 0);

        lv_obj_set_style_border_color(s_shell_sidebar, modulus_ui_color_outline_variant(), 0);

    }

    if (s_content) {

        lv_obj_set_style_bg_color(s_content, modulus_ui_color_surface_container_low(), 0);

    }

    highlight_tabs();

    settings_confirm_theme_refresh();
    settings_shell_kb_theme_refresh();

    if (lv_obj_has_flag(s_overlay, LV_OBJ_FLAG_HIDDEN)) {

        return;

    }

    /* F-T1: style-swap shell above; rebuild active tab only — hidden tabs rebuild
     * lazily on next visit (select_tab + build() lv_obj_clean). */
    for (int i = 0; i < SETTINGS_TAB_COUNT; i++) {
        destroy_tab_activity(i);
        if (i == s_active_tab && s_tab_panels[i]) {
            lv_obj_clean(s_tab_panels[i]);
        }
        s_tab_built[i] = false;
    }

    lv_obj_t *panel = ensure_tab_panel(s_active_tab);

    modulus_ui_settings_set_content_panel(panel);

    k_tabs[s_active_tab].build();

    s_tab_built[s_active_tab] = true;

    for (int i = 0; i < SETTINGS_TAB_COUNT; i++) {

        set_tab_panel_visible(i, i == s_active_tab);

    }

    resume_tab_activity(s_active_tab);

}


