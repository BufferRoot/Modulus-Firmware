/*

 * Material Design 3 theme tokens — dark/light palettes for Modulus UI.

 */

#include "ui_internal.h"
#include "ui_palette_schemes.h"

#include <nvs_shim.h>

#include <esp_log.h>
#include <math.h>

static const char *TAG = "ui_theme";



typedef struct {

    lv_color_t primary;

    lv_color_t on_primary;

    lv_color_t accent;

    lv_color_t on_accent;

    lv_color_t cycle;

    lv_color_t hold;

    lv_color_t home_all;

    lv_color_t surface;

    lv_color_t surface_dim;

    lv_color_t on_surface;

    lv_color_t on_surface_variant;

    lv_color_t outline;

    lv_color_t outline_variant;

    lv_color_t error;

    lv_color_t on_error;

    lv_color_t success;

    lv_color_t warning;

    lv_color_t neutral;

    lv_color_t inverse_surface;

    lv_color_t on_cycle;

    lv_color_t on_hold;

    lv_color_t on_home;

    lv_color_t icon_chrome;

    lv_color_t on_tinted_btn;

    lv_color_t primary_container;

    lv_color_t on_primary_container;

    lv_color_t secondary;

    lv_color_t on_secondary;

    lv_color_t secondary_container;

    lv_color_t on_secondary_container;

    lv_color_t tertiary;

    lv_color_t on_tertiary;

    lv_color_t tertiary_container;

    lv_color_t on_tertiary_container;

    lv_color_t error_container;

    lv_color_t on_error_container;

    lv_color_t inverse_on_surface;

    lv_color_t inverse_primary;

    lv_color_t surface_bright;

    lv_color_t semantic_stop;

    lv_color_t semantic_resume;

    lv_color_t semantic_power;

    lv_color_t surface_container_lowest;

    lv_color_t surface_container_low;

    lv_color_t surface_container;

    lv_color_t surface_container_high;

    lv_color_t surface_container_highest;

    lv_color_t scrim;

} ui_palette_t;



static ui_palette_t s_pal;

static bool s_dark = true;

static uint8_t s_accent = 0;

#define MOD_UI_ACCENT_COUNT 9

/* Seed accents live in scripts/gen_ui_palettes.py → ui_palette_schemes.h.
 * This table only supplies names + surface backgrounds. */
typedef struct {
    const char *name;
    uint32_t dark_bg;
    uint32_t light_bg;
} ui_accent_def_t;

static const ui_accent_def_t k_accents[MOD_UI_ACCENT_COUNT] = {
    {"Industrial Teal", 0x101417, 0xF0F2F5},
    {"Cyber-Industrial", 0x1A1C1E, 0xF0F2F5},
    {"Nocturnal Safety", 0x121212, 0xFFFFFF},
    {"Deep Sea", 0x0B1117, 0xEBF8FF},
    {"Steel & Ruby", 0x212121, 0xF8F9FA},
    {"Electric Orchid", 0x141414, 0xF3F0FF},
    {"Tactical Sage", 0x1C1F1A, 0xF1F8E9},
    {"Nordic White", 0x0D1117, 0xFFFFFF},
    {"Monochrome Pro", 0x121212, 0xFFFFFF},
};

static lv_color_t ui_mix(lv_color_t c1, lv_color_t c2, uint8_t ratio)
{
    return lv_color_mix(c2, c1, ratio);
}

static lv_color_t ui_lighten(lv_color_t c, uint8_t amount)
{
    return ui_mix(c, lv_color_white(), amount);
}

static lv_color_t ui_darken(lv_color_t c, uint8_t amount)
{
    return ui_mix(c, lv_color_black(), amount);
}

