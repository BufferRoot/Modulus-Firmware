//! MD3-style gesture recognizer (host UI engine).
//! Single-pointer primary path; pinch via synthetic 2nd pointer or scale feed.
//! Heap-free fixed state — safe for Core-0 UI; not for ISR.

const std = @import("std");

pub const Kind = enum {
    none,
    tap,
    double_tap,
    long_press,
    pan,
    scroll,
    swipe,
    drag,
    pickup_move,
    pinch,
    predictive_back,
    /// Long-press armed then drag (same as pickup_move; named for API clarity).
    compound,
};

pub const Phase = enum { begin, update, end, cancel };

pub const PointerPhase = enum { down, move, up, cancel };

pub const Pointer = struct {
    phase: PointerPhase,
    x: i32,
    y: i32,
    t_ms: u64,
    id: u8 = 0,
};

pub const Event = struct {
    kind: Kind = .none,
    phase: Phase = .end,
    x: i32 = 0,
    y: i32 = 0,
    dx: i32 = 0,
    dy: i32 = 0,
    /// Swipe / pan velocity (px/s), approximate.
    vx: f32 = 0,
    vy: f32 = 0,
    /// Pinch cumulative scale (1.0 = identity).
    scale: f32 = 1,
};

/// Thresholds — MD3 touch targets / Material motion dwell.
pub const Thresholds = struct {
    /// Movement before tap fails. Tab5 ST7123 reports ±20–40 px noise while
    /// a finger is held still; 18 px (phone MD3) cancelled real taps.
    slop: i32 = 40,
    long_press_ms: u64 = 500,
    double_tap_ms: u64 = 300,
    double_tap_slop: i32 = 48,
    /// Min distance for swipe recognition.
    swipe_min: i32 = 80,
    /// Min |velocity| px/s for swipe.
    swipe_vel: f32 = 600,
    /// Left-edge width for predictive back.
    edge_back: i32 = 28,
    /// Pan vs stationary.
    pan_slop: i32 = 12,
};

const QueueCap = 8;

