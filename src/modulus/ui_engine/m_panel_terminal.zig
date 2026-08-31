//! M-Panel Terminal — MDI console (LVGL `ui_quick_settings.c` qs_term parity).

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const widgets = @import("widgets.zig");
const tool_chrome = @import("m_panel_tool.zig");

const card_w: i32 = 1180;
const card_h: i32 = 600;
const input_h: i32 = tokens.Logical.touch_min;
const line_gap: i32 = tokens.Space.xs;
const line_role: tokens.TypeRole = .body_s;
const tx_prefix = "> ";

fn cardGeom(enter_t: f32) geom.Rect {
    const t = std.math.clamp(enter_t, 0, 1);
    const w: i32 = @intFromFloat(@as(f32, @floatFromInt(card_w)) * (0.92 + 0.08 * t));
    const h: i32 = @intFromFloat(@as(f32, @floatFromInt(card_h)) * (0.92 + 0.08 * t));
    return .{
        .x = @divTrunc(tokens.Logical.width - w, 2),
        .y = @divTrunc(tokens.Logical.height - h, 2),
        .w = w,
        .h = h,
    };
}

fn lineH() i32 {
    return font.faceHeight(font.faceForRole(line_role)) + line_gap;
}

pub fn logContentH(log: []const u8) i32 {
    if (log.len == 0) return lineH();
    var lines: i32 = 1;
    for (log) |c| {
        if (c == '\n') lines += 1;
    }
    return lines * lineH();
}

pub fn scrollMax(log: []const u8, view_h: i32) i32 {
    return @max(0, logContentH(log) - view_h);
}

fn paintLogLine(logical: *fb.LogicalFb, theme: tokens.Theme, x: i32, y: i32, line: []const u8) void {
    if (line.len == 0) return;
    if (std.mem.startsWith(u8, line, tx_prefix)) {
        const px = x;
        font.drawTextRole(logical, px, y, tx_prefix, theme.primary, line_role);
        const pw = font.textWidthStr(tx_prefix, line_role);
        font.drawTextRole(logical, px + pw, y, line[tx_prefix.len..], theme.on_surface, line_role);
    } else {
        font.drawTextRole(logical, x, y, line, theme.on_surface, line_role);
    }
}

fn paintLog(logical: *fb.LogicalFb, theme: tokens.Theme, view: geom.Rect, log: []const u8, scroll: i32) void {
    widgets.fillRoundRect(logical, view, tokens.Shape.md, theme.surface_container_low);
    widgets.strokeRoundRect(logical, view, tokens.Shape.md, theme.outline_variant, 1);
    if (log.len == 0) {
        font.drawTextRole(logical, view.x + tokens.Space.sm, view.y + tokens.Space.sm, "(no traffic yet)", theme.on_surface_variant, line_role);
        return;
    }
    logical.setClip(view);
    defer logical.setClip(null);
    var y = view.y + tokens.Space.sm - scroll;
    const lh = lineH();
    const tx = view.x + tokens.Space.sm;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= log.len) : (i += 1) {
        if (i == log.len or log[i] == '\n') {
            if (y + lh > view.y and y < view.y + view.h) {
                paintLogLine(logical, theme, tx, y, log[start..i]);
            }
            y += lh;
            start = i + 1;
        }
    }
}

pub const Ctx = struct {
    term_log: []const u8 = "",
    mdi_line: []const u8 = "",
    scroll_px: i32 = 0,
    input_focused: bool = false,
    auto_scroll: bool = true,
};

pub const Hit = enum {
    none,
    scrim,
    back,
    exit,
    auto_scroll,
    input,
    send,
};

pub const Layout = struct {
    header: tool_chrome.Header = .{},
    auto_scroll: geom.Rect = .{},
    log_view: geom.Rect = .{},
    input: geom.Rect = .{},
    send: geom.Rect = .{},
    scroll_max: i32 = 0,
};

