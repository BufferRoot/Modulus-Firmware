//! G-code job streamer — pendant acts as the sender over the grblHAL MPG port.
//!
//! Architecture (grblHAL core wiki, "MPG and DRO interfaces"):
//!   grblHAL's "MPG mode" is NOT a handwheel jog mode. It is a *stream
//!   ownership handoff*: in active mode the app is in full control and acts as
//!   a sender. So MPG must be ON for the whole job — with it off, grblHAL does
//!   not read our UART at all. (This is the opposite of Mach3/Mach4/LinuxCNC,
//!   where a program genuinely cannot run in MPG mode.)
//!
//! Claim protocol:
//!   - Send 0x8B to request control (we have no dedicated MPG pin over ESP-NOW).
//!   - grblHAL answers with a full report containing `|MPG:1` on success, or a
//!     normal report on refusal. We wait for the grant; we never assume it.
//!   - Claim only from Idle (grbl-Mega: mode switch allowed in IDLE only).
//!   - Release on completion/abort so the PC sender's UI re-enables (`|MPG:0`).
//!
//! Flow control is character counting, not ping-pong. Ping-pong costs one link
//! round trip per line; at ~5-15 ms over ESP-NOW that is 65-200 lines/s, and a
//! 3D finishing pass at 0.1 mm segments / 2000 mm/min needs ~333 lines/s.
//! Starving the planner mid-contour leaves dwell marks in the part.
//!
//! Duplicate safety: every emitted line carries a monotonic `seq`. ESP-NOW
//! unicast retries after a lost MAC ack can deliver the same frame twice, and a
//! replayed `G1 X10` is a second 10 mm move. The transport MUST drop frames
//! whose seq it has already delivered. The streamer never re-emits a seq.

const std = @import("std");

/// Conservative grblHAL RX buffer assumption for the MPG port. The primary
/// port is often 1024 B but the secondary is commonly 128 B; over-filling
/// silently drops characters mid-line, which corrupts G-code.
pub const default_rx_window: u16 = 128;

/// Max in-flight lines tracked for the character-count window.
pub const max_inflight: usize = 24;

/// No ack for this long with lines outstanding → fault + feed hold.
/// Link loss mid-cut must not leave the spindle down and the job orphaned.
pub const default_ack_timeout_ms: u32 = 4000;

/// grblHAL real-time command bytes.
pub const rt_mpg_toggle: u8 = 0x8B;
pub const rt_feed_hold: u8 = '!';
pub const rt_cycle_start: u8 = '~';
pub const rt_soft_reset: u8 = 0x18;

pub const State = enum {
    /// No job loaded.
    idle,
    /// Job loaded, waiting for the operator's Cycle Start.
    loaded,
    /// 0x8B sent, waiting for `|MPG:1`.
    claiming,
    /// Feeding lines under the character-count window.
    streaming,
    /// Feed hold asserted; window still draining.
    paused,
    /// All lines sent, waiting for the last acks.
    draining,
    /// Finished cleanly; MPG released.
    complete,
    /// Operator abort or fault; soft reset sent, MPG released.
    aborted,
};

pub const Fault = enum {
    none,
    /// grblHAL refused the MPG claim (no `|MPG:1`).
    claim_denied,
    /// MPG revoked mid-job.
    mpg_lost,
    /// Controller returned `error:N`.
    controller_error,
    /// No ack within the dead-man window.
    ack_timeout,
    /// Line source failed mid-job.
    read_failed,
};

pub const Action = union(enum) {
    none,
    /// Raw real-time byte to push to the controller.
    realtime: u8,
    /// A G-code line to transmit. `seq` must be used by the transport for
    /// duplicate suppression; `text` excludes the terminating newline.
    line: struct { seq: u32, text: []const u8 },
};

/// Pull-model line source so the state machine is testable without a
/// filesystem. On device this wraps modulus_usb_volume_read_lines.
pub const LineSource = struct {
    ctx: *anyopaque,
    /// Return line `index`, or null at EOF / on read error (see `failed`).
    readFn: *const fn (ctx: *anyopaque, index: u32, buf: []u8) ?[]const u8,
    /// Distinguishes clean EOF from an I/O failure after readFn returns null.
    failedFn: *const fn (ctx: *anyopaque) bool,

    fn read(self: LineSource, index: u32, buf: []u8) ?[]const u8 {
        return self.readFn(self.ctx, index, buf);
    }
    fn failed(self: LineSource) bool {
        return self.failedFn(self.ctx);
    }
};

