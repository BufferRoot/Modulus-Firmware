//! Binds `cnc.job_stream` to the pendant's USB volume and the CNC driver.
//!
//! The streamer is pure logic (see job_stream.zig); this is the only place
//! that touches the filesystem, the transport and the driver snapshot. It is
//! pumped from `systemTick` on Core 1, never from the UI thread — a paint-path
//! filesystem read is what caused the I2C storm.

const std = @import("std");
const build_options = @import("build_options");
const job_stream = @import("../cnc/job_stream.zig");

pub const Streamer = job_stream.Streamer;
pub const State = job_stream.State;
pub const Fault = job_stream.Fault;

const c = if (build_options.device_nvs) struct {
    extern fn modulus_usb_volume_read_lines(
        index: usize,
        first_line: usize,
        buf: [*]u8,
        buf_cap: usize,
        line_offsets: [*]u16,
        max_lines: usize,
    ) usize;
    extern fn modulus_usb_volume_line_count(index: usize) usize;
} else struct {
    pub fn modulus_usb_volume_read_lines(_: usize, _: usize, _: [*]u8, _: usize, _: [*]u16, _: usize) usize {
        return 0;
    }
    pub fn modulus_usb_volume_line_count(_: usize) usize {
        return 0;
    }
};

/// Reads one line at a time from a USB file.
///
/// A small look-ahead cache matters: `modulus_usb_volume_read_lines` seeks from
/// the start of the file on every call, so reading line N costs O(N). Fetching
/// a block per miss turns a full job from O(n^2) into O(n) seeks.
pub const UsbLineSource = struct {
    const block_lines: usize = 32;
    const block_bytes: usize = 2048;

    file_index: usize = 0,
    io_failed: bool = false,

    block_first: u32 = 0,
    block_n: usize = 0,
    block_loaded: bool = false,
    buf: [block_bytes]u8 = [_]u8{0} ** block_bytes,
    offsets: [block_lines]u16 = [_]u16{0} ** block_lines,

    pub fn init(self: *UsbLineSource, file_index: usize) void {
        self.* = .{ .file_index = file_index };
    }

    pub fn lineCount(self: *const UsbLineSource) u32 {
        return @intCast(c.modulus_usb_volume_line_count(self.file_index));
    }

    fn loadBlock(self: *UsbLineSource, first: u32) bool {
        self.block_n = c.modulus_usb_volume_read_lines(
            self.file_index,
            first,
            &self.buf,
            self.buf.len,
            &self.offsets,
            block_lines,
        );
        self.block_first = first;
        self.block_loaded = self.block_n > 0;
        return self.block_loaded;
    }

    fn readImpl(ctx: *anyopaque, index: u32, out: []u8) ?[]const u8 {
        const self: *UsbLineSource = @ptrCast(@alignCast(ctx));
        const in_block = self.block_loaded and
            index >= self.block_first and
            index < self.block_first + @as(u32, @intCast(self.block_n));
        if (!in_block) {
            if (!self.loadBlock(index)) return null; // EOF or read error
        }
        const rel = index - self.block_first;
        if (rel >= self.block_n) return null;
        const start = self.offsets[rel];
        const line = std.mem.sliceTo(self.buf[start..], 0);
        const n = @min(line.len, out.len);
        @memcpy(out[0..n], line[0..n]);
        return out[0..n];
    }

    fn failedImpl(ctx: *anyopaque) bool {
        const self: *UsbLineSource = @ptrCast(@alignCast(ctx));
        return self.io_failed;
    }

    pub fn source(self: *UsbLineSource) job_stream.LineSource {
        return .{ .ctx = self, .readFn = readImpl, .failedFn = failedImpl };
    }
};

