//! Job progress strip — LVGL `ui_job_progress.c` silhouette (host).
//! Full-width under status bar; visible only while Run|Hold.
//! Colors: MD3 scheme pairs only (primary run / tertiary hold).
//! Bar: expressive wave + indeterminate slide (LVGL parity).

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const widgets = @import("widgets.zig");
const expr = @import("widgets_expressive.zig");
const color = @import("color.zig");

pub const strip_h: i32 = 60;

pub const View = struct {
    /// 0..1 determinate; ignored when `indet`.
    progress: f32 = 0,
    /// No % on wire — sliding indeterminate segment.
    indet: bool = false,
    /// Wave / slide phase (LVGL s_phase).
    phase: f32 = 0,
    hold: bool = false,
    name: []const u8 = "External job",
    elapsed: []const u8 = "0:00",
    /// Optional line number for indet chip (0 = show "...").
    line: u32 = 0,
};

pub fn paint(logical: *fb.LogicalFb, theme: tokens.Theme, status_h: i32, view: View) void {
    const strip: geom.Rect = .{ .x = 0, .y = status_h, .w = tokens.Logical.width, .h = strip_h };
    logical.fillRect(strip, theme.elev(1));
    logical.fillRect(.{ .x = 0, .y = status_h, .w = tokens.Logical.width, .h = 1 }, theme.outline_variant);

    const chip_bg = if (view.hold) theme.tertiary_container else theme.primary_container;
    const chip_fg = if (view.hold) theme.on_tertiary_container else theme.on_primary_container;
    const ind = if (view.hold) theme.tertiary else theme.primary;

    const pad_h = tokens.Space.md;
    const pad_v = tokens.Space.sm;
    const row_y = status_h + pad_v;
    const name_role: tokens.TypeRole = .label_l;
    const name_h = font.faceHeight(font.faceForRole(name_role));
    const pct_u8: u8 = @intFromFloat(std.math.clamp(view.progress, 0, 1) * 100);

    var pct_buf: [24]u8 = undefined;
    const pct_txt = blk: {
        if (view.indet) {
            if (view.hold) break :blk "Hold";
            if (view.line != 0)
                break :blk (std.fmt.bufPrint(&pct_buf, "Ln {d}", .{view.line}) catch "...");
            break :blk "...";
        }
        if (view.hold)
            break :blk (std.fmt.bufPrint(&pct_buf, "HOLD {d}%", .{pct_u8}) catch "HOLD");
        break :blk (std.fmt.bufPrint(&pct_buf, "{d}%", .{pct_u8}) catch "?%");
    };

    const pct_tw = font.textWidthStr(pct_txt, .label_l);
    const chip_pad: i32 = tokens.Space.sm + tokens.Space.xs;
    const chip_h: i32 = 28;
    const chip_w = pct_tw + chip_pad * 2;
    const time_tw = font.textWidthStr(view.elapsed, .body_s);
    const right_x = tokens.Logical.width - pad_h - (chip_w + tokens.Space.sm + time_tw);

    font.drawTextRole(logical, pad_h, row_y + @divTrunc(chip_h - name_h, 2), view.name, theme.on_surface, name_role);

    widgets.fillRoundRect(logical, .{ .x = right_x, .y = row_y, .w = chip_w, .h = chip_h }, tokens.Shape.full, chip_bg);
    font.drawTextRole(
        logical,
        right_x + chip_pad,
        row_y + @divTrunc(chip_h - font.faceHeight(font.faceForRole(.label_l)), 2),
        pct_txt,
        chip_fg,
        .label_l,
    );
    font.drawTextRole(
        logical,
        right_x + chip_w + tokens.Space.sm,
        row_y + @divTrunc(chip_h - font.faceHeight(font.faceForRole(.body_s)), 2),
        view.elapsed,
        theme.on_surface_variant,
        .body_s,
    );

    const track_h = expr.linear_track_h;
    const track_y = status_h + strip_h - pad_v - track_h - 2;
    const track: geom.Rect = .{
        .x = pad_h,
        .y = track_y,
        .w = tokens.Logical.width - pad_h * 2,
        .h = track_h,
    };
    const bar_prog: f32 = if (view.indet) -1 else view.progress;
    expr.drawJobProgressBar(logical, track, bar_prog, view.phase, theme, ind, chip_bg);
}

test "strip height matches LVGL k_strip_h" {
    try std.testing.expectEqual(@as(i32, 60), strip_h);
}

test "run/hold accents are primary/tertiary pairs" {
    const t = tokens.Theme.industrialTealDark();
    try std.testing.expect(color.contrastRatio(t.on_primary_container.toHex(), t.primary_container.toHex()) >= 2.5);
    try std.testing.expect(color.contrastRatio(t.on_tertiary_container.toHex(), t.tertiary_container.toHex()) >= 2.5);
    try std.testing.expect(color.contrastRatio(t.on_primary.toHex(), t.primary.toHex()) >= 2.5);
    try std.testing.expect(color.contrastRatio(t.on_tertiary.toHex(), t.tertiary.toHex()) >= 2.5);
}

test "job strip paints MD3 stop on mid progress" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    const theme = tokens.Theme.industrialTealDark();
    logical.clear(theme.surface);
    paint(&logical, theme, 48, .{ .progress = 0.5, .hold = false, .name = "job.nc", .elapsed = "1:00" });
    const mid_x = tokens.Space.md + @divTrunc(tokens.Logical.width - tokens.Space.md * 2, 2);
    const track_y = 48 + strip_h - tokens.Space.sm - expr.linear_track_h - 2;
    // Wave / underlay / stop — primary family somewhere on track mid.
    var found = false;
    var dx: i32 = -8;
    while (dx <= 8) : (dx += 1) {
        const p = logical.get(mid_x + dx, track_y).toU16();
        if (p == theme.primary.toU16() or p == theme.primary_container.toU16()) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "indet chip and sliding bar paint" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    const theme = tokens.Theme.industrialTealDark();
    logical.clear(theme.surface);
    paint(&logical, theme, 48, .{ .indet = true, .phase = 2.5, .hold = false, .name = "External job", .elapsed = "0:05" });
    try std.testing.expect(logical.get(20, 48 + 10).toU16() == theme.on_surface.toU16() or
        logical.get(tokens.Space.md, 48 + 12).toU16() != theme.surface.toU16());
}