static void apply_semantic_colors(bool dark)
{
    /* Fills paired for ≥4.5:1 with on_tinted_btn (dashboard action labels).
     * Light fills also pass as title ink on surface (Hold modal). */
    if (dark) {
        s_pal.cycle = lv_color_hex(0x22C55E); /* vibrant green — color lock */
        s_pal.hold = lv_color_hex(0xF59E0B); /* golden orange */
        s_pal.home_all = lv_color_hex(0x1E3A8A); /* dark blue */
        s_pal.error = lv_color_hex(0xFFB4AB);
        s_pal.on_error = lv_color_hex(0x410002);
        s_pal.success = lv_color_hex(0x4CAF50);
        s_pal.warning = lv_color_hex(0xFFC107);
        s_pal.neutral = lv_color_hex(0x9E9E9E);
        s_pal.inverse_surface = lv_color_hex(0x424242);
        s_pal.on_cycle = lv_color_hex(0x0D0D12);
        s_pal.on_hold = lv_color_hex(0x0D0D12);
        s_pal.on_home = lv_color_hex(0xFFFFFF);
        s_pal.on_tinted_btn = lv_color_hex(0x0D0D12);
        s_pal.semantic_stop = lv_color_hex(0x991B1B); /* dark red */
        /* Lime, deliberately distinct from cycle green. */
        s_pal.semantic_resume = lv_color_hex(0xA3E635);
        s_pal.semantic_power = lv_color_hex(0x991B1B);
    } else {
        s_pal.cycle = lv_color_hex(0x15803D);
        s_pal.hold = lv_color_hex(0xC2410C);
        s_pal.home_all = lv_color_hex(0x1E3A8A);
        s_pal.error = lv_color_hex(0xB91C1C);
        s_pal.on_error = lv_color_hex(0xFFFFFF);
        s_pal.success = lv_color_hex(0x15803D);
        s_pal.warning = lv_color_hex(0xC2410C);
        s_pal.neutral = lv_color_hex(0x4B5563);
        s_pal.inverse_surface = lv_color_hex(0xE0E0E6);
        s_pal.on_cycle = lv_color_hex(0xFFFFFF);
        s_pal.on_hold = lv_color_hex(0xFFFFFF);
        s_pal.on_home = lv_color_hex(0xFFFFFF);
        s_pal.on_tinted_btn = lv_color_hex(0xFFFFFF);
        s_pal.semantic_stop = lv_color_hex(0x7F1D1D);
        s_pal.semantic_resume = lv_color_hex(0x4D7C0F);
        s_pal.semantic_power = lv_color_hex(0x7F1D1D);
    }
}

static void apply_accent_scheme(uint8_t accent_idx, bool dark)
{
    if (accent_idx >= MOD_UI_SCHEME_COUNT) {
        accent_idx = 0;
    }
    const ui_accent_scheme_t *sch = dark ? &k_ui_schemes_dark[accent_idx] : &k_ui_schemes_light[accent_idx];
    s_pal.primary = lv_color_hex(sch->primary);
    s_pal.accent = s_pal.primary;
    s_pal.on_primary = lv_color_hex(sch->on_primary);
    s_pal.on_accent = s_pal.on_primary;
    s_pal.primary_container = lv_color_hex(sch->primary_container);
    s_pal.on_primary_container = lv_color_hex(sch->on_primary_container);
    s_pal.secondary = lv_color_hex(sch->secondary);
    s_pal.on_secondary = lv_color_hex(sch->on_secondary);
    s_pal.secondary_container = lv_color_hex(sch->secondary_container);
    s_pal.on_secondary_container = lv_color_hex(sch->on_secondary_container);
    s_pal.tertiary = lv_color_hex(sch->tertiary);
    s_pal.on_tertiary = lv_color_hex(sch->on_tertiary);
    s_pal.tertiary_container = lv_color_hex(sch->tertiary_container);
    s_pal.on_tertiary_container = lv_color_hex(sch->on_tertiary_container);
    /* Accent-tinted surface inks + tonal container ladder (AA-gated in gen). */
    s_pal.on_surface = lv_color_hex(sch->on_surface);
    s_pal.on_surface_variant = lv_color_hex(sch->on_surface_variant);
    s_pal.outline = lv_color_hex(sch->outline);
    s_pal.outline_variant = lv_color_hex(sch->outline_variant);
    s_pal.icon_chrome = lv_color_hex(sch->icon_chrome);
    s_pal.surface_container_lowest = lv_color_hex(sch->surface_container_lowest);
    s_pal.surface_container_low = lv_color_hex(sch->surface_container_low);
    s_pal.surface_container = lv_color_hex(sch->surface_container);
    s_pal.surface_container_high = lv_color_hex(sch->surface_container_high);
    s_pal.surface_container_highest = lv_color_hex(sch->surface_container_highest);
}

