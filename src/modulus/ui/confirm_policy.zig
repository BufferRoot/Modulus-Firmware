//! Homogeneous confirm policy for cycle / spindle / zero / home / macro.
//! NVS values: 0=never, 1=always, 2=when_run (default for zero).

const std = @import("std");
const cnc_state = @import("../cnc/cnc_state.zig");
const settings_keys = @import("../core/settings_keys.zig");

pub const Policy = enum(u8) {
    never = 0,
    always = 1,
    when_run = 2,
};

pub const Action = enum {
    cycle,
    spindle,
    zero,
    home,
    macro,
};

pub fn defaultPolicy(action: Action) Policy {
    return switch (action) {
        .zero => .when_run,
        else => .never,
    };
}

pub fn nvsKey(action: Action) []const u8 {
    return switch (action) {
        .cycle => settings_keys.cnf_cycle,
        .spindle => settings_keys.cnf_spin,
        .zero => settings_keys.cnf_zero,
        .home => settings_keys.cnf_home,
        .macro => settings_keys.cnf_mac,
    };
}

pub fn parsePolicy(raw: u8) Policy {
    return switch (raw) {
        1 => .always,
        2 => .when_run,
        else => .never,
    };
}

pub fn needsConfirm(policy: Policy, state: cnc_state.MachineState) bool {
    return switch (policy) {
        .never => false,
        .always => state != .disconnected,
        .when_run => state == .run,
    };
}

pub fn needsConfirmRaw(policy_u8: u8, state: cnc_state.MachineState) bool {
    return needsConfirm(parsePolicy(policy_u8), state);
}

/// Legacy zero-while-run helper (policy default when_run).
pub fn needsConfirmZero(state: cnc_state.MachineState) bool {
    return needsConfirm(.when_run, state);
}

test "confirm policy: never / always / when_run" {
    try std.testing.expect(!needsConfirm(.never, .run));
    try std.testing.expect(!needsConfirm(.never, .idle));
    try std.testing.expect(needsConfirm(.always, .idle));
    try std.testing.expect(needsConfirm(.always, .run));
    try std.testing.expect(!needsConfirm(.always, .disconnected));
    try std.testing.expect(needsConfirm(.when_run, .run));
    try std.testing.expect(!needsConfirm(.when_run, .idle));
    try std.testing.expect(!needsConfirm(.when_run, .hold));
}

test "confirm policy: defaults and keys" {
    try std.testing.expect(defaultPolicy(.zero) == .when_run);
    try std.testing.expect(defaultPolicy(.cycle) == .never);
    try std.testing.expectEqualStrings("cnf_zero", nvsKey(.zero));
    try std.testing.expectEqualStrings("cnf_cycle", nvsKey(.cycle));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(parsePolicy(2)));
}
