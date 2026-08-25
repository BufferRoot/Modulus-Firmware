/* Probe tab for ui_quick_settings.c — textual include (shares its statics).
 * Pin indicator (500 ms hold), NVS settings, PRB: probe-engine cycles. */

typedef struct {
    const char *label;
    const char *key;
    uint16_t def_x10, min_x10, max_x10, step_x10;
} qs_probe_set_t;

static const qs_probe_set_t k_probe_sets[] = {
    {"Plate thickness (Z off)", "pb_zoff", 100, 0, 500, 5},
    {"Max travel",              "pb_max",  250, 20, 1000, 10},
    {"Probe feed",              "pb_feed", 750, 100, 5000, 250},
    {"Retract",                 "pb_retr", 20, 5, 200, 5},
    {"Tip diameter",            "pb_tip",  20, 0, 200, 5},
};

static lv_obj_t *s_probe_dot;    /* live pin indicator (NULL off-tab) */
static lv_obj_t *s_probe_lbl;
static lv_obj_t *s_probe_stat;
static uint32_t s_probe_hold_ms; /* trigger latched until this tick (500 ms) */

static float qs_probe_val(int i)
{
    return modulus_nvs_get_u16(k_probe_sets[i].key, k_probe_sets[i].def_x10) / 10.0f;
}

static void qs_probe_step_cb(lv_event_t *e)
{
    const intptr_t packed = (intptr_t)lv_event_get_user_data(e);
    const int i = (int)(packed >> 1);
    const bool up = (packed & 1) != 0;
    const qs_probe_set_t *s = &k_probe_sets[i];
    int32_t v = modulus_nvs_get_u16(s->key, s->def_x10);
    v += up ? s->step_x10 : -(int32_t)s->step_x10;
    if (v < s->min_x10) {
        v = s->min_x10;
    }
    if (v > s->max_x10) {
        v = s->max_x10;
    }
    modulus_nvs_set_u16(s->key, (uint16_t)v);
    lv_obj_t *vl = lv_obj_get_user_data(lv_event_get_target(e));
    if (vl) {
        char b[16];
        snprintf(b, sizeof(b), "%.1f", (double)(v / 10.0f));
        lv_label_set_text(vl, b);
    }
}

static void qs_probe_run_cb(lv_event_t *e)
{
    const uint8_t cycle = (uint8_t)(uintptr_t)lv_event_get_user_data(e);
    if (modulus_zig_probe_busy()) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
        return;
    }
    if (!modulus_zig_probe_start(cycle)) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
        return;
    }
    modulus_audio_play_ui(1);
    if (s_probe_stat) {
        lv_label_set_text(s_probe_stat, "Probe cycle running...");
    }
}

static void qs_probe_tick(void)
{
    if (!s_probe_dot) {
        return;
    }
    const bool trig = modulus_zig_probe_pin() != 0;
    const uint32_t now = lv_tick_get();
    if (trig) {
        s_probe_hold_ms = now + 500; /* hold indicator 500 ms past release */
    }
    const bool show = trig || (s_probe_hold_ms != 0 && now < s_probe_hold_ms);
    static int8_t s_last_show = -1;
    if ((int8_t)show != s_last_show) {
        s_last_show = (int8_t)show;
        lv_obj_set_style_bg_color(s_probe_dot,
                                  show ? modulus_ui_color_error()
                                       : modulus_ui_color_surface_container_high(),
                                  0);
    }
    if (s_probe_lbl) {
        modulus_ui_label_set_text_if_changed(s_probe_lbl,
                                             show ? "Probe: TRIGGERED" : "Probe: open");
    }
    if (s_probe_stat && !modulus_zig_probe_busy()) {
        modulus_ui_label_set_text_if_changed(s_probe_stat, "Idle - tap a cycle");
    }
}

static lv_obj_t *qs_probe_btn(lv_obj_t *parent, const char *txt, lv_event_cb_t cb,
                              void *user)
{
    lv_obj_t *b = lv_button_create(parent);
    lv_obj_set_size(b, lv_pct(31), MOD_UI_TOUCH_MIN);
    lv_obj_set_style_radius(b, MOD_UI_SHAPE_FULL, 0);
    lv_obj_set_style_shadow_width(b, 0, 0);
    lv_obj_set_style_bg_color(b, modulus_ui_color_secondary_container(), 0);
    lv_obj_set_style_bg_opa(b, LV_OPA_COVER, 0);
    modulus_ui_apply_pressed_state_layer_color(b, modulus_ui_color_on_secondary_container());
    lv_obj_t *l = lv_label_create(b);
    lv_label_set_text(l, txt);
    lv_obj_set_style_text_color(l, modulus_ui_color_on_secondary_container(), 0);
    lv_obj_set_style_text_font(l, MOD_UI_FONT_LABEL_M, 0);
    lv_obj_center(l);
    if (cb) {
        lv_obj_add_event_cb(b, cb, LV_EVENT_SHORT_CLICKED, user);
    }
    return b;
}

static void qs_probe_dot_delete_cb(lv_event_t *e)
{
    (void)e;
    s_probe_dot = NULL;
    s_probe_lbl = NULL;
    s_probe_stat = NULL;
}

