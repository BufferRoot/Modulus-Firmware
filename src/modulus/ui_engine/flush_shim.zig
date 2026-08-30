//! Host present + Tab5 DSI flush contract.
//!
//! Host: rotate measure / Win32 present. Device: rotate into the DPI *back*
//! buffer; with ≥2 FBs, `flush_flip` switches DMA (tear-free). Single FB:
//! cache write-back of dirty rows on the live scanout.

const std = @import("std");
const builtin = @import("builtin");
const color = @import("color.zig");
const geom = @import("geom.zig");
const fb = @import("fb.zig");
const tokens = @import("tokens.zig");

const device_flush = builtin.os.tag == .freestanding;

const FlushApi = if (device_flush) struct {
    extern fn modulus_ui_engine_flush_scanout() ?[*]color.Rgb565;
    extern fn modulus_ui_engine_flush_scanout_px() u32;
    extern fn modulus_ui_engine_flush_dual() bool;
    /// Cache write-back of dirty rows on the current back buffer.
    /// NOTE: a PPA-written rect really wants M2C (invalidate), not C2M — see
    /// ui_engine_flush_shim.c. Both M2C variants tried on device regressed the
    /// first paint, so this stays C2M until that is understood.
    extern fn modulus_ui_engine_flush_rows(y0: u16, y1: u16) c_int;
    extern fn modulus_ui_engine_flush_flip() c_int;
} else struct {
    pub fn modulus_ui_engine_flush_scanout() ?[*]color.Rgb565 {
        return null;
    }
    pub fn modulus_ui_engine_flush_scanout_px() u32 {
        return 0;
    }
    pub fn modulus_ui_engine_flush_dual() bool {
        return false;
    }
    pub fn modulus_ui_engine_flush_rows(_: u16, _: u16) c_int {
        return 0;
    }
    pub fn modulus_ui_engine_flush_flip() c_int {
        return -1;
    }
};

/// True when the device flips between ≥2 DPI framebuffers. Callers must then
/// repaint last frame's damage too — the back buffer is one frame behind.
pub fn dualBuffered() bool {
    return device_flush and FlushApi.modulus_ui_engine_flush_dual();
}

/// Current DPI back buffer Zig paints into, or null before bind.
/// Borrowed — `PanelFb.owned` must stay false. Pointer advances after flip.
pub fn scanoutPixels() ?[]color.Rgb565 {
    const ptr = FlushApi.modulus_ui_engine_flush_scanout() orelse return null;
    const n = FlushApi.modulus_ui_engine_flush_scanout_px();
    if (n == 0) return null;
    return ptr[0..n];
}

pub const PresentStats = struct {
    rects: u32 = 0,
    px: u32 = 0,
    /// Packed tiles submitted (host bring-up / device ABI mirror).
    tiles: u32 = 0,
    /// True when at least one rect was transposed by the CPU rather than the
    /// PPA. Recorded for diagnostics; the flush direction does not use it yet
    /// (see modulus_ui_engine_flush_rows).
    cpu_wrote: bool = false,
    /// Cache-sync calls the driver rejected — a dropped sync leaves a stale
    /// band on the panel, so it must be visible rather than swallowed.
    sync_errors: u32 = 0,
};

/// Matches firmware `k_dry_tile_w/h` — max packed stripe until PSRAM DMA.
pub const tile_max: i32 = 64;

// ponytail: host mirror of device BSS s_dry_tile; upgrade = PSRAM stripe when gate on.
var host_tile_scratch: [tile_max * tile_max]color.Rgb565 = undefined;
var host_last_flush_px: u32 = 0;

pub fn lastFlushPx() u32 {
    return host_last_flush_px;
}

fn validateTile(
    tile: []const color.Rgb565,
    tile_w: i32,
    tile_h: i32,
    panel_x: i32,
    panel_y: i32,
) error{InvalidArg}!usize {
    if (tile_w <= 0 or tile_h <= 0) return error.InvalidArg;
    if (panel_x < 0 or panel_y < 0) return error.InvalidArg;
    if ((panel_x + tile_w) > tokens.Logical.panel_w or (panel_y + tile_h) > tokens.Logical.panel_h)
        return error.InvalidArg;
    const need: usize = @intCast(tile_w * tile_h);
    if (tile.len < need) return error.InvalidArg;
    return need;
}

