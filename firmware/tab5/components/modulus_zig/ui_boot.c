#include "ui_internal.h"

#include <esp_log.h>
#include <stdio.h>

static const char *TAG = "ui_boot";

extern void modulus_ui_show_dashboard(void);
extern const char *modulus_zig_version(void);

static lv_timer_t *s_boot_tmr = NULL;
static lv_obj_t *s_boot_scr = NULL;

static void boot_timeout_cb(lv_timer_t *timer)
{
    (void)timer;
    ESP_LOGI(TAG, "Boot complete - loading dashboard");
    if (s_boot_scr) {
        lv_obj_delete(s_boot_scr);
        s_boot_scr = NULL;
    }
    if (s_boot_tmr) {
        lv_timer_delete(s_boot_tmr);
        s_boot_tmr = NULL;
    }
    modulus_ui_show_dashboard();
}

void modulus_ui_boot_arm_transition(void)
{
    if (s_boot_tmr) {
        return;
    }
    s_boot_tmr = lv_timer_create(boot_timeout_cb, 3000, NULL);
    lv_timer_set_repeat_count(s_boot_tmr, 1);
}

void modulus_ui_boot_create(void)
{
    if (s_boot_scr) {
        return;
    }
    lv_obj_t *scr = lv_obj_create(NULL);
    s_boot_scr = scr;
    lv_obj_set_size(scr, lv_pct(100), lv_pct(100));
    lv_obj_set_style_bg_color(scr, modulus_ui_color_surface_dim(), 0);
    lv_obj_set_style_bg_opa(scr, LV_OPA_COVER, 0);
    lv_obj_remove_flag(scr, LV_OBJ_FLAG_SCROLLABLE);

    lv_obj_t *col = lv_obj_create(scr);
    lv_obj_remove_style_all(col);
    lv_obj_set_size(col, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_center(col);
    lv_obj_set_flex_flow(col, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(col, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_row(col, MOD_UI_SPACE_XL, 0);

    lv_obj_t *title = lv_label_create(col);
    lv_label_set_text(title, "MODULUS");
    lv_obj_set_style_text_color(title, modulus_ui_color_primary(), 0);
    lv_obj_set_style_text_font(title, MOD_UI_FONT_SPLASH, 0);
    lv_obj_set_style_text_letter_space(title, 3, 0);
    lv_obj_set_style_opa(title, LV_OPA_COVER, 0);

    lv_obj_t *creator = lv_label_create(col);
    lv_label_set_text(creator, "Driven by M5Stack | Powered by Zig | Built on ESP-IDF");
    lv_obj_set_style_text_color(creator, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(creator, MOD_UI_FONT_CAPTION, 0);
    lv_obj_set_style_opa(creator, LV_OPA_COVER, 0);

    static char ver[24];
    snprintf(ver, sizeof(ver), "Version %s", modulus_zig_version());
    lv_obj_t *version = lv_label_create(col);
    lv_label_set_text(version, ver);
    lv_obj_set_style_text_color(version, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(version, MOD_UI_FONT_CAPTION, 0);
    lv_obj_set_style_opa(version, LV_OPA_COVER, 0);

    lv_screen_load(scr);
    lv_obj_invalidate(scr);
}