pub fn paint(logical: *fb.LogicalFb, theme: tokens.Theme, ctx: Ctx, enter_t: f32) Layout {
    widgets.fillScrim(logical, theme);
    const card = cardGeom(enter_t);
    widgets.fillRoundRect(logical, card, tokens.Shape.dialog, theme.elev(3));
    widgets.strokeRoundRect(logical, card, tokens.Shape.dialog, theme.outline_variant, 1);

    var lay: Layout = .{};
    lay.header = tool_chrome.headerChrome(card);
    tool_chrome.paintBackToPanel(logical, theme, lay.header.back);
    const title_x = lay.header.back.x + lay.header.back.w + tokens.Space.sm;
    tool_chrome.paintTitle(logical, theme, title_x, lay.header.back.y, "Terminal");
    tool_chrome.paintExit(logical, theme, lay.header.exit);

    const auto_lbl = "Auto scroll";
    const lbl_h = font.faceHeight(font.faceForRole(.label_m));
    const lbl_w = font.textWidthStr(auto_lbl, .label_m);
    const sw_x = lay.header.exit.x - tokens.Space.md - widgets.switch_w;
    const sw_y = lay.header.back.y + @divTrunc(tokens.Logical.touch_min - widgets.switch_h, 2);
    const lbl_x = sw_x - tokens.Space.sm - lbl_w;
    widgets.drawSwitchBool(logical, sw_x, sw_y, ctx.auto_scroll, theme);
    font.drawTextRole(
        logical,
        lbl_x,
        sw_y + @divTrunc(widgets.switch_h - lbl_h, 2),
        auto_lbl,
        theme.on_surface_variant,
        .label_m,
    );
    const sw_hit = widgets.switchHitRect(sw_x, sw_y);
    lay.auto_scroll = .{
        .x = lbl_x,
        .y = lay.header.back.y,
        .w = sw_hit.x + sw_hit.w - lbl_x,
        .h = tokens.Logical.touch_min,
    };

    const pad = tokens.Space.lg;
    const div_h: i32 = 1;
    const row_y = card.y + card.h - pad - input_h;
    const div_y = row_y - tokens.Space.sm - div_h;
    const body_top = lay.header.back.y + lay.header.back.h + tokens.Space.md;
    lay.log_view = .{
        .x = card.x + pad,
        .y = body_top,
        .w = card.w - pad * 2,
        .h = div_y - tokens.Space.sm - body_top,
    };
    lay.scroll_max = scrollMax(ctx.term_log, lay.log_view.h);
    const scroll = std.math.clamp(ctx.scroll_px, 0, lay.scroll_max);
    paintLog(logical, theme, lay.log_view, ctx.term_log, scroll);

    logical.fillRect(.{ .x = card.x + pad, .y = div_y, .w = card.w - pad * 2, .h = div_h }, theme.outline_variant);

    const send_w = @max(tokens.Logical.touch_min, font.textWidthStr("Send", .label_l) + tokens.ButtonSize.m.padX() * 2);
    lay.send = .{
        .x = card.x + card.w - pad - send_w,
        .y = row_y,
        .w = send_w,
        .h = input_h,
    };
    lay.input = .{
        .x = card.x + pad,
        .y = row_y,
        .w = lay.send.x - pad - tokens.Space.sm - (card.x + pad),
        .h = input_h,
    };
    widgets.drawOutlinedTextField(
        logical,
        lay.input,
        ctx.mdi_line,
        "MDI / $ command",
        ctx.input_focused,
        true,
        false,
        theme,
    );
    widgets.drawFilledButton(logical, lay.send, "Send", theme);
    return lay;
}

pub fn hit(layout: Layout, x: i32, y: i32) Hit {
    if (tool_chrome.hitBack(layout.header, x, y)) return .back;
    if (tool_chrome.hitExit(layout.header, x, y)) return .exit;
    if (tool_chrome.hitScrim(layout.header, x, y)) return .scrim;
    if (layout.auto_scroll.contains(x, y)) return .auto_scroll;
    if (layout.send.contains(x, y)) return .send;
    if (layout.input.contains(x, y)) return .input;
    return .none;
}

test "terminal send meets touch_min" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    const theme = tokens.Theme.industrialTealDark();
    const lay = paint(&logical, theme, .{ .term_log = "> G0\n", .mdi_line = "G1", .auto_scroll = true }, 1);
    try std.testing.expect(lay.send.h >= tokens.Logical.touch_min);
    try std.testing.expect(lay.input.h >= tokens.Logical.touch_min);
    try std.testing.expect(lay.auto_scroll.h >= tokens.Logical.touch_min);
    try std.testing.expect(hit(lay, lay.send.x + 4, lay.send.y + 4) == .send);
    try std.testing.expect(hit(lay, lay.auto_scroll.x + 4, lay.auto_scroll.y + 4) == .auto_scroll);
}

test "terminal auto scroll label is tappable" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    const lay = paint(&logical, tokens.Theme.industrialTealDark(), .{}, 1);
    const mid_x = lay.auto_scroll.x + @divTrunc(lay.auto_scroll.w, 2);
    const mid_y = lay.auto_scroll.y + @divTrunc(lay.auto_scroll.h, 2);
    try std.testing.expect(hit(lay, mid_x, mid_y) == .auto_scroll);
}

test "terminal log view fits above input divider" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    const lay = paint(&logical, tokens.Theme.industrialTealDark(), .{ .term_log = "line\n" ** 20 }, 1);
    try std.testing.expect(lay.log_view.h > 0);
    try std.testing.expect(lay.input.y > lay.log_view.y + lay.log_view.h);
}
