//! Status-bar battery glyph + tint from charge state and SoC.

const color = @import("color.zig");
const icons_phosphor = @import("icons_phosphor.zig");
const tokens = @import("tokens.zig");

/// Charge current (mA) at/above this → quick/fast charger chrome.
/// ponytail: crude rate gate; upgrade when charger IC exposes QC/PD mode.
pub const fast_charge_ma: f32 = 800.0;

pub const Chrome = struct {
    icon: icons_phosphor.Id,
    fg: color.Rgb565,
};

/// `charge_state`: 0=discharging 1=charging 2=full 3=error/no pack.
pub fn forState(theme: tokens.Theme, chrome: color.Rgb565, charge_state: u8, pct: u8, fast: bool) Chrome {
    const green = color.Rgb565.fromHex(0x24D391);
    const blue = color.Rgb565.fromHex(0x3B82F6);
    const amber = color.Rgb565.fromHex(0xFFB800);
    const p = @min(pct, 100);

    if (charge_state == 3) {
        return .{ .icon = .battery_warning, .fg = theme.err };
    }
    if (charge_state == 1) {
        if (fast) return .{ .icon = .battery_plus, .fg = blue };
        return .{ .icon = .battery_charging, .fg = green };
    }
    if (charge_state == 2) {
        return .{ .icon = .battery_full, .fg = green };
    }
    // Discharging — Phosphor vertical fill tiers.
    if (p >= 90) return .{ .icon = .battery_full, .fg = green };
    if (p >= 71) return .{ .icon = .battery_high, .fg = chrome };
    if (p >= 41) return .{ .icon = .battery_medium, .fg = chrome };
    if (p >= 11) return .{ .icon = .battery_low, .fg = amber };
    return .{ .icon = .battery_empty, .fg = theme.err };
}

pub fn isFastCharge(charge_state: u8, rate_ma: f32) bool {
    return charge_state == 1 and rate_ma >= fast_charge_ma;
}

test "battery chrome tiers" {
    const std = @import("std");
    const theme = tokens.Theme.industrialTealDark();
    const chrome = theme.on_surface_variant;

    try std.testing.expectEqual(icons_phosphor.Id.battery_warning, forState(theme, chrome, 3, 50, false).icon);
    try std.testing.expectEqual(icons_phosphor.Id.battery_charging, forState(theme, chrome, 1, 40, false).icon);
    try std.testing.expectEqual(icons_phosphor.Id.battery_plus, forState(theme, chrome, 1, 40, true).icon);
    try std.testing.expectEqual(icons_phosphor.Id.battery_full, forState(theme, chrome, 2, 100, false).icon);
    try std.testing.expectEqual(icons_phosphor.Id.battery_full, forState(theme, chrome, 0, 95, false).icon);
    try std.testing.expectEqual(icons_phosphor.Id.battery_high, forState(theme, chrome, 0, 80, false).icon);
    try std.testing.expectEqual(icons_phosphor.Id.battery_medium, forState(theme, chrome, 0, 55, false).icon);
    try std.testing.expectEqual(icons_phosphor.Id.battery_low, forState(theme, chrome, 0, 25, false).icon);
    try std.testing.expectEqual(icons_phosphor.Id.battery_empty, forState(theme, chrome, 0, 5, false).icon);
    try std.testing.expect(isFastCharge(1, 900));
    try std.testing.expect(!isFastCharge(1, 200));
    try std.testing.expect(!isFastCharge(0, 2000));
}
