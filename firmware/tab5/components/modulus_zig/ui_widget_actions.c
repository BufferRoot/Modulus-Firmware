#include "ui_internal.h"
#include "ui_quick_grid.h"
#include "ui_zero_confirm.h"
#include "ui_confirm_policy.h"
#include "cnc_cmd_exports.h"
#include "audio_shim.h"
#include "zb_automation.h"
#include "shop_recipe.h"

extern void modulus_zig_fill_cnc_status(modulus_cnc_status_t *out);

enum {
    k_pad_section = MOD_UI_SPACE_MD,
    k_wide_h = 112,
    k_home_h = 96,
    k_state_idle = 1,
    k_state_run = 2,
    k_state_hold = 3,
    k_state_jog = 4,
    k_state_alarm = 5,
    k_state_door = 6,
    k_state_check = 7,
    k_state_home = 8,
    k_acc_spindle_cw = 1 << 0,
    k_acc_spindle_ccw = 1 << 1,
    k_acc_mist = 1 << 2,
    k_acc_flood = 1 << 3,
};

typedef struct {
    lv_obj_t *btn;
    lv_obj_t *icon;
    lv_obj_t *lbl;
} action_wide_t;

static struct {
    lv_obj_t *col;
    lv_obj_t *quick_grid;
    action_wide_t cycle;
    lv_obj_t *cycle_split;
    action_wide_t hold;
    action_wide_t home;
    lv_obj_t *btn_quick[UI_QBTN_MAX_SLOTS];
    lv_obj_t *lbl_quick[UI_QBTN_MAX_SLOTS];
    lv_obj_t *icon_quick[UI_QBTN_MAX_SLOTS];
    uint8_t quick_assign[UI_QBTN_MAX_SLOTS];
} s_act = {};

static bool s_fan_on;
static uint8_t s_actions_state_cache = 0xFF;
static uint8_t s_qbtn_active_cache[UI_QBTN_MAX_SLOTS] = {
    0xFF, 0xFF, 0xFF, 0xFF,
};
static uint8_t s_spin_dir; /* 0=CW 1=CCW pending confirm */

static void apply_cycle(void *user)
{
    (void)user;
    modulus_zig_cmd_cycle_start();
}

static void apply_home(void *user)
{
    (void)user;
    modulus_zig_cmd_home_all();
}

static void apply_spindle(void *user)
{
    (void)user;
    if (s_spin_dir == 1) {
        modulus_zig_cmd_spindle_ccw();
    } else {
        modulus_zig_cmd_spindle_cw();
    }
}

static void apply_macro_line(void *user)
{
    (void)user;
    modulus_zig_cmd_run_macro();
    modulus_audio_play_ui(1);
}

static void apply_user_macro(void *user)
{
    const uint8_t assign = (uint8_t)(uintptr_t)user;
    if (ui_qbtn_fire_user(assign)) {
        modulus_audio_play_ui(1);
    }
}

static void cycle_click_cb(lv_event_t *e)
{
    (void)e;
    modulus_cnc_status_t st = {};
    modulus_zig_fill_cnc_status(&st);
    if (st.state == k_state_alarm) {
        modulus_zig_cmd_unlock();
        return;
    }
    if (st.state == k_state_run) {
        modulus_zig_cmd_stop();
        return;
    }
    if (st.state == k_state_door || st.state == k_state_home || st.state == k_state_jog) {
        return;
    }
    /* Soft interlock: Zigbee IAS door/contact open (never replaces E-Stop). */
    if (modulus_zb_door_blocks_cycle()) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
        return;
    }
    if (modulus_recipe_battery_blocks_cycle()) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
        return;
    }
    modulus_ui_cnf_request(MOD_CNF_ACT_CYCLE, st.state, "Cycle start?",
                           "Start or resume the program.", apply_cycle, NULL);
}

static void cycle_split_cb(lv_event_t *e)
{
    (void)e;
    modulus_zig_cmd_reset();
    modulus_ui_snackbar_show("Soft reset sent", 2200);
}