pub const Streamer = struct {
    state: State = .idle,
    fault: Fault = .none,

    src: ?LineSource = null,
    total_lines: u32 = 0,
    next_line: u32 = 0,
    acked_lines: u32 = 0,
    seq: u32 = 0,

    rx_window: u16 = default_rx_window,
    /// Bytes currently believed to sit in grblHAL's RX buffer.
    in_flight_bytes: u16 = 0,
    /// Byte cost of each unacked line, oldest first.
    lens: [max_inflight]u16 = [_]u16{0} ** max_inflight,
    head: usize = 0,
    len_n: usize = 0,

    ack_timeout_ms: u32 = default_ack_timeout_ms,
    last_ack_ms: u32 = 0,
    /// True when WE sent the 0x8B. Only then may we toggle it back off — if
    /// MPG was already granted (pin switching), releasing would take the
    /// operator out of a mode they had set up themselves.
    claimed: bool = false,
    /// Set once MPG is known-held. `|MPG:` only appears on transitions, so a
    /// missing flag must not be read as revocation before any grant was seen.
    saw_grant: bool = false,
    /// Set by the caller before `startRequest` when the controller has ALREADY
    /// granted MPG (pin switching, or a prior claim). 0x8B is a toggle, so
    /// claiming in that case turns MPG *off* and the job then waits forever for
    /// a `|MPG:1` that never arrives — observed on device as a permanent
    /// `claiming` state with no motion.
    mpg_already: bool = false,
    /// Scratch for the line currently being emitted.
    line_buf: [128]u8 = [_]u8{0} ** 128,

    pub fn reset(self: *Streamer) void {
        self.* = .{};
    }

    /// Arm a job. Does not move the machine — Cycle Start does that.
    pub fn load(self: *Streamer, src: LineSource, total_lines: u32) void {
        self.reset();
        self.src = src;
        self.total_lines = total_lines;
        self.state = .loaded;
    }

    pub fn isActive(self: *const Streamer) bool {
        return switch (self.state) {
            .claiming, .streaming, .paused, .draining => true,
            else => false,
        };
    }

    /// 0..1000 (per-mille avoids float in the CNC layer).
    pub fn progressPerMille(self: *const Streamer) u16 {
        if (self.total_lines == 0) return 0;
        const done: u64 = @min(self.acked_lines, self.total_lines);
        return @intCast(done * 1000 / self.total_lines);
    }

    // --- events from the protocol engine -------------------------------

    /// `|MPG:1` seen.
    pub fn onMpgGranted(self: *Streamer, now_ms: u32) void {
        if (self.state != .claiming) return;
        self.saw_grant = true;
        self.state = .streaming;
        self.last_ack_ms = now_ms;
    }

    /// `|MPG:0` seen — either our own release, or revoked under us.
    pub fn onMpgLost(self: *Streamer) void {
        switch (self.state) {
            .claiming => self.failWith(.claim_denied),
            .streaming, .paused, .draining => self.failWith(.mpg_lost),
            else => {},
        }
    }

    pub fn onOk(self: *Streamer, now_ms: u32) void {
        if (!self.isActive()) return;
        self.popOldest();
        self.acked_lines +|= 1;
        self.last_ack_ms = now_ms;
        if (self.state == .draining and self.len_n == 0) {
            self.state = .complete;
        }
    }

    /// `error:N` — stop immediately. A rejected line means the remaining
    /// program is no longer valid in context (modal state has diverged).
    pub fn onError(self: *Streamer, _: u16) void {
        if (!self.isActive()) return;
        self.failWith(.controller_error);
    }

    pub fn hold(self: *Streamer) void {
        if (self.state == .streaming) self.state = .paused;
    }

    pub fn unhold(self: *Streamer, now_ms: u32) void {
        if (self.state == .paused) {
            self.state = .streaming;
            self.last_ack_ms = now_ms;
        }
    }

    pub fn abort(self: *Streamer) void {
        if (self.isActive() or self.state == .loaded) self.state = .aborted;
    }

    // --- pump ----------------------------------------------------------

    /// Called from sys_task. Returns the next action, or `.none` when there is
    /// nothing to do this tick. Call repeatedly until `.none` to fill the
    /// window in one pass.
    pub fn next(self: *Streamer, now_ms: u32) Action {
        switch (self.state) {
            .idle, .loaded, .complete, .aborted => return .none,
            .claiming => {
                if (now_ms -% self.last_ack_ms > self.ack_timeout_ms) {
                    self.failWith(.claim_denied);
                    return .{ .realtime = rt_soft_reset };
                }
                return .none;
            },
            .paused, .streaming, .draining => {},
        }

        // Dead-man: only meaningful while lines are outstanding.
        if (self.len_n > 0 and now_ms -% self.last_ack_ms > self.ack_timeout_ms) {
            self.failWith(.ack_timeout);
            return .{ .realtime = rt_feed_hold };
        }
        if (self.state != .streaming) return .none;

        if (self.next_line >= self.total_lines) {
            self.state = if (self.len_n == 0) .complete else .draining;
            return .none;
        }

        const src = self.src orelse {
            self.failWith(.read_failed);
            return .none;
        };
        const text = src.read(self.next_line, &self.line_buf) orelse {
            if (src.failed()) {
                self.failWith(.read_failed);
                return .none;
            }
            // Clean EOF earlier than total_lines claimed — treat as done.
            self.total_lines = self.next_line;
            self.state = if (self.len_n == 0) .complete else .draining;
            return .none;
        };

        // +1 for the newline grblHAL will count in its RX buffer.
        const cost: u16 = @intCast(@min(text.len + 1, std.math.maxInt(u16)));
        if (cost > self.rx_window) {
            // Single line longer than the whole buffer — unsendable.
            self.failWith(.read_failed);
            return .none;
        }
        if (self.len_n >= max_inflight) return .none;
        if (self.in_flight_bytes + cost > self.rx_window) return .none;

        self.pushLen(cost);
        self.next_line += 1;
        self.seq +%= 1;
        return .{ .line = .{ .seq = self.seq, .text = text } };
    }

    /// Action the caller must perform on entering/leaving the job.
    ///
    /// `mpg_already` matters: 0x8B is a TOGGLE, not a claim. If the controller
    /// has already granted MPG (pin-based switching, or a previous claim),
    /// sending 0x8B turns it OFF and the job then waits forever for a `|MPG:1`
    /// that never arrives. Observed on device as `stream=claiming` with no
    /// progress. When we already hold it, skip the toggle and stream directly.
    pub fn startRequest(
        self: *Streamer,
        now_ms: u32,
        machine_idle: bool,
    ) ?Action {
        if (self.state != .loaded) return null;
        // grbl-Mega: switching to MPG mode is only allowed when in IDLE.
        if (!machine_idle) return null;
        self.last_ack_ms = now_ms;
        if (self.mpg_already) {
            self.saw_grant = true;
            self.state = .streaming;
            return .none;
        }
        self.claimed = true;
        self.state = .claiming;
        return .{ .realtime = rt_mpg_toggle };
    }

    /// Release action once terminal; caller sends it then may reset().
    pub fn releaseAction(self: *const Streamer) ?Action {
        return switch (self.state) {
            .complete, .aborted => if (self.claimed) .{ .realtime = rt_mpg_toggle } else .none,
            else => null,
        };
    }

    // --- internals ------------------------------------------------------

    fn failWith(self: *Streamer, f: Fault) void {
        self.fault = f;
        self.state = .aborted;
    }

    fn pushLen(self: *Streamer, cost: u16) void {
        const slot = (self.head + self.len_n) % max_inflight;
        self.lens[slot] = cost;
        self.len_n += 1;
        self.in_flight_bytes += cost;
    }

    fn popOldest(self: *Streamer) void {
        if (self.len_n == 0) return;
        const cost = self.lens[self.head];
        self.in_flight_bytes -|= cost;
        self.head = (self.head + 1) % max_inflight;
        self.len_n -= 1;
    }
};

