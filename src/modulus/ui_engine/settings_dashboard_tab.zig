//! Settings → Dashboard & Handwheel (host port of ui_settings_tab_dashboard.c).

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const form = @import("settings_form.zig");
const prefs_mod = @import("settings_prefs.zig");

pub const Hit = enum {
    none,
    edit_incr,
    jog_mode,
    axes,
    wcs,
    wcs_lock,
    cnf_cycle,
    cnf_spin,
    cnf_zero,
    cnf_home,
    cnf_mac,
    coal,
    pend,
    encdiv,
    jogspd,
    contpct,
    stepacc,
    macro0,
    macro1,
    macro2,
    macro3,
    add_qbtn,
    arrange,
    ovr_left,
    ovr_right,
    mpg_dir,
    probe,
    hw_ref,
    unit_mm,
    link_mach,
    link_cnc,
    link_disp,
    reset,
};

pub const Layout = struct {
    jog_mode: geom.Rect = .{},
    axes: geom.Rect = .{},
    wcs: geom.Rect = .{},
    wcs_lock: geom.Rect = .{},
    cnf_cycle: geom.Rect = .{},
    cnf_spin: geom.Rect = .{},
    cnf_zero: geom.Rect = .{},
    cnf_home: geom.Rect = .{},
    cnf_mac: geom.Rect = .{},
    coal: geom.Rect = .{},
    pend: geom.Rect = .{},
    encdiv: geom.Rect = .{},
    jogspd: geom.Rect = .{},
    contpct: geom.Rect = .{},
    stepacc: geom.Rect = .{},
    edit_incr: geom.Rect = .{},
    macro_row: [4]geom.Rect = .{ .{}, .{}, .{}, .{} },
    add_qbtn: geom.Rect = .{},
    arrange: geom.Rect = .{},
    ovr_left: geom.Rect = .{},
    ovr_right: geom.Rect = .{},
    mpg_dir: geom.Rect = .{},
    probe: geom.Rect = .{},
    hw_ref: geom.Rect = .{},
    unit_mm: geom.Rect = .{},
    link_mach: geom.Rect = .{},
    link_cnc: geom.Rect = .{},
    link_disp: geom.Rect = .{},
    reset: geom.Rect = .{},
    content_h: i32 = 0,
};