static void qs_build_probe(lv_obj_t *panel)
{
    lv_obj_t *pin = lv_obj_create(panel);
    lv_obj_remove_style_all(pin);
    lv_obj_set_size(pin, lv_pct(100), 40);
    qs_disable_scroll(pin);
    lv_obj_set_flex_flow(pin, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(pin, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(pin, MOD_UI_SPACE_SM, 0);
    s_probe_dot = lv_obj_create(pin);
    lv_obj_remove_style_all(s_probe_dot);
    lv_obj_set_size(s_probe_dot, 24, 24);
    lv_obj_set_style_radius(s_probe_dot, MOD_UI_SHAPE_FULL, 0);
    lv_obj_set_style_bg_opa(s_probe_dot, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_color(s_probe_dot, modulus_ui_color_surface_container_high(), 0);
    lv_obj_add_event_cb(s_probe_dot, qs_probe_dot_delete_cb, LV_EVENT_DELETE, NULL);
    s_probe_lbl = lv_label_create(pin);
    lv_label_set_text(s_probe_lbl, "Probe: open");
    lv_obj_set_style_text_color(s_probe_lbl, modulus_ui_color_on_surface(), 0);
    lv_obj_set_style_text_font(s_probe_lbl, MOD_UI_FONT_BODY_M, 0);
    s_probe_hold_ms = 0;

    s_probe_stat = lv_label_create(panel);
    lv_label_set_text(s_probe_stat, "Idle - tap a cycle");
    lv_obj_set_style_text_color(s_probe_stat, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(s_probe_stat, MOD_UI_FONT_BODY_M, 0);

    for (int i = 0; i < (int)(sizeof(k_probe_sets) / sizeof(k_probe_sets[0])); i++) {
        lv_obj_t *row = lv_obj_create(panel);
        lv_obj_remove_style_all(row);
        lv_obj_set_size(row, lv_pct(100), MOD_UI_TOUCH_MIN);
        qs_disable_scroll(row);
        lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
        lv_obj_set_flex_align(row, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER,
                              LV_FLEX_ALIGN_CENTER);
        lv_obj_t *nl = lv_label_create(row);
        lv_label_set_text(nl, k_probe_sets[i].label);
        lv_obj_set_style_text_color(nl, modulus_ui_color_on_surface(), 0);
        lv_obj_set_style_text_font(nl, MOD_UI_FONT_BODY_M, 0);

        lv_obj_t *ctl = lv_obj_create(row);
        lv_obj_remove_style_all(ctl);
        lv_obj_set_size(ctl, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
        qs_disable_scroll(ctl);
        lv_obj_set_flex_flow(ctl, LV_FLEX_FLOW_ROW);
        lv_obj_set_style_pad_column(ctl, MOD_UI_SPACE_SM, 0);

        char vb[16];
        snprintf(vb, sizeof(vb), "%.1f", (double)qs_probe_val(i));
        lv_obj_t *minus = qs_probe_btn(ctl, "-", qs_probe_step_cb,
                                       (void *)(intptr_t)((i << 1) | 0));
        lv_obj_set_size(minus, 52, MOD_UI_TOUCH_MIN);
        lv_obj_t *vl = lv_label_create(ctl);
        lv_label_set_text(vl, vb);
        lv_obj_set_style_text_color(vl, modulus_ui_color_on_surface(), 0);
        lv_obj_set_style_text_font(vl, MOD_UI_FONT_BODY_M, 0);
        lv_obj_set_width(vl, 64);
        lv_obj_set_style_text_align(vl, LV_TEXT_ALIGN_CENTER, 0);
        lv_obj_t *plus = qs_probe_btn(ctl, "+", qs_probe_step_cb,
                                      (void *)(intptr_t)((i << 1) | 1));
        lv_obj_set_size(plus, 52, MOD_UI_TOUCH_MIN);
        lv_obj_set_user_data(minus, vl);
        lv_obj_set_user_data(plus, vl);
    }

    lv_obj_t *grid = lv_obj_create(panel);
    lv_obj_remove_style_all(grid);
    lv_obj_set_size(grid, lv_pct(100), LV_SIZE_CONTENT);
    qs_disable_scroll(grid);
    lv_obj_set_flex_flow(grid, LV_FLEX_FLOW_ROW_WRAP);
    lv_obj_set_style_pad_column(grid, MOD_UI_SPACE_SM, 0);
    lv_obj_set_style_pad_row(grid, MOD_UI_SPACE_SM, 0);
    qs_probe_btn(grid, "Z probe", qs_probe_run_cb, (void *)(uintptr_t)MODULUS_PROBE_Z_PLATE);
    qs_probe_btn(grid, "Edge X-", qs_probe_run_cb, (void *)(uintptr_t)MODULUS_PROBE_EDGE_X_NEG);
    qs_probe_btn(grid, "Edge Y-", qs_probe_run_cb, (void *)(uintptr_t)MODULUS_PROBE_EDGE_Y_NEG);
    qs_probe_btn(grid, "Center finder", qs_probe_run_cb, (void *)(uintptr_t)MODULUS_PROBE_CENTER);
    qs_probe_btn(grid, "180 deg edge", qs_probe_run_cb, (void *)(uintptr_t)MODULUS_PROBE_EDGE_180_X);
    qs_probe_btn(grid, "Tool setter", qs_probe_run_cb, (void *)(uintptr_t)MODULUS_PROBE_TOOL_SETTER);
}
