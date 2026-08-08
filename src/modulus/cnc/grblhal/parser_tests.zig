//! grblHAL parser integration tests.

const std = @import("std");
const cnc_state = @import("../cnc_state.zig");
const rt = @import("rt.zig");
const parser_mod = @import("parser.zig");

const Parser = parser_mod.Parser;
const ParseEvent = parser_mod.ParseEvent;

test "cnc: parser status report" {
    var p = Parser.init();
    const evt = p.parseLine("<Idle|MPos:1.0,2.0,3.0|FS:500,12000>");
    try std.testing.expectEqual(ParseEvent.status_report, evt);
    try std.testing.expectEqual(cnc_state.MachineState.idle, p.status.state);
    try std.testing.expectEqual(@as(f32, 1.0), p.status.mpos.x);
    try std.testing.expectEqual(@as(u32, 12000), p.status.spindle_speed);
}

test "cnc: parser status |T:n| updates tool_number from gcode tool change" {
    var p = Parser.init();
    _ = p.parseLine("<Idle|MPos:0,0,0|T:7|FS:0,0>");
    try std.testing.expectEqual(@as(u8, 7), p.status.tool_number);
    _ = p.parseLine("<Run|MPos:1,0,0|T:12>");
    try std.testing.expectEqual(@as(u8, 12), p.status.tool_number);
}

test "cnc: parser MPos+WCO derives WPos" {
    var p = Parser.init();
    _ = p.parseLine("<Run|MPos:10.0,20.0,5.0|WCO:1.0,2.0,3.0|FS:500,0>");
    try std.testing.expectEqual(cnc_state.MachineState.run, p.status.state);
    try std.testing.expectEqual(@as(f32, 9.0), p.status.wpos.x);
    try std.testing.expectEqual(@as(f32, 18.0), p.status.wpos.y);
    try std.testing.expectEqual(@as(f32, 2.0), p.status.wpos.z);
}

test "cnc: parser WPos+WCO derives MPos" {
    var p = Parser.init();
    _ = p.parseLine("<Idle|WPos:9.0,18.0,2.0|WCO:1.0,2.0,3.0>");
    try std.testing.expectEqual(@as(f32, 10.0), p.status.mpos.x);
    try std.testing.expectEqual(@as(f32, 20.0), p.status.mpos.y);
    try std.testing.expectEqual(@as(f32, 5.0), p.status.mpos.z);
}

test "cnc: parser door/check/sleep/tool states" {
    var p = Parser.init();
    _ = p.parseLine("<Door:1|MPos:0,0,0>");
    try std.testing.expectEqual(cnc_state.MachineState.door, p.status.state);
    try std.testing.expectEqual(@as(u8, 1), p.status.door_substate);
    _ = p.parseLine("<Check|MPos:0,0,0>");
    try std.testing.expectEqual(cnc_state.MachineState.check, p.status.state);
    _ = p.parseLine("<Sleep|MPos:0,0,0>");
    try std.testing.expectEqual(cnc_state.MachineState.sleep, p.status.state);
    _ = p.parseLine("<Tool|MPos:0,0,0>");
    try std.testing.expectEqual(cnc_state.MachineState.tool, p.status.state);
}

test "cnc: parser WCS Ln Bf H Pn FS-actual tags" {
    var p = Parser.init();
    _ = p.parseLine("<Run|MPos:0,0,0|FS:500,12000,11950|Bf:30,512|Ln:42|WCS:G55|H:1,7|Pn:XYZ>");
    try std.testing.expectEqual(cnc_state.WCS.g55, p.status.wcs);
    try std.testing.expectEqual(@as(u32, 42), p.status.line_number);
    try std.testing.expectEqual(@as(u16, 30), p.status.buf_plan);
    try std.testing.expectEqual(@as(u16, 512), p.status.buf_rx);
    try std.testing.expectEqual(@as(u32, 11950), p.status.spindle_actual);
    try std.testing.expect(p.status.homed);
    try std.testing.expectEqual(@as(u8, 7), p.status.homed_axes);
    try std.testing.expectEqual(rt.pin.LIMIT_X | rt.pin.LIMIT_Y | rt.pin.LIMIT_Z, p.status.pin_state);
    // Omitting |Pn: means all pins released — must clear, not latch.
    _ = p.parseLine("<Idle|MPos:0,0,0|WCS:G59.3>");
    try std.testing.expectEqual(@as(u32, 0), p.status.pin_state);
    try std.testing.expectEqual(cnc_state.WCS.g59_3, p.status.wcs);
}

