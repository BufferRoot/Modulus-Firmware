//! Host UI-engine demo — LVGL-shaped Modulus shell (host-only).
//!
//! ```text
//! zig build ui-demo           # Win32 window (dirty-rect present)
//! zig build ui-demo-bench     # headless proof (CI)
//! ```
//!
//! Gestures assigned: tap, double-tap QS, long-press. Wheel=scroll. Keys: Space Quick Settings | T D P M | Esc quit.

const std = @import("std");
const builtin = @import("builtin");
const ui_engine = @import("ui_engine");
const host_win32 = ui_engine.host_win32;
const gestures = ui_engine.gestures;

pub const std_options: std.Options = .{
    .log_level = .info,
};

/// Target frame period for host demo (60 Hz). Sleep only leftover time.
const frame_target_ms: u32 = 16;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    const bench = for (args) |a| {
        if (std.mem.eql(u8, a, "--bench")) break true;
    } else false;

    if (bench) {
        try runBench(gpa, io);
        return;
    }
    if (builtin.os.tag != .windows) {
        const msg = "ui-demo window requires Windows; use --bench\n";
        try std.Io.File.stdout().writeStreamingAll(io, msg);
        try runBench(gpa, io);
        return;
    }
    try runWindow(gpa, io);
}

fn paceFrame(frame_start_ms: u64) void {
    host_win32.paceFrameMs(frame_start_ms, frame_target_ms);
}

fn runWindow(gpa: std.mem.Allocator, io: std.Io) !void {
    var eng = try ui_engine.engine.Engine.create(gpa);
    defer eng.destroy(gpa);

    var view = try host_win32.View.open("Modulus UI Engine");
    defer view.close();

    const hello =
        \\Modulus UI Engine — gestures + boot splash ~3s
        \\  Tap / double-tap status / long-press | wheel scroll
        \\  T theme | D dialog | P PIN | M catalog | Space QS | Esc quit
        \\
    ;
    try std.Io.File.stdout().writeStreamingAll(io, hello);

    var input: host_win32.Input = .{};
    var recog: gestures.Recognizer = .{};
    var pointer_down = false;
    var clock_ms: u64 = 0;

    while (!input.quit) {
        const frame_start = host_win32.tickMs();
        input = .{};
        view.poll(&input);
        if (input.quit) break;

        clock_ms +%= 16; // ~60 Hz frame clock for gesture timers

        // LVGL: ignore chrome input until splash timer completes.
        if (eng.onBoot()) {
            _ = eng.tick(1.0 / 60.0);
            _ = view.presentDirty(eng.logical.pixels, eng.presentRects(), eng.prefs.display.flip);
            paceFrame(frame_start);
            continue;
        }

        if (input.wheel_y != 0) {
            eng.nudgeScroll(@as(f32, @floatFromInt(input.wheel_y)) * -24.0);
        }
        if (input.hover_x >= 0) {
            eng.handleHover(input.hover_x, input.hover_y);
        }
        if (input.chars_len > 0 or input.key_backspace) {
            eng.handleTextInput(input.chars[0..input.chars_len], input.key_backspace);
        }
        if (input.key_space and !eng.searchFocused()) eng.openQuickSettings();
        if (input.key_theme and !eng.searchFocused()) eng.toggleTheme();
        if (input.key_dialog and !eng.searchFocused()) eng.openDialog();
        if (input.key_pin and !eng.searchFocused()) eng.openPin();
        if (input.key_catalog and !eng.searchFocused()) eng.openCatalog();
        if (input.key_tab) eng.handleFocusTab(false);
        if (input.key_shift_tab) eng.handleFocusTab(true);
        if (input.key_enter) eng.activateFocus();

        // Pointer → gesture recognizer (tap on up; keep handleClick for tests).
        if (input.click_x >= 0) {
            pointer_down = true;
            recog.feed(.{
                .phase = .down,
                .x = input.click_x,
                .y = input.click_y,
                .t_ms = clock_ms,
            });
            eng.handlePointerDown(input.click_x, input.click_y);
        }
        if (pointer_down and input.drag_active) {
            recog.feed(.{
                .phase = .move,
                .x = input.drag_x,
                .y = input.drag_y,
                .t_ms = clock_ms,
            });
            // Widget slider tracking — not a gesture-action assignment.
            eng.handlePointerDrag(input.drag_x, input.drag_y);
        }
        if (input.pointer_up) {
            const ux = if (input.drag_x >= 0) input.drag_x else if (input.hover_x >= 0) input.hover_x else 0;
            const uy = if (input.drag_y >= 0) input.drag_y else if (input.hover_y >= 0) input.hover_y else 0;
            recog.feed(.{
                .phase = .up,
                .x = ux,
                .y = uy,
                .t_ms = clock_ms,
            });
            pointer_down = false;
            _ = eng.handlePointerUp();
        }

        recog.tick(clock_ms);
        recog.flushPendingTap(clock_ms);
        while (recog.poll()) |ev| {
            eng.handleGesture(ev);
        }

        const m = eng.tick(1.0 / 60.0);
        const presented = view.presentDirty(eng.logical.pixels, eng.presentRects(), eng.prefs.display.flip);
        _ = m;
        _ = presented;

        paceFrame(frame_start);
    }
}