static void hold_click_cb(lv_event_t *e)
{
    (void)e;
    modulus_cnc_status_t st = {};
    modulus_zig_fill_cnc_status(&st);
    if (st.state == k_state_hold) {
        if (modulus_zb_door_blocks_cycle() || modulus_recipe_battery_blocks_cycle()) {
            modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
            return;
        }
        modulus_zig_cmd_cycle_start();
        return;
    }
    if (st.state == k_state_alarm) {
        /* Hard-limit recovery: Ctrl-X then $X after welcome banner. */
        modulus_zig_cmd_reset();
        return;
    }
    /* Run / Idle / etc.: feed hold only — Cancel Job is Cycle while running. */
    modulus_zig_cmd_feed_hold();
}

static void home_click_cb(lv_event_t *e)
{
    (void)e;
    modulus_cnc_status_t st = {};
    modulus_zig_fill_cnc_status(&st);
    if (st.state == k_state_run || st.state == k_state_alarm || st.state == k_state_door ||
        st.state == k_state_home || st.state == k_state_jog) {
        return;
    }
    modulus_ui_cnf_request(MOD_CNF_ACT_HOME, st.state, "Home all axes?",
                           "Machine will run a homing cycle.", apply_home, NULL);
}

static void quick_click_cb(lv_event_t *e)
{
    const uint8_t assign = (uint8_t)(uintptr_t)lv_event_get_user_data(e);
    modulus_cnc_status_t st = {};
    modulus_zig_fill_cnc_status(&st);
    switch (assign) {
    case UI_QBTN_SPINDLE_CW:
        s_spin_dir = 0;
        modulus_ui_cnf_request(MOD_CNF_ACT_SPIN, st.state, "Start spindle CW?",
                               "Spindle will start clockwise.", apply_spindle, NULL);
        break;
    case UI_QBTN_SPINDLE_CCW:
        s_spin_dir = 1;
        modulus_ui_cnf_request(MOD_CNF_ACT_SPIN, st.state, "Start spindle CCW?",
                               "Spindle will start counterclockwise.", apply_spindle, NULL);
        break;
    case UI_QBTN_MACRO:
        modulus_ui_cnf_request(MOD_CNF_ACT_MAC, st.state, "Run macro?",
                               "Sends the quick macro G-code line.", apply_macro_line, NULL);
        break;
    case UI_QBTN_COOLANT:
        modulus_zig_cmd_coolant_toggle();
        break;
    case UI_QBTN_FAN:
        s_fan_on = !s_fan_on;
        modulus_zig_cmd_fan_toggle();
        break;
    case UI_QBTN_MIST:
        modulus_zig_cmd_mist_toggle();
        break;
    case UI_QBTN_SINGLE_STEP:
        if (st.state != k_state_alarm && st.state != k_state_door && st.state != k_state_home) {
            modulus_zig_cmd_single_step();
        }
        break;
    case UI_QBTN_ZERO_ALL:
        modulus_ui_zero_all_request(st.state);
        break;
    case UI_QBTN_USER0:
    case UI_QBTN_USER1:
    case UI_QBTN_USER2:
    case UI_QBTN_USER3:
        modulus_ui_cnf_request(MOD_CNF_ACT_MAC, st.state, "Run custom macro?",
                               "Sends the assigned macro G-code.", apply_user_macro,
                               (void *)(uintptr_t)assign);
        break;
    default:
        break;
    }
}

