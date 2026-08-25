//! MD3-ish paint primitives (no LVGL) — switches, nav destinations, chips.

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const icons_phosphor = @import("icons_phosphor.zig");
const color = @import("color.zig");

pub const switch_w: i32 = 52;
pub const switch_h: i32 = 32;
pub const thumb: i32 = 24;

const scrim_black = color.Rgb565{ .r = 0, .g = 0, .b = 0 };

/// Opaque MD3 scrim fill (no underlay) — tonal stand-in for black@32% over surface.
pub fn fillScrim(logical: *fb.LogicalFb, theme: tokens.Theme) void {
    fillScrimRect(logical, .{
        .x = 0,
        .y = 0,
        .w = tokens.Logical.width,
        .h = tokens.Logical.height,
    }, theme);
}

pub fn fillScrimRect(logical: *fb.LogicalFb, r: geom.Rect, theme: tokens.Theme) void {
    logical.fillRect(r, theme.scrim);
}

/// Blend MD3 scrim over already-painted underlay (preferred for QS / keyboard / dialogs).
pub fn paintScrimOver(logical: *fb.LogicalFb, r: geom.Rect, theme: tokens.Theme) void {
    _ = theme;
    logical.blendRect(r, scrim_black, tokens.Theme.scrim_alpha);
}

/// Trailing switch x in a settings content row.
pub fn switchTrailingX(row_x: i32, row_w: i32) i32 {
    return row_x + row_w - switch_w - tokens.Space.md;
}

/// MD3 switch — `progress` 0=off .. 1=on (spring-driven).
/// Off: small thumb. On: larger thumb with optional check *inside* the handle.
/// Track color blends continuously (no mid-morph snap at 0.5 — that read as choppy).
pub fn drawSwitch(
    logical: *fb.LogicalFb,
    x: i32,
    y: i32,
    progress: f32,
    theme: tokens.Theme,
    icons: bool,
    enabled: bool,
) void {
    const t = std.math.clamp(progress, 0, 1);
    const on = t >= 0.5;
    const track: geom.Rect = .{ .x = x, .y = y, .w = switch_w, .h = switch_h };
    const rad = tokens.Shape.full;

    if (!enabled) {
        const track_c = if (on) theme.primary_container else theme.surface_container_high;
        fillRoundRect(logical, track, rad, track_c);
        if (!on) strokeRoundRect(logical, track, rad, theme.outline_variant, 1);
    } else {
        const off_track = theme.surface_container_highest;
        const on_track = theme.primary;
        const a: u8 = @intFromFloat(t * 255.0);
        fillRoundRect(logical, track, rad, color.blendRgb565(off_track, on_track, a));
        if (t < 0.85) {
            const stroke_a: u8 = @intFromFloat((1.0 - t) * 255.0);
            strokeRoundRect(logical, track, rad, color.blendRgb565(theme.outline, on_track, stroke_a), 1);
        }
    }

    // MD3: unselected handle ~16dp, selected ~24dp (morph with progress).
    const r_off: f32 = 8;
    const r_on: f32 = 12;
    const thr = r_off + (r_on - r_off) * t;
    const thr_i: i32 = @intFromFloat(thr);
    const pad: f32 = 4;
    const travel = @as(f32, @floatFromInt(switch_w)) - pad * 2 - thr * 2;
    const cx = x + @as(i32, @intFromFloat(pad + thr + travel * t));
    const cy = y + @divTrunc(switch_h, 2);
    const thumb_off = theme.outline;
    const thumb_on = theme.on_primary;
    const thumb_c = if (!enabled)
        theme.on_surface_variant
    else
        color.blendRgb565(thumb_off, thumb_on, @intFromFloat(t * 255.0));
    fillCircle(logical, cx, cy, thr_i, thumb_c);

    // Check inside selected handle (not on track).
    if (enabled and icons and t > 0.55) {
        const icon_c = color.blendRgb565(theme.on_surface_variant, theme.primary, @intFromFloat(((t - 0.55) / 0.45) * 255.0));
        icons_phosphor.drawCenteredScaled(logical, cx, cy, .check, icon_c, 14);
    }
}

pub fn switchHitRect(x: i32, y: i32) geom.Rect {
    // Visual 52×32; expand to ≥48dp touch.
    const pad_y = @divTrunc(tokens.Logical.touch_min - switch_h, 2);
    return .{ .x = x - 4, .y = y - pad_y, .w = switch_w + 8, .h = tokens.Logical.touch_min };
}

/// Instant on/off convenience.
pub fn drawSwitchBool(logical: *fb.LogicalFb, x: i32, y: i32, on: bool, theme: tokens.Theme) void {
    drawSwitch(logical, x, y, if (on) 1 else 0, theme, true, true);
}

pub fn switchRect(x: i32, y: i32) geom.Rect {
    return switchHitRect(x, y);
}

pub fn drawChevronRight(logical: *fb.LogicalFb, cx: i32, cy: i32, half: i32, c: @import("color.zig").Rgb565) void {
    var i: i32 = -half;
    while (i <= half) : (i += 1) {
        const inset: i32 = @divTrunc(@as(i32, @intCast(@abs(i))), 2);
        logical.fillRect(.{ .x = cx - half + inset, .y = cy + i, .w = half - inset + 1, .h = 1 }, c);
    }
}

/// MD3 search bar trailing clear slot (≈48dp icon button).
pub const search_clear_w: i32 = tokens.Logical.touch_min;
pub const search_result_row_h: i32 = 44;

pub fn searchClearHit(bar: geom.Rect) geom.Rect {
    return .{
        .x = bar.x + bar.w - search_clear_w,
        .y = bar.y,
        .w = search_clear_w,
        .h = bar.h,
    };
}

pub fn searchResultsPanel(bar: geom.Rect) geom.Rect {
    return .{
        .x = bar.x,
        .y = bar.y + bar.h + tokens.Space.xs,
        .w = bar.w,
        .h = @min(220, search_result_row_h * 5 + 24),
    };
}

fn drawClearGlyph(logical: *fb.LogicalFb, cx: i32, cy: i32, half: i32, fg: @import("color.zig").Rgb565) void {
    var i: i32 = -half;
    while (i <= half) : (i += 1) {
        put(logical, cx + i, cy + i, fg);
        put(logical, cx + i, cy - i, fg);
        put(logical, cx + i + 1, cy + i, fg);
        put(logical, cx + i + 1, cy - i, fg);
    }
}

/// MD3 search bar — elev 3 pill, Phosphor search, body_l; clear when non-empty.
pub fn drawSearchField(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    text: []const u8,
    focused: bool,
    theme: tokens.Theme,
) void {
    drawSearchBar(logical, r, text, "Search tabs", focused, theme);
}

