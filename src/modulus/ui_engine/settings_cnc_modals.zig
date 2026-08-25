//! CNC settings overlays — connection profiles + `$$` dump browser (LVGL parity).

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const widgets = @import("widgets.zig");
const expr = @import("widgets_expressive.zig");
const prefs_mod = @import("settings_prefs.zig");

pub const Kind = enum { none, profiles, dump };

pub const ProfHit = enum {
    none,
    close,
    save,
    activate0,
    activate1,
    activate2,
    activate3,
    rename0,
    rename1,
    rename2,
    rename3,
};

pub const DumpHit = enum { none, close };

pub const ProfLayout = struct {
    card: geom.Rect = .{},
    close: geom.Rect = .{},
    save: geom.Rect = .{},
    activate: [prefs_mod.profile_slots]geom.Rect = [_]geom.Rect{.{}} ** prefs_mod.profile_slots,
    rename: [prefs_mod.profile_slots]geom.Rect = [_]geom.Rect{.{}} ** prefs_mod.profile_slots,
};

pub const DumpState = struct {
    open: bool = false,
    ticks: u8 = 0,
    ready: bool = false,
    failed: bool = false,
    buf: [1024]u8 = undefined,
    len: usize = 0,
    close: geom.Rect = .{},
    card: geom.Rect = .{},
    body: geom.Rect = .{},
    /// Pixel scroll into the $$ text body.
    scroll_px: i32 = 0,
    scroll_max: i32 = 0,

    pub fn begin(self: *DumpState) void {
        self.* = .{ .open = true };
    }

    pub fn cancel(self: *DumpState) void {
        self.* = .{};
    }

    pub fn text(self: *const DumpState) []const u8 {
        return self.buf[0..self.len];
    }

    /// Host stub: advance progress then inject sample `$$` lines.
    pub fn tick(self: *DumpState) bool {
        if (!self.open or self.ready or self.failed) return false;
        if (self.ticks < 95) self.ticks +|= 5;
        if (self.ticks >= 95) {
            const sample =
                \\$0=10
                \\$1=25
                \\$10=1
                \\$11=0.010
                \\$20=0
                \\$21=0
                \\$22=1
                \\$30=1000
                \\$100=80.000
                \\$101=80.000
                \\$102=800.000
                \\$110=5000.000
                \\$111=5000.000
                \\$112=500.000
                \\$120=100.000
                \\$121=100.000
                \\$122=10.000
                \\$130=200.000
                \\$131=200.000
                \\$132=100.000
            ;
            const n = @min(sample.len, self.buf.len);
            @memcpy(self.buf[0..n], sample[0..n]);
            self.len = n;
            self.ready = true;
            self.ticks = 100;
        }
        return true;
    }

    fn lineCount(self: *const DumpState) usize {
        if (self.len == 0) return 0;
        var n: usize = 1;
        for (self.buf[0..self.len]) |c| {
            if (c == '\n') n += 1;
        }
        return n;
    }
};

const close_sz: i32 = tokens.Logical.touch_min;
const row_h: i32 = tokens.Logical.touch_min + tokens.Space.sm; // 56 — room between 48dp hits

fn paintCloseX(logical: *fb.LogicalFb, theme: tokens.Theme, r: geom.Rect) void {
    widgets.drawTonalCloseButton(logical, r, theme);
}

