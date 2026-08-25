//! Settings → Display & Theme (host port of ui_settings_tab_display.c).

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const color = @import("color.zig");
const fb = @import("fb.zig");
const form = @import("settings_form.zig");
const prefs_mod = @import("settings_prefs.zig");

pub const Hit = enum {
    none,
    bright,
    darkmode,
    accent,
    contrast,
    font_scale,
    glove,
    notify,
    notify_level,
    wake,
    sw_icons,
    flip,
    lefty,
    single_pane,
    pwr_sleep,
    refr,
    smooth,
    motion,
    theme_ref,
    reset,
};

pub const Layout = struct {
    bright: geom.Rect = .{},
    darkmode: geom.Rect = .{},
    accent: geom.Rect = .{},
    contrast: geom.Rect = .{},
    font_scale: geom.Rect = .{},
    glove: geom.Rect = .{},
    notify: geom.Rect = .{},
    notify_level: geom.Rect = .{},
    wake: geom.Rect = .{},
    sw_icons: geom.Rect = .{},
    flip: geom.Rect = .{},
    lefty: geom.Rect = .{},
    single_pane: geom.Rect = .{},
    pwr_sleep: geom.Rect = .{},
    refr: geom.Rect = .{},
    smooth: geom.Rect = .{},
    motion: geom.Rect = .{},
    theme_ref: geom.Rect = .{},
    reset: geom.Rect = .{},
    content_h: i32 = 0,
};

fn formatTokenHex(c: color.Rgb565, buf: *[8]u8) []const u8 {
    return std.fmt.bufPrint(buf, "#{X:0>6}", .{@as(u32, c.toHex())}) catch "#000000";
}