pub fn drawSearchBar(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    text: []const u8,
    placeholder: []const u8,
    focused: bool,
    theme: tokens.Theme,
) void {
    const rad = tokens.Shape.full;
    fillRoundRect(logical, r, rad, theme.elev(3));
    if (focused) {
        strokeRoundRect(logical, r, rad, theme.primary, 2);
    }
    const icy = r.y + @divTrunc(r.h, 2);
    icons_phosphor.drawCentered(logical, r.x + tokens.Space.md + 12, icy, .search, theme.on_surface_variant);
    const empty = text.len == 0;
    const shown = if (empty) placeholder else text;
    const fg = if (empty) theme.on_surface_variant else theme.on_surface;
    const tx = r.x + tokens.Space.md + 32;
    font.drawTextRole(logical, tx, r.y + @divTrunc(r.h - font.faceHeight(.ui16), 2), shown, fg, .body_l);
    if (!empty) {
        const ch = searchClearHit(r);
        drawClearGlyph(logical, ch.x + @divTrunc(ch.w, 2), icy, 6, theme.on_surface_variant);
    }
}

pub fn drawSearchFieldFocused(logical: *fb.LogicalFb, r: geom.Rect, text: []const u8, theme: tokens.Theme) void {
    drawSearchField(logical, r, text, true, theme);
}

/// MD3 outlined text field — `surface` fill, `Shape.sm`, idle `outline_variant` /
/// focus `primary` / error `err`. Empty uses placeholder + `on_surface_variant`.
pub fn drawOutlinedTextField(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    text: []const u8,
    placeholder: []const u8,
    focused: bool,
    enabled: bool,
    err: bool,
    theme: tokens.Theme,
) void {
    drawTextFieldChrome(logical, r, text, placeholder, .{
        .filled = false,
        .focused = focused,
        .enabled = enabled,
        .err = err,
        .center = false,
        .role = .body_l,
    }, theme);
}

/// Centered outlined field (date/time segment chips).
pub fn drawOutlinedTextFieldCentered(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    text: []const u8,
    focused: bool,
    theme: tokens.Theme,
    role: tokens.TypeRole,
) void {
    drawTextFieldChrome(logical, r, text, "", .{
        .filled = false,
        .focused = focused,
        .enabled = true,
        .err = false,
        .center = true,
        .role = role,
    }, theme);
}

/// MD3 filled text field — tonal container + outline; focus stroke primary.
pub fn drawFilledTextField(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    text: []const u8,
    placeholder: []const u8,
    focused: bool,
    enabled: bool,
    theme: tokens.Theme,
) void {
    drawTextFieldChrome(logical, r, text, placeholder, .{
        .filled = true,
        .focused = focused,
        .enabled = enabled,
        .err = false,
        .center = false,
        .role = .body_l,
    }, theme);
}

const TextFieldOpts = struct {
    filled: bool,
    focused: bool,
    enabled: bool,
    err: bool,
    center: bool,
    role: tokens.TypeRole,
};

fn drawTextFieldChrome(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    text: []const u8,
    placeholder: []const u8,
    opts: TextFieldOpts,
    theme: tokens.Theme,
) void {
    const rad = tokens.Shape.sm;
    const fill = if (!opts.enabled)
        theme.surface_container_low
    else if (opts.filled)
        theme.surface_container_highest
    else
        theme.surface;
    fillRoundRect(logical, r, rad, fill);

    const stroke_c = if (!opts.enabled)
        theme.outline_variant
    else if (opts.err)
        theme.err
    else if (opts.focused)
        theme.primary
    else
        theme.outline_variant;
    const stroke_w: i32 = if (opts.enabled and (opts.focused or opts.err)) 2 else 1;
    strokeRoundRect(logical, r, rad, stroke_c, stroke_w);

    const empty = text.len == 0;
    const shown = if (empty) placeholder else text;
    if (shown.len == 0) return;
    const fg = if (!opts.enabled or empty) theme.on_surface_variant else theme.on_surface;
    const face_h = font.faceHeight(font.faceForRole(opts.role));
    const ty = r.y + @divTrunc(r.h - face_h, 2);
    const tx = if (opts.center)
        r.x + @divTrunc(r.w - font.textWidthStr(shown, opts.role), 2)
    else
        r.x + tokens.Space.md;
    font.drawTextRole(logical, tx, ty, shown, fg, opts.role);
}

/// Modulus settings category — icon + label, selected = primary_container pill.
pub fn drawSettingsCategory(
    logical: *fb.LogicalFb,
    x: i32,
    y: i32,
    w: i32,
    h: i32,
    label: []const u8,
    selected: bool,
    theme: tokens.Theme,
) void {
    if (selected) {
        fillRoundRect(logical, .{ .x = x + 10, .y = y + 4, .w = w - 20, .h = h - 8 }, 16, theme.secondary_container);
    }
    const fg = if (selected) theme.on_secondary_container else theme.on_surface;
    font.drawTextRole(logical, x + 52, y + @divTrunc(h - font.faceHeight(.ui16), 2), label, fg, .title_s);
}

/// Nav rail destination — selected = tonal pill + label.
pub fn drawNavItem(
    logical: *fb.LogicalFb,
    x: i32,
    y: i32,
    w: i32,
    label: []const u8,
    selected: bool,
    theme: tokens.Theme,
) void {
    const h: i32 = 56;
    if (selected) {
        fillRoundRect(logical, .{ .x = x + 8, .y = y, .w = w - 16, .h = h }, 16, theme.primary_container);
    }
    const tw = font.textWidth(label.len, 1);
    const tx = x + @divTrunc(w - tw, 2);
    const ty = y + 22;
    const fg = if (selected) theme.on_primary_container else theme.on_surface_variant;
    font.drawText(logical, tx, ty, label, fg, 1);
}

/// MD3 common-button emphasis + CNC rail roles (color-locked cycle/hold/home/stop).
pub const ButtonKind = enum {
    filled,
    tonal,
    elevated,
    outlined,
    text,
    danger,
    danger_tonal,
    primary_container,
    secondary,
    tertiary,
    tertiary_container,
    cycle,
    hold,
    home,
    stop,
    feed_resume,
};

/// MD3 interaction states for common buttons.
pub const ButtonState = enum { enabled, hovered, focused, pressed, disabled };

/// Icon-button container styles (Compose IconButton variants).
pub const IconButtonStyle = enum { standard, filled, tonal, outlined };

fn buttonRadius(r: geom.Rect) i32 {
    return @min(tokens.Shape.button, @divTrunc(@min(r.w, r.h), 2));
}

fn buttonLabelY(r: geom.Rect) i32 {
    const fh = font.faceHeight(font.faceForRole(.label_l));
    return r.y + @divTrunc(r.h - fh, 2);
}

pub fn buttonStateAlpha(state: ButtonState) u8 {
    return switch (state) {
        .enabled, .disabled => 0,
        .hovered => tokens.StateLayer.hover,
        .focused => tokens.StateLayer.focus,
        .pressed => tokens.StateLayer.press,
    };
}