pub fn paintProfiles(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    c: *const prefs_mod.CncPrefs,
    enter_t: f32,
) ProfLayout {
    widgets.fillScrim(logical, theme);

    const t = std.math.clamp(enter_t, 0, 1);
    const card_w0: i32 = 560;
    const card_h0: i32 = 540;
    const card_w: i32 = @intFromFloat(@as(f32, @floatFromInt(card_w0)) * (0.88 + 0.12 * t));
    const card_h: i32 = @intFromFloat(@as(f32, @floatFromInt(card_h0)) * (0.88 + 0.12 * t));
    const card: geom.Rect = .{
        .x = @divTrunc(tokens.Logical.width - card_w, 2),
        .y = @divTrunc(tokens.Logical.height - card_h, 2),
        .w = card_w,
        .h = card_h,
    };
    widgets.fillRoundRect(logical, card, tokens.Shape.dialog, theme.elev(3));

    var lay: ProfLayout = .{ .card = card };
    font.drawTextRole(logical, card.x + tokens.Space.lg, card.y + tokens.Space.md, "Connection profiles", theme.on_surface, .title_l);
    lay.close = .{
        .x = card.x + card.w - close_sz - tokens.Space.md,
        .y = card.y + tokens.Space.sm,
        .w = close_sz,
        .h = close_sz,
    };
    paintCloseX(logical, theme, lay.close);

    font.drawTextRole(
        logical,
        card.x + tokens.Space.lg,
        card.y + 56,
        "Activate applies proto/transport/hosts then reconnects.",
        theme.on_surface_variant,
        .body_s,
    );

    const hit_h = tokens.Logical.touch_min;
    const active = @min(c.prof, prefs_mod.profile_slots - 1);
    var i: usize = 0;
    while (i < prefs_mod.profile_slots) : (i += 1) {
        const y = card.y + 88 + @as(i32, @intCast(i)) * row_h;
        const name = c.profileName(@intCast(i));
        var label_buf: [40]u8 = undefined;
        const label = if (name.len > 0)
            (std.fmt.bufPrint(&label_buf, "Slot {d}: {s}", .{ i + 1, name }) catch "Slot")
        else
            (std.fmt.bufPrint(&label_buf, "Slot {d}: (empty)", .{i + 1}) catch "Slot");

        const act: geom.Rect = .{
            .x = card.x + tokens.Space.lg,
            .y = y,
            .w = card.w - tokens.Space.lg * 2 - 140,
            .h = hit_h,
        };
        widgets.fillRoundRect(logical, act, tokens.Shape.sm, if (i == active) theme.secondary_container else theme.surface_container_high);
        const lh = font.faceHeight(font.faceForRole(.body_m));
        font.drawTextRole(logical, act.x + 12, act.y + @divTrunc(act.h - lh, 2), label, if (i == active) theme.on_secondary_container else theme.on_surface, .body_m);
        if (i == active) {
            const ah = font.faceHeight(font.faceForRole(.label_m));
            font.drawTextRole(logical, act.x + act.w - 64, act.y + @divTrunc(act.h - ah, 2), "Active", theme.primary, .label_m);
        }
        lay.activate[i] = act;

        const ren: geom.Rect = .{
            .x = card.x + card.w - tokens.Space.lg - 128,
            .y = y,
            .w = 128,
            .h = hit_h,
        };
        widgets.drawTonalButton(logical, ren, "Rename", theme);
        lay.rename[i] = ren;
    }

    const btn_h = tokens.ButtonSize.m.height();
    lay.save = .{
        .x = card.x + tokens.Space.lg,
        .y = card.y + card.h - btn_h - tokens.Space.lg,
        .w = card.w - tokens.Space.lg * 2,
        .h = @max(btn_h, hit_h),
    };
    widgets.drawFilledButton(logical, lay.save, "Save current to active slot", theme);
    return lay;
}

pub fn hitProfiles(lay: ProfLayout, x: i32, y: i32) ProfHit {
    if (lay.close.contains(x, y)) return .close;
    if (lay.save.contains(x, y)) return .save;
    inline for (0..prefs_mod.profile_slots) |i| {
        if (lay.activate[i].contains(x, y)) {
            return switch (i) {
                0 => .activate0,
                1 => .activate1,
                2 => .activate2,
                else => .activate3,
            };
        }
        if (lay.rename[i].contains(x, y)) {
            return switch (i) {
                0 => .rename0,
                1 => .rename1,
                2 => .rename2,
                else => .rename3,
            };
        }
    }
    if (!lay.card.contains(x, y)) return .close;
    return .none;
}

