//! grblHAL probe engine — multi-touch cycles with `[PRB:…]` readback between moves.
//! Core 1 / poll-driven; fixed buffers only (no heap).

const std = @import("std");
const cnc_state = @import("cnc_state.zig");
const settings_keys = @import("../core/settings_keys.zig");
const settings_store = @import("../core/settings_store.zig");
const parse_event = @import("grblhal/parse_event.zig");
const driver_ops = @import("driver_ops.zig");

pub const Cycle = enum(u8) {
    z_plate = 0,
    edge_x_neg = 1,
    edge_y_neg = 2,
    center = 3,
    edge_180_x = 4,
    tool_setter = 5,
};

pub const Config = struct {
    plate_z: f32 = 10,
    max_travel: f32 = 25,
    feed: f32 = 75,
    retract: f32 = 2,
    tip_dia: f32 = 2,

    pub fn fromStore(store: ?*settings_store.Store) Config {
        var c: Config = .{};
        if (store) |s| {
            c.plate_z = @as(f32, @floatFromInt(s.getU16(settings_keys.pb_zoff, 100))) / 10.0;
            c.max_travel = @as(f32, @floatFromInt(s.getU16(settings_keys.pb_max, 250))) / 10.0;
            c.feed = @as(f32, @floatFromInt(s.getU16(settings_keys.pb_feed, 750))) / 10.0;
            c.retract = @as(f32, @floatFromInt(s.getU16(settings_keys.pb_retr, 20))) / 10.0;
            c.tip_dia = @as(f32, @floatFromInt(s.getU16(settings_keys.pb_tip, 20))) / 10.0;
        }
        return c;
    }
};

const Phase = enum(u8) {
    idle,
    running,
    done,
    failed,
};

const Wait = enum(u8) {
    none,
    ok,
    probe, // ok + PRB after G38.2
};