/// Fill + outline + state/ripple for a button; returns content ink. No label.
pub fn drawButtonSurface(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    kind: ButtonKind,
    state: ButtonState,
    theme: tokens.Theme,
    ripple_t: f32,
    ripple_x: i32,
    ripple_y: i32,
) @import("color.zig").Rgb565 {
    if (r.isEmpty()) return theme.on_surface;
    const rad = buttonRadius(r);
    if (state == .disabled) {
        fillRoundRect(logical, r, rad, theme.surface_container_highest);
        if (kind == .outlined) strokeRoundRect(logical, r, rad, theme.outline_variant, 1);
        return theme.on_surface_variant;
    }

    var ink = theme.on_surface;
    switch (kind) {
        .filled => {
            fillRoundRect(logical, r, rad, theme.primary);
            ink = theme.on_primary;
        },
        .tonal => {
            fillRoundRect(logical, r, rad, theme.secondary_container);
            ink = theme.on_secondary_container;
        },
        .elevated => {
            const elev: u3 = if (state == .hovered or state == .pressed) 3 else 1;
            fillRoundRect(logical, r, rad, theme.elev(elev));
            ink = theme.primary;
        },
        .outlined => {
            fillRoundRect(logical, r, rad, theme.surface);
            strokeRoundRect(logical, r, rad, theme.outline, 1);
            ink = theme.primary;
        },
        .text => {
            ink = theme.primary;
        },
        .danger => {
            fillRoundRect(logical, r, rad, theme.err);
            ink = theme.on_error;
        },
        .danger_tonal => {
            fillRoundRect(logical, r, rad, theme.error_container);
            ink = theme.on_error_container;
        },
        .primary_container => {
            fillRoundRect(logical, r, rad, theme.primary_container);
            ink = theme.on_primary_container;
        },
        .secondary => {
            fillRoundRect(logical, r, rad, theme.secondary);
            ink = theme.on_secondary;
        },
        .tertiary => {
            fillRoundRect(logical, r, rad, theme.tertiary);
            ink = theme.on_tertiary;
        },
        .tertiary_container => {
            fillRoundRect(logical, r, rad, theme.tertiary_container);
            ink = theme.on_tertiary_container;
        },
        .cycle => {
            fillRoundRect(logical, r, rad, theme.cycle);
            ink = theme.on_cycle;
        },
        .hold => {
            fillRoundRect(logical, r, rad, theme.hold);
            ink = theme.on_hold;
        },
        .home => {
            fillRoundRect(logical, r, rad, theme.home);
            ink = theme.on_home;
        },
        .stop => {
            fillRoundRect(logical, r, rad, theme.stop);
            ink = theme.on_stop;
        },
        .feed_resume => {
            fillRoundRect(logical, r, rad, theme.feed_resume);
            ink = theme.on_feed_resume;
        },
    }

    const a = buttonStateAlpha(state);
    if (a != 0) drawStateLayerInk(logical, r, rad, ink, a);
    if (state == .pressed and ripple_t > 0.02) {
        const rx = if (r.contains(ripple_x, ripple_y)) ripple_x else r.x + @divTrunc(r.w, 2);
        const ry = if (r.contains(ripple_x, ripple_y)) ripple_y else r.y + @divTrunc(r.h, 2);
        drawButtonRipple(logical, r, rx, ry, ripple_t, ink);
    }
    return ink;
}

/// Map live pointer/focus into MD3 ButtonState (hover/focus rects may be padded hits).
pub fn resolveButtonState(
    r: geom.Rect,
    hover: geom.Rect,
    focus: geom.Rect,
    press_x: i32,
    press_y: i32,
    press_active: bool,
    disabled: bool,
) ButtonState {
    if (disabled) return .disabled;
    if (press_active and r.contains(press_x, press_y)) return .pressed;
    if (!focus.isEmpty() and !geom.Rect.intersect(focus, r).isEmpty()) return .focused;
    if (!hover.isEmpty() and !geom.Rect.intersect(hover, r).isEmpty()) return .hovered;
    return .enabled;
}

/// ≥48dp touch target around a visual button rect.
pub fn buttonTouchHit(r: geom.Rect) geom.Rect {
    const need = tokens.Logical.touch_min;
    const dw = @max(0, need - r.w);
    const dh = @max(0, need - r.h);
    return .{
        .x = r.x - @divTrunc(dw, 2),
        .y = r.y - @divTrunc(dh, 2),
        .w = r.w + dw,
        .h = r.h + dh,
    };
}

/// Ripple clipped to button bounds (ink = content color).
pub fn drawButtonRipple(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    cx: i32,
    cy: i32,
    t: f32,
    ink: @import("color.zig").Rgb565,
) void {
    if (r.isEmpty()) return;
    const u = std.math.clamp(t, 0, 1);
    const max_r = @max(r.w, r.h);
    const rad: i32 = @max(2, @as(i32, @intFromFloat(@as(f32, @floatFromInt(max_r)) * u)));
    const a: u8 = @intFromFloat(@as(f32, @floatFromInt(tokens.StateLayer.press)) * (1.0 - u * 0.55));
    var y: i32 = @max(r.y, cy - rad);
    const y2 = @min(r.y + r.h, cy + rad + 1);
    while (y < y2) : (y += 1) {
        var x: i32 = @max(r.x, cx - rad);
        const x2 = @min(r.x + r.w, cx + rad + 1);
        while (x < x2) : (x += 1) {
            const dx = x - cx;
            const dy = y - cy;
            if (dx * dx + dy * dy <= rad * rad) logical.blendAt(x, y, ink, a);
        }
    }
}

/// Unified MD3 common button — token colors, label_l, stadium shape, state layers.
pub fn drawButton(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    label: []const u8,
    kind: ButtonKind,
    state: ButtonState,
    theme: tokens.Theme,
) void {
    drawButtonRippled(logical, r, label, kind, state, theme, 0, 0, 0);
}

/// Same as `drawButton`, plus clipped press ripple when `ripple_t` > 0.
pub fn drawButtonRippled(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    label: []const u8,
    kind: ButtonKind,
    state: ButtonState,
    theme: tokens.Theme,
    ripple_t: f32,
    ripple_x: i32,
    ripple_y: i32,
) void {
    if (r.isEmpty()) return;
    const ink = drawButtonSurface(logical, r, kind, state, theme, ripple_t, ripple_x, ripple_y);
    if (label.len == 0) return;
    const tw = font.textWidthStr(label, .label_l);
    font.drawTextRole(
        logical,
        r.x + @divTrunc(r.w - tw, 2),
        buttonLabelY(r),
        label,
        ink,
        .label_l,
    );
}

/// Resolve hover/focus/press then paint (optional ripple).
pub fn drawButtonInteractive(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    label: []const u8,
    kind: ButtonKind,
    theme: tokens.Theme,
    hover: geom.Rect,
    focus: geom.Rect,
    press_x: i32,
    press_y: i32,
    press_active: bool,
    disabled: bool,
    ripple_t: f32,
) void {
    const state = resolveButtonState(r, hover, focus, press_x, press_y, press_active, disabled);
    drawButtonRippled(logical, r, label, kind, state, theme, ripple_t, press_x, press_y);
}

pub fn drawFilledButton(logical: *fb.LogicalFb, r: geom.Rect, label: []const u8, theme: tokens.Theme) void {
    drawButton(logical, r, label, .filled, .enabled, theme);
}

pub fn drawFilledButtonSized(logical: *fb.LogicalFb, x: i32, y: i32, size: tokens.ButtonSize, label: []const u8, theme: tokens.Theme) geom.Rect {
    const h = size.height();
    const pad = size.padX();
    const tw = font.textWidthStr(label, .label_l);
    const r: geom.Rect = .{ .x = x, .y = y, .w = tw + pad * 2, .h = h };
    drawButton(logical, r, label, .filled, .enabled, theme);
    return r;
}