// ---------------------------------------------------------------------------
// Tests — the streamer moves a machine, so the logic is pinned here before it
// ever reaches hardware.
// ---------------------------------------------------------------------------

const TestSource = struct {
    lines: []const []const u8,
    fail_at: ?u32 = null,
    io_failed: bool = false,

    fn read(ctx: *anyopaque, index: u32, buf: []u8) ?[]const u8 {
        const self: *TestSource = @ptrCast(@alignCast(ctx));
        if (self.fail_at) |f| {
            if (index >= f) {
                self.io_failed = true;
                return null;
            }
        }
        if (index >= self.lines.len) return null;
        const s = self.lines[index];
        @memcpy(buf[0..s.len], s);
        return buf[0..s.len];
    }
    fn failed(ctx: *anyopaque) bool {
        const self: *TestSource = @ptrCast(@alignCast(ctx));
        return self.io_failed;
    }
    fn source(self: *TestSource) LineSource {
        return .{ .ctx = self, .readFn = read, .failedFn = failed };
    }
};

const demo = [_][]const u8{
    "G21 G90",
    "G0 X0 Y0",
    "G1 X10 F600",
    "G1 Y10",
    "M30",
};

fn loaded(s: *Streamer, ts: *TestSource) void {
    s.load(ts.source(), @intCast(ts.lines.len));
}

