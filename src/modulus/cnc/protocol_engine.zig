//! Multi-protocol CNC engine facade — grblHAL / Grbl / FluidNC / LinuxCNC / Mach3-Mach4 / Masso Link.

const cnc_config = @import("cnc_config.zig");
const cnc_state = @import("cnc_state.zig");
const grbl_engine = @import("grblhal/engine.zig");
const lcnc_engine = @import("linuxcnc/engine.zig");
const mach_engine = @import("mach3/engine.zig");
const masso_engine = @import("masso/engine.zig");
const lc_parse = @import("linuxcnc/parse_event.zig");
const mach_parse = @import("mach3/parse_event.zig");
const masso_parse = @import("masso/parser.zig");
const settings_dump_mod = @import("settings_dump.zig");
const gh_session = @import("grblhal/session.zig");

pub const SendFn = grbl_engine.SendFn;
pub const SessionState = gh_session.SessionState;
pub const ParseEvent = grbl_engine.ParseEvent;

pub const Engine = struct {
    active: cnc_config.Protocol = .grblhal,
    grbl: grbl_engine.Engine = undefined,
    lcnc: lcnc_engine.Engine = undefined,
    mach: mach_engine.Engine = undefined,
    masso: masso_engine.Engine = undefined,

    pub fn init(send_fn: ?SendFn) Engine {
        return .{
            .grbl = grbl_engine.Engine.init(send_fn),
            .lcnc = lcnc_engine.Engine.init(send_fn),
            .mach = mach_engine.Engine.init(send_fn),
            .masso = masso_engine.Engine.init(send_fn),
        };
    }

    pub fn setProtocol(self: *Engine, protocol: cnc_config.Protocol) void {
        self.active = protocol;
        if (cnc_config.usesGrblEngine(protocol)) {
            self.grbl.setProtocol(protocol);
        }
    }

    pub fn setLinuxCncPasswords(self: *Engine, connect_pw: []const u8, enable_pw: []const u8) void {
        self.lcnc.setPasswords(connect_pw, enable_pw);
    }

    pub fn setMassoExpectedSerial(self: *Engine, sn: u16) void {
        self.masso.setExpectedSerial(sn);
    }

    pub fn setSendFn(self: *Engine, send_fn: ?SendFn) void {
        self.grbl.setSendFn(send_fn);
        self.lcnc.setSendFn(send_fn);
        self.mach.setSendFn(send_fn);
        self.masso.setSendFn(send_fn);
    }

    pub fn onConnect(self: *Engine, tick_ms: u32) void {
        switch (self.active) {
            .linux_cnc => self.lcnc.onConnect(tick_ms),
            .mach3_mach4 => self.mach.onConnect(tick_ms),
            .masso => self.masso.onConnect(tick_ms),
            else => self.grbl.onConnect(tick_ms),
        }
    }

    pub fn onDisconnect(self: *Engine) void {
        self.grbl.onDisconnect();
        self.lcnc.onDisconnect();
        self.mach.onDisconnect();
        self.masso.onDisconnect();
    }

    pub fn feed(self: *Engine, data: []const u8, response_tick_ms: ?u32) void {
        switch (self.active) {
            .linux_cnc => self.lcnc.feed(data, response_tick_ms),
            .mach3_mach4 => self.mach.feed(data, response_tick_ms),
            .masso => self.masso.feed(data, response_tick_ms),
            else => self.grbl.feed(data, response_tick_ms),
        }
    }

    pub fn poll(self: *Engine, tick_ms: u32) void {
        switch (self.active) {
            .linux_cnc => self.lcnc.poll(tick_ms),
            .mach3_mach4 => self.mach.poll(tick_ms),
            .masso => self.masso.poll(tick_ms),
            else => self.grbl.poll(tick_ms),
        }
    }

    /// Monotonic ack counters for the job streamer. grblHAL only — the other
    /// protocols have no per-line ack contract, so a job cannot be streamed to
    /// them and the counters stay zero.
    pub fn okCount(self: *const Engine) u32 {
        return switch (self.active) {
            .linux_cnc, .mach3_mach4, .masso => 0,
            else => self.grbl.ok_count,
        };
    }

    pub fn errCount(self: *const Engine) u32 {
        return switch (self.active) {
            .linux_cnc, .mach3_mach4, .masso => 0,
            else => self.grbl.err_count,
        };
    }

    /// True when this protocol supports pendant-as-sender job streaming.
    pub fn supportsJobStream(self: *const Engine) bool {
        return switch (self.active) {
            .linux_cnc, .mach3_mach4, .masso => false,
            else => true,
        };
    }

    pub fn setPollInterval(self: *Engine, ms: u16) void {
        self.grbl.setPollInterval(ms);
        self.lcnc.setPollInterval(ms);
        self.mach.setPollInterval(ms);
    }

    pub fn session(self: *const Engine) SessionState {
        return switch (self.active) {
            .linux_cnc => self.lcnc.session(),
            .mach3_mach4 => self.mach.session(),
            .masso => self.masso.session(),
            else => self.grbl.session(),
        };
    }

    pub fn status(self: *const Engine) cnc_state.MachineStatus {
        return switch (self.active) {
            .linux_cnc => self.lcnc.status(),
            .mach3_mach4 => self.mach.status(),
            .masso => self.masso.status(),
            else => self.grbl.status(),
        };
    }

    pub fn nowTickMs(self: *const Engine) u32 {
        return switch (self.active) {
            .linux_cnc => self.lcnc.tick_ms,
            .mach3_mach4 => self.mach.tick_ms,
            .masso => self.masso.tick_ms,
            else => self.grbl.tick_ms,
        };
    }

    pub fn send(self: *Engine, data: []const u8) void {
        switch (self.active) {
            .linux_cnc => self.lcnc.send(data),
            .mach3_mach4 => self.mach.send(data),
            .masso => self.masso.send(data),
            else => self.grbl.send(data),
        }
    }

    pub fn last_event(self: *const Engine) ParseEvent {
        return switch (self.active) {
            .linux_cnc => if (self.lcnc.last_event == lc_parse.ParseEvent.set_ack) .ok else .none,
            .mach3_mach4 => if (self.mach.last_event == mach_parse.ParseEvent.ok) .ok else .none,
            .masso => switch (self.masso.last_event) {
                masso_parse.ParseEvent.version, masso_parse.ParseEvent.config, masso_parse.ParseEvent.status => .ok,
                else => .none,
            },
            else => self.grbl.last_event,
        };
    }

    pub fn lastEventIsOk(self: *const Engine) bool {
        return self.last_event() == .ok;
    }

    pub var settings_dump: ?*settings_dump_mod.SettingsDump = null;

    pub fn setSettingsDump(self: *Engine, cap: ?*settings_dump_mod.SettingsDump) void {
        self.grbl.settings_dump = cap;
        self.lcnc.settings_dump = cap;
        self.mach.settings_dump = cap;
    }

    pub fn sendFeedHold(self: *Engine) void {
        switch (self.active) {
            .linux_cnc => self.lcnc.sendFeedHold(),
            .mach3_mach4 => self.mach.sendFeedHold(),
            .masso => self.masso.sendFeedHold(),
            else => self.grbl.sendFeedHold(),
        }
    }

    pub fn sendCycleStart(self: *Engine) void {
        switch (self.active) {
            .linux_cnc => self.lcnc.sendCycleStart(),
            .mach3_mach4 => self.mach.sendCycleStart(),
            .masso => self.masso.sendCycleStart(),
            else => self.grbl.sendCycleStart(),
        }
    }

    pub fn sendJog(self: *Engine, axis: u8, distance: f32, feed_rate: f32, incremental: bool, metric: bool) void {
        switch (self.active) {
            .linux_cnc => self.lcnc.sendJog(axis, distance, feed_rate, incremental, metric),
            .mach3_mach4 => self.mach.sendJog(axis, distance, feed_rate, incremental, metric),
            .masso => self.masso.sendJog(axis, distance, feed_rate, incremental, metric),
            else => self.grbl.sendJog(axis, distance, feed_rate, incremental, metric),
        }
    }

    pub fn sendJogCancel(self: *Engine) void {
        switch (self.active) {
            .linux_cnc => self.lcnc.sendJogCancel(),
            .mach3_mach4 => self.mach.sendJogCancel(),
            .masso => self.masso.sendJogCancel(),
            else => self.grbl.sendJogCancel(),
        }
    }

    pub fn sendHome(self: *Engine, axis: u8) void {
        switch (self.active) {
            .linux_cnc => self.lcnc.sendHome(axis),
            .mach3_mach4 => self.mach.sendHome(axis),
            .masso => self.masso.sendHome(axis),
            else => self.grbl.sendHome(axis),
        }
    }

    pub fn sendUnlock(self: *Engine) void {
        switch (self.active) {
            .linux_cnc => self.lcnc.sendUnlock(),
            .mach3_mach4 => self.mach.sendUnlock(),
            .masso => self.masso.sendUnlock(),
            else => self.grbl.sendUnlock(),
        }
    }

    pub fn requestUnlockAfterWelcome(self: *Engine) void {
        switch (self.active) {
            .linux_cnc, .mach3_mach4, .masso => {},
            else => self.grbl.requestUnlockAfterWelcome(),
        }
    }

    pub fn sendReset(self: *Engine) void {
        switch (self.active) {
            .linux_cnc => self.lcnc.sendReset(),
            .mach3_mach4 => self.mach.sendReset(),
            .masso => self.masso.sendReset(),
            else => self.grbl.sendReset(),
        }
    }

    pub fn sendGcode(self: *Engine, line: []const u8) void {
        switch (self.active) {
            .linux_cnc => self.lcnc.sendGcode(line),
            .mach3_mach4 => self.mach.sendGcode(line),
            .masso => self.masso.sendGcode(line),
            else => self.grbl.sendGcode(line),
        }
    }

    pub fn sendFeedOverride(self: *Engine, delta_pct: i8) void {
        switch (self.active) {
            .linux_cnc => self.lcnc.sendFeedOverride(delta_pct),
            .mach3_mach4 => self.mach.sendFeedOverride(delta_pct),
            .masso => self.masso.sendFeedOverride(delta_pct),
            else => self.grbl.sendFeedOverride(delta_pct),
        }
    }

    pub fn sendRapidOverride(self: *Engine, pct: u8) void {
        switch (self.active) {
            .linux_cnc => self.lcnc.sendRapidOverride(pct),
            .mach3_mach4 => self.mach.sendRapidOverride(pct),
            .masso => self.masso.sendRapidOverride(pct),
            else => self.grbl.sendRapidOverride(pct),
        }
    }

    pub fn sendSpindleOverride(self: *Engine, delta_pct: i8) void {
        switch (self.active) {
            .linux_cnc => self.lcnc.sendSpindleOverride(delta_pct),
            .mach3_mach4 => self.mach.sendSpindleOverride(delta_pct),
            .masso => self.masso.sendSpindleOverride(delta_pct),
            else => self.grbl.sendSpindleOverride(delta_pct),
        }
    }

    pub fn sendSpindleStopToggle(self: *Engine) void {
        switch (self.active) {
            .linux_cnc => self.lcnc.sendSpindleStopToggle(),
            .mach3_mach4 => self.mach.sendSpindleStopToggle(),
            .masso => self.masso.sendSpindleStopToggle(),
            else => self.grbl.sendSpindleStopToggle(),
        }
    }

    pub fn sendCoolantFloodToggle(self: *Engine) void {
        switch (self.active) {
            .linux_cnc => self.lcnc.sendCoolantFloodToggle(),
            .mach3_mach4 => self.mach.sendCoolantFloodToggle(),
            .masso => self.masso.sendCoolantFloodToggle(),
            else => self.grbl.sendCoolantFloodToggle(),
        }
    }

    pub fn sendCoolantMistToggle(self: *Engine) void {
        switch (self.active) {
            .linux_cnc => self.lcnc.sendCoolantMistToggle(),
            .mach3_mach4 => self.mach.sendCoolantMistToggle(),
            .masso => self.masso.sendCoolantMistToggle(),
            else => self.grbl.sendCoolantMistToggle(),
        }
    }

    pub fn sendFanToggle(self: *Engine) void {
        switch (self.active) {
            .linux_cnc => self.lcnc.sendFanToggle(),
            .mach3_mach4 => self.mach.sendFanToggle(),
            .masso => self.masso.sendFanToggle(),
            else => self.grbl.sendFanToggle(),
        }
    }

    pub fn sendSingleStepToggle(self: *Engine) void {
        switch (self.active) {
            .linux_cnc => self.lcnc.sendSingleStepToggle(),
            .mach3_mach4 => self.mach.sendSingleStepToggle(),
            .masso => self.masso.sendSingleStepToggle(),
            else => self.grbl.sendSingleStepToggle(),
        }
    }

    pub fn sendMpgToggle(self: *Engine) void {
        switch (self.active) {
            .linux_cnc => self.lcnc.sendMpgToggle(),
            .mach3_mach4 => self.mach.sendMpgToggle(),
            .masso => self.masso.sendMpgToggle(),
            else => self.grbl.sendMpgToggle(),
        }
    }

    pub fn sendStop(self: *Engine) void {
        switch (self.active) {
            .linux_cnc => self.lcnc.sendStop(),
            .mach3_mach4 => self.mach.sendStop(),
            .masso => self.masso.sendStop(),
            else => self.grbl.sendStop(),
        }
    }

    pub fn sendFeedOverridePct(self: *Engine, pct: u8) void {
        switch (self.active) {
            .linux_cnc => self.lcnc.sendFeedOverridePct(pct),
            .mach3_mach4 => self.mach.sendFeedOverridePct(pct),
            .masso => self.masso.sendFeedOverridePct(pct),
            else => {
                self.grbl.sendFeedOverride(0);
                const delta: i16 = @as(i16, pct) - 100;
                if (delta == 0) return;
                const positive = delta > 0;
                var steps: i16 = if (positive) delta else -delta;
                while (steps >= 10) : (steps -= 10) {
                    self.grbl.sendFeedOverride(if (positive) 10 else -10);
                }
                while (steps > 0) : (steps -= 1) {
                    self.grbl.sendFeedOverride(if (positive) 1 else -1);
                }
            },
        }
    }

    pub fn sendSpindleOverridePct(self: *Engine, pct: u8) void {
        switch (self.active) {
            .linux_cnc => self.lcnc.sendSpindleOverridePct(pct),
            .mach3_mach4 => self.mach.sendSpindleOverridePct(pct),
            .masso => self.masso.sendSpindleOverridePct(pct),
            else => {
                self.grbl.sendSpindleOverride(0);
                const delta: i16 = @as(i16, pct) - 100;
                if (delta == 0) return;
                const positive = delta > 0;
                var steps: i16 = if (positive) delta else -delta;
                while (steps >= 10) : (steps -= 10) {
                    self.grbl.sendSpindleOverride(if (positive) 10 else -10);
                }
                while (steps > 0) : (steps -= 1) {
                    self.grbl.sendSpindleOverride(if (positive) 1 else -1);
                }
            },
        }
    }
};
