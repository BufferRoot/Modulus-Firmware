//! Masso Link RX parser — status/version/config (RE'd fields only).

const std = @import("std");
const cnc_state = @import("../cnc_state.zig");
const crc = @import("crc.zig");

pub const ParseEvent = enum(u8) {
    none = 0,
    version,
    config,
    status,
    bad_crc,
};

pub const Parser = struct {
    status: cnc_state.MachineStatus = .{},
    serial_num: u16 = 0,
    version_ok: bool = false,
    config_ok: bool = false,
    job_pct: u8 = 0,
    line_number: u8 = 0,
    last_line_ms: u32 = 0,
    hold_suspect: bool = false,

    pub fn init() Parser {
        return .{};
    }

    /// Feed one complete UDP datagram.
    pub fn parsePacket(self: *Parser, data: []const u8, tick_ms: u32) ParseEvent {
        if (data.len < 5) return .none;
        const expect = crc.crc16Ccitt(data[2..]);
        const got: u16 = @as(u16, data[0]) | (@as(u16, data[1]) << 8);
        if (got != expect) return .bad_crc;
        if (data[2] != 0x03 or data[3] != 0x00) return .none;
        const typ = data[4];
        return switch (typ) {
            0x02 => self.onVersion(data),
            0x03 => self.onConfig(data),
            0x01 => self.onStatus(data, tick_ms),
            else => .none,
        };
    }

    fn onVersion(self: *Parser, data: []const u8) ParseEvent {
        _ = data;
        self.version_ok = true;
        return .version;
    }

    fn onConfig(self: *Parser, data: []const u8) ParseEvent {
        if (data.len >= 7) {
            self.serial_num = @as(u16, data[5]) | (@as(u16, data[6]) << 8);
        }
        self.config_ok = true;
        return .config;
    }

    fn onStatus(self: *Parser, data: []const u8, tick_ms: u32) ParseEvent {
        // 270-byte status: byte5 progress, byte6 run flag, byte12 prompt, byte13 line.
        if (data.len < 14) return .none;
        self.job_pct = data[5];
        const run = data[6] == 0x02;
        const line = data[13];
        if (line != self.line_number) {
            self.line_number = line;
            self.last_line_ms = tick_ms;
            self.hold_suspect = false;
        } else if (run and line > 0 and tick_ms -% self.last_line_ms >= 1500) {
            self.hold_suspect = true;
        }
        if (data[12] == 0x00) {
            self.status.state = .hold;
        } else if (self.hold_suspect) {
            self.status.state = .hold;
        } else if (run) {
            self.status.state = .run;
        } else {
            self.status.state = .idle;
        }
        self.status.sd_percent = @as(f32, @floatFromInt(self.job_pct));
        // DRO XYZ not present in published Link status — leave previous/zero.
        return .status;
    }
};

test "masso: status maps run/idle" {
    var p = Parser.init();
    var pkt: [270]u8 = .{0} ** 270;
    pkt[2] = 0x03;
    pkt[3] = 0x00;
    pkt[4] = 0x01;
    pkt[5] = 50;
    pkt[6] = 0x02;
    pkt[12] = 0x01;
    pkt[13] = 3;
    const c = crc.crc16Ccitt(pkt[2..]);
    pkt[0] = @truncate(c);
    pkt[1] = @truncate(c >> 8);
    try std.testing.expectEqual(ParseEvent.status, p.parsePacket(&pkt, 100));
    try std.testing.expectEqual(cnc_state.MachineState.run, p.status.state);
}