static void build_palette(uint32_t bg_hex, bool dark, uint8_t accent_idx)
{
    const lv_color_t bg = lv_color_hex(bg_hex);

    apply_accent_scheme(accent_idx, dark);

    s_pal.surface = bg;
    s_pal.inverse_on_surface = dark ? lv_color_hex(0xE0E0E6) : lv_color_hex(0x1A1C1E);
    /* MD3: inverse_primary is the primary of the OPPOSITE scheme (for use on
     * inverse_surface, e.g. snackbar actions) — not a lightened variant. */
    {
        const uint8_t safe_idx = (accent_idx < MOD_UI_SCHEME_COUNT) ? accent_idx : 0;
        s_pal.inverse_primary = dark ? lv_color_hex(k_ui_schemes_light[safe_idx].primary)
                                     : lv_color_hex(k_ui_schemes_dark[safe_idx].primary);
    }

    if (dark) {
        s_pal.surface_dim = ui_darken(bg, 40);
        s_pal.surface_bright = ui_lighten(bg, 22);
    } else {
        s_pal.surface_dim = ui_darken(bg, 12);
        s_pal.surface_bright = bg;
    }
    /* Opaque cover under sw_rotate — never translucent MD3 32% scrim. */
    s_pal.scrim = lv_color_black();

    /* Fixed industrial semantic layer — accent-independent CNC safety colors. */
    apply_semantic_colors(dark);
    s_pal.error_container = dark ? ui_mix(s_pal.error, bg, 52) : ui_mix(s_pal.error, bg, 232);
    s_pal.on_error_container = dark ? s_pal.error : s_pal.on_error;
}

/* MD3 user contrast: 0=standard, 1=medium, 2=high — outline/ink + surface steps. */
static void apply_contrast_level(bool dark)
{
    const uint8_t level = modulus_nvs_get_u8("ui_contrast", 0);
    if (level == 0) {
        return;
    }
    const uint8_t outline_amt = level >= 2 ? 100 : 50;
    const uint8_t variant_amt = level >= 2 ? 70 : 35;
    const uint8_t step_amt = level >= 2 ? 28 : 14;
    if (dark) {
        s_pal.outline = ui_lighten(s_pal.outline, outline_amt);
        s_pal.outline_variant = ui_lighten(s_pal.outline_variant, outline_amt / 2);
        s_pal.on_surface_variant =
            ui_mix(s_pal.on_surface_variant, s_pal.on_surface, variant_amt);
        s_pal.surface_container_low = ui_lighten(s_pal.surface_container_low, step_amt / 2);
        s_pal.surface_container = ui_lighten(s_pal.surface_container, step_amt);
        s_pal.surface_container_high = ui_lighten(s_pal.surface_container_high, step_amt);
        s_pal.surface_container_highest =
            ui_lighten(s_pal.surface_container_highest, step_amt + step_amt / 2);
    } else {
        s_pal.outline = ui_darken(s_pal.outline, outline_amt);
        s_pal.outline_variant = ui_darken(s_pal.outline_variant, outline_amt / 2);
        s_pal.on_surface_variant =
            ui_mix(s_pal.on_surface_variant, s_pal.on_surface, variant_amt);
        s_pal.surface_container_low = ui_darken(s_pal.surface_container_low, step_amt / 2);
        s_pal.surface_container = ui_darken(s_pal.surface_container, step_amt);
        s_pal.surface_container_high = ui_darken(s_pal.surface_container_high, step_amt);
        s_pal.surface_container_highest =
            ui_darken(s_pal.surface_container_highest, step_amt + step_amt / 2);
    }
}

static void load_palette(void)
{
    s_accent = modulus_nvs_get_u8("accent", 0);
    if (s_accent >= MOD_UI_ACCENT_COUNT) {
        s_accent = 0;
    }
    s_dark = modulus_nvs_get_u8("darkmode", 1) != 0;

    const ui_accent_def_t *a = &k_accents[s_accent];
    const uint32_t bg = s_dark ? a->dark_bg : a->light_bg;
    build_palette(bg, s_dark, s_accent);
    apply_contrast_level(s_dark);
}

const char *modulus_ui_accent_name(uint8_t idx)
{
    if (idx >= MOD_UI_ACCENT_COUNT) {
        return "Unknown";
    }
    return k_accents[idx].name;
}

uint8_t modulus_ui_get_accent(void)
{
    return s_accent;
}



bool modulus_ui_is_dark_mode(void)

{

    return s_dark;

}



void modulus_ui_touch_scroll_tune(void)
{
    /* Touch responsiveness: default LVGL needs 10 px of finger travel before a
     * scroll starts and decelerates throws hard. 4 px start + softer throw
     * makes 1280x720 settings lists track the finger with less dead zone.
     * Indev-global on purpose — dashboard lists benefit identically. */
    static bool s_done = false;
    if (s_done) {
        return;
    }
    for (lv_indev_t *i = lv_indev_get_next(NULL); i; i = lv_indev_get_next(i)) {
        if (lv_indev_get_type(i) == LV_INDEV_TYPE_POINTER) {
            lv_indev_set_scroll_limit(i, 4);
            lv_indev_set_scroll_throw(i, 8);
        }
    }
    s_done = true;
}