pub fn paint(logical: *fb.LogicalFb, theme: tokens.Theme, disp: prefs_mod.DisplayPrefs, scroll: i32) Layout {
    var cur: form.Cursor = .{};
    var lay: Layout = .{};
    const adv = form.isAdvanced();

    _ = form.paintModeToggle(logical, theme, &cur, scroll, adv);

    form.paintSection(logical, theme, &cur, scroll, "Display & theme");

    form.paintSection(logical, theme, &cur, scroll, "Brightness");
    lay.bright = form.paintSliderUnit(logical, theme, &cur, scroll, "Brightness", disp.bright, 5, 100, "%");

    form.paintSection(logical, theme, &cur, scroll, "Theme");
    lay.darkmode = form.paintTwoLine(logical, theme, &cur, scroll, "Dark mode", "OLED-friendly tonal surfaces", disp.darkmode);
    lay.accent = form.paintDropdown(logical, theme, &cur, scroll, "Accent", disp.accentName());
    const ct = [_][]const u8{ "Standard", "Medium", "High" };
    lay.contrast = form.paintSegment(logical, theme, &cur, scroll, "Contrast", &ct, disp.ui_contrast);
    form.paintNote(logical, theme, &cur, scroll, "Raises outline and secondary text contrast for bright shops.");
    const fs = [_][]const u8{ "Small", "Default", "Large", "Largest" };
    lay.font_scale = form.paintSegment(logical, theme, &cur, scroll, "Font size", &fs, @min(disp.font_scale, 3));
    form.paintNote(logical, theme, &cur, scroll, "System-wide MD3 type scale - settings, dashboard, dialogs.");
    if (!theme.contrastOk()) {
        form.paintNote(logical, theme, &cur, scroll, "Contrast check failed for this accent - try another or raise contrast.");
    }

    form.paintSection(logical, theme, &cur, scroll, "Touch");
    lay.glove = form.paintTwoLine(logical, theme, &cur, scroll, "Glove-friendly touch", "Softer threshold on device; host +8px hit pad", disp.touch_glove);

    form.paintSection(logical, theme, &cur, scroll, "Notifications");
    lay.notify = form.paintTwoLine(logical, theme, &cur, scroll, "Snackbar messages", "Brief toasts at the bottom of the screen", disp.notify_en);
    if (disp.notify_en) {
        const nl = [_][]const u8{ "All", "Important", "Errors" };
        lay.notify_level = form.paintSegment(logical, theme, &cur, scroll, "Show", &nl, disp.notify_level);
        form.paintNote(logical, theme, &cur, scroll, "Undo prompts and failures always count as important.");
    }

    if (adv) {
        form.paintSection(logical, theme, &cur, scroll, "Motion");
        lay.wake = form.paintTwoLine(logical, theme, &cur, scroll, "Wake on motion", "BMI270 - Tab5 only", disp.wake_motion);
        lay.sw_icons = form.paintTwoLine(logical, theme, &cur, scroll, "Switch check icons", "Check inside handle when on; small knob when off", disp.sw_icons);
        form.paintNote(logical, theme, &cur, scroll, "MD3: check sits in the selected thumb; plain small knob when off.");

        form.paintSection(logical, theme, &cur, scroll, "Orientation");
        lay.flip = form.paintTwoLine(logical, theme, &cur, scroll, "Flip display", "180 deg panel rotate", disp.flip);
        lay.lefty = form.paintTwoLine(logical, theme, &cur, scroll, "Left-handed layout", "Mirror DRO and actions", disp.lefty);
        lay.single_pane = form.paintTwoLine(logical, theme, &cur, scroll, "Single-pane settings", "Compact hub -> detail (no nav rail)", disp.single_pane);
    }

    lay.pwr_sleep = form.paintAction(logical, theme, &cur, scroll, "Power & sleep", "Open tab");

    if (adv) {
        form.paintSection(logical, theme, &cur, scroll, "Performance");
        const rf = [_][]const u8{ "Fastest", "Balanced", "Power saver" };
        lay.refr = form.paintSegment(logical, theme, &cur, scroll, "Dashboard refresh", &rf, disp.refr_hz);
        form.paintNote(logical, theme, &cur, scroll, disp.refrHint());
        lay.smooth = form.paintTwoLine(logical, theme, &cur, scroll, "Smooth animations", "Spring motion; off = snappy utility", disp.smooth_anim);
        const ms = [_][]const u8{ "Standard", "Expressive" };
        lay.motion = form.paintSegment(logical, theme, &cur, scroll, "Motion style", &ms, disp.motion_scheme);
        form.paintNote(logical, theme, &cur, scroll, "Expressive uses springier sheet/dialog motion and shape morph on controls.");

        if (disp.theme_ref_exp) {
            form.paintDetail(logical, theme, &cur, scroll, "Panel", "1280 x 720 MIPI-DSI");
            form.paintDetail(logical, theme, &cur, scroll, "Backlight", "PWM via BSP (GPIO22)");
            form.paintDetail(logical, theme, &cur, scroll, "Rotation", if (disp.flip) "Flipped (180 deg on)" else "Normal (180 deg off)");
            form.paintDetail(logical, theme, &cur, scroll, "Color mode", if (disp.darkmode) "Dark" else "Light");
            form.paintDetail(logical, theme, &cur, scroll, "Accent theme", disp.accentName());
            form.paintDetail(logical, theme, &cur, scroll, "Font size", disp.fontScaleName());
            var hx: [8]u8 = undefined;
            form.paintDetail(logical, theme, &cur, scroll, "Token primary", formatTokenHex(theme.primary, &hx));
            form.paintDetail(logical, theme, &cur, scroll, "Token surface", formatTokenHex(theme.surface, &hx));
            form.paintDetail(logical, theme, &cur, scroll, "Token on-surface", formatTokenHex(theme.on_surface, &hx));
            form.paintDetail(logical, theme, &cur, scroll, "Token error", formatTokenHex(theme.err, &hx));
            // Host Theme has no dedicated success; secondary is StatusKind.ok fill.
            form.paintDetail(logical, theme, &cur, scroll, "Token success", formatTokenHex(theme.secondary, &hx));
            lay.theme_ref = form.paintAction(logical, theme, &cur, scroll, "Hide theme reference", "");
        } else {
            lay.theme_ref = form.paintAction(logical, theme, &cur, scroll, "Show theme reference", "");
        }

        lay.reset = form.paintAction(logical, theme, &cur, scroll, "Reset display & theme", "Restores defaults");
    }

    lay.content_h = cur.y + 40;
    return lay;
}