pub fn drawTonalButton(logical: *fb.LogicalFb, r: geom.Rect, label: []const u8, theme: tokens.Theme) void {
    drawButton(logical, r, label, .tonal, .enabled, theme);
}

pub fn drawDangerButton(logical: *fb.LogicalFb, r: geom.Rect, label: []const u8, theme: tokens.Theme) void {
    drawButton(logical, r, label, .danger, .enabled, theme);
}

pub fn drawDangerTonalButton(logical: *fb.LogicalFb, r: geom.Rect, label: []const u8, theme: tokens.Theme) void {
    drawButton(logical, r, label, .danger_tonal, .enabled, theme);
}

/// Icon-button chrome only (fill + state). Returns content ink for custom glyphs.
pub fn drawIconButtonChrome(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    style: IconButtonStyle,
    state: ButtonState,
    selected: bool,
    theme: tokens.Theme,
) @import("color.zig").Rgb565 {
    if (r.isEmpty()) return theme.on_surface_variant;
    const rad = buttonRadius(r);
    var ink = theme.on_surface_variant;

    if (state == .disabled) {
        fillRoundRect(logical, r, rad, theme.surface_container_highest);
        return theme.on_surface_variant;
    }

    switch (style) {
        .standard => {
            if (selected) {
                fillRoundRect(logical, r, rad, theme.secondary_container);
                ink = theme.on_secondary_container;
            }
        },
        .filled => {
            fillRoundRect(logical, r, rad, if (selected) theme.primary else theme.primary_container);
            ink = if (selected) theme.on_primary else theme.on_primary_container;
        },
        .tonal => {
            // Filled-tonal: secondary_container at rest (MD3); selected same container.
            fillRoundRect(logical, r, rad, theme.secondary_container);
            ink = theme.on_secondary_container;
        },
        .outlined => {
            fillRoundRect(logical, r, rad, if (selected) theme.inverse_surface else theme.surface);
            strokeRoundRect(logical, r, rad, theme.outline, 1);
            ink = if (selected) theme.inverse_on_surface else theme.on_surface_variant;
        },
    }
    const a = buttonStateAlpha(state);
    if (a != 0) drawStateLayerInk(logical, r, rad, ink, a);
    return ink;
}

/// MD3 icon button — `selected` = toggle on (filled/outlined swap); tonal always filled-tonal.
pub fn drawIconButton(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    style: IconButtonStyle,
    state: ButtonState,
    selected: bool,
    theme: tokens.Theme,
) void {
    const ink = drawIconButtonChrome(logical, r, style, state, selected, theme);
    const cx = r.x + @divTrunc(r.w, 2);
    const cy = r.y + @divTrunc(r.h, 2);

    // Glyph: check when selected, plus when idle.
    if (selected) {
        var i: i32 = 0;
        while (i < 4) : (i += 1) {
            logical.put(cx - 4 + i, cy + i - 1, ink);
            logical.put(cx - 4 + i, cy + i, ink);
        }
        i = 0;
        while (i < 6) : (i += 1) {
            logical.put(cx + i - 1, cy + 2 - i, ink);
            logical.put(cx + i - 1, cy + 3 - i, ink);
        }
    } else {
        logical.fillRect(.{ .x = cx - 6, .y = cy - 2, .w = 12, .h = 4 }, ink);
        logical.fillRect(.{ .x = cx - 2, .y = cy - 6, .w = 4, .h = 12 }, ink);
    }
}

pub fn drawAssistChip(logical: *fb.LogicalFb, r: geom.Rect, label: []const u8, theme: tokens.Theme) void {
    fillRoundRect(logical, r, @divTrunc(r.h, 2), theme.primary_container);
    const tw = font.textWidthStr(label, .label_l);
    const tx = r.x + @divTrunc(r.w - tw, 2);
    const ty = r.y + @divTrunc(r.h - font.faceHeight(font.faceForRole(.label_l)), 2);
    font.drawTextRole(logical, tx, ty, label, theme.on_primary_container, .label_l);
}

/// MD3 filter chip — selected = secondary_container; idle = outline_variant.
pub fn drawFilterChip(logical: *fb.LogicalFb, r: geom.Rect, label: []const u8, selected: bool, theme: tokens.Theme) void {
    const rad = tokens.Shape.full;
    if (selected) {
        fillRoundRect(logical, r, rad, theme.secondary_container);
        const tw = font.textWidthStr(label, .label_l);
        font.drawTextRole(
            logical,
            r.x + @divTrunc(r.w - tw, 2),
            r.y + @divTrunc(r.h - font.faceHeight(font.faceForRole(.label_l)), 2),
            label,
            theme.on_secondary_container,
            .label_l,
        );
    } else {
        fillRoundRect(logical, r, rad, theme.surface_container_low);
        strokeRoundRect(logical, r, rad, theme.outline_variant, 1);
        const tw = font.textWidthStr(label, .label_l);
        font.drawTextRole(
            logical,
            r.x + @divTrunc(r.w - tw, 2),
            r.y + @divTrunc(r.h - font.faceHeight(font.faceForRole(.label_l)), 2),
            label,
            theme.on_surface_variant,
            .label_l,
        );
    }
}

/// Single-select segmented button (MD3) — selected = secondary container + outline.
/// Labels centered in each equal slice (proportional glyph metrics, not len*avg).
pub fn drawSegmented(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    labels: []const []const u8,
    selected: usize,
    theme: tokens.Theme,
) void {
    drawSegmentedF(logical, r, labels, @floatFromInt(selected), theme);
}

/// Segmented control with spring-smoothed selection index (0..n-1).
pub fn drawSegmentedF(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    labels: []const []const u8,
    selected_f: f32,
    theme: tokens.Theme,
) void {
    if (labels.len == 0 or r.isEmpty()) return;
    const n = @as(i32, @intCast(labels.len));
    const n_f: f32 = @floatFromInt(labels.len);
    const sel = std.math.clamp(selected_f, 0, n_f - 1);
    // LVGL track: surface_container_high + outline (not highest — weak vs containers).
    fillRoundRect(logical, r, @divTrunc(r.h, 2), theme.surface_container_high);
    strokeRoundRect(logical, r, @divTrunc(r.h, 2), theme.outline_variant, 1);
    const role: tokens.TypeRole = .body_s; // LVGL segmented: BODY_M (14)
    const fh = font.faceHeight(font.faceForRole(role));
    const inset: i32 = 2; // LVGL pad_all 2
    // Sliding stadium pill between slots.
    {
        const idx0: i32 = @intFromFloat(@floor(sel));
        const idx1 = @min(idx0 + 1, n - 1);
        const frac = sel - @as(f32, @floatFromInt(idx0));
        // Slice widths must not subtract r.x (sx already includes origin).
        const off0 = @divTrunc(r.w * idx0, n);
        const off1 = @divTrunc(r.w * idx1, n);
        const sw0 = @divTrunc(r.w * (idx0 + 1), n) - off0;
        const sw1 = @divTrunc(r.w * (idx1 + 1), n) - off1;
        const px = r.x + off0 + @as(i32, @intFromFloat(@as(f32, @floatFromInt(off1 - off0)) * frac));
        const pw = sw0 + @as(i32, @intFromFloat(@as(f32, @floatFromInt(sw1 - sw0)) * frac));
        const pill_w = @max(1, pw - inset * 2);
        const pill: geom.Rect = .{
            .x = px + inset,
            .y = r.y + inset,
            .w = pill_w,
            .h = @max(1, r.h - inset * 2),
        };
        // Industrial dark: container-on-container is ~1.3:1 — use primary for selected
        // so selection reads (WCAG UI ≥3:1). Text uses on_primary.
        fillRoundRect(logical, pill, @divTrunc(pill.h, 2), theme.primary);
    }
    for (labels, 0..) |label, i| {
        const sx = r.x + @divTrunc(r.w * @as(i32, @intCast(i)), n);
        const sx_next = r.x + @divTrunc(r.w * @as(i32, @intCast(i + 1)), n);
        const slice_w = sx_next - sx;
        const tw = font.textWidthStr(label, role);
        const tx = sx + @divTrunc(slice_w - tw, 2);
        const ty = r.y + @divTrunc(r.h - fh, 2);
        const near = @abs(sel - @as(f32, @floatFromInt(i))) < 0.5;
        font.drawTextRole(
            logical,
            tx,
            ty,
            label,
            if (near) theme.on_primary else theme.on_surface_variant,
            role,
        );
    }
}

