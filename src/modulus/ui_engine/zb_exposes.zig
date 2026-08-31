//! zigbee2mqtt-style expose derivation, sizing, and format helpers.

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const widgets = @import("widgets.zig");
const color = @import("color.zig");
const settings_prefs = @import("settings_prefs.zig");
const icons_phosphor = @import("icons_phosphor.zig");

pub const E = settings_prefs.ZbExpose;
pub const Snap = settings_prefs.ZbDevSnap;

pub const Field = enum(u8) {
    none,
    state,
    brightness,
    color_temp,
    color_xy,
    effect,
    min_brightness,
    max_brightness,
    light_type,
    countdown,
    child_lock,
    power_block,
    contact,
    device_temperature,
    power_outage_count,
    trigger_count,
    battery,
    cover,
};

pub const effect_labels = [_][]const u8{ "blink", "breathe", "okay", "channel_change", "finish_effect", "stop_effect" };
pub const light_type_labels = [_][]const u8{ "led", "halogen", "incandescent", "fluorescent" };

pub const row_h: i32 = tokens.Logical.touch_min;
pub const slider_extra: i32 = tokens.Space.sm + tokens.Space.xs;
pub const title_row_h: i32 = icons_phosphor.size + tokens.Space.sm + tokens.TypeRole.title_m.lineHeight();
pub const power_block_h: i32 = tokens.TypeRole.body_m.lineHeight() * 2 + tokens.Space.md;
pub const color_label_h: i32 = tokens.TypeRole.label_m.lineHeight();
pub const color_bar_visual_h: i32 = tokens.Space.md + tokens.Space.xs;
pub const color_bar_h: i32 = color_label_h + tokens.Space.xs + row_h;
pub const readonly_h: i32 = row_h;
pub const exposes_link_h: i32 = row_h;
pub const footer_h: i32 = row_h;

pub fn active(snap: Snap) u32 {
    if (snap.exposes != 0) return snap.exposes;
    return deriveFromCaps(snap);
}

fn deriveFromCaps(snap: Snap) u32 {
    const Z = settings_prefs.ZbCap;
    var e: u32 = 0;
    if (snap.caps == 0 or (snap.caps & Z.onoff) != 0) e |= E.state;
    if ((snap.caps & Z.level) != 0) {
        e |= E.brightness | E.effect;
    }
    if ((snap.caps & Z.color) != 0) {
        e |= E.color_temp | E.color_xy | E.light_type | E.min_brightness | E.max_brightness;
    }
    if ((snap.caps & (Z.power | Z.meter)) != 0) {
        e |= E.power | E.current | E.voltage | E.energy | E.countdown | E.child_lock;
    }
    if ((snap.caps & Z.sensor) != 0 and snap.zone_seen) e |= E.contact;
    if ((snap.caps & Z.sensor) != 0) {
        e |= E.device_temperature | E.power_outage_count | E.trigger_count;
        if (snap.battery_pct != 255) e |= E.battery;
    }
    if ((snap.caps & Z.cover) != 0) e |= E.cover;
    return e;
}

pub fn has(exposes: u32, bit: u32) bool {
    return (exposes & bit) != 0;
}

pub fn cardBodyHeight(snap: Snap) i32 {
    const ex = active(snap);
    var h: i32 = title_row_h;
    if (has(ex, E.state)) h += row_h;
    if (has(ex, E.brightness)) h += row_h + slider_extra;
    if (has(ex, E.color_temp)) h += row_h + slider_extra;
    if (has(ex, E.color_xy)) h += color_bar_h + tokens.Space.sm;
    if (has(ex, E.effect)) h += row_h;
    if (has(ex, E.min_brightness)) h += row_h + slider_extra;
    if (has(ex, E.max_brightness)) h += row_h + slider_extra;
    if (has(ex, E.light_type)) h += row_h;
    if (has(ex, E.countdown)) h += row_h + slider_extra;
    if (has(ex, E.power) or has(ex, E.current) or has(ex, E.voltage) or has(ex, E.energy)) h += power_block_h;
    if (has(ex, E.child_lock)) h += row_h;
    if (has(ex, E.contact)) h += readonly_h;
    if (has(ex, E.device_temperature)) h += readonly_h;
    if (has(ex, E.power_outage_count)) h += readonly_h;
    if (has(ex, E.trigger_count)) h += readonly_h;
    if (has(ex, E.cover)) h += row_h;
    h += exposes_link_h + footer_h + tokens.Space.md;
    return h;
}

pub fn sliderPctFromLevel(level: u8) u8 {
    return @intCast(@min(100, (@as(u16, level) * 100) / 254));
}

pub fn levelFromSliderPct(pct: u8) u8 {
    return @intCast(@min(254, (@as(u16, pct) * 254) / 100));
}

pub fn countdownPct(seconds: u32) u8 {
    const max_s: u32 = 43200;
    return @intCast(@min(100, (seconds * 100) / max_s));
}

pub fn countdownFromPct(pct: u8) u32 {
    const max_s: u32 = 43200;
    return @as(u32, pct) * max_s / 100;
}

pub fn colorTempPct(mireds: u16) u8 {
    const lo: u16 = 153;
    const hi: u16 = 500;
    const v = std.math.clamp(mireds, lo, hi);
    return @intCast(@min(100, @divTrunc(@as(i32, @intCast(v - lo)) * 100, hi - lo)));
}

pub fn colorTempFromPct(pct: u8) u16 {
    const lo: i32 = 153;
    const hi: i32 = 500;
    const t: i32 = lo + @divTrunc(@as(i32, pct) * (hi - lo), 100);
    return @intCast(std.math.clamp(t, lo, hi));
}

