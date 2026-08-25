//! MD3 Expressive motion physics coordinator (host UI engine).
//! Wraps `spring.zig` with scheme presets, transitions, and fling — heap-free.
//! Spec: https://m3.material.io/styles/motion/overview/how-it-works

const std = @import("std");
const tokens = @import("tokens.zig");
const spring = @import("spring.zig");

pub const Scheme = tokens.MotionScheme;

/// Named spring / transition recipes.
pub const Preset = enum {
    /// Position / size (snappy).
    spatial,
    /// Color / opacity / morph (softer).
    effects,
    /// Screen enter (emphasized decelerate dwell).
    enter,
    /// Screen exit (emphasized accelerate).
    exit,
    /// Shared-axis tab / pane shift.
    shared_axis,
    /// Fling / scroll coast (slightly underdamped spatial).
    fling,
};

pub const Physics = struct {
    scheme: Scheme = .expressive,

    pub fn init(scheme: Scheme) Physics {
        return .{ .scheme = scheme };
    }

    pub fn setScheme(self: *Physics, scheme: Scheme) void {
        self.scheme = scheme;
    }

    pub fn applySpatial(self: Physics, s: *spring.Spring) void {
        s.stiffness = self.scheme.spatialStiffness();
        s.damping = self.scheme.spatialDamping();
    }

    pub fn applyEffects(self: Physics, s: *spring.Spring) void {
        s.stiffness = self.scheme.effectsStiffness();
        s.damping = self.scheme.effectsDamping();
    }

    pub fn applyPreset(self: Physics, s: *spring.Spring, preset: Preset) void {
        const p = self.params(preset);
        s.stiffness = p.stiffness;
        s.damping = p.damping;
        if (p.epsilon) |e| s.epsilon = e;
    }

    const Params = struct { stiffness: f32, damping: f32, epsilon: ?f32 = null };

    pub fn params(self: Physics, preset: Preset) Params {
        return switch (preset) {
            .spatial, .shared_axis => .{
                .stiffness = self.scheme.spatialStiffness(),
                .damping = self.scheme.spatialDamping(),
            },
            .effects => .{
                .stiffness = self.scheme.effectsStiffness(),
                .damping = self.scheme.effectsDamping(),
            },
            .enter => .{
                // Emphasized decelerate — softer settle into place.
                .stiffness = self.scheme.spatialStiffness() * 0.85,
                .damping = self.scheme.spatialDamping() * 1.15,
            },
            .exit => .{
                // Emphasized accelerate — quicker leave.
                .stiffness = self.scheme.spatialStiffness() * 1.25,
                .damping = self.scheme.spatialDamping() * 0.9,
            },
            .fling => .{
                .stiffness = self.scheme.spatialStiffness() * 0.55,
                .damping = self.scheme.spatialDamping() * 0.75,
                .epsilon = tokens.Motion.scroll_epsilon,
            },
        };
    }

    pub fn makeSpring(self: Physics, preset: Preset, value: f32) spring.Spring {
        const p = self.params(preset);
        var s = spring.Spring.init(value, p.stiffness, p.damping);
        if (p.epsilon) |e| s.epsilon = e;
        return s;
    }

    /// Apply scheme to the Engine's primary spatial/effects springs.
    pub fn applyToSprings(
        self: Physics,
        scroll: *spring.Spring,
        sheet: *spring.Spring,
        tab_axis: *spring.Spring,
        effects: []*spring.Spring,
    ) void {
        self.applySpatial(scroll);
        self.applySpatial(sheet);
        self.applySpatial(tab_axis);
        for (effects) |s| self.applyEffects(s);
    }

    /// Shared-axis enter kick (value = offset → 0).
    pub fn kickSharedAxis(self: Physics, s: *spring.Spring) void {
        self.applyPreset(s, .shared_axis);
        s.value = tokens.Motion.shared_axis_px;
        s.velocity = 0;
        s.setTarget(0);
    }

    /// Impulse fling then chase a projected target inside [lo, hi].
    pub fn fling(self: Physics, s: *spring.Spring, velocity: f32, lo: f32, hi: f32) void {
        self.applyPreset(s, .fling);
        s.impulse(velocity);
        // Project coast distance from v / (2ζ-ish) — ponytail: linear scale of |v|.
        const coast = velocity * 0.18;
        const nt = std.math.clamp(s.target + coast, lo, hi);
        s.setTarget(nt);
    }

    /// Soft wheel nudge (keeps spatial scheme, light impulse).
    pub fn wheelNudge(self: Physics, s: *spring.Spring, dy: f32, lo: f32, hi: f32) void {
        self.applySpatial(s);
        s.impulse(dy * 0.35);
        s.setTarget(std.math.clamp(s.target + dy, lo, hi));
    }

    /// Settings/content scroll: move target only, critically damped chase.
    /// No impulse — underdamped+impulse rubberbanded mid-list on fast pans.
    pub fn trackScroll(self: Physics, s: *spring.Spring, dy: f32, lo: f32, hi: f32) void {
        _ = self;
        const k: f32 = tokens.Motion.scroll_track_stiffness;
        s.stiffness = k;
        s.damping = 2.0 * @sqrt(k); // ζ=1 — eases in, no overshoot jiggle
        s.epsilon = tokens.Motion.scroll_epsilon;
        s.setTarget(std.math.clamp(s.target + dy, lo, hi));
        // Bound detachment on very fast pans (~one row) without ringing.
        const max_lag: f32 = 40;
        const err = s.target - s.value;
        if (@abs(err) > max_lag) {
            s.value = s.target - std.math.clamp(err, -max_lag, max_lag);
        }
    }

    /// Enter kick: value = from_px → 0 (generic slide-in; snack uses snack_fx instead).
    pub fn kickEnter(self: Physics, s: *spring.Spring, from_px: f32) void {
        self.applyPreset(s, .enter);
        s.value = from_px;
        s.velocity = 0;
        s.setTarget(0);
    }
};