/// Hollow rounded outline — border only (never fill interior).
/// Prior impl filled the whole rect; stroke-after-content blanked settings.
pub fn strokeRoundRect(logical: *fb.LogicalFb, r: geom.Rect, radius: i32, c: @import("color.zig").Rgb565, thickness: i32) void {
    if (r.isEmpty() or thickness <= 0) return;
    const rad = @min(radius, @divTrunc(@min(r.w, r.h), 2));
    const t = @min(thickness, @max(1, @divTrunc(@min(r.w, r.h), 2)));
    // Straight edges (inset by corner rad).
    if (r.w > rad * 2) {
        logical.fillRect(.{ .x = r.x + rad, .y = r.y, .w = r.w - rad * 2, .h = t }, c);
        logical.fillRect(.{ .x = r.x + rad, .y = r.y + r.h - t, .w = r.w - rad * 2, .h = t }, c);
    }
    if (r.h > rad * 2) {
        logical.fillRect(.{ .x = r.x, .y = r.y + rad, .w = t, .h = r.h - rad * 2 }, c);
        logical.fillRect(.{ .x = r.x + r.w - t, .y = r.y + rad, .w = t, .h = r.h - rad * 2 }, c);
    }
    if (rad > 0) {
        // Quarter arcs only — full rings left ghost circles inside the panel.
        strokeCornerArc(logical, r.x + rad, r.y + rad, rad, t, c, .nw);
        strokeCornerArc(logical, r.x + r.w - rad - 1, r.y + rad, rad, t, c, .ne);
        strokeCornerArc(logical, r.x + rad, r.y + r.h - rad - 1, rad, t, c, .sw);
        strokeCornerArc(logical, r.x + r.w - rad - 1, r.y + r.h - rad - 1, rad, t, c, .se);
    }
}

/// Paint pixels in each corner AABB that lie *outside* the rounded rect.
/// Restores scrim after pane `fillRect`s that square the card corners.
pub fn punchRoundRectOutside(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    radius: i32,
    outside: @import("color.zig").Rgb565,
) void {
    if (r.isEmpty()) return;
    const rad = @min(radius, @divTrunc(@min(r.w, r.h), 2));
    if (rad <= 0) return;
    // Centers match fillRoundRect circles.
    punchCornerOutside(logical, r.x, r.y, r.x + rad, r.y + rad, rad, outside);
    punchCornerOutside(logical, r.x + r.w - rad, r.y, r.x + r.w - rad - 1, r.y + rad, rad, outside);
    punchCornerOutside(logical, r.x, r.y + r.h - rad, r.x + rad, r.y + r.h - rad - 1, rad, outside);
    punchCornerOutside(logical, r.x + r.w - rad, r.y + r.h - rad, r.x + r.w - rad - 1, r.y + r.h - rad - 1, rad, outside);
}

fn punchCornerOutside(
    logical: *fb.LogicalFb,
    box_x: i32,
    box_y: i32,
    cx: i32,
    cy: i32,
    rad: i32,
    outside: @import("color.zig").Rgb565,
) void {
    const r2 = rad * rad;
    var y: i32 = 0;
    while (y < rad) : (y += 1) {
        var x: i32 = 0;
        while (x < rad) : (x += 1) {
            const px = box_x + x;
            const py = box_y + y;
            const dx = px - cx;
            const dy = py - cy;
            if (dx * dx + dy * dy > r2) {
                logical.put(px, py, outside);
            }
        }
    }
}

const CornerQuad = enum { nw, ne, sw, se };

fn strokeCornerArc(
    logical: *fb.LogicalFb,
    cx: i32,
    cy: i32,
    rad: i32,
    thick: i32,
    c: @import("color.zig").Rgb565,
    quad: CornerQuad,
) void {
    const outer2 = rad * rad;
    const inner = rad - thick;
    const inner2: i32 = if (inner <= 0) 0 else inner * inner;
    var y: i32 = -rad;
    while (y <= rad) : (y += 1) {
        var x: i32 = -rad;
        while (x <= rad) : (x += 1) {
            const ok = switch (quad) {
                .nw => x <= 0 and y <= 0,
                .ne => x >= 0 and y <= 0,
                .sw => x <= 0 and y >= 0,
                .se => x >= 0 and y >= 0,
            };
            if (!ok) continue;
            const d2 = x * x + y * y;
            if (d2 <= outer2 and d2 >= inner2) put(logical, cx + x, cy + y, c);
        }
    }
}

pub fn drawChevronUp(logical: *fb.LogicalFb, cx: i32, cy: i32, half: i32, c: @import("color.zig").Rgb565) void {
    var y: i32 = 0;
    while (y <= half) : (y += 1) {
        const w = y * 2 + 1;
        logical.fillRect(.{ .x = cx - y, .y = cy - half + y, .w = w, .h = 2 }, c);
    }
}

pub fn drawChevronDown(logical: *fb.LogicalFb, cx: i32, cy: i32, half: i32, c: @import("color.zig").Rgb565) void {
    var y: i32 = 0;
    while (y <= half) : (y += 1) {
        const w = (half - y) * 2 + 1;
        logical.fillRect(.{ .x = cx - (half - y), .y = cy + y, .w = w, .h = 2 }, c);
    }
}

/// Circular tonal close (MD3 filled-tonal icon button + X glyph).
pub fn drawTonalCloseButton(logical: *fb.LogicalFb, r: geom.Rect, theme: tokens.Theme) void {
    const ink = drawIconButtonChrome(logical, r, .tonal, .enabled, false, theme);
    const cx = r.x + @divTrunc(r.w, 2);
    const cy = r.y + @divTrunc(r.h, 2);
    var i: i32 = -6;
    while (i <= 6) : (i += 1) {
        logical.fillRect(.{ .x = cx + i, .y = cy + i, .w = 2, .h = 2 }, ink);
        logical.fillRect(.{ .x = cx + i, .y = cy - i, .w = 2, .h = 2 }, ink);
    }
}