pub fn formatPowerBlock(snap: Snap, buf: []u8) []const u8 {
    if (snap.sensors_seen == 0) return "Power - tap Refresh";
    return std.fmt.bufPrint(buf, "Power {d}.{d}W  {d}.{d}A  {d}.{d}V  {d}.{d} kWh", .{
        @divTrunc(@abs(snap.power_raw), 10),
        @mod(@abs(snap.power_raw), 10),
        @divTrunc(@as(i32, @intCast(snap.curr_raw)), 1000),
        @mod(@as(i32, @intCast(snap.curr_raw)), 1000),
        snap.volt_raw / 10,
        snap.volt_raw % 10,
        @divTrunc(@as(i32, @intCast(snap.energy_raw)), 100),
        @mod(@as(i32, @intCast(snap.energy_raw)), 100),
    }) catch "Power";
}

pub fn fieldLabel(f: Field) []const u8 {
    return switch (f) {
        .state => "State",
        .brightness => "Brightness",
        .color_temp => "Color temp",
        .color_xy => "Color XY",
        .effect => "Effect",
        .min_brightness => "Min brightness",
        .max_brightness => "Max brightness",
        .light_type => "Light type",
        .countdown => "Countdown",
        .child_lock => "Child lock",
        .contact => "Contact",
        .device_temperature => "Device temperature",
        .power_outage_count => "Power outage count",
        .trigger_count => "Trigger count",
        .battery => "Battery",
        else => "",
    };
}

pub fn dropdownLabels(f: Field) []const []const u8 {
    return switch (f) {
        .effect => effect_labels[0..],
        .light_type => light_type_labels[0..],
        else => &[_][]const u8{},
    };
}

pub fn dropdownValue(snap: Snap, f: Field) []const u8 {
    const labs = dropdownLabels(f);
    if (labs.len == 0) return "--";
    const idx: usize = switch (f) {
        .effect => @min(snap.effect_idx, @as(u8, @intCast(labs.len - 1))),
        .light_type => @min(snap.light_type_idx, @as(u8, @intCast(labs.len - 1))),
        else => 0,
    };
    return labs[idx];
}

/// Horizontal RGB-ish gradient + XY marker (ponytail: spectrum hex; frame uses theme).
pub fn paintColorBar(logical: *fb.LogicalFb, r: geom.Rect, snap: Snap, theme: tokens.Theme) void {
    widgets.fillRoundRect(logical, r, tokens.Shape.xs, theme.surface_container_high);
    const inset = tokens.Space.xs;
    const inner: geom.Rect = .{
        .x = r.x + inset,
        .y = r.y + inset,
        .w = @max(1, r.w - inset * 2),
        .h = @max(1, r.h - inset * 2),
    };
    const w = inner.w;
    // ponytail: literal spectrum stops — not theme-derived; border/marker are.
    const left = color.Rgb565.fromHex(0xff0044);
    const mid = color.Rgb565.fromHex(0x44ff88);
    const right = color.Rgb565.fromHex(0x4488ff);
    var x: i32 = 0;
    while (x < w) : (x += 1) {
        const t: f32 = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(w));
        const c = if (t < 0.5)
            color.blendRgb565(left, mid, @intFromFloat(t * 2.0 * 255.0))
        else
            color.blendRgb565(mid, right, @intFromFloat((t - 0.5) * 2.0 * 255.0));
        logical.fillRect(.{ .x = inner.x + x, .y = inner.y, .w = 1, .h = inner.h }, c);
    }
    widgets.strokeRoundRect(logical, r, tokens.Shape.xs, theme.outline_variant, 1);
    const marker: i32 = 12;
    const mx = inner.x + @divTrunc(@as(i32, @intCast(snap.color_x)) * @max(1, w - marker), 65535);
    const my = inner.y + @divTrunc(@as(i32, @intCast(snap.color_y)) * @max(1, inner.h - marker), 65535);
    widgets.fillRoundRect(logical, .{ .x = mx, .y = my, .w = marker, .h = marker }, tokens.Shape.full, theme.on_surface);
    widgets.strokeRoundRect(logical, .{ .x = mx, .y = my, .w = marker, .h = marker }, tokens.Shape.full, theme.outline, 1);
}

pub fn paintSliderRow(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    r: geom.Rect,
    label: []const u8,
    pct: u8,
    value_text: ?[]const u8,
) void {
    font.drawTextRole(logical, r.x + tokens.Space.sm, r.y, label, theme.on_surface_variant, .label_m);
    if (value_text) |vt| {
        const tw = font.textWidthStr(vt, .label_m);
        font.drawTextRole(logical, r.x + r.w - tw - tokens.Space.sm, r.y, vt, theme.on_surface_variant, .label_m);
    }
    const track_y = r.y + font.faceHeight(font.faceForRole(.label_m)) + tokens.Space.xs;
    const track: geom.Rect = .{ .x = r.x + tokens.Space.sm, .y = track_y, .w = r.w - tokens.Space.md, .h = 8 };
    widgets.drawSlider(logical, track, @as(f32, @floatFromInt(pct)) / 100.0, theme);
}

test "derive exposes for light cap" {
    const snap: Snap = .{ .caps = settings_prefs.ZbCap.level | settings_prefs.ZbCap.color };
    const ex = active(snap);
    try std.testing.expect((ex & E.brightness) != 0);
    try std.testing.expect((ex & E.color_temp) != 0);
}

test "countdown round trip" {
    const s: u32 = 3600;
    const pct = countdownPct(s);
    try std.testing.expect(countdownFromPct(pct) > 0);
}