pub const Recognizer = struct {
    thr: Thresholds = .{},
    down: bool = false,
    down_x: i32 = 0,
    down_y: i32 = 0,
    down_ms: u64 = 0,
    last_x: i32 = 0,
    last_y: i32 = 0,
    last_ms: u64 = 0,
    moved: bool = false,
    long_fired: bool = false,
    long_armed: bool = false, // long press recognized; drag → pickup
    compound_emitted: bool = false,
    // Double-tap
    pending_tap: bool = false,
    pending_x: i32 = 0,
    pending_y: i32 = 0,
    pending_ms: u64 = 0,
    // Pinch (2 pointers or scale feed)
    pointers: [2]?struct { x: i32, y: i32 } = .{ null, null },
    pinch_start_dist: f32 = 0,
    pinch_active: bool = false,
    // Edge back
    edge_start: bool = false,

    q: [QueueCap]Event = [_]Event{.{}} ** QueueCap,
    q_len: usize = 0,

    pub fn reset(self: *Recognizer) void {
        self.* = .{ .thr = self.thr };
    }

    pub fn feed(self: *Recognizer, p: Pointer) void {
        switch (p.phase) {
            .down => self.onDown(p),
            .move => self.onMove(p),
            .up => self.onUp(p),
            .cancel => self.onCancel(p.t_ms),
        }
    }

    /// Host Ctrl+wheel / touch-zoom stand-in.
    pub fn feedScale(self: *Recognizer, scale_delta: f32, x: i32, y: i32, t_ms: u64) void {
        _ = t_ms;
        if (scale_delta == 0) return;
        self.push(.{
            .kind = .pinch,
            .phase = .update,
            .x = x,
            .y = y,
            .scale = 1.0 + scale_delta,
        });
    }

    /// Call each frame so long-press can fire without move/up.
    pub fn tick(self: *Recognizer, now_ms: u64) void {
        if (!self.down or self.long_fired or self.moved) return;
        if (now_ms - self.down_ms < self.thr.long_press_ms) return;
        self.long_fired = true;
        self.long_armed = true;
        self.push(.{
            .kind = .long_press,
            .phase = .end,
            .x = self.down_x,
            .y = self.down_y,
        });
    }

    /// Expire waiting double-tap window (no extra tap — already emitted on first up).
    pub fn flushPendingTap(self: *Recognizer, now_ms: u64) void {
        if (!self.pending_tap) return;
        if (now_ms - self.pending_ms < self.thr.double_tap_ms) return;
        self.pending_tap = false;
    }

    pub fn poll(self: *Recognizer) ?Event {
        if (self.q_len == 0) return null;
        const e = self.q[0];
        var i: usize = 1;
        while (i < self.q_len) : (i += 1) self.q[i - 1] = self.q[i];
        self.q_len -= 1;
        return e;
    }

    fn push(self: *Recognizer, e: Event) void {
        if (self.q_len >= QueueCap) {
            // Drop oldest
            var i: usize = 1;
            while (i < self.q_len) : (i += 1) self.q[i - 1] = self.q[i];
            self.q_len -= 1;
        }
        self.q[self.q_len] = e;
        self.q_len += 1;
    }

    fn onDown(self: *Recognizer, p: Pointer) void {
        if (p.id <= 1) {
            self.pointers[p.id] = .{ .x = p.x, .y = p.y };
            self.tryStartPinch();
        }
        if (p.id != 0) return;

        self.down = true;
        self.down_x = p.x;
        self.down_y = p.y;
        self.down_ms = p.t_ms;
        self.last_x = p.x;
        self.last_y = p.y;
        self.last_ms = p.t_ms;
        self.moved = false;
        self.long_fired = false;
        self.long_armed = false;
        self.compound_emitted = false;
        self.edge_start = p.x <= self.thr.edge_back;
    }

    fn onMove(self: *Recognizer, p: Pointer) void {
        if (p.id <= 1) {
            self.pointers[p.id] = .{ .x = p.x, .y = p.y };
            if (self.updatePinch(p.x, p.y)) return;
        }
        if (p.id != 0 or !self.down) return;

        const dx = p.x - self.down_x;
        const dy = p.y - self.down_y;
        const adx = @abs(dx);
        const ady = @abs(dy);
        if (!self.moved and (adx > self.thr.slop or ady > self.thr.slop)) {
            self.moved = true;
        }
        if (!self.moved) {
            self.last_x = p.x;
            self.last_y = p.y;
            self.last_ms = p.t_ms;
            return;
        }

        const fdx = p.x - self.last_x;
        const fdy = p.y - self.last_y;
        const dt = if (p.t_ms > self.last_ms) p.t_ms - self.last_ms else 1;
        const vx = @as(f32, @floatFromInt(fdx)) * 1000.0 / @as(f32, @floatFromInt(dt));
        const vy = @as(f32, @floatFromInt(fdy)) * 1000.0 / @as(f32, @floatFromInt(dt));

        if (self.long_armed) {
            self.push(.{
                .kind = .pickup_move,
                .phase = .update,
                .x = p.x,
                .y = p.y,
                .dx = fdx,
                .dy = fdy,
                .vx = vx,
                .vy = vy,
            });
            if (!self.compound_emitted) {
                self.compound_emitted = true;
                self.push(.{
                    .kind = .compound,
                    .phase = .begin,
                    .x = p.x,
                    .y = p.y,
                    .dx = fdx,
                    .dy = fdy,
                });
            }
        } else if (self.edge_start and dx > self.thr.pan_slop and adx > ady) {
            self.push(.{
                .kind = .predictive_back,
                .phase = .update,
                .x = p.x,
                .y = p.y,
                .dx = dx,
                .dy = dy,
                .vx = vx,
                .vy = vy,
            });
        } else if (ady >= adx) {
            // Vertical finger drag = pan/scroll (MD3 scrollable regions).
            self.push(.{
                .kind = .pan,
                .phase = .update,
                .x = p.x,
                .y = p.y,
                .dx = fdx,
                .dy = fdy,
                .vx = vx,
                .vy = vy,
            });
        } else {
            self.push(.{
                .kind = .drag,
                .phase = .update,
                .x = p.x,
                .y = p.y,
                .dx = fdx,
                .dy = fdy,
                .vx = vx,
                .vy = vy,
            });
        }

        self.last_x = p.x;
        self.last_y = p.y;
        self.last_ms = p.t_ms;
    }

    fn onUp(self: *Recognizer, p: Pointer) void {
        if (p.id <= 1) {
            self.pointers[p.id] = null;
            if (self.pinch_active) {
                self.pinch_active = false;
                self.pinch_start_dist = 0;
                self.push(.{ .kind = .pinch, .phase = .end, .x = p.x, .y = p.y, .scale = 1 });
            }
        }
        if (p.id != 0 or !self.down) return;

        const dx = p.x - self.down_x;
        const dy = p.y - self.down_y;
        const adx = @abs(dx);
        const ady = @abs(dy);
        const dt = if (p.t_ms > self.down_ms) p.t_ms - self.down_ms else 1;
        const vx = @as(f32, @floatFromInt(dx)) * 1000.0 / @as(f32, @floatFromInt(dt));
        const vy = @as(f32, @floatFromInt(dy)) * 1000.0 / @as(f32, @floatFromInt(dt));

        defer {
            self.down = false;
            self.long_armed = false;
            self.edge_start = false;
        }

        if (self.edge_start and dx >= self.thr.swipe_min and adx > ady) {
            self.push(.{
                .kind = .predictive_back,
                .phase = .end,
                .x = p.x,
                .y = p.y,
                .dx = dx,
                .dy = dy,
                .vx = vx,
                .vy = vy,
            });
            self.pending_tap = false;
            return;
        }

        if (self.moved) {
            const swipe_ok = (adx >= self.thr.swipe_min or ady >= self.thr.swipe_min) and
                (@abs(vx) >= self.thr.swipe_vel or @abs(vy) >= self.thr.swipe_vel or
                    adx >= self.thr.swipe_min * 2 or ady >= self.thr.swipe_min * 2);
            if (swipe_ok and !self.long_fired) {
                self.push(.{
                    .kind = .swipe,
                    .phase = .end,
                    .x = p.x,
                    .y = p.y,
                    .dx = dx,
                    .dy = dy,
                    .vx = vx,
                    .vy = vy,
                });
            } else if (self.long_armed) {
                self.push(.{
                    .kind = .pickup_move,
                    .phase = .end,
                    .x = p.x,
                    .y = p.y,
                    .dx = dx,
                    .dy = dy,
                });
            } else {
                self.push(.{
                    .kind = .drag,
                    .phase = .end,
                    .x = p.x,
                    .y = p.y,
                    .dx = dx,
                    .dy = dy,
                    .vx = vx,
                    .vy = vy,
                });
            }
            self.pending_tap = false;
            return;
        }

        if (self.long_fired) {
            self.pending_tap = false;
            return; // long_press already emitted
        }

        // Press-capture: hit identity is the down sample, not the release.
        // Finger jitter within slop used to land taps on a neighbor button when
        // up coords were used (dense jog/actions rails).
        const hx = self.down_x;
        const hy = self.down_y;

        // Tap immediately; second tap in window → double_tap (MD3 lists keep click snappy).
        if (self.pending_tap and
            p.t_ms - self.pending_ms <= self.thr.double_tap_ms and
            @abs(hx - self.pending_x) <= self.thr.double_tap_slop and
            @abs(hy - self.pending_y) <= self.thr.double_tap_slop)
        {
            self.pending_tap = false;
            self.push(.{
                .kind = .double_tap,
                .phase = .end,
                .x = hx,
                .y = hy,
            });
            return;
        }

        self.push(.{
            .kind = .tap,
            .phase = .end,
            .x = hx,
            .y = hy,
        });
        self.pending_tap = true;
        self.pending_x = hx;
        self.pending_y = hy;
        self.pending_ms = p.t_ms;
    }

    fn onCancel(self: *Recognizer, t_ms: u64) void {
        _ = t_ms;
        self.down = false;
        self.pending_tap = false;
        self.long_armed = false;
        self.pinch_active = false;
        self.pointers = .{ null, null };
        self.push(.{ .kind = .none, .phase = .cancel });
    }

    fn tryStartPinch(self: *Recognizer) void {
        const a = self.pointers[0] orelse return;
        const b = self.pointers[1] orelse return;
        const dx: f32 = @floatFromInt(b.x - a.x);
        const dy: f32 = @floatFromInt(b.y - a.y);
        self.pinch_start_dist = @sqrt(dx * dx + dy * dy);
        if (self.pinch_start_dist < 1) self.pinch_start_dist = 1;
        self.pinch_active = true;
        self.push(.{
            .kind = .pinch,
            .phase = .begin,
            .x = @divTrunc(a.x + b.x, 2),
            .y = @divTrunc(a.y + b.y, 2),
            .scale = 1,
        });
    }

    fn updatePinch(self: *Recognizer, _: i32, _: i32) bool {
        if (!self.pinch_active) return false;
        const a = self.pointers[0] orelse return false;
        const b = self.pointers[1] orelse return false;
        const dx: f32 = @floatFromInt(b.x - a.x);
        const dy: f32 = @floatFromInt(b.y - a.y);
        const dist = @sqrt(dx * dx + dy * dy);
        const scale = dist / self.pinch_start_dist;
        self.push(.{
            .kind = .pinch,
            .phase = .update,
            .x = @divTrunc(a.x + b.x, 2),
            .y = @divTrunc(a.y + b.y, 2),
            .scale = scale,
        });
        return true;
    }
};