pub const Engine = struct {
    phase: Phase = .idle,
    cycle: Cycle = .z_plate,
    step: u8 = 0,
    cfg: Config = .{},
    wait: Wait = .none,
    got_ok: bool = false,
    deadline_ms: u32 = 0,
    x_hi: f32 = 0,
    x_lo: f32 = 0,
    y_hi: f32 = 0,
    y_lo: f32 = 0,
    center_x: f32 = 0,
    center_y: f32 = 0,

    pub fn busy(self: *const Engine) bool {
        return self.phase == .running;
    }

    pub fn failed(self: *const Engine) bool {
        return self.phase == .failed;
    }

    pub fn cancel(self: *Engine) void {
        self.phase = .idle;
        self.wait = .none;
        self.got_ok = false;
    }

    pub fn start(self: *Engine, cycle: Cycle, cfg: Config, drv: anytype) bool {
        if (self.busy()) return false;
        if (drv.snapshot.state != .idle) return false;
        self.* = .{
            .phase = .running,
            .cycle = cycle,
            .cfg = cfg,
        };
        self.advance(drv);
        return self.phase == .running;
    }

    pub fn poll(self: *Engine, tick_ms: u32, drv: anytype) void {
        if (self.phase != .running) return;
        if (tick_ms >= self.deadline_ms and self.deadline_ms != 0) {
            self.fail();
            return;
        }
        if (drv.snapshot.state == .alarm or drv.snapshot.state == .disconnected) {
            self.fail();
        }
    }

    pub fn onEvent(self: *Engine, evt: parse_event.ParseEvent, st: *cnc_state.MachineStatus, drv: anytype) void {
        if (self.phase != .running) return;

        switch (evt) {
            .ok => {
                if (self.wait == .ok or self.wait == .probe) {
                    self.got_ok = true;
                    self.tryAdvanceAfterWait(st, drv);
                }
            },
            .probe_result, .status_report => {
                if (self.wait == .probe and st.probe_fresh) {
                    self.tryAdvanceAfterWait(st, drv);
                }
            },
            .err, .alarm => self.fail(),
            else => {},
        }
    }

    fn tryAdvanceAfterWait(self: *Engine, st: *cnc_state.MachineStatus, drv: anytype) void {
        switch (self.wait) {
            .ok => {
                if (!self.got_ok) return;
                st.probe_fresh = false;
                self.wait = .none;
                self.got_ok = false;
                self.step += 1;
                self.advance(drv);
            },
            .probe => {
                if (!self.got_ok or !st.probe_fresh) return;
                if (!st.probe_ok) {
                    self.fail();
                    return;
                }
                self.captureProbe(st);
                st.probe_fresh = false;
                self.wait = .none;
                self.got_ok = false;
                self.step += 1;
                self.advance(drv);
            },
            .none => {},
        }
    }

    fn captureProbe(self: *Engine, st: *cnc_state.MachineStatus) void {
        switch (self.cycle) {
            .center => switch (self.step) {
                1 => self.x_hi = st.probe_mpos.x,
                3 => {
                    self.x_lo = st.probe_mpos.x;
                    self.center_x = (self.x_hi + self.x_lo) / 2.0;
                },
                5 => self.y_hi = st.probe_mpos.y,
                7 => {
                    self.y_lo = st.probe_mpos.y;
                    self.center_y = (self.y_hi + self.y_lo) / 2.0;
                },
                else => {},
            },
            .edge_180_x => switch (self.step) {
                1 => self.x_hi = st.probe_mpos.x,
                3 => self.center_x = (self.x_hi + st.probe_mpos.x) / 2.0,
                else => {},
            },
            else => {},
        }
    }

    fn fail(self: *Engine) void {
        self.phase = .failed;
        self.wait = .none;
    }

    fn finish(self: *Engine) void {
        self.phase = .done;
        self.wait = .none;
    }

    fn armWait(self: *Engine, wait: Wait, tick_ms: u32) void {
        self.wait = wait;
        self.got_ok = false;
        self.deadline_ms = tick_ms +% 60_000;
    }

    fn sendLine(_: *Engine, drv: anytype, line: []const u8) void {
        driver_ops.sendGcodeClamped(drv, line);
    }

    fn sendFmt(self: *Engine, drv: anytype, comptime fmt: []const u8, args: anytype) void {
        var buf: [64]u8 = undefined;
        const txt = std.fmt.bufPrint(&buf, fmt, args) catch return;
        self.sendLine(drv, txt);
    }

    fn advance(self: *Engine, drv: anytype) void {
        const tick = drv.engine.nowTickMs();
        const max = self.cfg.max_travel;
        const feed = self.cfg.feed;
        const retr = self.cfg.retract;
        const tip_r = self.cfg.tip_dia / 2.0;

        switch (self.cycle) {
            .z_plate => switch (self.step) {
                0 => {
                    self.sendLine(drv, "G91");
                    self.armWait(.ok, tick);
                },
                1 => {
                    self.sendFmt(drv, "G38.2 Z-{d:.1} F{d:.0}", .{ max, feed });
                    self.armWait(.probe, tick);
                },
                2 => {
                    self.sendFmt(drv, "G10 L20 P0 Z{d:.2}", .{self.cfg.plate_z});
                    self.armWait(.ok, tick);
                },
                3 => {
                    self.sendFmt(drv, "G0 Z{d:.1}", .{retr});
                    self.armWait(.ok, tick);
                },
                4 => {
                    self.sendLine(drv, "G90");
                    self.finish();
                },
                else => self.fail(),
            },
            .edge_x_neg => switch (self.step) {
                0 => {
                    self.sendLine(drv, "G91");
                    self.armWait(.ok, tick);
                },
                1 => {
                    self.sendFmt(drv, "G38.2 X-{d:.1} F{d:.0}", .{ max, feed });
                    self.armWait(.probe, tick);
                },
                2 => {
                    self.sendFmt(drv, "G10 L20 P0 X{d:.2}", .{tip_r});
                    self.armWait(.ok, tick);
                },
                3 => {
                    self.sendFmt(drv, "G0 X{d:.1}", .{retr});
                    self.armWait(.ok, tick);
                },
                4 => {
                    self.sendLine(drv, "G90");
                    self.finish();
                },
                else => self.fail(),
            },
            .edge_y_neg => switch (self.step) {
                0 => {
                    self.sendLine(drv, "G91");
                    self.armWait(.ok, tick);
                },
                1 => {
                    self.sendFmt(drv, "G38.2 Y-{d:.1} F{d:.0}", .{ max, feed });
                    self.armWait(.probe, tick);
                },
                2 => {
                    self.sendFmt(drv, "G10 L20 P0 Y{d:.2}", .{tip_r});
                    self.armWait(.ok, tick);
                },
                3 => {
                    self.sendFmt(drv, "G0 Y{d:.1}", .{retr});
                    self.armWait(.ok, tick);
                },
                4 => {
                    self.sendLine(drv, "G90");
                    self.finish();
                },
                else => self.fail(),
            },
            .center => switch (self.step) {
                0 => {
                    self.sendLine(drv, "G91");
                    self.armWait(.ok, tick);
                },
                1 => {
                    self.sendFmt(drv, "G38.2 X{d:.1} F{d:.0}", .{ max, feed });
                    self.armWait(.probe, tick);
                },
                2 => {
                    self.sendFmt(drv, "G0 X-{d:.1}", .{retr});
                    self.armWait(.ok, tick);
                },
                3 => {
                    self.sendFmt(drv, "G38.2 X-{d:.1} F{d:.0}", .{ max, feed });
                    self.armWait(.probe, tick);
                },
                4 => {
                    self.sendFmt(drv, "G0 X{d:.1}", .{retr});
                    self.armWait(.ok, tick);
                },
                5 => {
                    self.sendFmt(drv, "G38.2 Y{d:.1} F{d:.0}", .{ max, feed });
                    self.armWait(.probe, tick);
                },
                6 => {
                    self.sendFmt(drv, "G0 Y-{d:.1}", .{retr});
                    self.armWait(.ok, tick);
                },
                7 => {
                    self.sendFmt(drv, "G38.2 Y-{d:.1} F{d:.0}", .{ max, feed });
                    self.armWait(.probe, tick);
                },
                8 => {
                    self.sendLine(drv, "G90");
                    self.armWait(.ok, tick);
                },
                9 => {
                    self.sendFmt(drv, "G53 G0 X{d:.3} Y{d:.3}", .{ self.center_x, self.center_y });
                    self.armWait(.ok, tick);
                },
                10 => {
                    self.sendLine(drv, "G10 L20 P0 X0 Y0");
                    self.finish();
                },
                else => self.fail(),
            },
            .edge_180_x => switch (self.step) {
                0 => {
                    self.sendLine(drv, "G91");
                    self.armWait(.ok, tick);
                },
                1 => {
                    self.sendFmt(drv, "G38.2 X{d:.1} F{d:.0}", .{ max, feed });
                    self.armWait(.probe, tick);
                },
                2 => {
                    self.sendFmt(drv, "G0 X-{d:.1}", .{retr});
                    self.armWait(.ok, tick);
                },
                3 => {
                    self.sendFmt(drv, "G38.2 X-{d:.1} F{d:.0}", .{ max, feed });
                    self.armWait(.probe, tick);
                },
                4 => {
                    self.sendLine(drv, "G90");
                    self.armWait(.ok, tick);
                },
                5 => {
                    self.sendFmt(drv, "G53 G0 X{d:.3}", .{self.center_x});
                    self.armWait(.ok, tick);
                },
                6 => {
                    self.sendLine(drv, "G10 L20 P0 X0");
                    self.finish();
                },
                else => self.fail(),
            },
            .tool_setter => switch (self.step) {
                0 => {
                    self.sendLine(drv, "G91");
                    self.armWait(.ok, tick);
                },
                1 => {
                    self.sendFmt(drv, "G38.2 Z-{d:.1} F{d:.0}", .{ max, feed });
                    self.armWait(.probe, tick);
                },
                2 => {
                    self.sendFmt(drv, "G10 L20 P0 Z{d:.2}", .{self.cfg.plate_z});
                    self.armWait(.ok, tick);
                },
                3 => {
                    self.sendFmt(drv, "G0 Z{d:.1}", .{retr});
                    self.armWait(.ok, tick);
                },
                4 => {
                    self.sendLine(drv, "G90");
                    self.finish();
                },
                else => self.fail(),
            },
        }
    }
};

test {
    _ = @import("probe_engine_tests.zig");
}