pub fn paintDump(logical: *fb.LogicalFb, theme: tokens.Theme, st: *DumpState, enter_t: f32) void {
    widgets.fillScrim(logical, theme);

    const t = std.math.clamp(enter_t, 0, 1);
    const card_w0: i32 = 720;
    const card_h0: i32 = 520;
    const card_w: i32 = @intFromFloat(@as(f32, @floatFromInt(card_w0)) * (0.88 + 0.12 * t));
    const card_h: i32 = @intFromFloat(@as(f32, @floatFromInt(card_h0)) * (0.88 + 0.12 * t));
    const card: geom.Rect = .{
        .x = @divTrunc(tokens.Logical.width - card_w, 2),
        .y = @divTrunc(tokens.Logical.height - card_h, 2),
        .w = card_w,
        .h = card_h,
    };
    st.card = card;
    widgets.fillRoundRect(logical, card, tokens.Shape.dialog, theme.elev(3));

    const title_h = font.faceHeight(font.faceForRole(.title_l));
    var y = card.y + tokens.Space.md;
    font.drawTextRole(logical, card.x + tokens.Space.lg, y, "Controller settings ($$)", theme.on_surface, .title_l);
    y += title_h + tokens.Space.sm;

    const status: []const u8 = if (st.failed)
        "Failed - connect in Idle or buffer full"
    else if (st.ready)
        (if (st.len > 0) "Controller settings loaded" else "Empty response")
    else
        "Requesting $$ from controller...";
    const status_fg = if (st.failed) theme.err else theme.on_surface_variant;
    const body_h = font.faceHeight(font.faceForRole(.body_m));
    font.drawTextRole(logical, card.x + tokens.Space.lg, y, status, status_fg, .body_m);
    y += body_h + tokens.Space.sm;

    const track: geom.Rect = .{
        .x = card.x + tokens.Space.lg,
        .y = y,
        .w = card.w - tokens.Space.lg * 2,
        .h = 4,
    };
    expr.drawLinearProgress(logical, track, @as(f32, @floatFromInt(st.ticks)) / 100.0, theme);
    y += 4 + tokens.Space.md;

    const btn_h = @max(tokens.ButtonSize.m.height(), tokens.Logical.touch_min);
    st.body = .{
        .x = card.x + tokens.Space.lg,
        .y = y,
        .w = card.w - tokens.Space.lg * 2,
        .h = card.y + card.h - btn_h - tokens.Space.lg - tokens.Space.md - y,
    };
    widgets.fillRoundRect(logical, st.body, tokens.Shape.sm, theme.surface_container_low);

    const line_h = font.faceHeight(font.faceForRole(.body_s)) + 2;
    const content_h: i32 = @intCast(st.lineCount() * @as(usize, @intCast(line_h)) + 16);
    st.scroll_max = @max(0, content_h - st.body.h);
    st.scroll_px = std.math.clamp(st.scroll_px, 0, st.scroll_max);

    if (st.ready and st.len > 0) {
        logical.setClip(st.body);
        defer logical.setClip(null);
        var draw_y = st.body.y + 8 - st.scroll_px;
        var line_start: usize = 0;
        while (line_start < st.len) {
            const rest = st.buf[line_start..st.len];
            const nl = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
            const line = rest[0..nl];
            if (draw_y + line_h >= st.body.y and draw_y < st.body.y + st.body.h and line.len > 0) {
                font.drawTextRole(logical, st.body.x + 8, draw_y, line, theme.on_surface, .body_s);
            }
            draw_y += line_h;
            line_start += nl + 1;
            if (nl >= rest.len) break;
        }
    }

    st.close = .{
        .x = card.x + card.w - 140 - tokens.Space.lg,
        .y = card.y + card.h - btn_h - tokens.Space.md,
        .w = 140,
        .h = btn_h,
    };
    expr.drawTextButton(logical, st.close, "Close", theme);
}

pub fn hitDump(st: DumpState, x: i32, y: i32) DumpHit {
    if (st.close.contains(x, y)) return .close;
    if (!st.card.contains(x, y)) return .close;
    return .none;
}

test "cnc modals: dump tick completes with sample" {
    var st: DumpState = .{};
    st.begin();
    var n: u32 = 0;
    while (!st.ready and n < 40) : (n += 1) {
        _ = st.tick();
    }
    try std.testing.expect(st.ready);
    try std.testing.expect(st.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, st.text(), "$110=") != null);
}

test "cnc modals: profile hits meet touch_min" {
    var logical = try fb.LogicalFb.alloc(std.testing.allocator);
    defer logical.deinit(std.testing.allocator);
    const theme = tokens.Theme.industrialTealDark();
    const c: prefs_mod.CncPrefs = .{};
    const lay = paintProfiles(&logical, theme, &c, 1);
    try std.testing.expect(lay.close.h >= tokens.Logical.touch_min);
    try std.testing.expect(lay.activate[0].h >= tokens.Logical.touch_min);
    try std.testing.expect(lay.rename[0].h >= tokens.Logical.touch_min);
    try std.testing.expect(lay.save.h >= tokens.Logical.touch_min);
}
