//! Host tests for probe_engine — PRB-gated step advance.

const std = @import("std");
const testing = std.testing;
const probe_engine = @import("probe_engine.zig");
const cnc_state = @import("cnc_state.zig");
const driver_mod = @import("driver.zig");
const test_util = @import("driver_test_util.zig");

const Driver = driver_mod.Driver;

test "probe: driver cmdProbeStart sends G-code" {
    var drv = Driver.init(.{});
    var tx: usize = 0;
    drv.setSendFn(test_util.countSend(&tx));
    test_util.connectToReady(&drv, 0);
    drv.feed("ok\n");
    drv.feed("<Idle|MPos:0,0,0>\n");
    drv.poll(0);
    try testing.expect(drv.cmdProbeStart(.z_plate));
    try testing.expect(tx > 0);
}

test "probe: bracket PRB parse marks fresh" {
    const parser_mod = @import("grblhal/parser.zig");
    const parse_event = @import("grblhal/parse_event.zig");
    var p = parser_mod.Parser.init();
    try testing.expectEqual(parse_event.ParseEvent.probe_result, p.parseLine("[PRB:1.0,2.0,-0.5:1]"));
    try testing.expect(p.status.probe_fresh);
    try testing.expect(p.status.probe_ok);
}

test "probe: center midpoint math" {
    var pe: probe_engine.Engine = .{};
    pe.cycle = .center;
    pe.step = 3;
    pe.wait = .probe;
    pe.got_ok = true;
    pe.x_hi = 12.0;
    var st: cnc_state.MachineStatus = .{};
    st.probe_fresh = true;
    st.probe_ok = true;
    st.probe_mpos = .{ .x = 8.0 };
    var tx: usize = 0;
    var drv = Driver.init(.{});
    drv.setSendFn(test_util.countSend(&tx));
    drv.snapshot.state = .idle;
    pe.phase = .running;
    pe.onEvent(.probe_result, &st, &drv);
    try testing.expectEqual(@as(f32, 10.0), pe.center_x);
}