fn runBench(gpa: std.mem.Allocator, io: std.Io) !void {
    const full = ui_engine.flush_shim.fullFramePx();
    var peak_sheet: u32 = 0;
    var peak_scroll: u32 = 0;
    var peak_present: u32 = 0;
    var peak_idle: u32 = 0;

    {
        var eng = try ui_engine.engine.Engine.create(gpa);
        defer eng.destroy(gpa);
        eng.skipBoot();
        eng.openSettings();
        var settle: u32 = 0;
        while (settle < 5) : (settle += 1) _ = eng.tick(1.0 / 60.0);

        eng.openQuickSettings();
        var f: u32 = 0;
        while (f < 45) : (f += 1) {
            const m = eng.tick(1.0 / 60.0);
            peak_sheet = @max(peak_sheet, m.rotate_px);
        }
    }

    {
        var eng = try ui_engine.engine.Engine.create(gpa);
        defer eng.destroy(gpa);
        eng.skipBoot();
        eng.openSettings();
        var settle: u32 = 0;
        while (settle < 5) : (settle += 1) _ = eng.tick(1.0 / 60.0);

        eng.setScrollTarget(280);
        var f: u32 = 0;
        while (f < 45) : (f += 1) {
            const m = eng.tick(1.0 / 60.0);
            peak_scroll = @max(peak_scroll, m.rotate_px);
            peak_present = @max(peak_present, m.present_px);
        }
    }

    {
        var eng = try ui_engine.engine.Engine.create(gpa);
        defer eng.destroy(gpa);
        eng.skipBoot();
        var settle: u32 = 0;
        while (settle < 10) : (settle += 1) _ = eng.tick(1.0 / 60.0);
        var f: u32 = 0;
        while (f < 90) : (f += 1) {
            const m = eng.tick(1.0 / 60.0);
            peak_idle = @max(peak_idle, m.rotate_px);
        }
    }

    // CI golden gates — fail the process on full-frame regress (ui-demo-bench).
    if (peak_scroll >= full) return error.ScrollDirtyFullFrame;
    if (peak_present >= full) return error.PresentDirtyFullFrame;
    if (peak_idle >= full) return error.IdleDirtyFullFrame;
    // Idle dashboard should stay regional (status/DRO springs), not near-full.
    // After job-wave throttle: peak_idle typically status/DRO band ≪ half frame.
    if (peak_idle > full / 4) return error.IdleDirtyTooLarge;

    var buf: [384]u8 = undefined;
    const line = try std.fmt.bufPrint(
        &buf,
        "ui-demo-bench full={d} peak_sheet={d} peak_scroll={d} peak_present={d} peak_idle={d} single_fb=1 golden=ok\n",
        .{ full, peak_sheet, peak_scroll, peak_present, peak_idle },
    );
    try std.Io.File.stdout().writeStreamingAll(io, line);
}
