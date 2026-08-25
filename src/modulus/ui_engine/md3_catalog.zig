//! Host MD3 Expressive catalog — interactive showcase of tokens + components.
//! Open with M. Esc / click header back returns to dashboard.
//! Refs: https://m3.material.io/blog/building-with-m3-expressive

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const widgets = @import("widgets.zig");
const expr = @import("widgets_expressive.zig");
const spring = @import("spring.zig");
const form = @import("settings_form.zig");

pub const header_h: i32 = 64;
pub const content_x: i32 = 24;

pub const State = struct {
    scroll: spring.Spring = spring.Spring.spatial(0),
    load_fx: spring.Spring = spring.Spring.effects(0),
    content_h: i32 = 1680,
    group_sel: usize = 1,
    nav_sel: usize = 0,
    rail_sel: usize = 0,
    progress: f32 = 0.65,
    slider: f32 = 0.4,
    switch_on: bool = true,
    switch_icons: bool = true,
    load_phase: f32 = 0,
    vibrant: bool = true,
    fab_menu_open: bool = false,
    back: geom.Rect = .{},
    vibrant_chip: geom.Rect = .{},
    group_row: geom.Rect = .{},
    split: geom.Rect = .{},
    fab: geom.Rect = .{},
    fab_ext: geom.Rect = .{},
    slider_row: geom.Rect = .{},
    switch_row: geom.Rect = .{},
    nav_bar: geom.Rect = .{},
    icon_a: geom.Rect = .{},
    icon_b: geom.Rect = .{},
    icon_tog: bool = false,
    demo_btn: geom.Rect = .{},
    hover_ptr: geom.Rect = .{},
    press_x: i32 = -1,
    press_y: i32 = -1,
    press_t: f32 = 0,
    press_active: bool = false,

    pub fn theme(self: State, base_dark: bool) tokens.Theme {
        if (self.vibrant) {
            return if (base_dark) tokens.Theme.expressiveVibrantDark() else tokens.Theme.industrialTealLight();
        }
        return if (base_dark) tokens.Theme.industrialTealDark() else tokens.Theme.industrialTealLight();
    }
};

