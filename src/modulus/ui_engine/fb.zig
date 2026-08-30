//! Logical landscape FB + native portrait panel via rotate-on-write.

const std = @import("std");
const color = @import("color.zig");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");

pub const LogicalFb = struct {
    pixels: []color.Rgb565,
    w: u16 = tokens.Logical.width,
    h: u16 = tokens.Logical.height,
    /// Optional scissor — null = full buffer. Used by settings scroll content.
    clip: ?geom.Rect = null,
    /// Shared-axis / transient paint offset (added to put/fill/blend).
    origin_x: i32 = 0,
    origin_y: i32 = 0,

    pub fn alloc(allocator: std.mem.Allocator) !LogicalFb {
        const n = @as(usize, tokens.Logical.width) * @as(usize, tokens.Logical.height);
        const pixels = try allocator.alloc(color.Rgb565, n);
        @memset(pixels, color.Rgb565.fromHex(0x000000));
        return .{ .pixels = pixels };
    }

    pub fn deinit(self: *LogicalFb, allocator: std.mem.Allocator) void {
        allocator.free(self.pixels);
        self.pixels = &.{};
    }

    pub fn setClip(self: *LogicalFb, r: ?geom.Rect) void {
        self.clip = r;
    }

    pub fn clear(self: *LogicalFb, c: color.Rgb565) void {
        @memset(self.pixels, c);
    }

    pub fn fillRect(self: *LogicalFb, r: geom.Rect, c: color.Rgb565) void {
        const shifted: geom.Rect = .{
            .x = r.x + self.origin_x,
            .y = r.y + self.origin_y,
            .w = r.w,
            .h = r.h,
        };
        var bounds = geom.Rect.intersect(shifted, .{
            .x = 0,
            .y = 0,
            .w = self.w,
            .h = self.h,
        });
        if (self.clip) |cl| bounds = geom.Rect.intersect(bounds, cl);
        if (bounds.isEmpty()) return;
        var y: i32 = bounds.y;
        while (y < bounds.y + bounds.h) : (y += 1) {
            const row = @as(usize, @intCast(y)) * @as(usize, self.w);
            const x0: usize = @intCast(bounds.x);
            const x1: usize = @intCast(bounds.x + bounds.w);
            @memset(self.pixels[row + x0 .. row + x1], c);
        }
    }

    pub fn put(self: *LogicalFb, x: i32, y: i32, c: color.Rgb565) void {
        const px = x + self.origin_x;
        const py = y + self.origin_y;
        if (px < 0 or py < 0 or px >= self.w or py >= self.h) return;
        if (self.clip) |cl| {
            if (!cl.contains(px, py)) return;
        }
        const i = @as(usize, @intCast(py)) * @as(usize, self.w) + @as(usize, @intCast(px));
        self.pixels[i] = c;
    }

    pub fn blendAt(self: *LogicalFb, x: i32, y: i32, fg: color.Rgb565, a: u8) void {
        const px = x + self.origin_x;
        const py = y + self.origin_y;
        if (px < 0 or py < 0 or px >= self.w or py >= self.h) return;
        if (self.clip) |cl| {
            if (!cl.contains(px, py)) return;
        }
        const i = @as(usize, @intCast(py)) * @as(usize, self.w) + @as(usize, @intCast(px));
        self.pixels[i] = color.blendRgb565(self.pixels[i], fg, a);
    }

    /// Blend `fg` over every pixel in `r` (MD3 opaque scrim over painted underlay).
    pub fn blendRect(self: *LogicalFb, r: geom.Rect, fg: color.Rgb565, a: u8) void {
        if (a == 0) return;
        if (a >= 255) {
            self.fillRect(r, fg);
            return;
        }
        const shifted: geom.Rect = .{
            .x = r.x + self.origin_x,
            .y = r.y + self.origin_y,
            .w = r.w,
            .h = r.h,
        };
        var bounds = geom.Rect.intersect(shifted, .{
            .x = 0,
            .y = 0,
            .w = self.w,
            .h = self.h,
        });
        if (self.clip) |cl| bounds = geom.Rect.intersect(bounds, cl);
        if (bounds.isEmpty()) return;
        var y: i32 = bounds.y;
        while (y < bounds.y + bounds.h) : (y += 1) {
            const row = @as(usize, @intCast(y)) * @as(usize, self.w);
            var x: i32 = bounds.x;
            while (x < bounds.x + bounds.w) : (x += 1) {
                const i = row + @as(usize, @intCast(x));
                self.pixels[i] = color.blendRgb565(self.pixels[i], fg, a);
            }
        }
    }

    pub fn get(self: *const LogicalFb, x: i32, y: i32) color.Rgb565 {
        if (x < 0 or y < 0 or x >= self.w or y >= self.h) return .{ .r = 0, .g = 0, .b = 0 };
        const i = @as(usize, @intCast(y)) * @as(usize, self.w) + @as(usize, @intCast(x));
        return self.pixels[i];
    }
};

