//! Critically-damped-ish spring (MD3 Expressive motion).
//! Spatial = position/size; Effects = color/opacity progress 0..1.

const std = @import("std");
const tokens = @import("tokens.zig");

pub const Spring = struct {
    value: f32,
    target: f32,
    velocity: f32 = 0,
    stiffness: f32,
    damping: f32,
    /// Settled when |v| and |error| below epsilon.
    epsilon: f32 = 0.05,

    pub fn init(value: f32, stiffness: f32, damping: f32) Spring {
        return .{
            .value = value,
            .target = value,
            .stiffness = stiffness,
            .damping = damping,
        };
    }

    pub fn spatial(value: f32) Spring {
        return init(value, tokens.Motion.spatial_stiffness, tokens.Motion.spatial_damping);
    }

    pub fn effects(value: f32) Spring {
        return init(value, tokens.Motion.effects_stiffness, tokens.Motion.effects_damping);
    }

    pub fn setTarget(self: *Spring, target: f32) void {
        self.target = target;
    }

    /// Kick velocity (scroll fling / wheel).
    pub fn impulse(self: *Spring, dv: f32) void {
        self.velocity += dv;
    }

    pub fn settled(self: *const Spring) bool {
        const err = self.target - self.value;
        return @abs(err) < self.epsilon and @abs(self.velocity) < self.epsilon;
    }

    /// Advance by dt_sec. Returns true if still moving.
    /// Backward Euler — unconditionally stable. Explicit Euler diverged once
    /// `damping * dt >= 2`, which Tab5 hits at its 33-50 ms frame period.
    pub fn step(self: *Spring, dt_sec: f32) bool {
        @setFloatMode(.optimized);
        if (dt_sec <= 0) return !self.settled();
        // Cap dt — one huge frame must not explode stiffness*err into Inf (Tab5 settings tabs).
        const dt = @min(dt_sec, 0.05);
        const err = self.target - self.value;
        const denom = 1 + self.damping * dt + self.stiffness * dt * dt;
        self.velocity = (self.velocity + self.stiffness * err * dt) / denom;
        self.value += self.velocity * dt;
        if (!std.math.isFinite(self.value) or !std.math.isFinite(self.velocity)) {
            self.value = self.target;
            self.velocity = 0;
            return false;
        }
        if (self.settled()) {
            self.value = self.target;
            self.velocity = 0;
            return false;
        }
        return true;
    }
};

test "stiff spring settles at Tab5 frame period" {
    // damping*dt = 3.9 here — explicit Euler would oscillate and diverge.
    var s = Spring.init(0, 1500, 78);
    s.setTarget(100);
    var prev = s.value;
    var i: usize = 0;
    while (i < 60) : (i += 1) {
        if (!s.step(0.05)) break;
        try @import("std").testing.expect(s.value >= prev - 0.001); // monotone, no ringing
        try @import("std").testing.expect(s.value <= 100.001); // no overshoot
        prev = s.value;
    }
    try @import("std").testing.expect(@abs(s.value - 100) < 0.1);
}

test "spring step recovers from non-finite blow-up" {
    var s = Spring.init(0, 1e9, 1);
    s.setTarget(100);
    s.velocity = 1e20;
    _ = s.step(1.0);
    try @import("std").testing.expect(std.math.isFinite(s.value));
    try @import("std").testing.expect(std.math.isFinite(s.velocity));
}