/// Host sink — mirrors gated `modulus_ui_engine_flush_tile_rgb565` (count + bounds).
pub fn hostFlushTile(
    tile: []const color.Rgb565,
    tile_w: i32,
    tile_h: i32,
    panel_x: i32,
    panel_y: i32,
) error{InvalidArg}!void {
    const need = try validateTile(tile, tile_w, tile_h, panel_x, panel_y);
    host_last_flush_px = @intCast(need);
}

const sinkTile = hostFlushTile;

/// Copy dirty set for present after rotate flush (engine keeps this).
pub fn copyDirty(dst: *geom.DirtySet(geom.dirty_cap), src: *const geom.DirtySet(geom.dirty_cap)) void {
    dst.clear();
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        dst.add(src.rects[i]);
    }
}

/// Landscape logical rect → portrait panel rect (90° CW, matches `fb.PanelFb.blitRotated`).
pub fn logicalToPanelRect(logical: geom.Rect) geom.Rect {
    if (logical.isEmpty()) return .empty();
    const W: i32 = tokens.Logical.width;
    // (lx,ly) → (ly, W-1-lx); AABB of corners:
    // panel_x ∈ [y, y+h), panel_y ∈ [W-x-w, W-x)
    return .{
        .x = logical.y,
        .y = W - logical.x - logical.w,
        .w = logical.h,
        .h = logical.w,
    };
}

pub fn mapDirtyToPanel(dst: *geom.DirtySet(geom.dirty_cap), src: *const geom.DirtySet(geom.dirty_cap)) void {
    dst.clear();
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        const pr = logicalToPanelRect(src.rects[i]);
        const clipped = geom.Rect.intersect(pr, .{
            .x = 0,
            .y = 0,
            .w = tokens.Logical.panel_w,
            .h = tokens.Logical.panel_h,
        });
        dst.add(clipped);
    }
}

/// Count dirty area only (single-FB host — no panel write).
pub fn measureDirty(dirty: *const geom.DirtySet(geom.dirty_cap)) PresentStats {
    var stats: PresentStats = .{};
    const full = geom.Rect{ .x = 0, .y = 0, .w = tokens.Logical.width, .h = tokens.Logical.height };
    var i: usize = 0;
    while (i < dirty.len) : (i += 1) {
        const b = geom.Rect.intersect(dirty.rects[i], full);
        if (b.isEmpty()) continue;
        stats.rects += 1;
        stats.px += b.area();
    }
    return stats;
}

/// Rotate dirty logical rects into panel (Tab5 dual-FB path). No-op write if panel empty.
pub fn flushRotated(panel: *fb.PanelFb, logical: *const fb.LogicalFb, dirty: *const geom.DirtySet(geom.dirty_cap)) PresentStats {
    if (!panel.hasBuffer()) {
        const stats = measureDirty(dirty);
        panel.last_write_px = stats.px;
        return stats;
    }
    var stats: PresentStats = .{};
    var i: usize = 0;
    while (i < dirty.len) : (i += 1) {
        panel.blitRotated(logical, dirty.rects[i]);
        stats.px += panel.last_write_px;
        stats.rects += 1;
        // Mixed frame: one CPU fallback rect makes the whole span need C2M.
        if (!panel.last_write_was_dma and panel.last_write_px > 0) stats.cpu_wrote = true;
    }
    panel.last_write_px = stats.px;
    return stats;
}

