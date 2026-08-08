//! grblHAL probe coordinate readback — `[PRB:x,y,z:1]` and `|PRB:…|`.

const std = @import("std");
const cnc_state = @import("../cnc_state.zig");

/// Parse `x,y,z:1` body (machine coords + success flag).
pub fn applyProbeBody(status: *cnc_state.MachineStatus, body: []const u8) bool {
    const colon = std.mem.lastIndexOfScalar(u8, body, ':') orelse return false;
    if (colon + 1 >= body.len) return false;
    parsePosition(body[0..colon], &status.probe_mpos);
    status.probe_ok = body[colon + 1] == '1';
    status.probe_fresh = true;
    return true;
}

fn parsePosition(val: []const u8, pos: *cnc_state.Position) void {
    var iter = std.mem.splitScalar(u8, val, ',');
    const fields = [_]*f32{ &pos.x, &pos.y, &pos.z, &pos.a, &pos.b, &pos.c };
    var i: usize = 0;
    while (iter.next()) |part| : (i += 1) {
        if (i >= fields.len) break;
        fields[i].* = std.fmt.parseFloat(f32, part) catch 0;
    }
}

test "cnc: probe PRB body parse" {
    var st: cnc_state.MachineStatus = .{};
    try std.testing.expect(applyProbeBody(&st, "1.5,2.0,-0.25:1"));
    try std.testing.expect(st.probe_fresh);
    try std.testing.expect(st.probe_ok);
    try std.testing.expectEqual(@as(f32, 1.5), st.probe_mpos.x);
    try std.testing.expectEqual(@as(f32, 2.0), st.probe_mpos.y);
    try std.testing.expectEqual(@as(f32, -0.25), st.probe_mpos.z);
    try std.testing.expect(applyProbeBody(&st, "0,0,0:0"));
    try std.testing.expect(!st.probe_ok);
}