static float theme_lin(float c)
{
    return (c <= 0.04045f) ? (c / 12.92f) : powf((c + 0.055f) / 1.055f, 2.4f);
}

static float theme_rel_l(lv_color_t c)
{
    const uint32_t u = lv_color_to_u32(c);
    const float r = theme_lin((float)((u >> 16) & 0xFFu) / 255.0f);
    const float g = theme_lin((float)((u >> 8) & 0xFFu) / 255.0f);
    const float b = theme_lin((float)(u & 0xFFu) / 255.0f);
    return 0.2126f * r + 0.7152f * g + 0.0722f * b;
}

static float theme_contrast(lv_color_t a, lv_color_t b)
{
    const float la = theme_rel_l(a);
    const float lb = theme_rel_l(b);
    const float hi = (la > lb) ? la : lb;
    const float lo = (la > lb) ? lb : la;
    return (hi + 0.05f) / (lo + 0.05f);
}

bool modulus_ui_theme_contrast_ok(void)
{
    /* Device gamma spot-check: key text/fill pairs must clear WCAG AA. */
    const float pairs[] = {
        theme_contrast(s_pal.on_surface, s_pal.surface),
        theme_contrast(s_pal.on_surface_variant, s_pal.surface),
        theme_contrast(s_pal.on_primary, s_pal.primary),
        theme_contrast(s_pal.on_primary_container, s_pal.primary_container),
        theme_contrast(s_pal.on_tinted_btn, s_pal.cycle),
        theme_contrast(s_pal.on_tinted_btn, s_pal.hold),
        theme_contrast(s_pal.on_tinted_btn, s_pal.home_all),
        theme_contrast(s_pal.on_error, s_pal.error),
    };
    for (unsigned i = 0; i < sizeof(pairs) / sizeof(pairs[0]); i++) {
        if (pairs[i] < 4.5f) {
            return false;
        }
    }
    return theme_contrast(s_pal.outline, s_pal.surface) >= 3.0f;
}

void modulus_ui_theme_apply(void)
{
    load_palette();
    const bool aa = modulus_ui_theme_contrast_ok();
    ESP_LOGI(TAG, "theme AA %s accent=%u dark=%d (%s)", aa ? "pass" : "FAIL",
             (unsigned)s_accent, (int)s_dark, modulus_ui_accent_name(s_accent));

    modulus_ui_touch_scroll_tune();

    modulus_ui_dashboard_theme_refresh();

    modulus_ui_status_bar_theme_refresh();

    modulus_ui_actions_theme_refresh();

    modulus_ui_dro_theme_refresh();

    modulus_ui_jog_theme_refresh();

    modulus_ui_overrides_theme_refresh();

    modulus_ui_settings_theme_refresh();

    modulus_ui_quick_settings_theme_refresh();

    modulus_ui_pin_theme_refresh();

    settings_modals_theme_refresh();

    settings_time_modal_theme_refresh();

    modulus_ui_power_menu_theme_refresh();

    modulus_ui_wireless_theme_refresh();

    modulus_ui_state_modal_theme_refresh();

    modulus_ui_keyboards_theme_refresh();

    lv_obj_t *scr = lv_screen_active();

    if (!scr) {

        return;

    }

    lv_obj_set_style_bg_color(scr, s_pal.surface, 0);

    lv_obj_set_style_bg_opa(scr, LV_OPA_COVER, 0);

    lv_obj_set_style_text_color(scr, s_pal.on_surface, 0);

}



lv_color_t modulus_ui_color_surface(void)

{

    return s_pal.surface;

}



lv_color_t modulus_ui_color_primary(void)

{

    return s_pal.primary;

}



lv_color_t modulus_ui_color_on_primary(void)

{

    return s_pal.on_primary;

}



lv_color_t modulus_ui_color_accent(void)

{

    return s_pal.accent;

}



lv_color_t modulus_ui_color_on_accent(void)

{

    return s_pal.on_accent;

}



lv_color_t modulus_ui_color_cycle(void)

{

    return s_pal.cycle;

}



lv_color_t modulus_ui_color_hold(void)

{

    return s_pal.hold;

}



lv_color_t modulus_ui_color_home_all(void)

{

    return s_pal.home_all;

}



lv_color_t modulus_ui_color_surface_dim(void)

{

    return s_pal.surface_dim;

}



lv_color_t modulus_ui_color_on_surface(void)

{

    return s_pal.on_surface;

}



lv_color_t modulus_ui_color_on_surface_variant(void)