/// Circular tonal icon button (status bar gear/power).
pub fn drawCircleButton(logical: *fb.LogicalFb, cx: i32, cy: i32, radius: i32, fill: @import("color.zig").Rgb565) void {
    fillCircle(logical, cx, cy, radius, fill);
}

/// MD3 continuous slider — matches Tab5 LVGL theme intent (full track, primary handle Ø20).
pub const slider_track_h: i32 = 4;
pub const slider_handle_r: i32 = 10;
/// Label / value columns on settings rows (8dp grid).
pub const slider_label_w: i32 = tokens.Space.md * 12; // 192
pub const slider_value_w: i32 = tokens.Space.md * 6; // 96

pub fn sliderTrackInRow(row: geom.Rect) geom.Rect {
    const gap = tokens.Space.md;
    return .{
        .x = row.x + slider_label_w + gap,
        .y = row.y + @divTrunc(row.h - slider_track_h, 2),
        .w = @max(0, row.w - slider_label_w - slider_value_w - gap * 2),
        .h = slider_track_h,
    };
}

/// `t` 0..1. `tick_stops` = discrete stop count along span (0 = continuous, no ticks).
pub fn drawContinuousSlider(
    logical: *fb.LogicalFb,
    track: geom.Rect,
    t: f32,
    theme: tokens.Theme,
    tick_stops: u32,
) void {
    if (track.w <= 0 or track.h <= 0) return;
    const rad = tokens.Shape.full;
    const tc = std.math.clamp(t, 0, 1);
    fillRoundRect(logical, track, rad, theme.surface_container_highest);

    // Discrete stops on inactive track (small-span integer ranges).
    if (tick_stops >= 2 and tick_stops <= 17) {
        const n = tick_stops - 1;
        var i: u32 = 0;
        while (i <= n) : (i += 1) {
            const fx = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
            const x = track.x + @as(i32, @intFromFloat(@as(f32, @floatFromInt(track.w)) * fx));
            const mark_h: i32 = 8;
            logical.fillRect(.{
                .x = x,
                .y = track.y + @divTrunc(track.h, 2) - @divTrunc(mark_h, 2),
                .w = 2,
                .h = mark_h,
            }, theme.outline_variant);
        }
    }

    const fill_w = @max(slider_track_h, @as(i32, @intFromFloat(@as(f32, @floatFromInt(track.w)) * tc)));
    fillRoundRect(logical, .{ .x = track.x, .y = track.y, .w = fill_w, .h = track.h }, rad, theme.primary);
    const cy = track.y + @divTrunc(track.h, 2);
    const cx = track.x + fill_w;
    // Handle = primary disk; light on-primary center stop (device knob pad stand-in).
    drawCircleButton(logical, cx, cy, slider_handle_r, theme.primary);
    drawCircleButton(logical, cx, cy, 3, theme.on_primary);
}

/// Catalog / bare track bounds — same metrics as settings track segment.
pub fn drawSlider(logical: *fb.LogicalFb, r: geom.Rect, value: f32, theme: tokens.Theme) void {
    const track: geom.Rect = .{
        .x = r.x + slider_handle_r,
        .y = r.y + @divTrunc(r.h - slider_track_h, 2),
        .w = @max(0, r.w - slider_handle_r * 2),
        .h = slider_track_h,
    };
    drawContinuousSlider(logical, track, value, theme, 0);
}

/// MD3 snackbar — inverse surface, bottom-aligned (opaque). Optional action label.
pub fn drawSnackbar(logical: *fb.LogicalFb, message: []const u8, theme: tokens.Theme) void {
    _ = drawSnackbarAction(logical, message, null, theme);
}

pub fn drawSnackbarAction(logical: *fb.LogicalFb, message: []const u8, action: ?[]const u8, theme: tokens.Theme) geom.Rect {
    return drawSnackbarActionLift(logical, message, action, theme, 0);
}

/// `lift_px` — positive raises snack during enter spring.
pub fn drawSnackbarActionLift(logical: *fb.LogicalFb, message: []const u8, action: ?[]const u8, theme: tokens.Theme, lift_px: i32) geom.Rect {
    const pad = tokens.Space.md;
    const h: i32 = tokens.ButtonSize.m.height() + tokens.Space.sm;
    const max_w: i32 = 720;
    const tw = font.textWidthRole(message.len, .body_m);
    var action_w: i32 = 0;
    if (action) |a| {
        action_w = font.textWidthRole(a.len, .label_l) + tokens.Space.md * 2;
    }
    const w = @min(max_w, tw + pad * 2 + action_w + (if (action != null) tokens.Space.sm else 0));
    const r: geom.Rect = .{
        .x = @divTrunc(@as(i32, tokens.Logical.width) - w, 2),
        .y = tokens.Logical.height - h - pad - lift_px,
        .w = w,
        .h = h,
    };
    fillRoundRect(logical, r, tokens.Shape.sm, theme.inverse_surface);
    font.drawTextRole(logical, r.x + pad, r.y + 18, message, theme.inverse_on_surface, .body_m);
    var action_rect: geom.Rect = .{};
    if (action) |a| {
        action_rect = .{
            .x = r.x + r.w - action_w - tokens.Space.xs,
            .y = r.y + tokens.Space.xs,
            .w = action_w,
            .h = r.h - tokens.Space.sm,
        };
        font.drawTextRole(logical, action_rect.x + tokens.Space.sm, action_rect.y + 14, a, theme.inverse_primary, .label_l);
    }
    return action_rect;
}

pub fn snackbarRect(message: []const u8) geom.Rect {
    return snackbarRectAction(message, null);
}

pub fn snackbarRectAction(message: []const u8, action: ?[]const u8) geom.Rect {
    const pad = tokens.Space.md;
    const h: i32 = tokens.ButtonSize.m.height() + tokens.Space.sm;
    const tw = font.textWidthRole(message.len, .body_m);
    var action_w: i32 = 0;
    if (action) |a| {
        action_w = font.textWidthRole(a.len, .label_l) + tokens.Space.md * 2;
    }
    const w = @min(@as(i32, 720), tw + pad * 2 + action_w + (if (action != null) tokens.Space.sm else 0));
    return .{
        .x = @divTrunc(@as(i32, tokens.Logical.width) - w, 2),
        .y = tokens.Logical.height - h - pad,
        .w = w,
        .h = h,
    };
}

/// Basic MD3 dialog card centered on scrim (opaque cover).
/// `enter_t` 0..1 scales card (container-transform enter).
pub fn drawDialog(
    logical: *fb.LogicalFb,
    title: []const u8,
    body: []const u8,
    theme: tokens.Theme,
) geom.Rect {
    return drawDialogEnter(logical, title, body, theme, 1);
}

