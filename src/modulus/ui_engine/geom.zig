//! Axis-aligned rects + dirty union (no heap).

/// Host glove mode: expand hit tests by this many logical px (0 = normal).
pub var hit_pad: i32 = 0;

/// Engine / flush dirty list capacity (raise to cut merge-all → full-frame).
pub const dirty_cap: usize = 64;

/// Count of `DirtySet.add` cap overflows (each collapses the set to one AABB,
/// usually the full frame). Surfaced in the perf HUD — a rising count means
/// `dirty_cap` is too small for the busiest screen.
pub var merge_all_events: u32 = 0;

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

        /// Merging on *any* overlap and stopping at the first hit left two
        /// defects: the grown rect could still overlap a later slot (so the
        /// same pixels were rotated twice, and `totalArea` over-counted), and a
        /// one-pixel corner touch unioned two far-apart rects plus the gap
        /// between them into one near-full-screen AABB.
        /// Now: cascade until nothing more merges, and only merge when the
        /// union stays within 1.5x the summed area. Separate rects cost
        /// `a + b` writes (overlap rotated twice), merged costs `u`, so the
        /// allowance keeps real overlaps merged while a corner kiss — where
        /// `u` explodes to cover the gap — is left as two rects.
        pub fn add(self: *Self, r: Rect) void {
            if (r.isEmpty()) return;
            var merged = r;
            var i: usize = 0;
            while (i < self.len) {
                const cur = self.rects[i];
                const u = Rect.unionBounds(cur, merged);
                const overlaps = !Rect.intersect(cur, merged).isEmpty();
                if (overlaps and u.area() * 2 <= (cur.area() + merged.area()) * 3) {
                    merged = u;
                    self.len -= 1;
                    self.rects[i] = self.rects[self.len];
                    continue; // re-test slot i (swap-removed tail landed here)
                }
                i += 1;
            }
            if (self.len < cap) {
                self.rects[self.len] = merged;
                self.len += 1;
                return;
            }
            // Cap hit: collapse to one AABB. Counted so the perf HUD can show
            // full-frame collapses instead of leaving them to be guessed at.
            merge_all_events +%= 1;
            var bounds = merged;
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

test "dirty keeps corner-touching rects apart" {
    const t = @import("std").testing;
    var d: DirtySet(8) = .{};
    // 1 px of overlap at the corner; union would be 200x200 = 40000 vs 2*10201.
    d.add(.{ .x = 0, .y = 0, .w = 101, .h = 101 });
    d.add(.{ .x = 100, .y = 100, .w = 100, .h = 100 });
    try t.expectEqual(@as(usize, 2), d.len);
    try t.expect(d.totalArea() < 40000);
}

test "dirty cascades so no two slots overlap" {
    const t = @import("std").testing;
    var d: DirtySet(8) = .{};
    d.add(.{ .x = 0, .y = 0, .w = 40, .h = 40 });
    d.add(.{ .x = 60, .y = 0, .w = 40, .h = 40 });
    try t.expectEqual(@as(usize, 2), d.len);
    // Bridges both: old code merged into slot 0 only and left slot 1 overlapping.
    d.add(.{ .x = 30, .y = 0, .w = 40, .h = 40 });
    try t.expectEqual(@as(usize, 1), d.len);
    var i: usize = 0;
    while (i < d.len) : (i += 1) {
        var j = i + 1;
        while (j < d.len) : (j += 1) {
            try t.expect(Rect.intersect(d.rects[i], d.rects[j]).isEmpty());
        }
    }
}

test "dirty totalArea does not double count after cascade" {
    const t = @import("std").testing;
    var d: DirtySet(8) = .{};
    d.add(.{ .x = 0, .y = 0, .w = 20, .h = 20 });
    d.add(.{ .x = 10, .y = 10, .w = 20, .h = 20 });
    d.add(.{ .x = 5, .y = 5, .w = 20, .h = 20 });
    try t.expectEqual(@as(usize, 1), d.len);
    try t.expectEqual(d.rects[0].area(), d.totalArea());
}

test "dirty merge-all is counted" {
    const t = @import("std").testing;
    const before = merge_all_events;
    var d: DirtySet(2) = .{};
    d.add(.{ .x = 0, .y = 0, .w = 10, .h = 10 });
    d.add(.{ .x = 500, .y = 0, .w = 10, .h = 10 });
    d.add(.{ .x = 0, .y = 500, .w = 10, .h = 10 });
    try t.expectEqual(@as(usize, 1), d.len);
    try t.expectEqual(before + 1, merge_all_events);
}
