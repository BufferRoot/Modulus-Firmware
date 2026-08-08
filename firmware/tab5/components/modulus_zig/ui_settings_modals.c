#include "ui_settings_modals_priv.h"

void settings_modals_theme_refresh(void)
{
    settings_transport_modal_theme_refresh();
    settings_pin_modal_theme_refresh();
    settings_incr_modal_theme_refresh();
    settings_macro_modal_theme_refresh();
    settings_mach_name_modal_theme_refresh();
    settings_qbtn_modal_theme_refresh();
    settings_grbl_dump_modal_theme_refresh();
    settings_wcs_modal_theme_refresh();
    settings_mpg_modal_theme_refresh();
    settings_maint_modal_theme_refresh();
    settings_wl_adv_modal_theme_refresh();
    settings_idle_lock_modal_theme_refresh();
    settings_probe_modal_theme_refresh();
}