/// Fixed pool of effects springs keyed by widget id (switches, sliders, segments).
/// Heap-free; LRU eviction when full.
pub const WidgetPool = struct {
    /// Settings pages paint many switches/sliders/segments; 32 evicted mid-morph → choppy pills.
    pub const capacity: usize = 72;

    const Slot = struct {
        key: u32 = 0,
        used: bool = false,
        stamp: u32 = 0,
        spring: spring.Spring = spring.Spring.spatial(0),
    };

    slots: [capacity]Slot = [_]Slot{.{}} ** capacity,
    clock: u32 = 1,
    /// When true, sample returns target immediately (smooth_anim off).
    instant: bool = false,

    pub fn hashKey(label: []const u8) u32 {
        // FNV-1a 32 — stable across frames for the same label.
        var h: u32 = 2166136261;
        for (label) |c| {
            h ^= c;
            h *%= 16777619;
        }
        return h;
    }

    pub fn applyScheme(self: *WidgetPool, phys: Physics) void {
        for (&self.slots) |*s| {
            // Spatial (not soft effects) — settings controls match Jog snappiness.
            if (s.used) phys.applySpatial(&s.spring);
        }
    }

    pub fn sample(self: *WidgetPool, phys: Physics, key: u32, target: f32) f32 {
        if (self.instant) return target;
        const slot = self.getOrInsert(phys, key, target);
        if (slot.spring.target != target) slot.spring.setTarget(target);
        slot.stamp = self.clock;
        self.clock +%= 1;
        return slot.spring.value;
    }

    pub fn sampleBool(self: *WidgetPool, phys: Physics, key: u32, on: bool) f32 {
        return self.sample(phys, key, if (on) 1 else 0);
    }

    /// Press morph: snap to 1 then spring back to 0 (MD3 press release).
    pub fn pulse(self: *WidgetPool, phys: Physics, key: u32) void {
        if (self.instant) return;
        const slot = self.getOrInsert(phys, key, 1);
        slot.spring.value = 1;
        slot.spring.velocity = 0;
        slot.spring.setTarget(0);
        slot.stamp = self.clock;
        self.clock +%= 1;
    }

    pub fn stepAll(self: *WidgetPool, dt_sec: f32) bool {
        if (self.instant) return false;
        var any = false;
        for (&self.slots) |*s| {
            if (s.used and s.spring.step(dt_sec)) any = true;
        }
        return any;
    }

    fn makeControlSpring(phys: Physics, initial: f32) spring.Spring {
        var s = phys.makeSpring(.spatial, initial);
        // Tighter settle than default spatial — stop full-pane settings repaints sooner.
        s.epsilon = 0.02;
        return s;
    }

    fn getOrInsert(self: *WidgetPool, phys: Physics, key: u32, initial: f32) *Slot {
        for (&self.slots) |*s| {
            if (s.used and s.key == key) return s;
        }
        for (&self.slots) |*s| {
            if (!s.used) {
                s.* = .{
                    .key = key,
                    .used = true,
                    .stamp = self.clock,
                    .spring = makeControlSpring(phys, initial),
                };
                return s;
            }
        }
        // Prefer settled springs — never yank a mid-flight segment/switch morph.
        var victim: usize = 0;
        var best_stamp: u32 = std.math.maxInt(u32);
        var found_settled = false;
        for (self.slots, 0..) |s, i| {
            const settled = s.spring.settled();
            if (settled and (!found_settled or s.stamp < best_stamp)) {
                found_settled = true;
                best_stamp = s.stamp;
                victim = i;
            } else if (!found_settled and s.stamp < best_stamp) {
                best_stamp = s.stamp;
                victim = i;
            }
        }
        self.slots[victim] = .{
            .key = key,
            .used = true,
            .stamp = self.clock,
            .spring = makeControlSpring(phys, initial),
        };
        return &self.slots[victim];
    }
};

pub fn hashLabel(label: []const u8) u32 {
    return WidgetPool.hashKey(label);
}

