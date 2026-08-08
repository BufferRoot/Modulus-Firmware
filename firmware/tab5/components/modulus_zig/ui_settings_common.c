#include "ui_settings_common.h"
#include "ui_settings_priv.h"
#include "ui_internal.h"
#include "ui_icons.h"
#include "nvs_shim.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *const k_baud[] = {
    "9600", "19200", "38400", "57600", "115200", "250000", "1000000",
};

const char *settings_baud_str(uint8_t idx)
{
    return (idx <= 6) ? k_baud[idx] : k_baud[4];
}

static const char *const k_cnc_transport_names[SETTINGS_CNC_TRANSPORT_COUNT] = {
    "ESP-NOW", "WebSocket", "Telnet", "Serial USB",
    "RS-485",  "BLE HID",   "I2C",    "CAN Bus",
};

const char *settings_cnc_transport_name(uint8_t idx)
{
    if (idx >= SETTINGS_CNC_TRANSPORT_COUNT) {
        return "Off";
    }
    return k_cnc_transport_names[idx];
}

const char *settings_cnc_transport_dropdown_opts(void)
{
    static char opts[96];
    static bool built = false;
    if (!built) {
        size_t pos = 0;
        for (int i = 0; i < SETTINGS_CNC_TRANSPORT_COUNT; i++) {
            const char *name = k_cnc_transport_names[i];
            const size_t nlen = strlen(name);
            if (i > 0 && pos + 1 < sizeof(opts)) {
                opts[pos++] = '\n';
            }
            if (pos + nlen < sizeof(opts)) {
                memcpy(opts + pos, name, nlen);
                pos += nlen;
            }
        }
        opts[pos] = '\0';
        built = true;
    }
    return opts;
}

static const char *const k_cnc_protocol_names[SETTINGS_CNC_PROTOCOL_COUNT] = {
    "GrblHAL", "Grbl", "FluidNC", "LinuxCNC", "Mach3/Mach4", "Masso",
};

const char *settings_cnc_protocol_name(uint8_t idx)
{
    if (idx >= SETTINGS_CNC_PROTOCOL_COUNT) {
        return "GrblHAL";
    }
    return k_cnc_protocol_names[idx];
}

/* Quick-macro slot storage: NVS "cnc_mac<slot>" = "Label|on|off|icon".
 * icon = decimal modulus_ui_icon_id_t (optional; default SCROLL).
 * Empty off-gcode = momentary button; non-empty = toggle. Returns false when
 * the slot is unset. */
bool settings_macro_slot_load(uint8_t slot, char *name, size_t name_len,
                              char *on, size_t on_len, char *off, size_t off_len,
                              uint8_t *icon_out)
{
    if (slot >= SETTINGS_MACRO_SLOTS || !name || !on || !off) {
        return false;
    }
    char key[12];
    snprintf(key, sizeof(key), "cnc_mac%u", (unsigned)slot);
    char raw[192];
    if (!modulus_nvs_get_str(key, raw, sizeof(raw)) || raw[0] == '\0') {
        return false;
    }
    name[0] = on[0] = off[0] = '\0';
    if (icon_out) {
        *icon_out = (uint8_t)MOD_UI_ICON_SCROLL;
    }
    char *save = NULL;
    const char *n = strtok_r(raw, "|", &save);
    const char *o = strtok_r(NULL, "|", &save);
    const char *f = strtok_r(NULL, "|", &save);
    const char *ic = strtok_r(NULL, "|", &save);
    if (!n || !o || o[0] == '\0') {
        return false;
    }
    strncpy(name, n, name_len - 1);
    name[name_len - 1] = '\0';
    strncpy(on, o, on_len - 1);
    on[on_len - 1] = '\0';
    if (f) {
        strncpy(off, f, off_len - 1);
        off[off_len - 1] = '\0';
    }
    if (icon_out && ic && ic[0]) {
        int v = atoi(ic);
        if (v >= 0 && v < (int)MOD_UI_ICON_COUNT) {
            *icon_out = (uint8_t)v;
        }
    }
    return true;
}