/// Owns the streamer plus its line source. One job at a time by design.
pub const JobRunner = struct {
    stream: Streamer = .{},
    src: UsbLineSource = .{},
    /// Last observed engine ack counters — deltas drive the flow-control window.
    last_ok: u32 = 0,
    last_err: u32 = 0,
    /// Terminal state captured before `finish` resets to idle. Without this a
    /// clean completion and an operator abort are indistinguishable to the UI.
    last_terminal: State = .idle,
    /// Mirrors `Streamer.state` for the UI without exposing the machine.
    pub fn state(self: *const JobRunner) State {
        return self.stream.state;
    }
    pub fn fault(self: *const JobRunner) Fault {
        return self.stream.fault;
    }
    pub fn progressPerMille(self: *const JobRunner) u16 {
        return self.stream.progressPerMille();
    }
    pub fn isActive(self: *const JobRunner) bool {
        return self.stream.isActive();
    }

    /// Arm a job from the USB catalog. Does not move the machine.
    pub fn load(self: *JobRunner, file_index: usize) bool {
        self.src.init(file_index);
        const n = self.src.lineCount();
        if (n == 0) return false;
        self.stream.load(self.src.source(), n);
        return true;
    }

    pub fn clear(self: *JobRunner) void {
        self.stream.reset();
    }

    /// Ask to start. Returns false when the job cannot begin yet (not loaded,
    /// or the machine is not Idle — grblHAL only allows the MPG mode switch
    /// from Idle). Emits the 0x8B claim; streaming waits for `|MPG:1`.
    pub fn requestStart(self: *JobRunner, drv: anytype, now_ms: u32, machine_idle: bool) bool {
        if (!drv.engine.supportsJobStream()) return false;
        // 0x8B is a toggle — if MPG is already granted, claiming would drop it.
        self.stream.mpg_already = blk: {
            drv.lockSnapshot();
            defer drv.unlockSnapshot();
            break :blk drv.snapshot.mpg_active or drv.snapshot.mpg_remote;
        };
        const act = self.stream.startRequest(now_ms, machine_idle) orelse return false;
        // Baseline the ack counters at claim time — anything the controller
        // acked before this job is not ours to count.
        self.last_ok = drv.engine.okCount();
        self.last_err = drv.engine.errCount();
        applyAction(drv, act);
        return true;
    }

    /// Pump from systemTick (Core 1). Feeds parser events in, drains actions
    /// out. Bounded per tick so one job cannot monopolise the CNC poll.
    pub fn pump(self: *JobRunner, drv: anytype, now_ms: u32) void {
        if (!self.stream.isActive()) return;

        // --- events in -------------------------------------------------
        // Ack deltas, not last_event: at ~300 lines/s against a 100 Hz tick,
        // sampling would miss most acks and stall the window.
        const ok_now = drv.engine.okCount();
        const err_now = drv.engine.errCount();
        if (self.last_err != err_now) {
            self.last_err = err_now;
            self.last_ok = ok_now;
            self.stream.onError(0);
            return;
        }
        var d = ok_now -% self.last_ok;
        self.last_ok = ok_now;
        while (d > 0) : (d -= 1) self.stream.onOk(now_ms);

        // grblHAL reports `|MPG:1` when our 0x8B claim is granted.
        const granted = blk: {
            drv.lockSnapshot();
            defer drv.unlockSnapshot();
            break :blk drv.snapshot.mpg_remote;
        };
        if (granted) {
            self.stream.onMpgGranted(now_ms);
        } else if (self.stream.saw_grant and self.stream.state != .claiming) {
            // `|MPG:` is only emitted on a transition, so a missing flag before
            // any grant means "not yet", not "revoked". Without saw_grant this
            // aborted every job on the first pump.
            self.stream.onMpgLost();
        }
        if (!self.stream.isActive()) {
            self.finish(drv);
            return;
        }

        // --- actions out -----------------------------------------------
        var guard: usize = 0;
        while (guard < job_stream.max_inflight) : (guard += 1) {
            const act = self.stream.next(now_ms);
            switch (act) {
                .none => break,
                else => applyAction(drv, act),
            }
        }
        self.finish(drv);
    }

    /// Terminal: hand control back so the PC sender's UI re-enables (`|MPG:0`).
    fn finish(self: *JobRunner, drv: anytype) void {
        const rel = self.stream.releaseAction() orelse return;
        self.last_terminal = self.stream.state;
        applyAction(drv, rel);
        // releaseAction is level-triggered; move off terminal so the toggle
        // is sent exactly once (a second 0x8B would re-claim the port).
        self.stream.state = .idle;
    }

    /// `.complete` or `.aborted` from the last finished job.
    pub fn lastTerminal(self: *const JobRunner) State {
        return self.last_terminal;
    }

    fn applyAction(drv: anytype, act: job_stream.Action) void {
        switch (act) {
            .none => {},
            .realtime => |b| switch (b) {
                job_stream.rt_mpg_toggle => drv.engine.sendMpgToggle(),
                job_stream.rt_feed_hold => drv.engine.sendFeedHold(),
                job_stream.rt_cycle_start => drv.engine.sendCycleStart(),
                job_stream.rt_soft_reset => drv.engine.sendReset(),
                else => {},
            },
            // Straight to the engine, NOT sendGcodeClamped: the spindle clamp
            // rewrites S words, and silently editing a line mid-job desyncs the
            // character count the controller is acking against.
            .line => |l| drv.engine.sendGcode(l.text),
        }
    }
};

test "usb line source reports clean EOF on the host stub" {
    var src: UsbLineSource = .{};
    src.init(0);
    var buf: [64]u8 = undefined;
    // Host stub returns 0 lines; that is EOF, not an I/O failure.
    try std.testing.expect(UsbLineSource.readImpl(&src, 0, &buf) == null);
    try std.testing.expect(!UsbLineSource.failedImpl(&src));
}

test "job runner refuses to arm an empty file" {
    var r: JobRunner = .{};
    try std.testing.expect(!r.load(0));
    try std.testing.expectEqual(State.idle, r.state());
}