test "load does not move the machine" {
    var ts = TestSource{ .lines = &demo };
    var s: Streamer = .{};
    loaded(&s, &ts);
    try std.testing.expectEqual(State.loaded, s.state);
    // Nothing is emitted until Cycle Start.
    try std.testing.expectEqual(Action.none, s.next(0));
}

test "claim only from idle, and only via 0x8B" {
    var ts = TestSource{ .lines = &demo };
    var s: Streamer = .{};
    loaded(&s, &ts);
    try std.testing.expect(s.startRequest(0, false) == null); // machine busy
    try std.testing.expectEqual(State.loaded, s.state);
    const a = s.startRequest(0, true).?;
    try std.testing.expectEqual(rt_mpg_toggle, a.realtime);
    try std.testing.expectEqual(State.claiming, s.state);
}

test "no line is sent before MPG is granted" {
    var ts = TestSource{ .lines = &demo };
    var s: Streamer = .{};
    loaded(&s, &ts);
    _ = s.startRequest(0, true);
    try std.testing.expectEqual(Action.none, s.next(10));
    s.onMpgGranted(20);
    try std.testing.expectEqual(State.streaming, s.state);
    switch (s.next(21)) {
        .line => |l| try std.testing.expectEqualStrings("G21 G90", l.text),
        else => return error.ExpectedLine,
    }
}

test "claim refusal aborts instead of streaming blind" {
    var ts = TestSource{ .lines = &demo };
    var s: Streamer = .{};
    loaded(&s, &ts);
    _ = s.startRequest(0, true);
    s.onMpgLost();
    try std.testing.expectEqual(State.aborted, s.state);
    try std.testing.expectEqual(Fault.claim_denied, s.fault);
}

test "character-count window bounds bytes in flight" {
    var ts = TestSource{ .lines = &demo };
    var s: Streamer = .{};
    loaded(&s, &ts);
    s.rx_window = 20; // room for ~2 short lines
    _ = s.startRequest(0, true);
    s.onMpgGranted(0);

    var sent: usize = 0;
    while (true) {
        switch (s.next(1)) {
            .line => sent += 1,
            else => break,
        }
    }
    try std.testing.expect(sent > 0);
    try std.testing.expect(s.in_flight_bytes <= s.rx_window);
    // Blocked until enough acks free space. Note one ack is not necessarily
    // enough: freeing an 8-byte line does not make room for a 12-byte one.
    try std.testing.expectEqual(Action.none, s.next(1));
    var acks: usize = 0;
    const resumed = while (acks < max_inflight) : (acks += 1) {
        s.onOk(2);
        switch (s.next(3)) {
            .line => break true,
            else => {
                if (s.len_n == 0 and s.state != .streaming) break false;
            },
        }
    } else false;
    try std.testing.expect(resumed);
    try std.testing.expect(s.in_flight_bytes <= s.rx_window);
}

test "seq is monotonic and never reused" {
    var ts = TestSource{ .lines = &demo };
    var s: Streamer = .{};
    loaded(&s, &ts);
    _ = s.startRequest(0, true);
    s.onMpgGranted(0);
    var last: u32 = 0;
    var n: usize = 0;
    while (n < demo.len) {
        switch (s.next(1)) {
            .line => |l| {
                try std.testing.expect(l.seq > last);
                last = l.seq;
                n += 1;
                s.onOk(1);
            },
            else => break,
        }
    }
    try std.testing.expectEqual(demo.len, n);
}