/// 0..1 progress spring for enter / exit / dialogs.
pub const Transition = struct {
    spring: spring.Spring,
    preset: Preset = .enter,

    pub fn enter(phys: Physics) Transition {
        var tr = Transition{ .spring = phys.makeSpring(.enter, 0), .preset = .enter };
        tr.spring.setTarget(1);
        return tr;
    }

    pub fn exit(phys: Physics) Transition {
        var tr = Transition{ .spring = phys.makeSpring(.exit, 1), .preset = .exit };
        tr.spring.setTarget(0);
        return tr;
    }

    pub fn effectsCrossfade(phys: Physics, from: f32, to: f32) Transition {
        var tr = Transition{ .spring = phys.makeSpring(.effects, from), .preset = .effects };
        tr.spring.setTarget(to);
        return tr;
    }

    pub fn step(self: *Transition, dt_sec: f32) bool {
        return self.spring.step(dt_sec);
    }

    pub fn progress(self: *const Transition) f32 {
        return self.spring.value;
    }

    pub fn settled(self: *const Transition) bool {
        return self.spring.settled();
    }
};

/// Legacy MD3 duration easing sample (transitions that are not spring-driven).
/// Emphasized: cubic-bezier(0.2, 0, 0, 1) — piecewise approx.
fn sampleEmphasized(u: f32) f32 {
    const x = std.math.clamp(u, 0, 1);
    // Smoothstep-ish with slower start (emphasized decelerate family).
    return x * x * (3 - 2 * x);
}

fn sampleEmphasizedDecelerate(u: f32) f32 {
    const x = std.math.clamp(u, 0, 1);
    return 1 - (1 - x) * (1 - x);
}

fn sampleEmphasizedAccelerate(u: f32) f32 {
    const x = std.math.clamp(u, 0, 1);
    return x * x;
}

/// Duration progress 0..1 over `ms` at `dt_sec` accum.
pub const DurationClock = struct {
    elapsed: f32 = 0,
    duration_sec: f32,

    pub fn initMs(ms: u32) DurationClock {
        return .{ .duration_sec = @as(f32, @floatFromInt(ms)) / 1000.0 };
    }

    pub fn step(self: *DurationClock, dt_sec: f32) f32 {
        self.elapsed += dt_sec;
        if (self.duration_sec <= 0) return 1;
        return std.math.clamp(self.elapsed / self.duration_sec, 0, 1);
    }

    pub fn done(self: *const DurationClock) bool {
        return self.elapsed >= self.duration_sec;
    }
};

test "physics makeSpring reaches target" {
    const phys = Physics.init(.expressive);
    var s = phys.makeSpring(.spatial, 0);
    s.setTarget(50);
    var i: usize = 0;
    while (i < 400 and s.step(1.0 / 60.0)) : (i += 1) {}
    try std.testing.expect(s.settled());
}

test "fling moves target with velocity" {
    var phys = Physics.init(.standard);
    var s = phys.makeSpring(.spatial, 0);
    s.setTarget(0);
    phys.fling(&s, 800, 0, 500);
    try std.testing.expect(s.target > 0);
    try std.testing.expect(s.target <= 500);
    try std.testing.expect(s.velocity > 0);
}

test "transition enter settles near 1" {
    const phys = Physics.init(.expressive);
    var tr = Transition.enter(phys);
    var i: usize = 0;
    while (i < 400 and tr.step(1.0 / 60.0)) : (i += 1) {}
    try std.testing.expect(tr.progress() > 0.95);
}

test "duration clock and easing bounds" {
    var c = DurationClock.initMs(400);
    _ = c.step(0.2);
    try std.testing.expect(!c.done());
    _ = c.step(0.3);
    try std.testing.expect(c.done());
    try std.testing.expectEqual(@as(f32, 0), sampleEmphasized(0));
    try std.testing.expectEqual(@as(f32, 1), sampleEmphasized(1));
    try std.testing.expect(sampleEmphasizedDecelerate(0.5) > 0.5);
    try std.testing.expect(sampleEmphasizedAccelerate(0.5) < 0.5);
}

test "kickSharedAxis zeros target" {
    var phys = Physics.init(.expressive);
    var s = phys.makeSpring(.spatial, 0);
    phys.kickSharedAxis(&s);
    try std.testing.expectEqual(tokens.Motion.shared_axis_px, s.value);
    try std.testing.expectEqual(@as(f32, 0), s.target);
}

test "widget pool springs toward bool" {
    const phys = Physics.init(.expressive);
    var pool: WidgetPool = .{};
    const k = hashLabel("Dark mode");
    _ = pool.sampleBool(phys, k, false);
    const mid = pool.sampleBool(phys, k, true);
    try std.testing.expect(mid < 1);
    var i: usize = 0;
    while (i < 200 and pool.stepAll(1.0 / 60.0)) : (i += 1) {}
    try std.testing.expect(pool.sampleBool(phys, k, true) > 0.95);
}