/// Rotate into the panel back buffer, then present.
///
/// Dual DPI FB: cache-sync dirty rows, flip DMA to that buffer, re-point
/// `panel.pixels` at the new back. Single FB: cache-sync only (live scanout).
pub fn presentRotated(
    panel: *fb.PanelFb,
    logical: *const fb.LogicalFb,
    dirty: *const geom.DirtySet(geom.dirty_cap),
) PresentStats {
    var stats = flushRotated(panel, logical, dirty);
    if (!device_flush or !panel.hasBuffer()) return stats;

    // Stack local by measurement: hoisting this to BSS moved the zig_ui
    // high-water mark by 0 bytes — present runs after the paint tree, not
    // under it. See Engine.flushDirty.
    var panel_dirty_buf: geom.DirtySet(geom.dirty_cap) = .{};
    const panel_dirty = &panel_dirty_buf;
    mapDirtyToPanel(panel_dirty, dirty);
    // One msync per rect, NOT one merged y-span. Merging looked like a win
    // (flush_rows syncs whole panel rows, so rects sharing a row got synced
    // twice) but the status bar sits at one end of the panel and the actions
    // grid at the other, so min..max covered the whole framebuffer — the
    // health line read a full 921600 px every frame. Per-rect over-syncs a
    // little; the merged span over-synced everything.
    var i: usize = 0;
    while (i < panel_dirty.len) : (i += 1) {
        const r = panel_dirty.rects[i];
        if (r.isEmpty()) continue;
        const rc = FlushApi.modulus_ui_engine_flush_rows(
            @intCast(@max(r.y, 0)),
            @intCast(@max(r.y + r.h, 0)),
        );
        if (rc != 0) stats.sync_errors += 1;
    }

    if (FlushApi.modulus_ui_engine_flush_dual()) {
        if (FlushApi.modulus_ui_engine_flush_flip() == 0) {
            if (scanoutPixels()) |next| {
                panel.pixels = next;
                panel.owned = false;
            }
        }
    }
    return stats;
}

/// Pack one dirty AABB into a contiguous panel-space tile (stride = panel_w of AABB).
/// For DSI `draw_bitmap`-style submit without a full 1.8 MB panel FB.
pub fn rotateIntoTile(
    logical: *const fb.LogicalFb,
    dirty: geom.Rect,
    out: []color.Rgb565,
) error{BufferTooSmall}!struct { rect: geom.Rect, px: u32 } {
    const bounds = geom.Rect.intersect(dirty, .{
        .x = 0,
        .y = 0,
        .w = logical.w,
        .h = logical.h,
    });
    if (bounds.isEmpty()) return .{ .rect = .empty(), .px = 0 };
    const pr = logicalToPanelRect(bounds);
    const need = pr.area();
    if (out.len < need) return error.BufferTooSmall;

    const lw: usize = logical.w;
    const tw: usize = @intCast(pr.w);
    const src = logical.pixels;
    const lx0 = bounds.x;
    const lx1 = bounds.x + bounds.w;
    const ly0 = bounds.y;
    const ly1 = bounds.y + bounds.h;

    var written: u32 = 0;
    var lx: i32 = lx0;
    while (lx < lx1) : (lx += 1) {
        const panel_y: i32 = @as(i32, @intCast(lw)) - 1 - lx;
        const row_off: usize = @intCast(panel_y - pr.y);
        var src_i = @as(usize, @intCast(ly0)) * lw + @as(usize, @intCast(lx));
        var dst_i = row_off * tw;
        var ly: i32 = ly0;
        // Host: vector lanes OK. Device riscv32: no V ext — scalar only (illegal insn).
        if (comptime builtin.os.tag != .freestanding) {
            while (ly + 8 <= ly1) : (ly += 8) {
                @prefetch(src.ptr + src_i + lw * 8, .{ .rw = .read, .locality = 3, .cache = .data });
                var lane: @Vector(8, u16) = undefined;
                inline for (0..8) |k| {
                    lane[k] = src[src_i + k * lw].toU16();
                }
                const tile: *[8]color.Rgb565 = @ptrCast(@alignCast(out.ptr + dst_i));
                inline for (0..8) |k| {
                    tile[k] = color.Rgb565.fromU16(lane[k]);
                }
                dst_i += 8;
                src_i += lw * 8;
                written += 8;
            }
        }
        while (ly < ly1) : (ly += 1) {
            out[dst_i] = src[src_i];
            dst_i += 1;
            src_i += lw;
            written += 1;
        }
    }
    return .{ .rect = pr, .px = written };
}