pub fn drawDialogEnter(
    logical: *fb.LogicalFb,
    title: []const u8,
    body: []const u8,
    theme: tokens.Theme,
    enter_t: f32,
) geom.Rect {
    fillScrim(logical, theme);
    const t = std.math.clamp(enter_t, 0, 1);
    const card_w: i32 = @intFromFloat(520.0 * (0.88 + 0.12 * t));
    const card_h: i32 = @intFromFloat(240.0 * (0.88 + 0.12 * t));
    const card: geom.Rect = .{
        .x = @divTrunc(@as(i32, tokens.Logical.width) - card_w, 2),
        .y = @divTrunc(@as(i32, tokens.Logical.height) - card_h, 2),
        .w = card_w,
        .h = card_h,
    };
    fillRoundRect(logical, card, tokens.Shape.dialog, theme.elev(3));
    font.drawTextRole(logical, card.x + tokens.Space.lg, card.y + tokens.Space.lg, title, theme.on_surface, .title_l);
    font.drawTextRole(logical, card.x + tokens.Space.lg, card.y + 64, body, theme.on_surface_variant, .body_m);
    const ok_h = tokens.ButtonSize.m.height();
    const ok: geom.Rect = .{
        .x = card.x + card.w - 140 - tokens.Space.lg,
        .y = card.y + card.h - ok_h - tokens.Space.md,
        .w = 140,
        .h = ok_h,
    };
    drawFilledButton(logical, ok, "OK", theme);
    return ok;
}

/// Soft rounded fill (MD3 cards).
pub fn fillRoundRect(logical: *fb.LogicalFb, r: geom.Rect, radius: i32, c: @import("color.zig").Rgb565) void {
    if (r.isEmpty()) return;
    const rad = @min(radius, @divTrunc(@min(r.w, r.h), 2));
    logical.fillRect(.{ .x = r.x + rad, .y = r.y, .w = r.w - rad * 2, .h = r.h }, c);
    logical.fillRect(.{ .x = r.x, .y = r.y + rad, .w = rad, .h = r.h - rad * 2 }, c);
    logical.fillRect(.{ .x = r.x + r.w - rad, .y = r.y + rad, .w = rad, .h = r.h - rad * 2 }, c);
    fillCircle(logical, r.x + rad, r.y + rad, rad, c);
    fillCircle(logical, r.x + r.w - rad - 1, r.y + rad, rad, c);
    fillCircle(logical, r.x + rad, r.y + r.h - rad - 1, rad, c);
    fillCircle(logical, r.x + r.w - rad - 1, r.y + r.h - rad - 1, rad, c);
}

fn fillCircle(logical: *fb.LogicalFb, cx: i32, cy: i32, radius: i32, c: @import("color.zig").Rgb565) void {
    if (radius <= 0) return;
    const r2 = radius * radius;
    var y: i32 = -radius;
    while (y <= radius) : (y += 1) {
        const rem = r2 - y * y;
        if (rem < 0) continue;
        // Scanline span — one fillRect/row vs O(r²) put.
        const xmax: i32 = @intFromFloat(@floor(@sqrt(@as(f32, @floatFromInt(rem)))));
        logical.fillRect(.{ .x = cx - xmax, .y = cy + y, .w = xmax * 2 + 1, .h = 1 }, c);
    }
}

fn put(logical: *fb.LogicalFb, x: i32, y: i32, c: @import("color.zig").Rgb565) void {
    logical.put(x, y, c);
}

/// MD3 state layer — blend `ink` over container (press/hover/focus).
pub fn drawStateLayerInk(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    radius: i32,
    ink: @import("color.zig").Rgb565,
    alpha: u8,
) void {
    if (alpha == 0 or r.isEmpty()) return;
    const rad = @min(radius, @divTrunc(@min(r.w, r.h), 2));
    var y: i32 = r.y;
    while (y < r.y + r.h) : (y += 1) {
        var x: i32 = r.x;
        while (x < r.x + r.w) : (x += 1) {
            if (rad > 0) {
                const lx = x - r.x;
                const ly = y - r.y;
                const rx = r.w - 1 - lx;
                const ry = r.h - 1 - ly;
                if (lx < rad and ly < rad) {
                    const dx = rad - lx;
                    const dy = rad - ly;
                    if (dx * dx + dy * dy > rad * rad) continue;
                } else if (rx < rad and ly < rad) {
                    const dx = rad - rx;
                    const dy = rad - ly;
                    if (dx * dx + dy * dy > rad * rad) continue;
                } else if (lx < rad and ry < rad) {
                    const dx = rad - lx;
                    const dy = rad - ry;
                    if (dx * dx + dy * dy > rad * rad) continue;
                } else if (rx < rad and ry < rad) {
                    const dx = rad - rx;
                    const dy = rad - ry;
                    if (dx * dx + dy * dy > rad * rad) continue;
                }
            }
            logical.blendAt(x, y, ink, alpha);
        }
    }
}

/// MD3 state layer — on-surface blend over container (press/hover/focus).
pub fn drawStateLayer(logical: *fb.LogicalFb, r: geom.Rect, radius: i32, theme: tokens.Theme, alpha: u8) void {
    drawStateLayerInk(logical, r, radius, theme.on_surface, alpha);
}

/// Pressed filled button (state layer uses on-primary ink).
pub fn drawFilledButtonPressed(logical: *fb.LogicalFb, r: geom.Rect, label: []const u8, theme: tokens.Theme) void {
    drawButtonRippled(logical, r, label, .filled, .pressed, theme, 1, r.x + @divTrunc(r.w, 2), r.y + @divTrunc(r.h, 2));
}

/// Search view — bar + suggestion list (MD3 search).
pub fn drawSearchView(
    logical: *fb.LogicalFb,
    bar: geom.Rect,
    panel: geom.Rect,
    query: []const u8,
    suggestions: []const []const u8,
    theme: tokens.Theme,
) void {
    drawSearchBar(logical, bar, query, "Search", false, theme);
    fillRoundRect(logical, panel, tokens.Shape.lg, theme.elev(2));
    for (suggestions, 0..) |s, i| {
        const y = panel.y + 12 + @as(i32, @intCast(i)) * 44;
        if (y + 40 > panel.y + panel.h) break;
        font.drawTextRole(logical, panel.x + 16, y + 12, s, theme.on_surface, .body_m);
    }
}

test "outlined text field focus uses primary stroke" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    const theme = tokens.Theme.industrialTealDark();
    logical.clear(theme.surface);
    const r: geom.Rect = .{ .x = 40, .y = 40, .w = 200, .h = 48 };
    drawOutlinedTextField(&logical, r, "ok", "", true, true, false, theme);
    try std.testing.expect(logical.get(r.x + @divTrunc(r.w, 2), r.y).toU16() == theme.primary.toU16());
    // Interior fill (left pad, away from glyphs).
    try std.testing.expect(logical.get(r.x + 4, r.y + @divTrunc(r.h, 2)).toU16() == theme.surface.toU16());
}

test "outlined text field idle uses outline_variant" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    const theme = tokens.Theme.industrialTealDark();
    logical.clear(theme.surface);
    const r: geom.Rect = .{ .x = 40, .y = 40, .w = 200, .h = 48 };
    drawOutlinedTextField(&logical, r, "", "hint", false, true, false, theme);
    try std.testing.expect(logical.get(r.x + @divTrunc(r.w, 2), r.y).toU16() == theme.outline_variant.toU16());
}

test "search clear hit trails bar" {
    const r: geom.Rect = .{ .x = 40, .y = 80, .w = 260, .h = 48 };
    const c = searchClearHit(r);
    try std.testing.expect(c.x + c.w == r.x + r.w);
    try std.testing.expect(c.w == search_clear_w);
    try std.testing.expect(c.h == r.h);
}