test "tap emits on up" {
    var r: Recognizer = .{};
    r.feed(.{ .phase = .down, .x = 10, .y = 10, .t_ms = 0 });
    r.feed(.{ .phase = .up, .x = 10, .y = 10, .t_ms = 50 });
    const e = r.poll().?;
    try std.testing.expect(e.kind == .tap);
    try std.testing.expectEqual(@as(i32, 10), e.x);
    try std.testing.expectEqual(@as(i32, 10), e.y);
}

test "tap press-capture ignores release drift within slop" {
    var r: Recognizer = .{};
    r.feed(.{ .phase = .down, .x = 100, .y = 200, .t_ms = 0 });
    r.feed(.{ .phase = .move, .x = 112, .y = 208, .t_ms = 30 });
    r.feed(.{ .phase = .up, .x = 115, .y = 210, .t_ms = 50 });
    const e = r.poll().?;
    try std.testing.expect(e.kind == .tap);
    try std.testing.expectEqual(@as(i32, 100), e.x);
    try std.testing.expectEqual(@as(i32, 200), e.y);
}

test "double tap" {
    var r: Recognizer = .{};
    r.feed(.{ .phase = .down, .x = 10, .y = 10, .t_ms = 0 });
    r.feed(.{ .phase = .up, .x = 10, .y = 10, .t_ms = 40 });
    try std.testing.expect(r.poll().?.kind == .tap);
    r.feed(.{ .phase = .down, .x = 12, .y = 11, .t_ms = 120 });
    r.feed(.{ .phase = .up, .x = 12, .y = 11, .t_ms = 160 });
    const e = r.poll().?;
    try std.testing.expect(e.kind == .double_tap);
}