test "completes only after the last ack drains" {
    var ts = TestSource{ .lines = &demo };
    var s: Streamer = .{};
    loaded(&s, &ts);
    _ = s.startRequest(0, true);
    s.onMpgGranted(0);
    var pending: usize = 0;
    while (true) {
        switch (s.next(1)) {
            .line => pending += 1,
            else => break,
        }
    }
    try std.testing.expect(s.state == .draining or pending == demo.len);
    while (pending > 0) : (pending -= 1) {
        try std.testing.expect(s.state != .complete);
        s.onOk(2);
    }
    try std.testing.expectEqual(State.complete, s.state);
    try std.testing.expectEqual(@as(u16, 1000), s.progressPerMille());
    // Releasing MPG re-enables the PC sender's UI.
    try std.testing.expectEqual(rt_mpg_toggle, s.releaseAction().?.realtime);
}

test "controller error stops the job" {
    var ts = TestSource{ .lines = &demo };
    var s: Streamer = .{};
    loaded(&s, &ts);
    _ = s.startRequest(0, true);
    s.onMpgGranted(0);
    _ = s.next(1);
    s.onError(33);
    try std.testing.expectEqual(State.aborted, s.state);
    try std.testing.expectEqual(Fault.controller_error, s.fault);
    try std.testing.expectEqual(Action.none, s.next(2));
}

test "MPG revoked mid-job aborts" {
    var ts = TestSource{ .lines = &demo };
    var s: Streamer = .{};
    loaded(&s, &ts);
    _ = s.startRequest(0, true);
    s.onMpgGranted(0);
    _ = s.next(1);
    s.onMpgLost();
    try std.testing.expectEqual(Fault.mpg_lost, s.fault);
}

test "dead-man feed-holds when acks stop" {
    var ts = TestSource{ .lines = &demo };
    var s: Streamer = .{};
    loaded(&s, &ts);
    _ = s.startRequest(0, true);
    s.onMpgGranted(0);
    _ = s.next(1);
    // Silence past the timeout with a line outstanding.
    const a = s.next(1 + default_ack_timeout_ms + 1);
    try std.testing.expectEqual(rt_feed_hold, a.realtime);
    try std.testing.expectEqual(Fault.ack_timeout, s.fault);
}

test "hold pauses sending but keeps the window" {
    var ts = TestSource{ .lines = &demo };
    var s: Streamer = .{};
    loaded(&s, &ts);
    _ = s.startRequest(0, true);
    s.onMpgGranted(0);
    _ = s.next(1);
    s.hold();
    try std.testing.expectEqual(State.paused, s.state);
    try std.testing.expectEqual(Action.none, s.next(2));
    s.unhold(3);
    switch (s.next(4)) {
        .line => {},
        else => return error.ExpectedResume,
    }
}

test "read failure mid-job aborts rather than skipping lines" {
    var ts = TestSource{ .lines = &demo, .fail_at = 2 };
    var s: Streamer = .{};
    loaded(&s, &ts);
    _ = s.startRequest(0, true);
    s.onMpgGranted(0);
    var guard: usize = 0;
    while (guard < 16) : (guard += 1) {
        switch (s.next(1)) {
            .line => s.onOk(1),
            else => break,
        }
    }
    try std.testing.expectEqual(State.aborted, s.state);
    try std.testing.expectEqual(Fault.read_failed, s.fault);
}

test "a line longer than the RX window is refused, not truncated" {
    const long = [_][]const u8{"G1 X1 Y2 Z3 F600 (this line is deliberately longer than the window)"};
    var ts = TestSource{ .lines = &long };
    var s: Streamer = .{};
    loaded(&s, &ts);
    s.rx_window = 16;
    _ = s.startRequest(0, true);
    s.onMpgGranted(0);
    try std.testing.expectEqual(Action.none, s.next(1));
    try std.testing.expectEqual(Fault.read_failed, s.fault);
}

test "progress tracks acks, not sends" {
    var ts = TestSource{ .lines = &demo };
    var s: Streamer = .{};
    loaded(&s, &ts);
    _ = s.startRequest(0, true);
    s.onMpgGranted(0);
    _ = s.next(1);
    _ = s.next(1);
    try std.testing.expectEqual(@as(u16, 0), s.progressPerMille());
    s.onOk(2);
    try std.testing.expectEqual(@as(u16, 200), s.progressPerMille());
}

test "abort from loaded never claims MPG" {
    var ts = TestSource{ .lines = &demo };
    var s: Streamer = .{};
    loaded(&s, &ts);
    s.abort();
    try std.testing.expectEqual(State.aborted, s.state);
    try std.testing.expect(s.startRequest(0, true) == null);
}