test "filled button enabled uses primary container" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    const theme = tokens.Theme.industrialTealDark();
    logical.clear(theme.surface);
    const r: geom.Rect = .{ .x = 40, .y = 40, .w = 120, .h = tokens.ButtonSize.m.height() };
    drawButton(&logical, r, "Go", .filled, .enabled, theme);
    try std.testing.expect(logical.get(r.x + 8, r.y + @divTrunc(r.h, 2)).toU16() == theme.primary.toU16());
}

test "filled button disabled uses muted container" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    const theme = tokens.Theme.industrialTealDark();
    logical.clear(theme.surface);
    const r: geom.Rect = .{ .x = 40, .y = 40, .w = 120, .h = tokens.ButtonSize.m.height() };
    drawButton(&logical, r, "Go", .filled, .disabled, theme);
    try std.testing.expect(logical.get(r.x + 8, r.y + @divTrunc(r.h, 2)).toU16() == theme.surface_container_highest.toU16());
}

test "button size heights match MD3 expressive scale" {
    try std.testing.expectEqual(@as(i32, 32), tokens.ButtonSize.xs.height());
    try std.testing.expectEqual(@as(i32, 40), tokens.ButtonSize.s.height());
    try std.testing.expectEqual(@as(i32, 48), tokens.ButtonSize.m.height());
    try std.testing.expectEqual(@as(i32, 56), tokens.ButtonSize.l.height());
    try std.testing.expectEqual(@as(i32, 64), tokens.ButtonSize.xl.height());
}

test "resolveButtonState maps hover press disabled" {
    const r: geom.Rect = .{ .x = 10, .y = 10, .w = 100, .h = 48 };
    try std.testing.expect(resolveButtonState(r, .{}, .{}, 0, 0, false, true) == .disabled);
    try std.testing.expect(resolveButtonState(r, r, .{}, 0, 0, false, false) == .hovered);
    try std.testing.expect(resolveButtonState(r, .{}, r, 0, 0, false, false) == .focused);
    try std.testing.expect(resolveButtonState(r, .{}, .{}, 50, 30, true, false) == .pressed);
    try std.testing.expect(resolveButtonState(r, .{}, .{}, 0, 0, false, false) == .enabled);
}

test "buttonTouchHit expands below 48dp" {
    const r: geom.Rect = .{ .x = 10, .y = 10, .w = 40, .h = 32 };
    const h = buttonTouchHit(r);
    try std.testing.expect(h.w >= tokens.Logical.touch_min);
    try std.testing.expect(h.h >= tokens.Logical.touch_min);
}

test "button ripple stays inside rect" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    const theme = tokens.Theme.industrialTealDark();
    logical.clear(theme.surface);
    const r: geom.Rect = .{ .x = 100, .y = 100, .w = 80, .h = 48 };
    drawButtonRipple(&logical, r, 140, 124, 1, theme.on_primary);
    // Pixel clearly outside button must remain surface.
    try std.testing.expect(logical.get(50, 50).toU16() == theme.surface.toU16());
}

test "slider track uses space tokens" {
    const row: geom.Rect = .{ .x = 100, .y = 50, .w = 700, .h = 56 };
    const tr = sliderTrackInRow(row);
    try std.testing.expect(tr.h == slider_track_h);
    try std.testing.expect(tr.x == row.x + slider_label_w + tokens.Space.md);
    try std.testing.expect(tr.x + tr.w + tokens.Space.md + slider_value_w == row.x + row.w);
}

test "continuous slider paints primary fill" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    const theme = tokens.Theme.industrialTealDark();
    logical.clear(theme.surface);
    const track: geom.Rect = .{ .x = 40, .y = 40, .w = 200, .h = slider_track_h };
    drawContinuousSlider(&logical, track, 0.5, theme, 0);
    try std.testing.expect(logical.get(60, 42).toU16() == theme.primary.toU16());
    try std.testing.expect(logical.get(180, 42).toU16() == theme.surface_container_highest.toU16());
}

test "switch dirty footprint" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    const theme = tokens.Theme.industrialTealDark();
    logical.clear(theme.surface);
    drawSwitch(&logical, 100, 100, 1, theme, true, true);
    try std.testing.expect(logical.get(100 + switch_w - 8, 100 + 16).toU16() != theme.surface.toU16());
}

test "strokeRoundRect leaves interior" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    const theme = tokens.Theme.industrialTealDark();
    const fill = theme.elev(3);
    const ink = theme.outline_variant;
    const r: geom.Rect = .{ .x = 40, .y = 32, .w = 200, .h = 120 };
    fillRoundRect(&logical, r, tokens.Shape.dialog, fill);
    strokeRoundRect(&logical, r, tokens.Shape.dialog, ink, 1);
    try std.testing.expect(logical.get(r.x + @divTrunc(r.w, 2), r.y + @divTrunc(r.h, 2)).toU16() == fill.toU16());
    try std.testing.expect(logical.get(r.x + @divTrunc(r.w, 2), r.y).toU16() == ink.toU16());
    // Interior near BL corner center must not be a full ring ghost.
    const rad = tokens.Shape.dialog;
    const bl_cx = r.x + rad;
    const bl_cy = r.y + r.h - rad - 1;
    try std.testing.expect(logical.get(bl_cx + 8, bl_cy - 8).toU16() == fill.toU16());
}

test "punchRoundRectOutside restores squared corner" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    const theme = tokens.Theme.industrialTealDark();
    const r: geom.Rect = .{ .x = 40, .y = 40, .w = 200, .h = 160 };
    const rad = tokens.Shape.dialog;
    logical.clear(theme.scrim);
    fillRoundRect(&logical, r, rad, theme.elev(1));
    // Square the SE corner like a careless pane fillRect.
    logical.fillRect(.{ .x = r.x + r.w - rad, .y = r.y + r.h - rad, .w = rad, .h = rad }, theme.elev(1));
    const corner_px = r.x + r.w - 1;
    const corner_py = r.y + r.h - 1;
    try std.testing.expect(logical.get(corner_px, corner_py).toU16() == theme.elev(1).toU16());
    punchRoundRectOutside(&logical, r, rad, theme.scrim);
    try std.testing.expect(logical.get(corner_px, corner_py).toU16() == theme.scrim.toU16());
    // Interior of the round still elev(1).
    try std.testing.expect(logical.get(r.x + r.w - rad - 4, r.y + r.h - rad - 4).toU16() == theme.elev(1).toU16());
}

test "segmented selected pill contrasts track" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    const theme = tokens.Theme.industrialTealDark();
    const r: geom.Rect = .{ .x = 100, .y = 100, .w = 240, .h = 40 };
    const labels = [_][]const u8{ "A", "B", "C" };
    drawSegmented(&logical, r, &labels, 2, theme);
    const want = theme.primary.toU16();
    var primary_count: i32 = 0;
    var x: i32 = r.x;
    const cy = r.y + 4; // above label glyphs
    while (x < r.x + r.w) : (x += 1) {
        if (logical.get(x, cy).toU16() == want) primary_count += 1;
    }
    try std.testing.expect(primary_count >= 40);
    var p0: i32 = 0;
    x = r.x;
    while (x < r.x + @divTrunc(r.w, 3)) : (x += 1) {
        if (logical.get(x, cy).toU16() == want) p0 += 1;
    }
    try std.testing.expect(p0 < 8);
}