pub fn paint(logical: *fb.LogicalFb, theme: tokens.Theme, dash: prefs_mod.DashboardPrefs, scroll: i32) Layout {
    var cur: form.Cursor = .{};
    var lay: Layout = .{};
    const adv = form.isAdvanced();

    _ = form.paintModeToggle(logical, theme, &cur, scroll, adv);

    form.paintSection(logical, theme, &cur, scroll, "Dashboard & Handwheel");

    form.paintSection(logical, theme, &cur, scroll, "Jog increments");
    var ibuf: [48]u8 = undefined;
    const idet = std.fmt.bufPrint(&ibuf, "{s}, {s}, {s}, {s}", .{
        dash.incrSlice(0),
        dash.incrSlice(1),
        dash.incrSlice(2),
        dash.incrSlice(3),
    }) catch "incr";
    form.paintDetail(logical, theme, &cur, scroll, "Current", idet);
    lay.edit_incr = form.paintAction(logical, theme, &cur, scroll, "Edit increments", "");

    const jm = [_][]const u8{ "Step", "Cont", "Velo" };
    lay.jog_mode = form.paintSegment(logical, theme, &cur, scroll, "Jog mode", &jm, dash.jog_mode);

    form.paintSection(logical, theme, &cur, scroll, "Active axes");
    const ax = [_][]const u8{ "2", "3", "4", "5", "6" };
    lay.axes = form.paintSegment(logical, theme, &cur, scroll, "Axes", &ax, dash.axes_preset);

    form.paintSection(logical, theme, &cur, scroll, "Work coordinate system");
    lay.wcs = form.paintDropdown(logical, theme, &cur, scroll, "WCS", dash.wcsLabel());
    if (adv) {
        var lkbuf: [24]u8 = undefined;
        const locked = @popCount(dash.wcs_lock);
        const lk = if (locked == 0)
            "None locked"
        else
            (std.fmt.bufPrint(&lkbuf, "{d} locked", .{locked}) catch "?");
        lay.wcs_lock = form.paintAction(logical, theme, &cur, scroll, "WCS lock & names", lk);

        form.paintSection(logical, theme, &cur, scroll, "Confirm policy");
        form.paintNote(logical, theme, &cur, scroll, "Never / Always / When running.");
        lay.cnf_cycle = form.paintDropdown(logical, theme, &cur, scroll, "Cycle start", prefs_mod.ConfirmPolicy.label(dash.confirm.cycle));
        lay.cnf_spin = form.paintDropdown(logical, theme, &cur, scroll, "Spindle start", prefs_mod.ConfirmPolicy.label(dash.confirm.spin));
        lay.cnf_zero = form.paintDropdown(logical, theme, &cur, scroll, "Zero axes", prefs_mod.ConfirmPolicy.label(dash.confirm.zero));
        lay.cnf_home = form.paintDropdown(logical, theme, &cur, scroll, "Home", prefs_mod.ConfirmPolicy.label(dash.confirm.home));
        lay.cnf_mac = form.paintDropdown(logical, theme, &cur, scroll, "Macros", prefs_mod.ConfirmPolicy.label(dash.confirm.mac));

        form.paintSection(logical, theme, &cur, scroll, "Jog coalesce");
        form.paintNote(logical, theme, &cur, scroll, "Limits handwheel $J= flood.");
        lay.coal = form.paintSlider(logical, theme, &cur, scroll, "Coalesce window (ms)", dash.jog_coal_ms, 0, 100);
        lay.pend = form.paintSlider(logical, theme, &cur, scroll, "Max pending STEP detents", dash.jog_pend_max, 4, 64);
    }

    form.paintSection(logical, theme, &cur, scroll, "Handwheel / MPG");
    lay.encdiv = form.paintSlider(logical, theme, &cur, scroll, "Encoder counts/step", dash.encdiv, 1, 16);
    var jsbuf: [24]u8 = undefined;
    const jsl = std.fmt.bufPrint(&jsbuf, "{d}", .{dash.jogspdMmMin()}) catch "?";
    lay.jogspd = form.paintDropdown(logical, theme, &cur, scroll, "Max jog feed (mm/min)", jsl);
    form.paintNote(logical, theme, &cur, scroll, "Handwheel $J= feed cap.");
    if (adv) {
        lay.contpct = form.paintSliderUnit(logical, theme, &cur, scroll, "CONT speed rate %", dash.contpct, 10, 200, "%");
        form.paintNote(logical, theme, &cur, scroll, "Scales CONT feed. VELO uses wheel velocity only.");
        lay.stepacc = form.paintToggle(logical, theme, &cur, scroll, "STEP accuracy mode", dash.stepacc);
        form.paintNote(logical, theme, &cur, scroll, "1:1 wheel distance - detents are never dropped.");

        form.paintSection(logical, theme, &cur, scroll, "Quick buttons");
        form.paintNote(logical, theme, &cur, scroll, "Create buttons (aux pins, macros), then place them on the dashboard.");
        var any_mac = false;
        var qi: usize = 0;
        while (qi < 4) : (qi += 1) {
            if (!dash.macros[qi].occupied()) continue;
            any_mac = true;
            var dbuf: [96]u8 = undefined;
            const m = dash.macros[qi];
            const det = if (m.offSlice().len > 0)
                (std.fmt.bufPrint(&dbuf, "Toggle  {s} / {s}", .{ m.onSlice(), m.offSlice() }) catch "toggle")
            else
                (std.fmt.bufPrint(&dbuf, "Press  {s}", .{m.onSlice()}) catch "press");
            lay.macro_row[qi] = form.paintAction(logical, theme, &cur, scroll, m.nameSlice(), det);
        }
        if (!any_mac) {
            form.paintNote(logical, theme, &cur, scroll, "Example toggle: ON = M64 P0, OFF = M65 P0");
        }
        if (dash.firstFreeMacro() != null) {
            lay.add_qbtn = form.paintAction(logical, theme, &cur, scroll, "Add quick button", "Name + G-code");
        } else {
            form.paintNote(logical, theme, &cur, scroll, "All 4 custom buttons used. Edit one to change or free a slot.");
        }
        lay.arrange = form.paintAction(logical, theme, &cur, scroll, "Arrange on dashboard", "Choose what each slot shows");

        form.paintSection(logical, theme, &cur, scroll, "Override cards");
        form.paintNote(logical, theme, &cur, scroll, "Dashboard shows 2 of 3 - Feed, Spindle, Rapid.");
        const ovr_lbl = [_][]const u8{ "Feed", "Spindle", "Rapid" };
        const slots = dash.ovrSlots();
        lay.ovr_left = form.paintSegment(logical, theme, &cur, scroll, "Left card", &ovr_lbl, @intFromEnum(slots[0]));
        lay.ovr_right = form.paintSegment(logical, theme, &cur, scroll, "Right card", &ovr_lbl, @intFromEnum(slots[1]));

        form.paintSection(logical, theme, &cur, scroll, "MPG direction");
        lay.mpg_dir = form.paintAction(logical, theme, &cur, scroll, "MPG direction", "Per-axis invert");

        form.paintSection(logical, theme, &cur, scroll, "Probe");
        var pbuf: [24]u8 = undefined;
        const pd = std.fmt.bufPrint(&pbuf, "{d}.{d} mm plate", .{ dash.probe_zoff_x10 / 10, dash.probe_zoff_x10 % 10 }) catch "probe";
        lay.probe = form.paintAction(logical, theme, &cur, scroll, "Probe Z-plate", pd);

        form.paintSection(logical, theme, &cur, scroll, "Handwheel reference");
        if (dash.hw_ref_exp) {
            form.paintDetail(logical, theme, &cur, scroll, "To jog 1", "Tap an axis card (X/Y/Z) on the dashboard");
            form.paintDetail(logical, theme, &cur, scroll, "To jog 2", "Tap the MPG badge on the status bar");
            form.paintDetail(logical, theme, &cur, scroll, "To jog 3", "Turn the wheel - moves the selected axis");
            form.paintDetail(logical, theme, &cur, scroll, "Distance/detent", "Step size x Encoder counts/step");
            form.paintDetail(logical, theme, &cur, scroll, "Machine state", "Must be Idle (clear Alarm/Hold first)");
            form.paintDetail(logical, theme, &cur, scroll, "Port A Grove", "I2C1 SDA G53 / SCL G54");
            form.paintDetail(logical, theme, &cur, scroll, "Unit address", "0x59 ExtEncoder");
            form.paintDetail(logical, theme, &cur, scroll, "Power", "Enable EXT 5V in Power settings");
            lay.hw_ref = form.paintAction(logical, theme, &cur, scroll, "Hide handwheel reference", "");
        } else {
            lay.hw_ref = form.paintAction(logical, theme, &cur, scroll, "Show handwheel reference", "");
        }
    }

    form.paintSection(logical, theme, &cur, scroll, "Units");
    lay.unit_mm = form.paintToggle(logical, theme, &cur, scroll, "Metric (mm)", dash.unit_mm);

    if (adv) {
        form.paintSection(logical, theme, &cur, scroll, "Related settings");
        lay.link_mach = form.paintAction(logical, theme, &cur, scroll, "Machine", "Open tab");
        lay.link_cnc = form.paintAction(logical, theme, &cur, scroll, "CNC connection", "Open tab");
        lay.link_disp = form.paintAction(logical, theme, &cur, scroll, "Display & theme", "Left-handed layout");

        lay.reset = form.paintAction(logical, theme, &cur, scroll, "Reset dashboard & handwheel", "Restores defaults");
    }
    lay.content_h = cur.y + 40;
    return lay;
}

