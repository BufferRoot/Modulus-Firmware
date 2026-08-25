//! grblHAL alarm/error human-readable strings — grblhal_defs.h.

fn alarm_str(alarm: u8) []const u8 {
    return switch (alarm) {
        0 => "No alarm",
        1 => "Hard limit triggered",
        2 => "Soft limit - target out of range",
        3 => "Reset while in motion",
        4 => "Probe not in initial state",
        5 => "Probe did not contact",
        6 => "Reset during homing",
        7 => "Door open during homing",
        8 => "Homing pull-off failed",
        9 => "Homing switch not found",
        10 => "E-Stop asserted",
        11 => "Homing required",
        12 => "Limit switch engaged",
        13 => "Probe protection triggered",
        14 => "Spindle at speed timeout",
        else => "Unknown alarm",
    };
}

pub fn error_str(code: u8) []const u8 {
    return switch (code) {
        0 => "No error",
        1 => "Expected command letter",
        2 => "Bad number format",
        3 => "Invalid statement",
        4 => "Negative value",
        5 => "Homing disabled",
        6 => "Step pulse min",
        7 => "Setting read fail",
        8 => "Not idle",
        9 => "G-code lock",
        10 => "Soft limit",
        11 => "Overflow",
        12 => "Max step rate exceeded",
        13 => "Check door",
        14 => "Line length exceeded",
        15 => "Travel exceeded",
        16 => "Invalid jog command",
        17 => "Laser requires homing",
        18 => "Homing required",
        20 => "Unsupported command",
        21 => "Modal group violation",
        22 => "Undefined feed rate",
        24 => "Invalid target",
        253 => "User abort",
        else => "Unknown error",
    };
}

const std = @import("std");

test "cnc: alarm_str UI codes" {
    try std.testing.expectEqualStrings("Hard limit triggered", alarm_str(1));
    try std.testing.expectEqualStrings("Soft limit - target out of range", alarm_str(2));
    try std.testing.expectEqualStrings("E-Stop asserted", alarm_str(10));
}

test "cnc: error_str common codes" {
    try std.testing.expectEqualStrings("Not idle", error_str(8));
    try std.testing.expectEqualStrings("Invalid jog command", error_str(16));
    try std.testing.expectEqualStrings("User abort", error_str(253));
}
