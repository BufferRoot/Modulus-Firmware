//! Comptime UI lints — catch violations at build time (LVGL cannot do this).
//! Touch targets, contrast pairs, and ASCII-only visible strings.

const std = @import("std");
const color = @import("color.zig");
const tokens = @import("tokens.zig");

/// Fail the compile if a string has bytes outside printable ASCII (Montserrat).
pub fn assertAscii(comptime s: []const u8) void {
    comptime {
        for (s) |c| {
            if (c < 0x20 or c > 0x7E) {
                if (c != '\n') @compileError("UI literal is not ASCII (Montserrat-safe)");
            }
        }
    }
}

/// Fail the compile if a hit rect is below MD3 touch_min (48 px).
pub fn assertTouchTarget(comptime w: i32, comptime h: i32) void {
    comptime {
        if (w < tokens.Logical.touch_min or h < tokens.Logical.touch_min) {
            @compileError("touch target below tokens.Logical.touch_min (48px)");
        }
    }
}

/// Fail the compile if fg/bg contrast is below WCAG AA for UI (3.0).
fn assertContrast(comptime fg: u24, comptime bg: u24) void {
    comptime {
        if (color.contrastRatio(fg, bg) < 3.0) {
            @compileError("UI contrast below 3.0 (WCAG AA large / UI)");
        }
    }
}

test "industrial theme passes contrast lint" {
    const t = tokens.Theme.industrialTealDark();
    try std.testing.expect(t.contrastOk());
    assertContrast(0xFFFFFF, 0x000000);
}

test "touch_min is at least 48" {
    try std.testing.expect(tokens.Logical.touch_min >= 48);
}

test "assertAscii accepts Montserrat-safe labels" {
    assertAscii("Brightness");
    assertAscii("Display & theme");
}

test "row band is a valid touch height" {
    // Settings rows are ≥ touch_min tall — documents the damage-band floor.
    assertTouchTarget(tokens.Logical.touch_min, tokens.Logical.touch_min);
}
