//! Axis-aligned rects + dirty union (no heap).

/// Host glove mode: expand hit tests by this many logical px (0 = normal).
pub var hit_pad: i32 = 0;

/// Engine / flush dirty list capacity (raise to cut merge-all → full-frame).
pub const dirty_cap: usize = 64;

pub const Rect = struct {
    x: i32 = 0,
    y: i32 = 0,
    w: i32 = 0,
    h: i32 = 0,

    pub fn empty() Rect {
        return .{};
    }

    pub fn isEmpty(self: Rect) bool {
        return self.w <= 0 or self.h <= 0;
    }

    pub fn area(self: Rect) u32 {
        if (self.isEmpty()) return 0;
        return @intCast(self.w * self.h);
    }

    /// Optional inflate for glove-friendly host hits (set via `hit_pad`).
    pub fn contains(self: Rect, px: i32, py: i32) bool {
        if (self.isEmpty()) return false;
        const p = hit_pad;
        return px >= self.x - p and py >= self.y - p and px < self.x + self.w + p and py < self.y + self.h + p;
    }

    /// Exact bounds — no `hit_pad`. Use for panel routing so glove inflate
    /// cannot let the DRO column steal center/actions taps.
    pub fn containsStrict(self: Rect, px: i32, py: i32) bool {
        if (self.isEmpty()) return false;
        return px >= self.x and py >= self.y and px < self.x + self.w and py < self.y + self.h;
    }

    pub fn intersect(a: Rect, b: Rect) Rect {
        const x1 = @max(a.x, b.x);
        const y1 = @max(a.y, b.y);
        const x2 = @min(a.x + a.w, b.x + b.w);
        const y2 = @min(a.y + a.h, b.y + b.h);
        if (x2 <= x1 or y2 <= y1) return .empty();
        return .{ .x = x1, .y = y1, .w = x2 - x1, .h = y2 - y1 };
    }

    pub fn unionBounds(a: Rect, b: Rect) Rect {
        if (a.isEmpty()) return b;
        if (b.isEmpty()) return a;
        const x1 = @min(a.x, b.x);
        const y1 = @min(a.y, b.y);
        const x2 = @max(a.x + a.w, b.x + b.w);
        const y2 = @max(a.y + a.h, b.y + b.h);
        return .{ .x = x1, .y = y1, .w = x2 - x1, .h = y2 - y1 };
    }
};

/// Fixed-cap dirty list; merges overlapping into one bounds when full.
pub fn DirtySet(comptime cap: usize) type {
    return struct {
        rects: [cap]Rect = [_]Rect{.empty()} ** cap,
        len: usize = 0,

        const Self = @This();

        pub fn clear(self: *Self) void {
            self.len = 0;
        }

        pub fn add(self: *Self, r: Rect) void {
            if (r.isEmpty()) return;
            var i: usize = 0;
            while (i < self.len) : (i += 1) {
                const cur = self.rects[i];
                const hit = !Rect.intersect(cur, r).isEmpty();
                if (hit) {
                    self.rects[i] = Rect.unionBounds(cur, r);
                    return;
                }
            }
            if (self.len < cap) {
                self.rects[self.len] = r;
                self.len += 1;
                return;
            }
            // ponytail: merge-all when cap hit; tile grid later if needed
            var bounds = r;
            for (self.rects[0..self.len]) |cur| {
                bounds = Rect.unionBounds(bounds, cur);
            }
            self.rects[0] = bounds;
            self.len = 1;
        }

        pub fn totalArea(self: *const Self) u32 {
            var sum: u32 = 0;
            for (self.rects[0..self.len]) |r| sum += r.area();
            return sum;
        }
    };
}

test "dirty merges overlap" {
    var d: DirtySet(4) = .{};
    d.add(.{ .x = 0, .y = 0, .w = 10, .h = 10 });
    d.add(.{ .x = 5, .y = 5, .w = 10, .h = 10 });
    try @import("std").testing.expectEqual(@as(usize, 1), d.len);
    try @import("std").testing.expect(d.rects[0].area() > 100);
}