/// Portrait panel buffer. Landscape (lx,ly) → panel (ly, panel_w-1-lx) for 90° CW.
/// Optional: Tab5 `device_ui_runtime` hooks this so long rotates still sample touch.
pub var during_blit_pump: ?*const fn () void = null;

/// Optional: Tab5 hooks the P4 PPA here. Returns false to fall back to the CPU
/// transpose (PPA rejects unaligned/oversized blocks, and host has no PPA).
pub var hw_rotate: ?*const fn (src: []const color.Rgb565, dst: []color.Rgb565, src_w: u16, src_h: u16, dst_w: u16, dst_h: u16, r: geom.Rect, flipped: bool) bool = null;

pub const PanelFb = struct {
    pixels: []color.Rgb565,
    w: u16 = tokens.Logical.panel_w,
    h: u16 = tokens.Logical.panel_h,
    /// Pixels written last blit (rotate-on-write cost proxy).
    last_write_px: u32 = 0,
    /// True when the last blit went through `hw_rotate` (PPA DMA wrote `dst`,
    /// the CPU did not). The cache maintenance direction depends on this:
    /// CPU writes need write-back (C2M), DMA writes need invalidate (M2C).
    /// Flushing C2M after a DMA write pushes stale CPU lines over the DMA
    /// result — the buffer was seeded by memcpy at bind and may still hold
    /// dirty lines from a CPU-transpose fallback frame.
    last_write_was_dma: bool = false,
    /// False when `pixels` is the DPI scanout buffer (owned by the panel driver).
    owned: bool = true,
    /// "Flip display" — rotate 270° instead of 90° (Engine.mapPointer inverts touch to match).
    flipped: bool = false,

    pub fn alloc(allocator: std.mem.Allocator) !PanelFb {
        const n = @as(usize, tokens.Logical.panel_w) * @as(usize, tokens.Logical.panel_h);
        const pixels = try allocator.alloc(color.Rgb565, n);
        @memset(pixels, color.Rgb565.fromHex(0x000000));
        return .{ .pixels = pixels };
    }

    pub fn deinit(self: *PanelFb, allocator: std.mem.Allocator) void {
        // ponytail: empty slice = single-FB mode (no panel RSS).
        if (self.pixels.len == 0 or !self.owned) return;
        allocator.free(self.pixels);
        self.pixels = &.{};
    }

    pub fn hasBuffer(self: *const PanelFb) bool {
        return self.pixels.len > 0;
    }

    /// 90° CW rotate-on-write for one dirty AABB.
    /// Phase C: walk logical columns → contiguous panel-row stores (no per-pixel bounds).
    pub fn blitRotated(self: *PanelFb, logical: *const LogicalFb, dirty: geom.Rect) void {
        const bounds = geom.Rect.intersect(dirty, .{
            .x = 0,
            .y = 0,
            .w = logical.w,
            .h = logical.h,
        });
        if (bounds.isEmpty()) {
            self.last_write_px = 0;
            return;
        }

        const lw: usize = logical.w;
        const pw: usize = self.w;
        const ph: i32 = self.h;
        const src = logical.pixels;
        const dst = self.pixels;

        const lx0 = bounds.x;
        const lx1 = bounds.x + bounds.w;
        const ly0 = bounds.y;
        const ly1 = bounds.y + bounds.h;
        // panel_x = ly ∈ [ly0, ly1) must fit panel width (== logical height).
        if (ly0 < 0 or ly1 > @as(i32, @intCast(pw)) or ly0 >= ly1) {
            self.last_write_px = 0;
            return;
        }

        // Hardware first: the PPA does this transpose in silicon via DMA.
        if (hw_rotate) |hw| {
            if (hw(src, dst, logical.w, logical.h, self.w, self.h, bounds, self.flipped)) {
                self.last_write_px = @intCast(@as(u32, @intCast(bounds.w)) * @as(u32, @intCast(bounds.h)));
                self.last_write_was_dma = true;
                return;
            }
        }
        self.last_write_was_dma = false;

        var written: u32 = 0;
        // A 90° rotate reads a logical column (stride `lw` px) to fill a panel
        // row, so a column-major walk pulls a fresh 64-byte PSRAM line per
        // pixel and uses 2 bytes of it — ~700 ms for a full 1280×720 frame.
        // Tiling to 32×32 (one cache line == 32 RGB565 px on both axes) keeps
        // the source and destination lines of a tile resident, so each fetched
        // line is consumed 32 times instead of once.
        // ponytail: ~16x, enough for dirty-rect repaints. Ceiling is the CPU
        // doing the transpose at all; upgrade path is the P4 PPA block
        // (esp_driver_ppa scale-rotate-mirror) which rotates in silicon.
        const tile = 32;
        var band: u32 = 0;
        var lyb: i32 = ly0;
        while (lyb < ly1) : (lyb += tile) {
            const ly_end = @min(lyb + tile, ly1);
            var lxb: i32 = lx0;
            while (lxb < lx1) : (lxb += tile) {
                const lx_end = @min(lxb + tile, lx1);
                var ly: i32 = lyb;
                while (ly < ly_end) : (ly += 1) {
                    const src_row = @as(usize, @intCast(ly)) * lw;
                    const dst_col = if (self.flipped)
                        pw - 1 - @as(usize, @intCast(ly))
                    else
                        @as(usize, @intCast(ly));
                    var lx: i32 = lxb;
                    while (lx < lx_end) : (lx += 1) {
                        const panel_y: i32 = if (self.flipped) lx else @as(i32, @intCast(lw)) - 1 - lx;
                        if (panel_y < 0 or panel_y >= ph) continue;
                        dst[@as(usize, @intCast(panel_y)) * pw + dst_col] =
                            src[src_row + @as(usize, @intCast(lx))];
                        written += 1;
                    }
                }
            }
            // Full-frame rotate can run 100ms+ and starve the zig_ui touch
            // poll. Sample (no UI dispatch) every ~128 logical rows.
            band += 1;
            if (band % 4 == 0) {
                if (during_blit_pump) |pump| pump();
            }
        }
        self.last_write_px = written;
    }
};

