//! CNC machine snapshot — mirrors `cnc_state.h` (UI strings English on host).

const std = @import("std");

pub const MachineState = enum(u8) {
    disconnected = 0,
    idle,
    run,
    hold,
    jog,
    alarm,
    door,
    check,
    home,
    sleep,
    tool,
};

pub const Position = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
    a: f32 = 0,
    b: f32 = 0,
    c: f32 = 0,
};

pub const StepSize = enum(u8) {
    step_0_001 = 0,
    step_0_01,
    step_0_1,
    step_1_0,
    _count,
};

pub const JogMode = enum(u8) {
    step = 0,
    cont,
    /// Handwheel velocity sets the jog feed directly (jogspd × wheel speed).
    velo,
};

pub const ActiveAxis = enum(u8) {
    x = 0,
    y,
    z,
    a,
    b,
    c,
    off,
};

pub const WCS = enum(u8) {
    g54 = 0,
    g55,
    g56,
    g57,
    g58,
    g59,
    g59_1,
    g59_2,
    g59_3,
    _count,
};

pub const Overrides = struct {
    feed: u8 = 100,
    rapid: u8 = 100,
    spindle: u8 = 100,
};

pub const SpindleState = enum(u8) {
    stop = 0,
    cw,
    ccw,
};

pub const MachineStatus = struct {
    state: MachineState = .disconnected,
    wpos: Position = .{},
    mpos: Position = .{},
    wco: Position = .{},
    wcs: WCS = .g54,
    feed_rate: f32 = 0,
    feed_target: f32 = 0,
    spindle_speed: u32 = 0,
    spindle_target: u32 = 0,
    spindle_actual: u32 = 0,
    spindle_dir: SpindleState = .stop,
    overrides: Overrides = .{},
    line_number: u32 = 0,
    tool_number: u8 = 0,
    coolant_on: bool = false,
    alarm_code: u8 = 0,
    run_substate: u8 = 0,
    hold_substate: u8 = 0,
    door_substate: u8 = 0,
    buf_plan: u16 = 0,
    buf_rx: u16 = 0,
    pin_state: u32 = 0,
    accessories: u8 = 0,
    homed: bool = false,
    homed_axes: u8 = 0,
    mpg_remote: bool = false,
    active_axis: ActiveAxis = .x,
    step_size: StepSize = .step_0_1,
    jog_mode: JogMode = .step,
    mpg_active: bool = false,
    units_mm: bool = true,
    sd_state: u8 = 0,
    sd_streaming: bool = false,
    sd_percent: f32 = 0,
    /// Basename from SD:pct,path tag (FluidNC/grblHAL) — empty if unknown.
    sd_file: [32]u8 = .{0} ** 32,
    tlr_set: bool = false,
    diameter_mode: bool = false,
    scaled_axes: u8 = 0,
    last_input_result: i16 = 0,
    /// Last grblHAL `[PRB:…]` / `|PRB:…|` readback (machine coords).
    probe_mpos: Position = .{},
    probe_ok: bool = false,
    probe_fresh: bool = false,
};

pub fn activeAxisLetter(a: ActiveAxis) ?u8 {
    return switch (a) {
        .x => 'X',
        .y => 'Y',
        .z => 'Z',
        .a => 'A',
        .b => 'B',
        .c => 'C',
        .off => null,
    };
}

pub fn wcsStr(w: WCS) []const u8 {
    return switch (w) {
        .g54 => "G54",
        .g55 => "G55",
        .g56 => "G56",
        .g57 => "G57",
        .g58 => "G58",
        .g59 => "G59",
        .g59_1 => "G59.1",
        .g59_2 => "G59.2",
        .g59_3 => "G59.3",
        else => "?",
    };
}

/// G10 L20 / L2 `P` word for a WCS. G54→1 … G59.3→9.
/// Never 0 — classic Grbl and many controllers reject `P0` (error 2 / ignored).
pub fn wcsG10P(w: WCS) u8 {
    const idx = @intFromEnum(w);
    if (idx >= @intFromEnum(WCS._count)) return 1;
    return @intCast(idx + 1);
}

pub fn stepSizeVal(s: StepSize) f32 {
    return switch (s) {
        .step_0_001 => 0.001,
        .step_0_01 => 0.01,
        .step_0_1 => 0.1,
        .step_1_0 => 1.0,
        else => 0.1,
    };
}

// ── tests ──

test "cnc: wcsStr covers all offsets" {
    try std.testing.expectEqualStrings("G54", wcsStr(.g54));
    try std.testing.expectEqualStrings("G59.3", wcsStr(.g59_3));
}

test "cnc: stepSizeVal maps jog steps" {
    try std.testing.expectEqual(@as(f32, 0.001), stepSizeVal(.step_0_001));
    try std.testing.expectEqual(@as(f32, 1.0), stepSizeVal(.step_1_0));
}

test "cnc: activeAxisLetter" {
    try std.testing.expectEqual(@as(?u8, 'Z'), activeAxisLetter(.z));
    try std.testing.expectEqual(@as(?u8, null), activeAxisLetter(.off));
}