test "cnc: parser PRB bracket and status tag" {
    var p = Parser.init();
    try std.testing.expectEqual(ParseEvent.probe_result, p.parseLine("[PRB:1.0,2.0,-0.5:1]"));
    try std.testing.expect(p.status.probe_fresh);
    _ = p.parseLine("<Idle|MPos:0,0,0|PRB:3,4,5:1>");
    try std.testing.expectEqual(@as(f32, 3.0), p.status.probe_mpos.x);
}

test "cnc: parser tool-change accessory bit" {
    var p = Parser.init();
    _ = p.parseLine("<Tool|MPos:0,0,0|A:ST>");
    try std.testing.expectEqual(rt.accessory.SPINDLE_CW | rt.accessory.TOOL_CHANGE, p.status.accessories);
}

test "cnc: parser ok alarm welcome" {
    var p = Parser.init();
    try std.testing.expectEqual(ParseEvent.ok, p.parseLine("ok"));
    try std.testing.expectEqual(ParseEvent.alarm, p.parseLine("ALARM:1"));
    try std.testing.expectEqual(@as(u8, 1), p.last_alarm);
    try std.testing.expectEqual(ParseEvent.welcome, p.parseLine("GrblHAL 1.1f ['$' for help]"));
}

test "cnc: parser SD D Sc TLR In tags" {
    var p = Parser.init();
    _ = p.parseLine("<Idle|MPos:0,0,0|SD:1|D:1|Sc:XY|TLR:1|In:-3>");
    try std.testing.expectEqual(@as(u8, 1), p.status.sd_state);
    try std.testing.expect(p.status.diameter_mode);
    try std.testing.expectEqual(@as(u8, 0b11), p.status.scaled_axes);
    try std.testing.expect(p.status.tlr_set);
    try std.testing.expectEqual(@as(i16, -3), p.status.last_input_result);
    _ = p.parseLine("<Run|MPos:0,0,0|SD:45.5,job.nc>");
    try std.testing.expect(p.status.sd_streaming);
    try std.testing.expectEqual(@as(f32, 45.5), p.status.sd_percent);
    try std.testing.expectEqualStrings("job.nc", std.mem.sliceTo(&p.status.sd_file, 0));
    _ = p.parseLine("<Run|MPos:0,0,0|SD:10.0,/nc/parts/foo.ngc>");
    try std.testing.expectEqualStrings("foo.ngc", std.mem.sliceTo(&p.status.sd_file, 0));
    _ = p.parseLine("<Run|MPos:0,0,0|SD:33.0>");
    try std.testing.expect(p.status.sd_streaming);
    try std.testing.expectEqual(@as(f32, 33.0), p.status.sd_percent);
    _ = p.parseLine("<Run|MPos:0,0,0|Percent:67.5>");
    try std.testing.expectEqual(@as(f32, 67.5), p.status.sd_percent);
}

test "cnc: parser setting line" {
    var p = Parser.init();
    const evt = p.parseLine("$22=1");
    try std.testing.expectEqual(ParseEvent.setting, evt);
    try std.testing.expectEqual(@as(u16, 22), p.last_setting_id);
    try std.testing.expectEqualStrings("1", std.mem.sliceTo(&p.last_setting_val, 0));
}

test "cnc: parser info_response NEWOPT" {
    var p = Parser.init();
    const evt = p.parseLine("[NEWOPT:ENUMS,SD,WIFI]");
    try std.testing.expectEqual(ParseEvent.info_response, evt);
    try std.testing.expect(p.ctrl_info.caps.enums);
    try std.testing.expect(p.ctrl_info.caps.sd_card);
    try std.testing.expect(p.ctrl_info.caps.wifi);
}