{

    return s_pal.on_surface_variant;

}



lv_color_t modulus_ui_color_outline(void)

{

    return s_pal.outline;

}



lv_color_t modulus_ui_color_outline_variant(void)

{

    return s_pal.outline_variant;

}



lv_color_t modulus_ui_color_error(void)

{

    return s_pal.error;

}



lv_color_t modulus_ui_color_on_error(void)

{

    return s_pal.on_error;

}



lv_color_t modulus_ui_color_success(void)

{

    return s_pal.success;

}



lv_color_t modulus_ui_color_warning(void)

{

    return s_pal.warning;

}



lv_color_t modulus_ui_color_neutral(void)

{

    return s_pal.neutral;

}



lv_color_t modulus_ui_color_inverse_surface(void)

{

    return s_pal.inverse_surface;

}



lv_color_t modulus_ui_color_on_cycle(void)

{

    return s_pal.on_cycle;

}



lv_color_t modulus_ui_color_on_hold(void)

{

    return s_pal.on_hold;

}



lv_color_t modulus_ui_color_on_home(void)

{

    return s_pal.on_home;

}



lv_color_t modulus_ui_color_icon_chrome(void)

{

    return s_pal.icon_chrome;

}



lv_color_t modulus_ui_color_on_tinted_btn(void)

{

    return s_pal.on_tinted_btn;

}



lv_color_t modulus_ui_color_primary_container(void)
{
    return s_pal.primary_container;
}

lv_color_t modulus_ui_color_on_primary_container(void)
{
    return s_pal.on_primary_container;
}

lv_color_t modulus_ui_color_tertiary(void)
{
    return s_pal.tertiary;
}

lv_color_t modulus_ui_color_on_tertiary(void)
{
    return s_pal.on_tertiary;
}

lv_color_t modulus_ui_color_surface_container_lowest(void)
{
    return s_pal.surface_container_lowest;
}

lv_color_t modulus_ui_color_surface_container_low(void)
{
    return s_pal.surface_container_low;
}

lv_color_t modulus_ui_color_surface_container_high(void)
{
    return s_pal.surface_container_high;
}

lv_color_t modulus_ui_color_surface_container_highest(void)
{
    return s_pal.surface_container_highest;
}

lv_color_t modulus_ui_color_surface_container(void)
{
    return s_pal.surface_container;
}

lv_color_t modulus_ui_color_scrim(void)
{
    return s_pal.scrim;
}

lv_color_t modulus_ui_color_opaque_scrim(void)
{
    return s_pal.surface_dim;
}

lv_color_t modulus_ui_color_secondary(void)
{
    return s_pal.secondary;
}

lv_color_t modulus_ui_color_on_secondary(void)
{
    return s_pal.on_secondary;
}

lv_color_t modulus_ui_color_secondary_container(void)
{
    return s_pal.secondary_container;
}

lv_color_t modulus_ui_color_on_secondary_container(void)
{
    return s_pal.on_secondary_container;
}

lv_color_t modulus_ui_color_tertiary_container(void)
{
    return s_pal.tertiary_container;
}

lv_color_t modulus_ui_color_on_tertiary_container(void)
{
    return s_pal.on_tertiary_container;
}

lv_color_t modulus_ui_color_error_container(void)
{
    return s_pal.error_container;
}

lv_color_t modulus_ui_color_on_error_container(void)
{
    return s_pal.on_error_container;
}

lv_color_t modulus_ui_color_inverse_on_surface(void)
{
    return s_pal.inverse_on_surface;
}

lv_color_t modulus_ui_color_inverse_primary(void)
{
    return s_pal.inverse_primary;
}

lv_color_t modulus_ui_color_surface_bright(void)
{
    return s_pal.surface_bright;
}

lv_color_t modulus_ui_color_semantic_stop(void)
{
    return s_pal.semantic_stop;
}

lv_color_t modulus_ui_color_semantic_resume(void)
{
    return s_pal.semantic_resume;
}

lv_color_t modulus_ui_color_semantic_power(void)
{
    return s_pal.semantic_power;
}