pub fn hitTest(lay: Layout, dash: prefs_mod.DashboardPrefs, x: i32, y: i32) struct { hit: Hit, seg: ?usize, rect: geom.Rect } {
    _ = dash;
    const pairs = [_]struct { Hit, geom.Rect }{
        .{ .edit_incr, lay.edit_incr },
        .{ .jog_mode, lay.jog_mode },
        .{ .axes, lay.axes },
        .{ .wcs, lay.wcs },
        .{ .wcs_lock, lay.wcs_lock },
        .{ .cnf_cycle, lay.cnf_cycle },
        .{ .cnf_spin, lay.cnf_spin },
        .{ .cnf_zero, lay.cnf_zero },
        .{ .cnf_home, lay.cnf_home },
        .{ .cnf_mac, lay.cnf_mac },
        .{ .coal, lay.coal },
        .{ .pend, lay.pend },
        .{ .encdiv, lay.encdiv },
        .{ .jogspd, lay.jogspd },
        .{ .contpct, lay.contpct },
        .{ .stepacc, lay.stepacc },
        .{ .macro0, lay.macro_row[0] },
        .{ .macro1, lay.macro_row[1] },
        .{ .macro2, lay.macro_row[2] },
        .{ .macro3, lay.macro_row[3] },
        .{ .add_qbtn, lay.add_qbtn },
        .{ .arrange, lay.arrange },
        .{ .ovr_left, lay.ovr_left },
        .{ .ovr_right, lay.ovr_right },
        .{ .mpg_dir, lay.mpg_dir },
        .{ .probe, lay.probe },
        .{ .hw_ref, lay.hw_ref },
        .{ .unit_mm, lay.unit_mm },
        .{ .link_mach, lay.link_mach },
        .{ .link_cnc, lay.link_cnc },
        .{ .link_disp, lay.link_disp },
        .{ .reset, lay.reset },
    };
    for (pairs) |p| {
        if (p[1].isEmpty()) continue;
        if (p[1].contains(x, y)) {
            if (p[0] == .jog_mode) {
                if (form.segmentIndexAt(p[1], 3, x, y)) |i| return .{ .hit = .jog_mode, .seg = i, .rect = p[1] };
            } else if (p[0] == .axes) {
                if (form.segmentIndexAt(p[1], 5, x, y)) |i| return .{ .hit = .axes, .seg = i, .rect = p[1] };
            } else if (p[0] == .ovr_left or p[0] == .ovr_right) {
                if (form.segmentIndexAt(p[1], 3, x, y)) |i| return .{ .hit = p[0], .seg = i, .rect = p[1] };
            }
            return .{ .hit = p[0], .seg = null, .rect = p[1] };
        }
    }
    return .{ .hit = .none, .seg = null, .rect = .{} };
}

