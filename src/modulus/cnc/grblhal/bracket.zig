//! grblHAL bracket message parsing — [MSG:], [GC:], [OPT:], etc.

const std = @import("std");
const str_util = @import("../../core/str_util.zig");
const parse_util = @import("parse_util.zig");
const capabilities = @import("capabilities.zig");
const cnc_state = @import("../cnc_state.zig");
const parse_event = @import("parse_event.zig");
const probe_parse = @import("probe_parse.zig");

pub const Context = struct {
    status: *cnc_state.MachineStatus,
    ctrl_info: *capabilities.ControllerInfo,
    last_msg: *[128]u8,
};

pub fn parseBracketMessage(ctx: *Context, data: []const u8) parse_event.ParseEvent {
    if (std.mem.cutPrefix(u8, data, "MSG:")) |body| {
        str_util.copy(ctx.last_msg, body);
        return .message;
    }
    if (std.mem.cutPrefix(u8, data, "GC:")) |body| {
        parseGcState(ctx.status, body);
        return .parser_state_update;
    }
    if (std.mem.cutPrefix(u8, data, "OPT:")) |body| {
        capabilities.parseOptLine(body, ctx.ctrl_info);
        return .info_response;
    }
    if (std.mem.cutPrefix(u8, data, "AXS:")) |body| {
        capabilities.parseAxesInfo(body, ctx.ctrl_info);
        return .info_response;
    }
    if (data.len > 7 and std.mem.startsWith(u8, data, "NEWOPT:")) {
        capabilities.parseNewopt(data[7..], &ctx.ctrl_info.caps);
        return .info_response;
    }
    if (data.len > 9 and std.mem.startsWith(u8, data, "FIRMWARE:")) {
        str_util.copy(&ctx.ctrl_info.firmware, data[9..]);
        return .info_response;
    }
    if (data.len > 15 and std.mem.startsWith(u8, data, "DRIVER VERSION:")) {
        str_util.copy(&ctx.ctrl_info.driver_ver, data[15..]);
        return .info_response;
    }
    if (data.len > 7 and std.mem.startsWith(u8, data, "DRIVER:")) {
        str_util.copy(&ctx.ctrl_info.driver, data[7..]);
        return .info_response;
    }
    if (data.len > 6 and std.mem.startsWith(u8, data, "BOARD:")) {
        str_util.copy(&ctx.ctrl_info.board, data[6..]);
        return .info_response;
    }
    if (data.len > 8 and std.mem.startsWith(u8, data, "SETTING:")) return .setting_enum;
    if (data.len > 13 and std.mem.startsWith(u8, data, "SETTINGGROUP:")) return .setting_group_enum;
    if (data.len > 10 and std.mem.startsWith(u8, data, "ALARMCODE:")) return .alarm_enum;
    if (data.len > 10 and std.mem.startsWith(u8, data, "ERRORCODE:")) return .error_enum;
    if (data.len > 8 and std.mem.startsWith(u8, data, "SPINDLE:")) return .spindle_enum;
    if (std.mem.cutPrefix(u8, data, "PRB:")) |body| {
        _ = probe_parse.applyProbeBody(ctx.status, body);
        return .probe_result;
    }
    str_util.copy(ctx.last_msg, data);
    return .feedback;
}

fn parseGcState(status: *cnc_state.MachineStatus, data: []const u8) void {
    var parts = std.mem.splitScalar(u8, data, ' ');
    while (parts.next()) |tok| {
        if (tok.len < 2) continue;
        switch (tok[0]) {
            'T' => {
                // T / T0 / T01 / T99 from $G — active tool from G-code modal.
                if (tok.len >= 2 and tok[1] >= '0' and tok[1] <= '9') {
                    status.tool_number = parse_util.parseU8(tok[1..]) orelse status.tool_number;
                }
            },
            'F' => status.feed_target = std.fmt.parseFloat(f32, tok[1..]) catch 0,
            'S' => {
                const spd = std.fmt.parseFloat(f32, tok[1..]) catch 0;
                status.spindle_target = @trunc(spd);
            },
            else => {},
        }
    }
}

test "cnc: bracket GC parsing" {
    const parser_mod = @import("parser.zig");
    var p = parser_mod.Parser.init();
    const evt = p.parseLine("[GC:G0 G54 G17 G21 G90 M5 M9 T3 F500 S12000]");
    try std.testing.expectEqual(parse_event.ParseEvent.parser_state_update, evt);
    try std.testing.expectEqual(@as(u8, 3), p.status.tool_number);
    try std.testing.expectEqual(@as(f32, 500), p.status.feed_target);
    try std.testing.expectEqual(@as(u32, 12000), p.status.spindle_target);
}