bool settings_macro_slot_save(uint8_t slot, const char *name, const char *on, const char *off,
                              uint8_t icon)
{
    if (slot >= SETTINGS_MACRO_SLOTS || !name || !on || name[0] == '\0' || on[0] == '\0') {
        return false;
    }
    char n[16], o[64], f[64];
    strncpy(n, name, sizeof(n) - 1);
    n[sizeof(n) - 1] = '\0';
    strncpy(o, on, sizeof(o) - 1);
    o[sizeof(o) - 1] = '\0';
    f[0] = '\0';
    if (off) {
        strncpy(f, off, sizeof(f) - 1);
        f[sizeof(f) - 1] = '\0';
    }
    for (char *p = n; *p; p++) {
        if (*p == '|') {
            *p = ' ';
        }
    }
    for (char *p = o; *p; p++) {
        if (*p == '|') {
            *p = ' ';
        }
    }
    for (char *p = f; *p; p++) {
        if (*p == '|') {
            *p = ' ';
        }
    }
    if (icon >= (uint8_t)MOD_UI_ICON_COUNT) {
        icon = (uint8_t)MOD_UI_ICON_SCROLL;
    }
    char raw[192];
    char key[12];
    snprintf(raw, sizeof(raw), "%s|%s|%s|%u", n, o, f, (unsigned)icon);
    snprintf(key, sizeof(key), "cnc_mac%u", (unsigned)slot);
    modulus_nvs_set_str(key, raw);
    return true;
}

void settings_macro_slot_clear(uint8_t slot)
{
    if (slot >= SETTINGS_MACRO_SLOTS) {
        return;
    }
    char key[12];
    snprintf(key, sizeof(key), "cnc_mac%u", (unsigned)slot);
    modulus_nvs_set_str(key, "");
}

int settings_macro_slot_first_free(void)
{
    for (uint8_t slot = 0; slot < SETTINGS_MACRO_SLOTS; slot++) {
        char name[16], on[64], off[64];
        if (!settings_macro_slot_load(slot, name, sizeof(name), on, sizeof(on), off, sizeof(off),
                                      NULL)) {
            return (int)slot;
        }
    }
    return -1;
}

bool settings_cnc_protocol_implemented(uint8_t idx)
{
    return idx == 0 || idx == SETTINGS_CNC_PROTO_GRBL || idx == SETTINGS_CNC_PROTO_FLUIDNC ||
           idx == SETTINGS_CNC_PROTO_LINUXCNC || idx == SETTINGS_CNC_PROTO_MACH3 ||
           idx == SETTINGS_CNC_PROTO_MASSO;
}

bool settings_cnc_protocol_supports_dump(uint8_t idx)
{
    /* GrblHAL / Grbl / FluidNC ($$) + LinuxCNC (get ini). */
    return idx == 0 || idx == SETTINGS_CNC_PROTO_GRBL || idx == SETTINGS_CNC_PROTO_FLUIDNC ||
           idx == SETTINGS_CNC_PROTO_LINUXCNC;
}

bool settings_cnc_protocol_supports_envelope_paste(uint8_t idx)
{
    return idx == SETTINGS_CNC_PROTO_MACH3 || idx == SETTINGS_CNC_PROTO_MASSO;
}

uint8_t settings_cnc_protocol_preferred_transport(uint8_t idx)
{
    /* Must match cnc_config.preferredConnection / transport dropdown order. */
    switch (idx) {
    case SETTINGS_CNC_PROTO_LINUXCNC:
    case SETTINGS_CNC_PROTO_MACH3:
        return 2; /* Telnet */
    case SETTINGS_CNC_PROTO_FLUIDNC:
    case SETTINGS_CNC_PROTO_MASSO:
        return 1; /* WebSocket (network placeholder for Masso Link) */
    default:
        return 4; /* RS-485 */
    }
}