pub fn paint(logical: *fb.LogicalFb, base: tokens.Theme, st: *State) void {
    const theme = st.theme(base.dark);
    const scroll_i: i32 = @intFromFloat(@floor(st.scroll.value));

    logical.fillRect(.{ .x = 0, .y = 0, .w = tokens.Logical.width, .h = tokens.Logical.height }, theme.surface);

    // App bar (fixed)
    expr.drawAppBar(logical, .{ .x = 0, .y = 0, .w = tokens.Logical.width, .h = header_h }, "M3 Expressive catalog", theme);
    st.back = .{ .x = 8, .y = 8, .w = 100, .h = tokens.Logical.touch_min };
    expr.drawTextButton(logical, st.back, "Back", theme);

    st.vibrant_chip = .{ .x = tokens.Logical.width - 168, .y = 8, .w = 152, .h = tokens.Logical.touch_min };
    widgets.drawAssistChip(logical, st.vibrant_chip, if (st.vibrant) "Vibrant on" else "Vibrant off", theme);

    var y: i32 = header_h + 16 - scroll_i;
    const max_w: i32 = tokens.Logical.width - 200;

    // Emphasized type
    section(logical, theme, &y, "Emphasized typography");
    if (visible(y)) font.drawTextRole(logical, content_x, y, "Begin recording", theme.primary, .emph_display_l);
    y += 48;
    if (visible(y)) font.drawTextRole(logical, content_x, y, "Unread - 3 messages", theme.on_surface, .emph_headline_m);
    y += 40;
    if (visible(y)) font.drawTextRole(logical, content_x, y, "Standard body for comparison", theme.on_surface_variant, .body_m);
    y += 36;

    // Color roles
    section(logical, theme, &y, "Vibrant color roles");
    if (visible(y)) {
        swatch(logical, content_x, y, theme.primary, "primary");
        swatch(logical, content_x + 120, y, theme.primary_fixed, "p-fixed");
        swatch(logical, content_x + 240, y, theme.tertiary, "tertiary");
        swatch(logical, content_x + 360, y, theme.secondary_fixed, "s-fixed");
    }
    y += 56;

    // Shapes
    section(logical, theme, &y, "Shape library (host subset)");
    if (visible(y)) {
        const kinds = [_]tokens.Shape.Kind{ .rounded, .circle, .pill, .square, .diamond, .arch, .cookie, .clam, .soft_burst, .slanted };
        for (kinds, 0..) |k, i| {
            const col = @as(i32, @intCast(i % 5));
            const row = @as(i32, @intCast(i / 5));
            expr.drawShapeDemo(logical, content_x + col * 72, y + row * 64, 48, k, theme.primary_container);
        }
    }
    y += 140;

    // Common buttons — styles + interaction states
    section(logical, theme, &y, "Common buttons");
    if (visible(y)) {
        const bh = tokens.ButtonSize.m.height();
        widgets.drawButton(logical, .{ .x = content_x, .y = y, .w = 100, .h = bh }, "Filled", .filled, .enabled, theme);
        widgets.drawButton(logical, .{ .x = content_x + 112, .y = y, .w = 100, .h = bh }, "Tonal", .tonal, .enabled, theme);
        widgets.drawButton(logical, .{ .x = content_x + 224, .y = y, .w = 100, .h = bh }, "Outline", .outlined, .enabled, theme);
        widgets.drawButton(logical, .{ .x = content_x + 336, .y = y, .w = 100, .h = bh }, "Elevated", .elevated, .enabled, theme);
        widgets.drawButton(logical, .{ .x = content_x + 448, .y = y, .w = 88, .h = bh }, "Text", .text, .enabled, theme);
    }
    y += 56;
    if (visible(y)) {
        const bh = tokens.ButtonSize.m.height();
        widgets.drawButtonRippled(logical, .{ .x = content_x, .y = y, .w = 100, .h = bh }, "Hover", .filled, .hovered, theme, 0, 0, 0);
        widgets.drawButtonRippled(logical, .{ .x = content_x + 112, .y = y, .w = 100, .h = bh }, "Focus", .filled, .focused, theme, 0, 0, 0);
        widgets.drawButtonRippled(logical, .{ .x = content_x + 224, .y = y, .w = 120, .h = bh }, "Press+rip", .filled, .pressed, theme, st.load_phase, content_x + 284, y + 24);
        widgets.drawButton(logical, .{ .x = content_x + 356, .y = y, .w = 100, .h = bh }, "Disabled", .filled, .disabled, theme);
        widgets.drawButton(logical, .{ .x = content_x + 468, .y = y, .w = 100, .h = bh }, "Dis.out", .outlined, .disabled, theme);
    }
    y += 56;
    // Live interactive (hover/press from engine → resolveButtonState)
    if (visible(y)) {
        st.demo_btn = .{ .x = content_x, .y = y, .w = 160, .h = tokens.ButtonSize.m.height() };
        widgets.drawButtonInteractive(
            logical,
            st.demo_btn,
            "Live Apply",
            .filled,
            theme,
            st.hover_ptr,
            .{},
            st.press_x,
            st.press_y,
            st.press_active,
            false,
            st.press_t,
        );
        font.drawTextRole(logical, content_x + 176, y + 14, "resolveButtonState + stadium hover", theme.on_surface_variant, .label_s);
    }
    y += 56;
    if (visible(y)) {
        // Expressive sizes XS → XL (heights 32…64)
        _ = widgets.drawFilledButtonSized(logical, content_x, y + 16, .xs, "XS", theme);
        _ = widgets.drawFilledButtonSized(logical, content_x + 72, y + 12, .s, "S", theme);
        _ = widgets.drawFilledButtonSized(logical, content_x + 144, y + 8, .m, "M", theme);
        _ = widgets.drawFilledButtonSized(logical, content_x + 230, y + 4, .l, "L", theme);
        _ = widgets.drawFilledButtonSized(logical, content_x + 320, y, .xl, "XL", theme);
    }
    y += 72;

    // Chips + badge
    section(logical, theme, &y, "Chips / badge");
    if (visible(y)) {
        widgets.drawAssistChip(logical, .{ .x = content_x, .y = y, .w = 120, .h = tokens.Logical.touch_min }, "Assist", theme);
        expr.drawOutlineChip(logical, .{ .x = content_x + 136, .y = y, .w = 120, .h = tokens.Logical.touch_min }, "Outline", theme);
        widgets.drawFilterChip(logical, .{ .x = content_x + 272, .y = y, .w = 120, .h = tokens.Logical.touch_min }, "Filter on", true, theme);
        widgets.drawFilterChip(logical, .{ .x = content_x + 408, .y = y, .w = 120, .h = tokens.Logical.touch_min }, "Filter off", false, theme);
        expr.drawBadge(logical, content_x + 560, y + 12, 3, theme);
        font.drawTextRole(logical, content_x + 580, y + 16, "badge", theme.on_surface_variant, .label_s);
    }
    y += 64;

    // Icon buttons — variants + toggle
    section(logical, theme, &y, "Icon buttons");
    if (visible(y)) {
        const icy = y + 24;
        const ia_cx = content_x + 24;
        const ib_cx = content_x + 80;
        const ic_cx = content_x + 136;
        const id_cx = content_x + 192;
        expr.drawIconButtonState(logical, ia_cx, icy, .filled, .enabled, false, theme);
        expr.drawIconButtonState(logical, ib_cx, icy, .tonal, .enabled, false, theme);
        expr.drawIconButtonState(logical, ic_cx, icy, .outlined, .enabled, false, theme);
        expr.drawIconButtonState(logical, id_cx, icy, .standard, .enabled, st.icon_tog, theme);
        st.icon_a = expr.iconButtonHit(ia_cx, icy);
        st.icon_b = expr.iconButtonHit(id_cx, icy);
        font.drawTextRole(logical, content_x + 240, y + 16, if (st.icon_tog) "Toggle on (tap)" else "Toggle off (tap)", theme.on_surface_variant, .label_m);
    }
    y += 64;

    // Button group
    section(logical, theme, &y, "Button groups");
    st.group_row = .{ .x = content_x, .y = y, .w = @min(420, max_w), .h = 48 };
    if (visible(y)) {
        const labs = [_][]const u8{ "Day", "Week", "Month" };
        expr.drawButtonGroupF(logical, st.group_row, &labs, form.sampleWidget("catalog.group", @floatFromInt(st.group_sel)), theme);
    }
    y += 64;

    // Split
    section(logical, theme, &y, "Split button");
    st.split = .{ .x = content_x, .y = y, .w = 200, .h = 48 };
    if (visible(y)) expr.drawSplitButton(logical, st.split, "Save", theme);
    y += 64;

    // FAB family
    section(logical, theme, &y, "FABs / Extended / Menu");
    st.fab = .{ .x = content_x, .y = y, .w = 56, .h = 56 };
    st.fab_ext = .{ .x = content_x + 80, .y = y, .w = 180, .h = 56 };
    if (visible(y)) {
        expr.drawFab(logical, st.fab, theme);
        expr.drawExtendedFab(logical, st.fab_ext, "Compose", theme);
        if (st.fab_menu_open) {
            expr.drawFabMenuItem(logical, .{ .x = content_x + 280, .y = y, .w = 160, .h = 40 }, "New file", theme);
            expr.drawFabMenuItem(logical, .{ .x = content_x + 280, .y = y + 48, .w = 160, .h = 40 }, "Import", theme);
        }
    }
    y += if (st.fab_menu_open) 120 else 72;

    // Progress
    section(logical, theme, &y, "Progress / loading");
    if (visible(y)) {
        const ph = expr.linear_track_h;
        expr.drawLinearProgress(logical, .{ .x = content_x, .y = y + 12, .w = 360, .h = ph }, form.sampleWidget("catalog.progress", st.progress), theme);
        expr.drawCircularProgress(logical, content_x + 420, y + 28, 28, form.sampleWidget("catalog.progress", st.progress), theme);
        font.drawTextRole(logical, content_x + 460, y + 20, "4dp / stop / wave job", theme.on_surface_variant, .label_s);
    }
    y += 72;
    if (visible(y)) {
        expr.drawLoadingIndicator(logical, .{ .x = content_x, .y = y + 4, .w = 360, .h = expr.linear_track_h }, st.load_phase, theme);
        font.drawTextRole(logical, content_x + 380, y, "indet wave ~28%", theme.on_surface_variant, .label_s);
    }
    y += 40;

    // Shape morph
    section(logical, theme, &y, "Shape morph (LED)");
    if (visible(y)) {
        expr.drawShapeMorph(logical, content_x + 24, y + 24, 20, st.load_phase, theme.primary);
        expr.drawShapeMorph(logical, content_x + 88, y + 24, 20, 1.0 - st.load_phase, theme.tertiary);
    }
    y += 64;

    // Slider
    section(logical, theme, &y, "Sliders");
    st.slider_row = .{ .x = content_x, .y = y, .w = 400, .h = 40 };
    if (visible(y)) expr.drawSlider(logical, st.slider_row, form.sampleWidget("catalog.slider", st.slider), theme);
    y += 56;

    // Switch
    section(logical, theme, &y, "Switches");
    st.switch_row = .{ .x = content_x, .y = y, .w = 280, .h = tokens.Logical.touch_min };
    if (visible(y)) {
        const sy = y + @divTrunc(tokens.Logical.touch_min - widgets.switch_h, 2);
        const t_on = form.sampleWidgetBool("catalog.switch", st.switch_on);
        widgets.drawSwitch(logical, content_x, sy, t_on, theme, st.switch_icons, true);
        widgets.drawSwitch(logical, content_x + 72, sy, 0, theme, st.switch_icons, true);
        widgets.drawSwitch(logical, content_x + 144, sy, 1, theme, false, true);
        widgets.drawSwitch(logical, content_x + 216, sy, 1, theme, st.switch_icons, false);
        font.drawTextRole(logical, content_x + 280, sy + 8, "on / off / no-icon / disabled", theme.on_surface_variant, .label_m);
    }
    y += 64;

    // Text fields
    section(logical, theme, &y, "Text fields");
    if (visible(y)) {
        const fh: i32 = tokens.Logical.touch_min;
        const fw: i32 = 200;
        widgets.drawOutlinedTextField(logical, .{ .x = content_x, .y = y, .w = fw, .h = fh }, "", "Idle", false, true, false, theme);
        widgets.drawOutlinedTextField(logical, .{ .x = content_x + fw + 12, .y = y, .w = fw, .h = fh }, "Focused", "", true, true, false, theme);
        widgets.drawOutlinedTextField(logical, .{ .x = content_x + (fw + 12) * 2, .y = y, .w = fw, .h = fh }, "Invalid", "", false, true, true, theme);
        widgets.drawOutlinedTextField(logical, .{ .x = content_x + (fw + 12) * 3, .y = y, .w = fw, .h = fh }, "Disabled", "", false, false, false, theme);
    }
    y += 64;
    if (visible(y)) {
        widgets.drawFilledTextField(logical, .{ .x = content_x, .y = y, .w = 280, .h = tokens.Logical.touch_min }, "", "Filled idle", false, true, theme);
        widgets.drawFilledTextField(logical, .{ .x = content_x + 292, .y = y, .w = 280, .h = tokens.Logical.touch_min }, "Filled focus", "", true, true, theme);
        font.drawTextRole(logical, content_x + 584, y + 16, "outlined / filled", theme.on_surface_variant, .label_m);
    }
    y += 72;

    // Toolbar
    section(logical, theme, &y, "Toolbars");
    if (visible(y)) expr.drawToolbar(logical, .{ .x = content_x, .y = y, .w = 280, .h = 64 }, theme);
    y += 80;

    // Menu + search + ripple
    section(logical, theme, &y, "Menu / search / ripple");
    if (visible(y)) {
        expr.drawMenu(logical, .{ .x = content_x, .y = y, .w = 200, .h = 160 }, &[_][]const u8{ "Copy", "Paste", "Delete" }, 1, theme);
        widgets.drawSearchView(
            logical,
            .{ .x = content_x + 220, .y = y, .w = 320, .h = 48 },
            .{ .x = content_x + 220, .y = y + 56, .w = 320, .h = 120 },
            "",
            &[_][]const u8{ "Spindle override", "Feed hold", "Home all" },
            theme,
        );
        expr.drawRipple(logical, content_x + 600, y + 60, 48, st.load_phase, theme);
        widgets.drawFilledButtonPressed(logical, .{ .x = content_x + 660, .y = y + 40, .w = 120, .h = 48 }, "Pressed", theme);
    }
    y += 200;

    section(logical, theme, &y, "Checkbox / radio / tooltip / list");
    if (visible(y)) {
        expr.drawCheckbox(logical, content_x, y + 4, true, theme);
        expr.drawCheckbox(logical, content_x + 40, y + 4, false, theme);
        expr.drawRadio(logical, content_x + 100, y + 16, true, theme);
        expr.drawRadio(logical, content_x + 140, y + 16, false, theme);
        expr.drawTooltip(logical, content_x + 280, y + 48, "Feed hold", theme);
        expr.drawListItem(logical, .{ .x = content_x + 400, .y = y, .w = 320, .h = 56 }, "Spindle override", true, theme);
    }
    y += 80;

    section(logical, theme, &y, "Date / time pickers");
    if (visible(y)) {
        // Static MD3 modal chrome preview (interactive path: Settings → System → Set manually).
        const card: geom.Rect = .{ .x = content_x, .y = y, .w = 420, .h = 168 };
        widgets.fillRoundRect(logical, card, tokens.Shape.dialog, theme.elev(3));
        widgets.strokeRoundRect(logical, card, tokens.Shape.dialog, theme.outline_variant, 1);
        font.drawTextRole(logical, card.x + 16, card.y + 14, "Set date and time", theme.on_surface, .title_m);
        font.drawTextRole(logical, card.x + 16, card.y + 52, "Date", theme.on_surface_variant, .label_l);
        const fy = card.y + 48;
        inline for (.{ .{ 72, 88, "2026", false }, .{ 172, 64, "08", false }, .{ 248, 64, "21", false } }) |cell| {
            const fr: geom.Rect = .{ .x = card.x + cell[0], .y = fy, .w = cell[1], .h = 40 };
            widgets.drawOutlinedTextFieldCentered(logical, fr, cell[2], cell[3], theme, .title_m);
        }
        font.drawTextRole(logical, card.x + 16, card.y + 108, "Time", theme.on_surface_variant, .label_l);
        const ty = card.y + 104;
        inline for (.{ .{ 72, 64, "14", true }, .{ 148, 64, "30", false }, .{ 224, 64, "00", false } }) |cell| {
            const fr: geom.Rect = .{ .x = card.x + cell[0], .y = ty, .w = cell[1], .h = 40 };
            widgets.drawOutlinedTextFieldCentered(logical, fr, cell[2], cell[3], theme, .title_m);
        }
        widgets.drawTonalButton(logical, .{ .x = card.x + card.w - 200, .y = card.y + card.h - 48, .w = 88, .h = 40 }, "Cancel", theme);
        widgets.drawFilledButton(logical, .{ .x = card.x + card.w - 100, .y = card.y + card.h - 48, .w = 88, .h = 40 }, "Apply", theme);
        font.drawTextRole(logical, card.x + 440, card.y + 60, "Modal / elev 3 / input fields", theme.on_surface_variant, .body_s);
    }
    y += 200;

    // Layout class
    section(logical, theme, &y, "Window size class");
    if (visible(y)) {
        const wsc = tokens.WindowSizeClass.tab5();
        var buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Tab5 = {s}  maxContent={d}  margin={d}", .{
            @tagName(wsc),
            wsc.contentMaxWidth(),
            wsc.margin(),
        }) catch "size class";
        font.drawTextRole(logical, content_x, y, msg, theme.on_surface, .body_m);
    }
    y += 40;

    // Nav rail + bar
    section(logical, theme, &y, "Navigation rail");
    const rail_labs = [_][]const u8{ "Home", "Jobs", "Settings" };
    if (visible(y)) expr.drawNavRail(logical, .{ .x = content_x, .y = y, .w = 120, .h = 240 }, &rail_labs, st.rail_sel, theme);
    y += 256;

    section(logical, theme, &y, "Navigation bar");
    st.nav_bar = .{ .x = content_x, .y = y, .w = 480, .h = 72 };
    if (visible(y)) expr.drawNavBar(logical, st.nav_bar, &rail_labs, st.nav_sel, theme);
    y += 96;

    // Motion note
    section(logical, theme, &y, "Motion physics");
    if (visible(y)) font.drawTextRole(logical, content_x, y, "Spatial springs scroll this page; effects soft-load the bar.", theme.on_surface_variant, .body_s);
    y += 40;
    if (visible(y)) font.drawTextRole(logical, content_x, y, "MotionScheme.expressive / 10 host shapes / emph type tiers", theme.on_surface_variant, .label_s);
    y += 48;

    st.content_h = y + scroll_i + 40;
}

