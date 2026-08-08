//! Core 0 DRO vector batch — packs WPos/MPos axes for C ABI fill (no heap).

const cnc_state = @import("../cnc/cnc_state.zig");
const device_ui = @import("device_ui.zig");

pub const AxisVec6 = @Vector(6, f32);

pub fn packPosition(pos: cnc_state.Position) AxisVec6 {
    return .{ pos.x, pos.y, pos.z, pos.a, pos.b, pos.c };
}

pub fn storeWpos(out: *device_ui.CncStatus, v: AxisVec6) void {
    out.wpos_x = v[0];
    out.wpos_y = v[1];
    out.wpos_z = v[2];
    out.wpos_a = v[3];
    out.wpos_b = v[4];
    out.wpos_c = v[5];
}

pub fn storeMpos(out: *device_ui.CncStatus, v: AxisVec6) void {
    out.mpos_x = v[0];
    out.mpos_y = v[1];
    out.mpos_z = v[2];
    out.mpos_a = v[3];
    out.mpos_b = v[4];
    out.mpos_c = v[5];
}

/// Max absolute axis — cheap hint for adaptive UI refresh heuristics.
pub fn maxAbsAxis(v: AxisVec6) f32 {
    const abs_v = @abs(v);
    return @reduce(.Max, abs_v);
}

test "ui: dro vector pack/store round-trip" {
    var pos: cnc_state.Position = .{ .x = 1.5, .y = -2.0, .z = 0.25, .a = 90.0, .b = 45.0, .c = -10.0 };
    const v = packPosition(pos);
    try @import("std").testing.expectEqual(@as(f32, 90.0), maxAbsAxis(v));

    var st: device_ui.CncStatus = .{};
    storeWpos(&st, v);
    try @import("std").testing.expectEqual(@as(f32, 1.5), st.wpos_x);
    try @import("std").testing.expectEqual(@as(f32, -2.0), st.wpos_y);
    try @import("std").testing.expectEqual(@as(f32, 45.0), st.wpos_b);
    try @import("std").testing.expectEqual(@as(f32, -10.0), st.wpos_c);

    pos.x = 3.0;
    storeMpos(&st, packPosition(pos));
    try @import("std").testing.expectEqual(@as(f32, 3.0), st.mpos_x);
}