const char *settings_cnc_protocol_dropdown_opts(void)
{
    static char opts[128];
    static bool built = false;
    if (!built) {
        size_t pos = 0;
        for (int i = 0; i < SETTINGS_CNC_PROTOCOL_COUNT; i++) {
            const char *name = k_cnc_protocol_names[i];
            const size_t nlen = strlen(name);
            if (i > 0 && pos + 1 < sizeof(opts)) {
                opts[pos++] = '\n';
            }
            if (pos + nlen < sizeof(opts)) {
                memcpy(opts + pos, name, nlen);
                pos += nlen;
            }
        }
        opts[pos] = '\0';
        built = true;
    }
    return opts;
}

/* ── Confirm modal ───────────────────────────────────────────────── */

static lv_obj_t *s_confirm = NULL;
static settings_confirm_fn s_confirm_cb = NULL;
static settings_confirm_fn s_cancel_cb = NULL;
static bool s_confirm_destructive = false;

void settings_confirm_theme_refresh(void)
{
    modulus_ui_dialog_theme_refresh(s_confirm);
}

static void confirm_exit_ready(lv_anim_t *a)
{
    lv_obj_t *dlg = lv_anim_get_user_data(a);
    if (dlg) {
        lv_obj_delete(dlg);
    }
}

void settings_confirm_hide(void)
{
    if (!s_confirm) {
        s_confirm_cb = NULL;
        s_cancel_cb = NULL;
        s_confirm_destructive = false;
        return;
    }
    lv_obj_t *dlg = s_confirm;
    s_confirm = NULL;
    s_confirm_cb = NULL;
    s_cancel_cb = NULL;
    s_confirm_destructive = false;
    lv_obj_t *card = lv_obj_get_child(dlg, 0);
    if (card && modulus_ui_motion_smooth()) {
        modulus_ui_motion_dialog_exit(card, confirm_exit_ready, dlg);
        return;
    }
    lv_obj_delete(dlg);
}

static void confirm_cancel_cb(lv_event_t *e)
{
    (void)e;
    settings_confirm_fn cb = s_cancel_cb;
    settings_confirm_hide();
    if (cb) {
        cb();
    }
}

static void confirm_yes_cb(lv_event_t *e)
{
    (void)e;
    settings_confirm_fn cb = s_confirm_cb;
    settings_confirm_hide();
    if (cb) {
        cb();
    }
}

void settings_confirm_show(const char *title, const char *body,
                           const char *confirm_label, bool destructive,
                           settings_confirm_fn on_confirm,
                           settings_confirm_fn on_cancel)
{
    settings_confirm_hide();
    s_confirm_cb = on_confirm;
    s_cancel_cb = on_cancel;
    s_confirm_destructive = destructive;

    s_confirm = modulus_ui_dialog_scrim_create();

    lv_obj_t *card = modulus_ui_dialog_card_create(s_confirm, MOD_UI_DIALOG_W_COMPACT, 0);
    lv_obj_center(card);
    lv_obj_set_flex_align(card, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);

    modulus_ui_dialog_header(card, title, confirm_cancel_cb, NULL);
    lv_obj_t *msg = modulus_ui_dialog_supporting(card, body);
    lv_obj_set_style_text_align(msg, LV_TEXT_ALIGN_CENTER, 0);

    lv_obj_t *row = modulus_ui_dialog_actions(card, false);
    modulus_ui_dialog_action_btn(row, "Cancel", MOD_UI_DIALOG_BTN_TONAL, confirm_cancel_cb, NULL);
    modulus_ui_dialog_action_btn(row, confirm_label,
                                 destructive ? MOD_UI_DIALOG_BTN_DESTRUCTIVE
                                             : MOD_UI_DIALOG_BTN_FILLED,
                                 confirm_yes_cb, NULL);

    modulus_ui_dialog_scrim_bind_dismiss(s_confirm, confirm_cancel_cb, NULL);
    modulus_ui_motion_dialog_enter(card);
}

/* ── Extra row types ─────────────────────────────────────────────── */

