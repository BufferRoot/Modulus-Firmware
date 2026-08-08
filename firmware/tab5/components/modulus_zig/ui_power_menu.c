#include "ui_power_menu_priv.h"
#include "cnc_cmd_exports.h"

extern void modulus_zig_fill_cnc_status(modulus_cnc_status_t *out);

static modulus_pwr_menu_t s_menu = {};

static bool machine_busy(void)
{
    modulus_cnc_status_t st = {};
    modulus_zig_fill_cnc_status(&st);
    return st.connected && (st.state == 2 || st.state == 3 || st.state == 4);
}

static void hide_power_cb(lv_event_t *e)
{
    (void)e;
    modulus_ui_hide_power_menu();
}

static void card_click_cb(lv_event_t *e)
{
    lv_event_stop_bubbling(e);
}

static void reset_cb(lv_event_t *e)
{
    (void)e;
    modulus_zig_cmd_reset();
    modulus_ui_hide_power_menu();
}

static void unlock_cb(lv_event_t *e)
{
    (void)e;
    modulus_zig_cmd_unlock();
    modulus_ui_hide_power_menu();
}

static void restart_cb(lv_event_t *e)
{
    (void)e;
    if (machine_busy()) {
        return;
    }
    modulus_pwr_show_confirm(PWR_CONFIRM_RESTART, "Restart device",
                             "The device will reboot immediately.\n"
                             "Unsaved work may be lost.",
                             "Restart", false);
}

static void shutdown_cb(lv_event_t *e)
{
    (void)e;
    if (machine_busy()) {
        return;
    }
    modulus_pwr_show_confirm(PWR_CONFIRM_SHUTDOWN, "Shut down device",
                             "The device will power off.\n"
                             "Use the power button to turn it back on.",
                             "Power off", true);
}

static void reveal_menu(void)
{
    modulus_pwr_update_device_rows(s_menu.row_restart, s_menu.row_shutdown, machine_busy());
    if (s_menu.card) {
        lv_obj_set_style_translate_y(s_menu.card, 0, 0);
        modulus_ui_motion_dialog_enter(s_menu.card);
    }
    lv_obj_remove_flag(s_menu.overlay, LV_OBJ_FLAG_HIDDEN);
}

static void ensure_menu_built(void)
{
    if (s_menu.overlay) {
        return;
    }
    modulus_pwr_create_menu(&s_menu, hide_power_cb, card_click_cb, reset_cb, unlock_cb,
                            restart_cb, shutdown_cb);
}

void modulus_ui_prewarm_power_menu(void)
{
    ensure_menu_built();
}

void modulus_ui_show_power_menu(void)
{
    if (s_menu.overlay && !lv_obj_has_flag(s_menu.overlay, LV_OBJ_FLAG_HIDDEN)) {
        return;
    }
    ensure_menu_built();
    modulus_ui_pause_dashboard_refresh();
    reveal_menu();
}

static void pwr_exit_ready(lv_anim_t *a)
{
    (void)a;
    if (s_menu.overlay) {
        lv_obj_add_flag(s_menu.overlay, LV_OBJ_FLAG_HIDDEN);
    }
    if (s_menu.card) {
        lv_obj_set_style_translate_y(s_menu.card, 0, 0);
    }
    modulus_ui_resume_dashboard_refresh();
}

void modulus_ui_hide_power_menu(void)
{
    modulus_pwr_hide_confirm();
    if (!s_menu.overlay) {
        modulus_ui_resume_dashboard_refresh();
        return;
    }
    if (lv_obj_has_flag(s_menu.overlay, LV_OBJ_FLAG_HIDDEN)) {
        modulus_ui_resume_dashboard_refresh();
        return;
    }
    if (s_menu.card && modulus_ui_motion_smooth()) {
        modulus_ui_motion_dialog_exit(s_menu.card, pwr_exit_ready, NULL);
        return;
    }
    lv_obj_add_flag(s_menu.overlay, LV_OBJ_FLAG_HIDDEN);
    modulus_ui_resume_dashboard_refresh();
}

bool modulus_ui_power_menu_visible(void)
{
    return s_menu.overlay && !lv_obj_has_flag(s_menu.overlay, LV_OBJ_FLAG_HIDDEN);
}

void modulus_ui_power_menu_theme_refresh(void)
{
    if (!s_menu.overlay) {
        return;
    }
    /* Prewarmed tree caches button/label colors — rebuild from current palette. */
    const bool visible = !lv_obj_has_flag(s_menu.overlay, LV_OBJ_FLAG_HIDDEN);
    modulus_pwr_hide_confirm();
    lv_obj_delete(s_menu.overlay);
    s_menu = (modulus_pwr_menu_t){};
    ensure_menu_built();
    if (visible) {
        reveal_menu();
    }
}