void modulus_ui_apply_pressed_state_layer_color(lv_obj_t *obj, lv_color_t layer_color)
{
    /* MD3 state-layer motion + scroll-touch responsiveness: the 60 ms delay
     * means a press that turns into a scroll drag never paints the pressed
     * layer (LVGL sends PRESS_LOST once the scroll threshold is crossed), so
     * list rows no longer flash/repaint under a scrolling finger. */
    static const lv_style_prop_t k_press_props[] = {LV_STYLE_BG_OPA, LV_STYLE_BG_COLOR, 0};
    static lv_style_transition_dsc_t s_press_tr;
    static bool s_press_tr_ready = false;
    if (!s_press_tr_ready) {
        lv_style_transition_dsc_init(&s_press_tr, k_press_props, lv_anim_path_ease_out,
                                     80, 60, NULL);
        s_press_tr_ready = true;
    }
    lv_obj_set_style_bg_color(obj, layer_color, LV_STATE_PRESSED);
    lv_obj_set_style_bg_opa(obj, MOD_UI_STATE_LAYER_PRESSED, LV_STATE_PRESSED);
    lv_obj_set_style_transition(obj, &s_press_tr, LV_STATE_PRESSED);
}

void modulus_ui_apply_pressed_state_layer(lv_obj_t *obj)
{
    modulus_ui_apply_pressed_state_layer_color(obj, modulus_ui_color_on_surface());
}