lv_obj_t *settings_back_row(lv_obj_t *parent, const char *title, lv_event_cb_t cb)
{
    lv_obj_t *row = settings_action_row(parent, title, "");
    lv_obj_t *lbl = lv_obj_get_child(row, 0);
    if (lbl) {
        lv_label_set_text(lbl, "< Back");
        lv_obj_set_style_text_color(lbl, modulus_ui_color_primary(), 0);
    }
    lv_obj_t *rg = lv_obj_get_child(row, 1);
    if (rg) {
        lv_obj_t *sub = lv_label_create(rg);
        lv_label_set_text(sub, title);
        lv_obj_set_style_text_color(sub, modulus_ui_color_on_surface_variant(), 0);
        lv_obj_set_style_text_font(sub, MOD_UI_FONT_BODY_M, 0);
    }
    settings_bind_menu_click(row, cb, NULL);
    return row;
}

lv_obj_t *settings_coming_soon_row(lv_obj_t *parent, const char *label)
{
    lv_obj_t *row = settings_row_base(parent, 48, false);
    settings_row_label(row, label);
    lv_obj_t *tag = lv_label_create(row);
    lv_label_set_text(tag, "Coming soon");
    lv_obj_set_style_text_color(tag, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(tag, MOD_UI_FONT_BODY_M, 0);
    return row;
}

lv_obj_t *settings_not_implemented_row(lv_obj_t *parent, const char *label,
                                       const char *status)
{
    lv_obj_t *row = settings_row_base(parent, 48, false);
    settings_row_label(row, label);
    lv_obj_t *tag = lv_label_create(row);
    lv_label_set_text(tag, status ? status : "Not implemented");
    lv_obj_set_style_text_color(tag, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(tag, MOD_UI_FONT_BODY_M, 0);
    return row;
}

static void link_tab_cb(lv_event_t *e)
{
    const int tab = (int)(intptr_t)lv_event_get_user_data(e);
    modulus_ui_settings_select_tab(tab);
}

lv_obj_t *settings_link_tab_row(lv_obj_t *parent, const char *label,
                                const char *value, int target_tab)
{
    lv_obj_t *row = settings_action_row(parent, label, value);
    settings_bind_menu_click(row, link_tab_cb,
                        (void *)(intptr_t)target_tab);
    return row;
}

static void reset_click_cb(lv_event_t *e)
{
    const settings_reset_ctx_t *ctx = lv_event_get_user_data(e);
    settings_confirm_show(ctx->title, ctx->body, "Reset", true, ctx->fn, NULL);
}

lv_obj_t *settings_reset_row(lv_obj_t *parent, const char *label,
                             settings_reset_ctx_t *ctx)
{
    lv_obj_t *row = settings_destructive_row(parent, label, "Reset");
    settings_bind_menu_click(row, reset_click_cb, ctx);
    return row;
}

typedef struct {
    bool *expanded;
    settings_rebuild_fn rebuild_fn;
} expand_ctx_t;

static void expand_toggle_cb(lv_event_t *e)
{
    expand_ctx_t *ctx = lv_event_get_user_data(e);
    *ctx->expanded = !*ctx->expanded;
    if (ctx->rebuild_fn) {
        ctx->rebuild_fn();
    }
}

static void free_expand_ctx_cb(lv_event_t *e)
{
    lv_free(lv_event_get_user_data(e));
}

lv_obj_t *settings_expandable_link(lv_obj_t *parent, const char *show_label,
                                   const char *hide_label, bool *expanded,
                                   settings_rebuild_fn rebuild_fn)
{
    /* U4: per-row context. A single shared static was aliased by all 14
     * callers, so every expandable section toggled/rebuilt the last-built one
     * instead of its own. The ctx is owned by the row and freed on
     * LV_EVENT_DELETE (which fires on lv_obj_clean during theme refresh). */
    expand_ctx_t *ctx = lv_malloc(sizeof *ctx);
    if (!ctx) {
        return NULL;
    }
    ctx->expanded = expanded;
    ctx->rebuild_fn = rebuild_fn;
    const char *lbl = *expanded ? hide_label : show_label;
    lv_obj_t *row = settings_action_row(parent, lbl, "");
    if (!row) {
        lv_free(ctx);
        return NULL;
    }
    settings_bind_menu_click(row, expand_toggle_cb, ctx);
    lv_obj_add_event_cb(row, free_expand_ctx_cb, LV_EVENT_DELETE, ctx);
    return row;
}