static action_wide_t wide_btn(lv_obj_t *parent, modulus_ui_icon_id_t icon, const char *text,
                              lv_color_t bg, lv_color_t fg, lv_event_cb_t cb, bool stacked,
                              lv_coord_t h, bool grow)
{
    action_wide_t out = {};
    out.btn = lv_obj_create(parent);
    lv_obj_remove_style_all(out.btn);
    lv_obj_set_height(out.btn, h);
    if (grow) {
        lv_obj_set_flex_grow(out.btn, 1);
        lv_obj_set_width(out.btn, LV_SIZE_CONTENT);
    } else {
        lv_obj_set_width(out.btn, lv_pct(100));
    }
    lv_obj_set_style_bg_color(out.btn, bg, 0);
    lv_obj_set_style_bg_opa(out.btn, LV_OPA_COVER, 0);
    lv_obj_set_flex_flow(out.btn, stacked ? LV_FLEX_FLOW_COLUMN : LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(out.btn, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    if (stacked) {
        lv_obj_set_style_pad_row(out.btn, MOD_UI_SPACE_XS, 0);
    } else {
        lv_obj_set_style_pad_column(out.btn, 10, 0);
    }
    lv_obj_add_flag(out.btn, LV_OBJ_FLAG_CLICKABLE);
    modulus_ui_apply_pressed_state_layer_color(out.btn, modulus_ui_color_on_tinted_btn());
    modulus_ui_bind_press_morph(out.btn, MOD_UI_SHAPE_FULL, MOD_UI_SHAPE_LG_INC);
    lv_obj_add_event_cb(out.btn, cb, LV_EVENT_CLICKED, NULL);
    out.icon = modulus_ui_icon_create(out.btn, icon, MOD_UI_ICON_SZ_32);
    modulus_ui_icon_recolor(out.icon, modulus_ui_color_on_tinted_btn());
    out.lbl = lv_label_create(out.btn);
    lv_label_set_text(out.lbl, text);
    lv_obj_set_style_text_color(out.lbl, fg, 0);
    lv_obj_set_style_text_font(out.lbl, MOD_UI_FONT_TITLE_M, 0);
    return out;
}

static bool qbtn_assign_active(uint8_t assign, const modulus_cnc_status_t *st)
{
    const uint8_t a = st->accessories;
    switch (assign) {
    case UI_QBTN_SPINDLE_CW:
        return (a & k_acc_spindle_cw) != 0;
    case UI_QBTN_SPINDLE_CCW:
        return (a & k_acc_spindle_ccw) != 0;
    case UI_QBTN_MIST:
        return (a & k_acc_mist) != 0;
    case UI_QBTN_COOLANT:
        return (a & k_acc_flood) != 0;
    case UI_QBTN_FAN:
        return s_fan_on;
    case UI_QBTN_USER0:
    case UI_QBTN_USER1:
    case UI_QBTN_USER2:
    case UI_QBTN_USER3:
        return ui_qbtn_user_latched(assign);
    default:
        return false;
    }
}

static void qbtn_apply_active_style(int slot, bool active)
{
    lv_obj_t *btn = s_act.btn_quick[slot];
    if (!btn) {
        return;
    }
    if (active) {
        lv_obj_set_style_bg_color(btn, modulus_ui_color_primary_container(), 0);
        if (s_act.icon_quick[slot]) {
            modulus_ui_icon_recolor(s_act.icon_quick[slot], modulus_ui_color_primary());
        }
        if (s_act.lbl_quick[slot]) {
            lv_obj_set_style_text_color(s_act.lbl_quick[slot], modulus_ui_color_primary(), 0);
        }
    } else {
        lv_obj_set_style_bg_color(btn, modulus_ui_color_surface_container_high(), 0);
        if (s_act.icon_quick[slot]) {
            modulus_ui_icon_recolor(s_act.icon_quick[slot], modulus_ui_color_icon_chrome());
        }
        if (s_act.lbl_quick[slot]) {
            lv_obj_set_style_text_color(s_act.lbl_quick[slot], modulus_ui_color_on_surface_variant(), 0);
        }
    }
}

static void update_quick_button_states(const modulus_cnc_status_t *st)
{
    if (!st->connected) {
        s_fan_on = false;
    }
    for (int i = 0; i < UI_QBTN_MAX_SLOTS; i++) {
        if (!s_act.btn_quick[i]) {
            s_qbtn_active_cache[i] = 0xFF;
            continue;
        }
        const bool active = qbtn_assign_active(s_act.quick_assign[i], st);
        const uint8_t cached = active ? 1 : 0;
        if (s_qbtn_active_cache[i] == cached) {
            continue;
        }
        s_qbtn_active_cache[i] = cached;
        qbtn_apply_active_style(i, active);
    }
}

static void set_btn_dim(action_wide_t *a, bool dim)
{
    if (!a->btn) {
        return;
    }
    lv_obj_set_style_bg_opa(a->btn, dim ? LV_OPA_50 : LV_OPA_COVER, 0);
    if (dim) {
        lv_obj_remove_flag(a->btn, LV_OBJ_FLAG_CLICKABLE);
    } else {
        lv_obj_add_flag(a->btn, LV_OBJ_FLAG_CLICKABLE);
    }
}

static void build_quick_grid(void)
{
    if (!s_act.quick_grid) {
        return;
    }

    for (int i = 0; i < UI_QBTN_MAX_SLOTS; i++) {
        s_act.btn_quick[i] = NULL;
        s_act.lbl_quick[i] = NULL;
        s_act.icon_quick[i] = NULL;
        s_act.quick_assign[i] = ui_qbtn_slot_assign(i);
    }

    ui_qbtn_entry_t entries[UI_QBTN_MAX_SLOTS];
    const int active_count = ui_qbtn_collect_entries(entries, UI_QBTN_MAX_SLOTS);
    if (active_count == 0) {
        lv_obj_add_flag(s_act.quick_grid, LV_OBJ_FLAG_HIDDEN);
        lv_obj_clean(s_act.quick_grid);
        return;
    }

    lv_obj_remove_flag(s_act.quick_grid, LV_OBJ_FLAG_HIDDEN);

    ui_qbtn_build_opts_t opts = {
        .interactive = true,
        .click_cb = quick_click_cb,
        .panel_w = 280,
    };
    ui_qbtn_build_grid(s_act.quick_grid, entries, active_count, &opts);
    for (int i = 0; i < UI_QBTN_MAX_SLOTS; i++) {
        s_act.btn_quick[i] = opts.btn_by_slot[i];
        s_act.lbl_quick[i] = opts.lbl_by_slot[i];
        s_act.icon_quick[i] = opts.icon_by_slot[i];
        s_qbtn_active_cache[i] = 0xFF;
    }
    modulus_cnc_status_t st = {};
    modulus_zig_fill_cnc_status(&st);
    update_quick_button_states(&st);
}

void modulus_ui_actions_rebuild(void)
{
    build_quick_grid();
}

void modulus_ui_actions_create(lv_obj_t *parent)
{
    lv_obj_t *col = lv_obj_create(parent);
    lv_obj_remove_style_all(col);
    lv_obj_set_size(col, lv_pct(100), lv_pct(100));
    lv_obj_set_flex_flow(col, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(col, k_pad_section, 0);
    s_act.col = col;

    const lv_color_t tinted_fg = modulus_ui_color_on_tinted_btn();

    lv_obj_t *cycle_row = lv_obj_create(col);
    lv_obj_remove_style_all(cycle_row);
    lv_obj_set_width(cycle_row, lv_pct(100));
    lv_obj_set_height(cycle_row, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(cycle_row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(cycle_row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(cycle_row, MOD_UI_SPACE_XS, 0);
    lv_obj_remove_flag(cycle_row, LV_OBJ_FLAG_SCROLLABLE);

    s_act.cycle = wide_btn(cycle_row, MOD_UI_ICON_PLAY, "Cycle start", modulus_ui_color_cycle(),
                           tinted_fg, cycle_click_cb, true, k_wide_h, true);

    /* MD3 split / connected overflow: soft reset beside Cycle. */
    s_act.cycle_split = lv_obj_create(cycle_row);
    lv_obj_remove_style_all(s_act.cycle_split);
    lv_obj_set_size(s_act.cycle_split, 72, k_wide_h);
    lv_obj_set_style_bg_color(s_act.cycle_split, modulus_ui_color_secondary_container(), 0);
    lv_obj_set_style_bg_opa(s_act.cycle_split, LV_OPA_COVER, 0);
    lv_obj_add_flag(s_act.cycle_split, LV_OBJ_FLAG_CLICKABLE);
    modulus_ui_apply_pressed_state_layer_color(s_act.cycle_split,
                                               modulus_ui_color_on_secondary_container());
    modulus_ui_bind_press_morph(s_act.cycle_split, MOD_UI_SHAPE_FULL, MOD_UI_SHAPE_LG_INC);
    lv_obj_add_event_cb(s_act.cycle_split, cycle_split_cb, LV_EVENT_CLICKED, NULL);
    lv_obj_t *split_ico =
        modulus_ui_icon_create(s_act.cycle_split, MOD_UI_ICON_SPINDLE, MOD_UI_ICON_SZ_32);
    modulus_ui_icon_recolor(split_ico, modulus_ui_color_on_secondary_container());
    lv_obj_center(split_ico);

    s_act.hold = wide_btn(col, MOD_UI_ICON_PAUSE, "Feed hold", modulus_ui_color_hold(), tinted_fg,
                          hold_click_cb, true, k_wide_h, false);

    s_act.quick_grid = lv_obj_create(col);
    lv_obj_remove_style_all(s_act.quick_grid);
    lv_obj_set_width(s_act.quick_grid, lv_pct(100));
    lv_obj_set_flex_grow(s_act.quick_grid, 1);
    lv_obj_set_style_min_height(s_act.quick_grid, 120, 0);
    lv_obj_add_flag(s_act.quick_grid, LV_OBJ_FLAG_OVERFLOW_VISIBLE);
    lv_obj_set_scrollbar_mode(s_act.quick_grid, LV_SCROLLBAR_MODE_OFF);
    build_quick_grid();

    s_act.home = wide_btn(col, MOD_UI_ICON_HOUSE_FILL, "Home all", modulus_ui_color_home_all(), tinted_fg,
                          home_click_cb, false, k_home_h, false);
}

void modulus_ui_actions_theme_refresh(void)
{
    if (!s_act.col) {
        return;
    }
    const lv_color_t fg = modulus_ui_color_on_tinted_btn();
    for (int i = 0; i < UI_QBTN_MAX_SLOTS; i++) {
        s_qbtn_active_cache[i] = 0xFF;
    }
    modulus_cnc_status_t st = {};
    modulus_zig_fill_cnc_status(&st);
    update_quick_button_states(&st);
    if (s_act.cycle.lbl) {
        lv_obj_set_style_text_color(s_act.cycle.lbl, fg, 0);
        modulus_ui_icon_recolor(s_act.cycle.icon, fg);
    }
    if (s_act.hold.lbl) {
        lv_obj_set_style_text_color(s_act.hold.lbl, fg, 0);
        modulus_ui_icon_recolor(s_act.hold.icon, fg);
    }
    if (s_act.home.lbl) {
        lv_obj_set_style_text_color(s_act.home.lbl, fg, 0);
        modulus_ui_icon_recolor(s_act.home.icon, fg);
        lv_obj_set_style_bg_color(s_act.home.btn, MOD_UI_COLOR_SEMANTIC_HOME, 0);
    }
    if (s_act.cycle.btn) {
        lv_obj_set_style_bg_color(s_act.cycle.btn, MOD_UI_COLOR_SEMANTIC_CYCLE, 0);
    }
    if (s_act.cycle_split) {
        lv_obj_set_style_bg_color(s_act.cycle_split, modulus_ui_color_secondary_container(), 0);
        lv_obj_t *ico = lv_obj_get_child(s_act.cycle_split, 0);
        if (ico) {
            modulus_ui_icon_recolor(ico, modulus_ui_color_on_secondary_container());
        }
    }
    if (s_act.hold.btn) {
        lv_obj_set_style_bg_color(s_act.hold.btn, MOD_UI_COLOR_SEMANTIC_HOLD, 0);
    }
    s_actions_state_cache = 0xFF;
    modulus_ui_actions_update(&st);
}

void modulus_ui_actions_update(const modulus_cnc_status_t *st)
{
    if (!st || !s_act.cycle.lbl) {
        return;
    }
    update_quick_button_states(st);

    if (st->state == s_actions_state_cache) {
        return;
    }
    s_actions_state_cache = st->state;

    const bool running = (st->state == k_state_run);
    const bool held = (st->state == k_state_hold);
    const bool alarm = (st->state == k_state_alarm);
    const bool door = (st->state == k_state_door);
    const bool check = (st->state == k_state_check);
    const bool jogging = (st->state == k_state_jog);
    const bool homing = (st->state == k_state_home);
    const bool idle = (st->state == k_state_idle) || (st->state == 0) || check;
    const lv_color_t fg = modulus_ui_color_on_tinted_btn();

    if (alarm) {
        modulus_ui_icon_set(s_act.cycle.icon, MOD_UI_ICON_PLAY, MOD_UI_ICON_SZ_32);
        modulus_ui_icon_recolor(s_act.cycle.icon, fg);
        modulus_ui_label_set_text_if_changed(s_act.cycle.lbl, "Clear alarm");
        lv_obj_set_style_bg_color(s_act.cycle.btn, modulus_ui_color_error(), 0);
        set_btn_dim(&s_act.cycle, false);

        modulus_ui_icon_set(s_act.hold.icon, MOD_UI_ICON_STOP, MOD_UI_ICON_SZ_32);
        modulus_ui_icon_recolor(s_act.hold.icon, fg);
        modulus_ui_label_set_text_if_changed(s_act.hold.lbl, "Soft reset");
        lv_obj_set_style_bg_color(s_act.hold.btn, modulus_ui_color_error(), 0);
        set_btn_dim(&s_act.hold, false);

        set_btn_dim(&s_act.home, true);
        return;
    }

    if (door) {
        modulus_ui_icon_set(s_act.cycle.icon, MOD_UI_ICON_PLAY, MOD_UI_ICON_SZ_32);
        modulus_ui_icon_recolor(s_act.cycle.icon, fg);
        modulus_ui_label_set_text_if_changed(s_act.cycle.lbl, "Door open");
        lv_obj_set_style_bg_color(s_act.cycle.btn, MOD_UI_COLOR_SEMANTIC_CYCLE, 0);
        set_btn_dim(&s_act.cycle, true);

        modulus_ui_icon_set(s_act.hold.icon, MOD_UI_ICON_PAUSE, MOD_UI_ICON_SZ_32);
        modulus_ui_icon_recolor(s_act.hold.icon, fg);
        modulus_ui_label_set_text_if_changed(s_act.hold.lbl, "Feed hold");
        lv_obj_set_style_bg_color(s_act.hold.btn, MOD_UI_COLOR_SEMANTIC_HOLD, 0);
        set_btn_dim(&s_act.hold, false);

        set_btn_dim(&s_act.home, true);
        return;
    }

    if (homing) {
        modulus_ui_label_set_text_if_changed(s_act.cycle.lbl, "Homing...");
        set_btn_dim(&s_act.cycle, true);
        set_btn_dim(&s_act.hold, true);
        set_btn_dim(&s_act.home, true);
        return;
    }

    modulus_ui_icon_set(s_act.cycle.icon, running ? MOD_UI_ICON_STOP : MOD_UI_ICON_PLAY, MOD_UI_ICON_SZ_32);
    modulus_ui_icon_recolor(s_act.cycle.icon, fg);
    modulus_ui_label_set_text_if_changed(s_act.cycle.lbl, running ? "Stop cycle" : "Cycle start");
    lv_obj_set_style_bg_color(s_act.cycle.btn,
                              running ? MOD_UI_COLOR_SEMANTIC_STOP : MOD_UI_COLOR_SEMANTIC_CYCLE, 0);
    set_btn_dim(&s_act.cycle, jogging);
    if (idle) {
        lv_obj_set_style_bg_opa(s_act.cycle.btn, LV_OPA_COVER, 0);
    } else if (running) {
        lv_obj_set_style_bg_opa(s_act.cycle.btn, LV_OPA_70, 0);
    }

    modulus_ui_icon_set(s_act.hold.icon, held ? MOD_UI_ICON_PLAY : MOD_UI_ICON_PAUSE, MOD_UI_ICON_SZ_32);
    modulus_ui_icon_recolor(s_act.hold.icon, fg);
    modulus_ui_label_set_text_if_changed(s_act.hold.lbl, held ? "Feed resume" : "Feed hold");
    lv_obj_set_style_bg_color(s_act.hold.btn,
                              held ? MOD_UI_COLOR_SEMANTIC_RESUME : MOD_UI_COLOR_SEMANTIC_HOLD, 0);
    set_btn_dim(&s_act.hold, false);
    if (idle || jogging) {
        lv_obj_set_style_bg_opa(s_act.hold.btn, LV_OPA_70, 0);
    } else if (running || held) {
        lv_obj_set_style_bg_opa(s_act.hold.btn, LV_OPA_COVER, 0);
    }

    set_btn_dim(&s_act.home, running || jogging);
    if (!running && !jogging) {
        lv_obj_set_style_bg_color(s_act.home.btn, MOD_UI_COLOR_SEMANTIC_HOME, 0);
        lv_obj_set_style_bg_opa(s_act.home.btn, LV_OPA_COVER, 0);
    }
}