/// Count-only / host sink for panel-space dirty (what DSI DMA would touch).
pub fn deviceSubmitPanel(panel_dirty: *const geom.DirtySet(geom.dirty_cap)) PresentStats {
    var stats: PresentStats = .{};
    var i: usize = 0;
    while (i < panel_dirty.len) : (i += 1) {
        const r = panel_dirty.rects[i];
        if (r.isEmpty()) continue;
        stats.rects += 1;
        stats.px += r.area();
    }
    return stats;
}

/// Logical dirty → panel map → submit. No full-panel FB required.
pub fn deviceSubmit(logical_dirty: *const geom.DirtySet(geom.dirty_cap)) PresentStats {
    var panel_dirty: geom.DirtySet(geom.dirty_cap) = .{};
    mapDirtyToPanel(&panel_dirty, logical_dirty);
    return deviceSubmitPanel(&panel_dirty);
}

/// Pack each dirty AABB into ≤`tile_max`² stripes via `rotateIntoTile`, then host sink.
/// Host-only rotate cost model; the device presents via `presentRotated` instead.
pub fn submitDirtyTiles(
    logical: *const fb.LogicalFb,
    dirty: *const geom.DirtySet(geom.dirty_cap),
) PresentStats {
    return submitDirtyTilesBuf(logical, dirty, host_tile_scratch[0..]);
}

pub fn submitDirtyTilesBuf(
    logical: *const fb.LogicalFb,
    dirty: *const geom.DirtySet(geom.dirty_cap),
    scratch: []color.Rgb565,
) PresentStats {
    var stats: PresentStats = .{};
    if (scratch.len < tile_max * tile_max) return stats;

    const full: geom.Rect = .{ .x = 0, .y = 0, .w = logical.w, .h = logical.h };
    var i: usize = 0;
    while (i < dirty.len) : (i += 1) {
        const bounds = geom.Rect.intersect(dirty.rects[i], full);
        if (bounds.isEmpty()) continue;
        stats.rects += 1;

        var y = bounds.y;
        while (y < bounds.y + bounds.h) : (y += tile_max) {
            var x = bounds.x;
            while (x < bounds.x + bounds.w) : (x += tile_max) {
                const chunk = geom.Rect.intersect(bounds, .{
                    .x = x,
                    .y = y,
                    .w = tile_max,
                    .h = tile_max,
                });
                if (chunk.isEmpty()) continue;
                const got = rotateIntoTile(logical, chunk, scratch) catch continue;
                if (got.px == 0 or got.rect.isEmpty()) continue;
                sinkTile(
                    scratch[0..got.px],
                    got.rect.w,
                    got.rect.h,
                    got.rect.x,
                    got.rect.y,
                ) catch continue;
                stats.tiles += 1;
                stats.px += got.px;
            }
        }
    }
    return stats;
}

pub fn fullFramePx() u32 {
    return @as(u32, tokens.Logical.width) * @as(u32, tokens.Logical.height);
}

pub fn fullPanelPx() u32 {
    return @as(u32, tokens.Logical.panel_w) * @as(u32, tokens.Logical.panel_h);
}

test "logicalToPanelRect maps unit and AABB" {
    const u = logicalToPanelRect(.{ .x = 0, .y = 0, .w = 1, .h = 1 });
    try std.testing.expectEqual(@as(i32, 0), u.x);
    try std.testing.expectEqual(@as(i32, tokens.Logical.width - 1), u.y);
    try std.testing.expectEqual(@as(i32, 1), u.w);
    try std.testing.expectEqual(@as(i32, 1), u.h);

    const r = logicalToPanelRect(.{ .x = 10, .y = 20, .w = 100, .h = 50 });
    try std.testing.expectEqual(@as(i32, 20), r.x);
    try std.testing.expectEqual(@as(i32, tokens.Logical.width - 10 - 100), r.y);
    try std.testing.expectEqual(@as(i32, 50), r.w);
    try std.testing.expectEqual(@as(i32, 100), r.h);
    try std.testing.expectEqual(@as(u32, 5000), r.area());
}