pub fn hitTest(lay: Layout, x: i32, y: i32) struct { hit: Hit, seg: ?usize, rect: geom.Rect } {
    const pairs = [_]struct { Hit, geom.Rect }{
        .{ .bright, lay.bright },
        .{ .darkmode, lay.darkmode },
        .{ .accent, lay.accent },
        .{ .contrast, lay.contrast },
        .{ .font_scale, lay.font_scale },
        .{ .glove, lay.glove },
        .{ .notify, lay.notify },
        .{ .notify_level, lay.notify_level },
        .{ .wake, lay.wake },
        .{ .sw_icons, lay.sw_icons },
        .{ .flip, lay.flip },
        .{ .lefty, lay.lefty },
        .{ .single_pane, lay.single_pane },
        .{ .pwr_sleep, lay.pwr_sleep },
        .{ .refr, lay.refr },
        .{ .smooth, lay.smooth },
        .{ .motion, lay.motion },
        .{ .theme_ref, lay.theme_ref },
        .{ .reset, lay.reset },
    };
    for (pairs) |p| {
        if (p[1].contains(x, y)) {
            if (p[0] == .contrast) {
                if (form.segmentIndexAt(p[1], 3, x, y)) |i| return .{ .hit = .contrast, .seg = i, .rect = p[1] };
            } else if (p[0] == .font_scale) {
                if (form.segmentIndexAt(p[1], 4, x, y)) |i| return .{ .hit = .font_scale, .seg = i, .rect = p[1] };
            } else if (p[0] == .refr) {
                if (form.segmentIndexAt(p[1], 3, x, y)) |i| return .{ .hit = .refr, .seg = i, .rect = p[1] };
            } else if (p[0] == .motion) {
                if (form.segmentIndexAt(p[1], 2, x, y)) |i| return .{ .hit = .motion, .seg = i, .rect = p[1] };
            } else if (p[0] == .notify_level) {
                if (form.segmentIndexAt(p[1], 3, x, y)) |i| return .{ .hit = .notify_level, .seg = i, .rect = p[1] };
            }
            return .{ .hit = p[0], .seg = null, .rect = p[1] };
        }
    }
    return .{ .hit = .none, .seg = null, .rect = .{} };
}

/// Returns optional tab jump (Power = 5). Reset is handled by engine confirm.
pub fn applyHit(disp: *prefs_mod.DisplayPrefs, hit: Hit, seg: ?usize, x: i32, lay: Layout) ?usize {
    switch (hit) {
        .none, .reset, .accent => {},
        .bright => disp.bright = @intCast(@max(5, form.sliderValueAt(lay.bright, 5, 100, x))),
        .darkmode => disp.darkmode = !disp.darkmode,
        .contrast => if (seg) |i| {
            disp.ui_contrast = @intCast(i);
        },
        .font_scale => if (seg) |i| {
            disp.font_scale = @intCast(@min(i, 3));
        },
        .glove => disp.touch_glove = !disp.touch_glove,
        .notify => disp.notify_en = !disp.notify_en,
        .notify_level => if (seg) |i| {
            disp.notify_level = @intCast(i);
        },
        .wake => disp.wake_motion = !disp.wake_motion,
        .sw_icons => disp.sw_icons = !disp.sw_icons,
        .flip => disp.flip = !disp.flip,
        .lefty => disp.lefty = !disp.lefty,
        .single_pane => disp.single_pane = !disp.single_pane,
        .pwr_sleep => return 5,
        .refr => if (seg) |i| {
            disp.refr_hz = @intCast(i);
        },
        .smooth => disp.smooth_anim = !disp.smooth_anim,
        .motion => if (seg) |i| {
            disp.motion_scheme = @intCast(i);
        },
        .theme_ref => disp.theme_ref_exp = !disp.theme_ref_exp,
    }
    return null;
}