void modulus_ui_apply_keyboard_theme(lv_obj_t *kb)
{
    if (!kb) {
        return;
    }

    static const lv_style_prop_t k_kb_press_props[] = {LV_STYLE_BG_OPA, LV_STYLE_BG_COLOR, 0};
    static lv_style_transition_dsc_t s_kb_press_tr;
    static bool s_kb_press_tr_ready = false;
    if (!s_kb_press_tr_ready) {
        lv_style_transition_dsc_init(&s_kb_press_tr, k_kb_press_props, lv_anim_path_ease_out,
                                     80, 0, NULL);
        s_kb_press_tr_ready = true;
    }

    const uint32_t items = (uint32_t)LV_PART_ITEMS;
    const uint32_t items_pressed = (uint32_t)LV_PART_ITEMS | (uint32_t)LV_STATE_PRESSED;
    const uint32_t items_checked = (uint32_t)LV_PART_ITEMS | (uint32_t)LV_STATE_CHECKED;
    const uint32_t items_checked_pressed =
        (uint32_t)LV_PART_ITEMS | (uint32_t)LV_STATE_CHECKED | (uint32_t)LV_STATE_PRESSED;

    /* Tray: surface_container — keys sit one tonal step above via secondary_container. */
    lv_obj_set_style_bg_color(kb, modulus_ui_color_surface_container(), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(kb, LV_OPA_COVER, LV_PART_MAIN);
    lv_obj_set_style_border_width(kb, 1, LV_PART_MAIN);
    lv_obj_set_style_border_color(kb, modulus_ui_color_outline_variant(), LV_PART_MAIN);
    lv_obj_set_style_border_side(kb, LV_BORDER_SIDE_TOP, LV_PART_MAIN);
    lv_obj_set_style_radius(kb, 0, LV_PART_MAIN);
    lv_obj_set_style_shadow_width(kb, 0, LV_PART_MAIN);
    lv_obj_set_style_pad_all(kb, MOD_UI_SPACE_SM, LV_PART_MAIN);
    lv_obj_set_style_pad_gap(kb, MOD_UI_SPACE_XS, LV_PART_MAIN);

    /* MD3 tonal keys — accent-tinted fill tracks light/dark + seed palette. */
    lv_obj_set_style_bg_color(kb, modulus_ui_color_secondary_container(), items);
    lv_obj_set_style_bg_opa(kb, LV_OPA_COVER, items);
    lv_obj_set_style_text_color(kb, modulus_ui_color_on_secondary_container(), items);
    lv_obj_set_style_text_font(kb, MOD_UI_FONT_BODY_L, items);
    lv_obj_set_style_border_width(kb, 1, items);
    lv_obj_set_style_border_color(kb, modulus_ui_color_outline_variant(), items);
    lv_obj_set_style_radius(kb, MOD_UI_SHAPE_SM, items);
    lv_obj_set_style_shadow_width(kb, 0, items);

    lv_obj_set_style_bg_color(kb, modulus_ui_color_on_secondary_container(), items_pressed);
    lv_obj_set_style_bg_opa(kb, MOD_UI_STATE_LAYER_PRESSED, items_pressed);
    lv_obj_set_style_transition(kb, &s_kb_press_tr, items_pressed);

    /* Shift / caps checked — primary emphasis. */
    lv_obj_set_style_bg_color(kb, modulus_ui_color_primary(), items_checked);
    lv_obj_set_style_bg_opa(kb, LV_OPA_COVER, items_checked);
    lv_obj_set_style_text_color(kb, modulus_ui_color_on_primary(), items_checked);
    lv_obj_set_style_border_color(kb, modulus_ui_color_primary(), items_checked);

    lv_obj_set_style_bg_color(kb, modulus_ui_color_on_primary(), items_checked_pressed);
    lv_obj_set_style_bg_opa(kb, MOD_UI_STATE_LAYER_PRESSED, items_checked_pressed);
    lv_obj_set_style_transition(kb, &s_kb_press_tr, items_checked_pressed);
}

void modulus_ui_apply_textarea_theme(lv_obj_t *ta, bool readonly)
{
    if (!ta) {
        return;
    }

    lv_obj_set_style_radius(ta, MOD_UI_SHAPE_SM, 0);
    lv_obj_set_style_shadow_width(ta, 0, 0);
    lv_obj_set_style_pad_all(ta, MOD_UI_SPACE_SM, 0);
    lv_obj_set_style_text_font(ta, MOD_UI_FONT_BODY_M, 0);
    lv_obj_set_style_text_color(ta, modulus_ui_color_on_surface(), 0);
    lv_obj_set_style_border_width(ta, 1, 0);

    if (readonly) {
        /* MD3 filled log surface — tonal container, decorative outline. */
        lv_obj_set_style_bg_color(ta, modulus_ui_color_surface_container_high(), 0);
        lv_obj_set_style_bg_opa(ta, LV_OPA_COVER, 0);
        lv_obj_set_style_border_color(ta, modulus_ui_color_outline_variant(), 0);
        lv_obj_set_style_bg_color(ta, modulus_ui_color_surface_container_high(), LV_STATE_DISABLED);
        lv_obj_set_style_text_color(ta, modulus_ui_color_on_surface(), LV_STATE_DISABLED);
        lv_obj_set_style_border_color(ta, modulus_ui_color_outline_variant(), LV_STATE_DISABLED);
        lv_obj_set_style_opa(lv_textarea_get_label(ta), LV_OPA_COVER, LV_STATE_DISABLED);
        return;
    }

    /* MD3 outlined text field — surface fill, primary focus ring. */
    lv_obj_set_style_bg_color(ta, modulus_ui_color_surface(), 0);
    lv_obj_set_style_bg_opa(ta, LV_OPA_COVER, 0);
    lv_obj_set_style_border_color(ta, modulus_ui_color_outline_variant(), 0);
    lv_obj_set_style_border_color(ta, modulus_ui_color_primary(), LV_STATE_FOCUSED);
    lv_obj_set_style_text_color(ta, modulus_ui_color_on_surface_variant(),
                                (uint32_t)LV_PART_TEXTAREA_PLACEHOLDER);
}

void modulus_ui_apply_slider_theme(lv_obj_t *sl)
{
    if (!sl) {
        return;
    }
    /* MD3 continuous slider: inactive track = surface_container_highest,
     * active indicator = primary, handle = primary (no elevation shadow). */
    lv_obj_set_style_bg_color(sl, modulus_ui_color_surface_container_highest(), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(sl, LV_OPA_COVER, LV_PART_MAIN);
    lv_obj_set_style_radius(sl, MOD_UI_SHAPE_FULL, LV_PART_MAIN);
    lv_obj_set_style_bg_color(sl, modulus_ui_color_primary(), LV_PART_INDICATOR);
    lv_obj_set_style_bg_opa(sl, LV_OPA_COVER, LV_PART_INDICATOR);
    lv_obj_set_style_radius(sl, MOD_UI_SHAPE_FULL, LV_PART_INDICATOR);
    lv_obj_set_style_bg_color(sl, modulus_ui_color_primary(), LV_PART_KNOB);
    lv_obj_set_style_bg_opa(sl, LV_OPA_COVER, LV_PART_KNOB);
    lv_obj_set_style_radius(sl, MOD_UI_SHAPE_FULL, LV_PART_KNOB);
    lv_obj_set_style_pad_all(sl, MOD_UI_SPACE_XS + MOD_UI_SPACE_XS / 2, LV_PART_KNOB);
    lv_obj_set_style_shadow_width(sl, 0, LV_PART_KNOB);
    lv_obj_set_style_border_width(sl, 0, LV_PART_KNOB);
}

void modulus_ui_apply_dropdown_theme(lv_obj_t *dd)
{
    if (!dd) {
        return;
    }
    lv_obj_set_style_text_font(dd, MOD_UI_FONT_BODY_M, 0);
    lv_obj_set_style_text_color(dd, modulus_ui_color_on_surface(), 0);
    lv_obj_set_style_bg_color(dd, modulus_ui_color_surface_container_high(), 0);
    lv_obj_set_style_bg_opa(dd, LV_OPA_COVER, 0);
    lv_obj_set_style_border_color(dd, modulus_ui_color_outline(), 0);
    lv_obj_set_style_border_width(dd, 1, 0);
    lv_obj_set_style_radius(dd, MOD_UI_SHAPE_SM, 0);
    lv_obj_t *list = lv_dropdown_get_list(dd);
    if (!list) {
        return;
    }
    lv_obj_set_style_text_font(list, MOD_UI_FONT_BODY_M, 0);
    lv_obj_set_style_bg_color(list, modulus_ui_color_surface_container_high(), 0);
    lv_obj_set_style_text_color(list, modulus_ui_color_on_surface(), 0);
    lv_obj_set_style_bg_color(list, modulus_ui_color_primary_container(),
                              (uint32_t)LV_PART_SELECTED | (uint32_t)LV_STATE_CHECKED);
    lv_obj_set_style_text_color(list, modulus_ui_color_on_primary_container(),
                                (uint32_t)LV_PART_SELECTED | (uint32_t)LV_STATE_CHECKED);
}

void modulus_ui_apply_switch_theme(lv_obj_t *sw)
{
    if (!sw) {
        return;
    }
    /* MD3 switch: track outline / primary when checked; thumb on-primary / surface.
     * Optional Phosphor check on indicator when NVS sw_icons=1 (24px clipped by pad). */
    lv_obj_set_style_bg_color(sw, modulus_ui_color_surface_container_highest(), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(sw, LV_OPA_COVER, LV_PART_MAIN);
    lv_obj_set_style_radius(sw, MOD_UI_SHAPE_FULL, LV_PART_MAIN);
    lv_obj_set_style_border_width(sw, 0, LV_PART_MAIN);

    lv_obj_set_style_bg_color(sw, modulus_ui_color_primary(),
                              (uint32_t)LV_PART_INDICATOR | (uint32_t)LV_STATE_CHECKED);
    lv_obj_set_style_bg_opa(sw, LV_OPA_COVER,
                            (uint32_t)LV_PART_INDICATOR | (uint32_t)LV_STATE_CHECKED);
    lv_obj_set_style_bg_color(sw, modulus_ui_color_outline(), LV_PART_INDICATOR);
    lv_obj_set_style_bg_opa(sw, LV_OPA_60, LV_PART_INDICATOR);
    lv_obj_set_style_radius(sw, MOD_UI_SHAPE_FULL, LV_PART_INDICATOR);

    if (modulus_nvs_get_u8("sw_icons", 1) != 0) {
        const lv_image_dsc_t *check = modulus_ui_icon_dsc(MOD_UI_ICON_CHECK, MOD_UI_ICON_SZ_24);
        if (check) {
            lv_obj_set_style_bg_image_src(sw, check,
                                         (uint32_t)LV_PART_INDICATOR | (uint32_t)LV_STATE_CHECKED);
            lv_obj_set_style_bg_image_recolor(sw, modulus_ui_color_on_primary(),
                                              (uint32_t)LV_PART_INDICATOR | (uint32_t)LV_STATE_CHECKED);
            lv_obj_set_style_bg_image_recolor_opa(sw, LV_OPA_COVER,
                                                  (uint32_t)LV_PART_INDICATOR | (uint32_t)LV_STATE_CHECKED);
        }
        lv_obj_set_style_bg_image_src(sw, NULL, LV_PART_INDICATOR);
    }

    lv_obj_set_style_bg_color(sw, modulus_ui_color_on_primary(),
                              (uint32_t)LV_PART_KNOB | (uint32_t)LV_STATE_CHECKED);
    lv_obj_set_style_bg_color(sw, modulus_ui_color_on_surface_variant(), LV_PART_KNOB);
    lv_obj_set_style_bg_opa(sw, LV_OPA_COVER, LV_PART_KNOB);
    lv_obj_set_style_radius(sw, MOD_UI_SHAPE_FULL, LV_PART_KNOB);
    lv_obj_set_style_pad_all(sw, MOD_UI_SPACE_XS / 2, LV_PART_KNOB);
    lv_obj_set_style_shadow_width(sw, 0, LV_PART_KNOB);
    modulus_ui_apply_focus_ring(sw);
}

void modulus_ui_keyboards_theme_refresh(void)
{
    settings_cnc_masso_kb_theme_refresh();
    settings_dashboard_kb_theme_refresh();
    settings_wireless_inline_kb_theme_refresh();
    settings_machine_svc_kb_theme_refresh();
    modulus_ui_cnc_profiles_kb_theme_refresh();
}