test "rotate-on-write maps corner" {
    const gpa = std.testing.allocator;
    var logical = try LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    var panel = try PanelFb.alloc(gpa);
    defer panel.deinit(gpa);

    const red = color.Rgb565.fromHex(0xFF0000);
    logical.fillRect(.{ .x = 0, .y = 0, .w = 1, .h = 1 }, red);
    panel.blitRotated(&logical, .{ .x = 0, .y = 0, .w = 1, .h = 1 });
    // (0,0) → (0, 1279)
    const i = @as(usize, 1279) * @as(usize, 720) + 0;
    try std.testing.expectEqual(red.toU16(), panel.pixels[i].toU16());
    try std.testing.expectEqual(@as(u32, 1), panel.last_write_px);
}

test "flipped rotate mirrors the panel 180 degrees" {
    const gpa = std.testing.allocator;
    var logical = try LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    var panel = try PanelFb.alloc(gpa);
    defer panel.deinit(gpa);

    const red = color.Rgb565.fromHex(0xFF0000);
    logical.fillRect(.{ .x = 0, .y = 0, .w = 1, .h = 1 }, red);
    panel.flipped = true;
    panel.blitRotated(&logical, .{ .x = 0, .y = 0, .w = 1, .h = 1 });
    // Normal puts logical (0,0) at panel (0,1279); flipped puts it at the opposite corner.
    const i = @as(usize, 0) * @as(usize, 720) + 719;
    try std.testing.expectEqual(red.toU16(), panel.pixels[i].toU16());
    try std.testing.expectEqual(@as(u32, 1), panel.last_write_px);
}

test "rotate-on-write tile contiguous panel row" {
    const gpa = std.testing.allocator;
    var logical = try LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    var panel = try PanelFb.alloc(gpa);
    defer panel.deinit(gpa);

    const c0 = color.Rgb565.fromHex(0x00FF00);
    const c1 = color.Rgb565.fromHex(0x0000FF);
    // Logical column lx=2, rows ly=10..12 → panel_y = 1280-1-2 = 1277, panel_x = 10,11
    logical.put(2, 10, c0);
    logical.put(2, 11, c1);
    panel.blitRotated(&logical, .{ .x = 2, .y = 10, .w = 1, .h = 2 });
    const row = @as(usize, 1277) * @as(usize, 720);
    try std.testing.expectEqual(c0.toU16(), panel.pixels[row + 10].toU16());
    try std.testing.expectEqual(c1.toU16(), panel.pixels[row + 11].toU16());
    try std.testing.expectEqual(@as(u32, 2), panel.last_write_px);
}