test "long press on tick" {
    var r: Recognizer = .{};
    r.feed(.{ .phase = .down, .x = 5, .y = 5, .t_ms = 0 });
    r.tick(100);
    try std.testing.expect(r.poll() == null);
    r.tick(500);
    const e = r.poll().?;
    try std.testing.expect(e.kind == .long_press);
}

test "swipe horizontal" {
    var r: Recognizer = .{};
    r.feed(.{ .phase = .down, .x = 100, .y = 200, .t_ms = 0 });
    r.feed(.{ .phase = .move, .x = 200, .y = 205, .t_ms = 40 });
    r.feed(.{ .phase = .up, .x = 280, .y = 208, .t_ms = 80 });
    var saw_swipe = false;
    while (r.poll()) |e| {
        if (e.kind == .swipe) saw_swipe = true;
    }
    try std.testing.expect(saw_swipe);
}

test "predictive back from edge" {
    var r: Recognizer = .{};
    r.feed(.{ .phase = .down, .x = 8, .y = 300, .t_ms = 0 });
    r.feed(.{ .phase = .move, .x = 100, .y = 302, .t_ms = 50 });
    r.feed(.{ .phase = .up, .x = 160, .y = 304, .t_ms = 100 });
    var saw = false;
    while (r.poll()) |e| {
        if (e.kind == .predictive_back and e.phase == .end) saw = true;
    }
    try std.testing.expect(saw);
}

test "pinch from two pointers" {
    var r: Recognizer = .{};
    r.feed(.{ .phase = .down, .x = 100, .y = 100, .t_ms = 0, .id = 0 });
    r.feed(.{ .phase = .down, .x = 200, .y = 100, .t_ms = 0, .id = 1 });
    const begin = r.poll().?;
    try std.testing.expect(begin.kind == .pinch and begin.phase == .begin);
    r.feed(.{ .phase = .move, .x = 50, .y = 100, .t_ms = 20, .id = 0 });
    r.feed(.{ .phase = .move, .x = 250, .y = 100, .t_ms = 20, .id = 1 });
    var saw_update = false;
    while (r.poll()) |e| {
        if (e.kind == .pinch and e.phase == .update and e.scale > 1.0) saw_update = true;
    }
    try std.testing.expect(saw_update);
}

test "pickup after long press drag" {
    var r: Recognizer = .{};
    r.feed(.{ .phase = .down, .x = 50, .y = 50, .t_ms = 0 });
    r.tick(500);
    _ = r.poll(); // long_press
    r.feed(.{ .phase = .move, .x = 100, .y = 55, .t_ms = 560 });
    var saw = false;
    while (r.poll()) |e| {
        if (e.kind == .pickup_move or e.kind == .compound) saw = true;
    }
    try std.testing.expect(saw);
}

test "feedScale pinch stand-in" {
    var r: Recognizer = .{};
    r.feedScale(0.1, 640, 360, 0);
    const e = r.poll().?;
    try std.testing.expect(e.kind == .pinch);
    try std.testing.expect(e.scale > 1.0);
}