fn section(logical: *fb.LogicalFb, theme: tokens.Theme, y: *i32, title: []const u8) void {
    if (visible(y.*)) font.drawTextRole(logical, content_x, y.*, title, theme.primary, .title_m);
    y.* += 32;
}

fn visible(y: i32) bool {
    return y > -80 and y < tokens.Logical.height + 40;
}

fn swatch(logical: *fb.LogicalFb, x: i32, y: i32, c: @import("color.zig").Rgb565, label: []const u8) void {
    widgets.fillRoundRect(logical, .{ .x = x, .y = y, .w = 48, .h = 32 }, 8, c);
    font.drawText(logical, x, y + 36, label, c, 1);
}

pub const Hit = enum { none, back, vibrant, group, split, fab, slider, switch_tog, nav, icon_tog };

pub fn hitTest(st: *const State, x: i32, y: i32) Hit {
    if (st.back.contains(x, y)) return .back;
    if (st.vibrant_chip.contains(x, y)) return .vibrant;
    if (st.group_row.contains(x, y)) return .group;
    if (st.split.contains(x, y)) return .split;
    if (st.fab.contains(x, y) or st.fab_ext.contains(x, y)) return .fab;
    if (st.slider_row.contains(x, y)) return .slider;
    if (st.switch_row.contains(x, y)) return .switch_tog;
    if (st.nav_bar.contains(x, y)) return .nav;
    if (st.icon_b.contains(x, y)) return .icon_tog;
    return .none;
}