test "deviceSubmit maps area through panel" {
    var d: geom.DirtySet(geom.dirty_cap) = .{};
    d.add(.{ .x = 10, .y = 10, .w = 100, .h = 50 });
    const s = deviceSubmit(&d);
    try std.testing.expectEqual(@as(u32, 1), s.rects);
    try std.testing.expectEqual(@as(u32, 5000), s.px);
}

test "rotateIntoTile matches panel corner" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    const red = color.Rgb565.fromHex(0xFF0000);
    logical.fillRect(.{ .x = 0, .y = 0, .w = 1, .h = 1 }, red);
    var tile: [1]color.Rgb565 = undefined;
    const got = try rotateIntoTile(&logical, .{ .x = 0, .y = 0, .w = 1, .h = 1 }, &tile);
    try std.testing.expectEqual(@as(i32, 0), got.rect.x);
    try std.testing.expectEqual(@as(i32, tokens.Logical.width - 1), got.rect.y);
    try std.testing.expectEqual(red.toU16(), tile[0].toU16());
    try std.testing.expectEqual(@as(u32, 1), got.px);
}

test "flushRotated single-FB measures without buffer" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    var panel: fb.PanelFb = .{ .pixels = &.{} };
    var d: geom.DirtySet(geom.dirty_cap) = .{};
    d.add(.{ .x = 0, .y = 0, .w = 10, .h = 20 });
    const s = flushRotated(&panel, &logical, &d);
    try std.testing.expectEqual(@as(u32, 200), s.px);
    try std.testing.expectEqual(@as(u32, 200), panel.last_write_px);
}

// Mirrors firmware modulus_ui_engine_flush_dry_run tile (64×64) — host CI contract.
test "host dry-run tile area matches device stub" {
    var d: geom.DirtySet(geom.dirty_cap) = .{};
    d.add(.{ .x = 0, .y = 0, .w = 64, .h = 64 });
    const s = deviceSubmit(&d);
    try std.testing.expectEqual(@as(u32, 1), s.rects);
    try std.testing.expectEqual(@as(u32, 64 * 64), s.px);

    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    var tile: [64 * 64]color.Rgb565 = undefined;
    const got = try rotateIntoTile(&logical, .{ .x = 0, .y = 0, .w = 64, .h = 64 }, &tile);
    try std.testing.expectEqual(@as(u32, 64 * 64), got.px);
    try std.testing.expectEqual(@as(i32, 64), got.rect.w);
    try std.testing.expectEqual(@as(i32, 64), got.rect.h);
}

test "submitDirtyTiles packs and sinks 64x64" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    const green = color.Rgb565.fromHex(0x00FF00);
    logical.fillRect(.{ .x = 0, .y = 0, .w = 64, .h = 64 }, green);

    var d: geom.DirtySet(geom.dirty_cap) = .{};
    d.add(.{ .x = 0, .y = 0, .w = 64, .h = 64 });
    const s = submitDirtyTiles(&logical, &d);
    try std.testing.expectEqual(@as(u32, 1), s.rects);
    try std.testing.expectEqual(@as(u32, 1), s.tiles);
    try std.testing.expectEqual(@as(u32, 64 * 64), s.px);
    try std.testing.expectEqual(@as(u32, 64 * 64), lastFlushPx());
}

test "submitDirtyTiles slices large dirty into multiple tiles" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    var d: geom.DirtySet(geom.dirty_cap) = .{};
    d.add(.{ .x = 0, .y = 0, .w = 128, .h = 64 });
    const s = submitDirtyTiles(&logical, &d);
    try std.testing.expectEqual(@as(u32, 1), s.rects);
    try std.testing.expectEqual(@as(u32, 2), s.tiles);
    try std.testing.expectEqual(@as(u32, 128 * 64), s.px);
}