/// Returns optional tab jump. Reset / overlays handled by engine.
pub fn applyHit(dash: *prefs_mod.DashboardPrefs, hit: Hit, seg: ?usize, x: i32, lay: Layout) ?usize {
    switch (hit) {
        .none, .reset, .wcs, .jogspd, .mpg_dir, .edit_incr, .wcs_lock, .macro0, .macro1, .macro2, .macro3, .add_qbtn, .arrange, .cnf_cycle, .cnf_spin, .cnf_zero, .cnf_home, .cnf_mac => {},
        .jog_mode => if (seg) |i| {
            dash.jog_mode = @intCast(i);
        },
        .axes => if (seg) |i| {
            dash.axes_preset = @intCast(i);
        },
        .ovr_left => if (seg) |i| {
            dash.setOvrLeft(@intCast(i));
        },
        .ovr_right => if (seg) |i| {
            dash.setOvrRight(@intCast(i));
        },
        .coal => dash.jog_coal_ms = @intCast(form.sliderValueAt(lay.coal, 0, 100, x)),
        .pend => dash.jog_pend_max = @intCast(@max(4, form.sliderValueAt(lay.pend, 4, 64, x))),
        .encdiv => dash.encdiv = @intCast(@max(1, form.sliderValueAt(lay.encdiv, 1, 16, x))),
        .contpct => dash.contpct = @intCast(@max(10, form.sliderValueAt(lay.contpct, 10, 200, x))),
        .stepacc => dash.stepacc = !dash.stepacc,
        .probe => {},
        .hw_ref => dash.hw_ref_exp = !dash.hw_ref_exp,
        .unit_mm => dash.unit_mm = !dash.unit_mm,
        .link_mach => return 7,
        .link_cnc => return 0,
        .link_disp => return 2,
    }
    return null;
}