pub fn applyHit(st: *State, hit: Hit, x: i32) void {
    switch (hit) {
        .none, .back => {},
        .vibrant => st.vibrant = !st.vibrant,
        .icon_tog => st.icon_tog = !st.icon_tog,
        .group => {
            if (st.group_row.w > 0) {
                const seg = @divTrunc(x - st.group_row.x, @divTrunc(st.group_row.w, 3));
                if (seg >= 0 and seg < 3) st.group_sel = @intCast(seg);
            }
        },
        .split => st.fab_menu_open = !st.fab_menu_open,
        .fab => st.fab_menu_open = !st.fab_menu_open,
        .slider => {
            const inset = widgets.slider_handle_r;
            const tw = @max(1, st.slider_row.w - inset * 2);
            const t = @as(f32, @floatFromInt(x - st.slider_row.x - inset)) / @as(f32, @floatFromInt(tw));
            st.slider = std.math.clamp(t, 0, 1);
            st.progress = st.slider;
        },
        .switch_tog => {
            // First slot toggles on; second half of row toggles icons pref.
            if (x < st.switch_row.x + 72) {
                st.switch_on = !st.switch_on;
            } else if (x >= st.switch_row.x + 144 and x < st.switch_row.x + 216) {
                st.switch_icons = !st.switch_icons;
            }
        },
        .nav => {
            const slot = @divTrunc(st.nav_bar.w, 3);
            const i = @divTrunc(x - st.nav_bar.x, @max(1, slot));
            if (i >= 0 and i < 3) {
                st.nav_sel = @intCast(i);
                st.rail_sel = st.nav_sel;
            }
        },
    }
}

pub fn tick(st: *State, dt: f32) bool {
    // Effects spring drives indeterminate load phase (bounce 0↔1).
    if (st.load_fx.settled()) {
        st.load_fx.setTarget(if (st.load_fx.target < 0.5) 1 else 0);
    }
    const load_m = st.load_fx.step(dt);
    st.load_phase = st.load_fx.value;
    const scroll_m = st.scroll.step(dt);
    return load_m or scroll_m;
}

test "catalog paint height" {
    var logical = try fb.LogicalFb.alloc(std.testing.allocator);
    defer logical.deinit(std.testing.allocator);
    var st: State = .{};
    paint(&logical, tokens.Theme.industrialTealDark(), &st);
    try std.testing.expect(st.content_h > 800);
}
