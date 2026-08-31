//! Tab5 Zig UI scanout — Core-0 `zig_ui` task drives Engine.tick; LVGL paint suspended.

const std = @import("std");
const builtin = @import("builtin");
const ui_engine = @import("../ui_engine/root.zig");
const Engine = ui_engine.engine.Engine;
const fb = ui_engine.fb;
const dashboard = ui_engine.dashboard;
const dro_widget = ui_engine.dro_widget;
const device_runtime = @import("device_runtime.zig");
const device_ui_bridge = @import("device_ui_bridge.zig");
const CncStatus = @import("../ui/device_ui.zig").CncStatus;

comptime {
    if (builtin.os.tag != .freestanding) {
        @compileError("device_ui_runtime is Tab5 freestanding only");
    }
}

/// Touch is polled every call, but the engine only renders every Nth one.
const polls_per_frame: u32 = 3;
const frame_dt_sec: f32 = 0.030;
const max_dt_sec: f32 = 0.10;
/// Ignore a second click this soon after the last (guards residual bounce).
const click_refractory_ms: u64 = 120;

const cap_8bit: u32 = 1 << 2;
const cap_spiram: u32 = 1 << 10;

extern "c" fn heap_caps_aligned_alloc(alignment: usize, size: usize, caps: u32) callconv(.c) ?*anyopaque;
extern "c" fn heap_caps_free(ptr: ?*anyopaque) callconv(.c) void;
extern "c" fn modulus_touch_poll_for_zig(x: *i32, y: *i32, pressed: *c_int) callconv(.c) void;
extern "c" fn esp_timer_get_time() callconv(.c) i64;
extern "c" fn modulus_audio_play_ui(sound_id: u8) callconv(.c) void;
extern "c" fn modulus_ppa_init_zi() callconv(.c) c_int;
extern "c" fn modulus_ppa_rotate_block_zi(
    src: *const anyopaque,
    dst: *anyopaque,
    dst_bytes: u32,
    src_w: u32,
    src_h: u32,
    dst_w: u32,
    dst_h: u32,
    bx: u32,
    by: u32,
    bw: u32,
    bh: u32,
    flipped: c_int,
) callconv(.c) c_int;

/// `fb.hw_rotate` hook — PPA SRM instead of the CPU transpose.
fn ppaRotate(
    src: []const ui_engine.color.Rgb565,
    dst: []ui_engine.color.Rgb565,
    src_w: u16,
    src_h: u16,
    dst_w: u16,
    dst_h: u16,
    r: ui_engine.geom.Rect,
    flipped: bool,
) bool {
    if (r.x < 0 or r.y < 0 or r.w <= 0 or r.h <= 0) return false;
    return modulus_ppa_rotate_block_zi(
        src.ptr,
        dst.ptr,
        @intCast(dst.len * @sizeOf(ui_engine.color.Rgb565)),
        src_w,
        src_h,
        dst_w,
        dst_h,
        @intCast(r.x),
        @intCast(r.y),
        @intCast(r.w),
        @intCast(r.h),
        if (flipped) @as(c_int, 1) else 0,
    ) != 0;
}

const ui_sound_tick: u8 = 0;

/// Diagnostics use esp_rom_printf. std.log.* is a panic on this target — no
/// logFn in std_options and std_options_debug_io = std.Io.failing.
extern "c" fn esp_rom_printf(fmt: [*:0]const u8, ...) c_int;

/// Edge detector for job start/stop so the outcome is reported exactly once.
var g_job_was_active: bool = false;

const PsramAllocator = struct {
    fn alloc(_: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
        const bytes = @max(alignment.toByteUnits(), @sizeOf(usize));
        const p = heap_caps_aligned_alloc(bytes, len, cap_spiram | cap_8bit) orelse blk: {
            // Falling back to internal RAM for an Engine-sized allocation is a
            // big deal on a part with ~185 KB internal free — say so loudly.
            // esp_rom_printf, NOT std.log: this target has no logFn and
            // std_options_debug_io is std.Io.failing, so std.log.* panics with
            // "reached unreachable code".
            const q = heap_caps_aligned_alloc(bytes, len, cap_8bit) orelse return null;
            _ = esp_rom_printf("[ui] PSRAM alloc failed for %d B - using internal RAM\n", @as(c_int, @intCast(len)));
            break :blk q;
        };
        return @ptrCast(p);
    }

    fn resize(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) bool {
        return false;
    }

    fn remap(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) ?[*]u8 {
        return null;
    }

    fn free(_: *anyopaque, memory: []u8, _: std.mem.Alignment, _: usize) void {
        heap_caps_free(memory.ptr);
    }

    const vtable: std.mem.Allocator.VTable = .{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };
};

/// The vtable ignores `ptr`, but leaving it `undefined` puts an indeterminate
/// value in a struct that gets copied around. Point it at the vtable itself.
const psram_allocator: std.mem.Allocator = .{
    .ptr = @constCast(@ptrCast(&PsramAllocator.vtable)),
    .vtable = &PsramAllocator.vtable,
};

var g_eng: ?*Engine = null;
var g_was_pressed: bool = false;
var g_down_x: i32 = 0;
var g_down_y: i32 = 0;
var g_last_x: i32 = 0;
var g_last_y: i32 = 0;
/// Finger velocity (logical px per sample) — one-frame prediction before paint.
var g_vx: i32 = 0;
var g_vy: i32 = 0;
var g_last_frame_us: i64 = 0;
var g_poll: u32 = 0;
var g_last_click_ms: u64 = 0;
var g_fps_x10: u16 = 0;
var g_last_paint_us: u32 = 0;
var g_last_rotate_us: u32 = 0;
var g_last_dirty_kpx: u16 = 0;

fn nowMs() u64 {
    return @intCast(@divTrunc(esp_timer_get_time(), 1000));
}

fn nowUs() u64 {
    return @intCast(@max(esp_timer_get_time(), 0));
}

fn safeDtSec(now_us: i64) f32 {
    if (g_last_frame_us == 0) {
        g_last_frame_us = now_us;
        return frame_dt_sec;
    }
    const delta_us = now_us - g_last_frame_us;
    g_last_frame_us = now_us;
    if (delta_us <= 0) return frame_dt_sec;
    const raw = @as(f32, @floatFromInt(delta_us)) / 1_000_000.0;
    if (!std.math.isFinite(raw)) return frame_dt_sec;
    return std.math.clamp(raw, 0, max_dt_sec);
}

fn fireClick(eng: *Engine, x: i32, y: i32) void {
    const t = nowMs();
    if (g_last_click_ms != 0 and t - g_last_click_ms < click_refractory_ms) {
        return;
    }
    g_last_click_ms = t;
    modulus_audio_play_ui(ui_sound_tick);
    eng.handleClick(x, y);
}

/// Mid-blit (`dispatch_ui=false`): sample to keep contact alive only.
/// Never synthesize finger-up there — ST7123 dropouts were queueing a click
/// while the finger was still down, then a new down→up on the real release
/// (override +10×N → 200%, quick toggle flash, jog mode thrash).
fn feedTouch(eng: *Engine, dispatch_ui: bool) void {
    if (eng.screen == .boot) {
        g_was_pressed = false;
        return;
    }

    var x: i32 = -1;
    var y: i32 = -1;
    var pressed_i: c_int = 0;
    modulus_touch_poll_for_zig(&x, &y, &pressed_i);
    const pressed = pressed_i != 0;

    if (pressed) {
        device_ui_bridge.noteUserActivity();
        if (!g_was_pressed) {
            g_down_x = x;
            g_down_y = y;
            g_vx = 0;
            g_vy = 0;
            if (dispatch_ui) eng.handlePointerDown(x, y);
        } else if (dispatch_ui and (x != g_last_x or y != g_last_y)) {
            g_vx = x - g_last_x;
            g_vy = y - g_last_y;
            eng.handlePointerDrag(x, y);
        }
        g_last_x = x;
        g_last_y = y;
        g_was_pressed = true;
        return;
    }

    if (!g_was_pressed) return;

    // Phantom empty read during rotate — stay pressed.
    if (!dispatch_ui) return;

    const scrolled = eng.handlePointerUp();
    g_was_pressed = false;
    g_vx = 0;
    g_vy = 0;
    // Finger scroll past slop — do not synthesize a click on release.
    if (scrolled) return;

    // Press-capture only within the same dashboard panel. A down on DRO Home
    // then release on jog was still firing Home/Zero / axis select.
    const down_panel = dashboard.panelAt(g_down_x, g_down_y, eng.cnc);
    const up_panel = dashboard.panelAt(g_last_x, g_last_y, eng.cnc);
    if (down_panel != .none and down_panel == up_panel) {
        fireClick(eng, g_down_x, g_down_y);
    } else {
        fireClick(eng, g_last_x, g_last_y);
    }
}

/// LVGL parity: `up/down/reset_click_cb` → `modulus_zig_cmd_*_override`.
fn overrideSink(which: ui_engine.override_widget.Which, delta: i8) void {
    switch (which) {
        .feed => device_runtime.cmdFeedOverride(delta),
        .spindle => device_runtime.cmdSpindleOverride(delta),
        .rapid => {
            const eng = g_eng orelse return;
            device_runtime.cmdRapidOverride(eng.cnc.rapid_pct);
        },
    }
}

fn mpgSink() void {
    device_runtime.cmdMpgToggle();
}

fn wcsSink() void {
    device_runtime.cycleWcs();
}

fn uiSink(cmd: ui_engine.engine.CncUiCmd) bool {
    if (!device_runtime.isBootOk()) return false;
    switch (cmd) {
        .cycle_start => device_runtime.cmdCycleStart(),
        .stop => device_runtime.cmdStop(),
        .unlock => device_runtime.cmdUnlock(),
        .reset => device_runtime.cmdReset(),
        .feed_hold => device_runtime.cmdFeedHold(),
        .home_all => device_runtime.cmdHomeAll(),
        .home_axis => |a| device_runtime.cmdHomeAxis(a),
        .zero_axis => |a| return device_runtime.cmdZeroAxis(a),
        .zero_all => return device_runtime.cmdZeroAll(),
        .set_jog_mode => |m| device_runtime.setJogMode(m),
        .set_step_size => |s| device_runtime.setStepSize(s),
        .set_active_axis => |a| device_runtime.setActiveAxis(a),
        .spindle_cw => device_runtime.cmdSpindleCw(),
        .spindle_ccw => device_runtime.cmdSpindleCcw(),
        .coolant_toggle => device_runtime.cmdCoolantToggle(),
        .mist_toggle => device_runtime.cmdMistToggle(),
        .fan_toggle => device_runtime.cmdFanToggle(),
        .single_step => device_runtime.cmdSingleStep(),
        .run_macro => device_runtime.cmdRunMacro(),
    }
    return true;
}

fn mmToUm(mm: f32) i32 {
    if (!std.math.isFinite(mm)) return 0;
    const um = mm * 1000.0;
    if (!std.math.isFinite(um)) return 0;
    if (um > @as(f32, @floatFromInt(std.math.maxInt(i32)))) return std.math.maxInt(i32);
    if (um < @as(f32, @floatFromInt(std.math.minInt(i32)))) return std.math.minInt(i32);
    return @intFromFloat(um);
}

fn stateName(st: u8) []const u8 {
    return switch (st) {
        1 => "Idle",
        2 => "Run",
        3 => "Hold",
        4 => "Jog",
        5 => "Alarm",
        6 => "Door",
        7 => "Check",
        8 => "Home",
        9 => "Sleep",
        10 => "Tool",
        else => "Offline",
    };
}

/// Job streamer → UI. Progress drives the dashboard strip; a terminal fault
/// must surface, otherwise a refused MPG claim looks identical to a job that
/// simply has not started yet.
fn mirrorJobStatus(eng: *Engine) void {
    if (!device_runtime.isBootOk()) return;
    const js = device_runtime.jobStatus();

    if (js.active) {
        eng.cnc.job_progress = @as(f32, @floatFromInt(js.per_mille)) / 1000.0;
        eng.cnc.sd_streaming = true;
    } else if (g_job_was_active) {
        eng.cnc.sd_streaming = false;
    }

    // Edge-triggered: report the outcome once, when the job leaves active.
    if (g_job_was_active and !js.active) {
        switch (js.fault) {
            .none => {
                if (js.terminal == .complete) {
                    eng.cnc.job_progress = 1.0;
                    eng.showSnackbar("Job complete");
                } else {
                    // Operator abort: terminal without a fault.
                    eng.showSnackbar("Job aborted");
                }
            },
            .claim_denied => eng.showSnackbarError("MPG refused - is a sender streaming?"),
            .mpg_lost => eng.showSnackbarError("MPG lost - job stopped"),
            .controller_error => eng.showSnackbarError("Controller rejected a line"),
            .ack_timeout => eng.showSnackbarError("Link timeout - feed held"),
            .read_failed => eng.showSnackbarError("USB read failed - job stopped"),
        }
        eng.job_armed = false;
        eng.requestFull();
    }
    g_job_was_active = js.active;
}

/// LVGL `modulus_ui_status_bar_update` + overrides — machine-reported fields win.
fn mirrorCncStatus(eng: *Engine) void {
    if (!device_runtime.isBootOk()) return;
    // Load-bearing, do not "optimise" away: modulus_cnc_status_t has ~30
    // fields and device_runtime.fillCncStatus assigns 21. Without the zeroing
    // the remaining 9 would be stack garbage. ~400 B of memset at 33 Hz.
    var st: CncStatus = std.mem.zeroes(CncStatus);
    device_runtime.fillCncStatus(&st);

    // Machine wins — always assign (boot gate already returned above).
    eng.cnc.feed_pct = st.feed_ovr;
    eng.cnc.spindle_pct = st.spindle_ovr;
    eng.cnc.rapid_pct = st.rapid_ovr;

    eng.cnc.mpg_active = st.mpg_active != 0;
    eng.cnc.mpg_remote = device_runtime.mpgRemote() != 0;
    eng.cnc.connected = st.connected != 0;
    eng.cnc.session = st.session;
    device_ui_bridge.mirrorCncSession(eng, st.connected, st.session);
    eng.cnc.alarm_code = st.alarm_code;
    eng.cnc.mach_state = st.state;
    eng.cnc.wcs_i = @min(st.wcs, 5);
    eng.cnc.feed_mm_min = @intFromFloat(@max(st.feed_rate, 0));
    eng.cnc.spindle_rpm = st.spindle_rpm;
    eng.cnc.unit_mm = st.units_mm != 0;
    eng.cnc.dro.unit_mm = eng.cnc.unit_mm;
    eng.cnc.accessories = st.accessories;
    // Fan is not in grblHAL A: accessories — latch local; clear when offline.
    if (st.connected == 0) eng.cnc.fan_on = false;
    eng.cnc.sd_percent = st.sd_percent;
    eng.cnc.line_number = st.line_number;
    eng.cnc.sd_streaming = st.sd_streaming != 0;
    eng.cnc.homing_block = st.homing_block != 0;

    eng.cnc.jog_mode = @min(@as(usize, st.jog_mode), 2);
    eng.cnc.jog_incr = @min(@as(usize, st.step_size), 3);
    // Prefs must match driver — applyPrefs() reloads jog from dash prefs.
    eng.prefs.dash.jog_mode = @intCast(eng.cnc.jog_mode);
    eng.prefs.dash.jog_incr_sel = @intCast(eng.cnc.jog_incr);
    eng.cnc.syncJogFromFields();

    const axis_sel = @min(@as(usize, st.active_axis), eng.cnc.dro.axis_count -| 1);
    eng.cnc.dro.selected = axis_sel;

    const wpos = [_]f32{ st.wpos_x, st.wpos_y, st.wpos_z, st.wpos_a, st.wpos_b, st.wpos_c };
    const mpos = [_]f32{ st.mpos_x, st.mpos_y, st.mpos_z, st.mpos_a, st.mpos_b, st.mpos_c };
    var ai: usize = 0;
    while (ai < dro_widget.max_axes) : (ai += 1) {
        eng.cnc.dro.work_um[ai] = mmToUm(wpos[ai]);
        eng.cnc.dro.mach_um[ai] = mmToUm(mpos[ai]);
    }

    const file = std.mem.sliceTo(&st.sd_file, 0);
    if (file.len > 0) {
        const n = @min(file.len, eng.cnc.job_name_buf.len);
        @memcpy(eng.cnc.job_name_buf[0..n], file[0..n]);
        if (n < eng.cnc.job_name_buf.len) eng.cnc.job_name_buf[n] = 0;
        eng.cnc.job_name = eng.cnc.job_name_buf[0..n];
    } else {
        // Driver cleared `|SD:` — drop stale demo/host name so strip matches machine.
        eng.cnc.job_name_buf[0] = 0;
        eng.cnc.job_name = "";
    }

    eng.cnc.state = stateName(st.state);
    if (st.alarm_code != 0) eng.cnc.state = "Alarm";
    // Phase only — do not call setPhase (it overwrites sd_streaming from phase).
    // Engine.syncMirroredChromePaint catches strip/LED/layout like setMachinePhase.
    eng.cnc.actions.phase = switch (st.state) {
        2 => .run,
        3 => .hold,
        else => .idle,
    };
    eng.cnc.syncJobProgressFromSd();

    const tool_n = @min(st.tool_number, 99);
    if (std.fmt.bufPrint(&eng.cnc.tool_buf, "T{d:0>2}", .{tool_n})) |s| {
        eng.cnc.tool = s;
    } else |_| {}

    eng.syncStatusBarChrome();
}

fn mirrorLiveTelemetry(eng: *Engine) void {
    device_ui_bridge.mirrorBatteryClock(eng);
}

fn blitTouchPump() void {
    const eng = g_eng orelse return;
    feedTouch(eng, false);
}

export fn modulus_zig_ui_boot() c_int {
    if (g_eng != null) return 1;
    const scanout = ui_engine.flush_shim.scanoutPixels() orelse return 0;
    fb.during_blit_pump = &blitTouchPump;
    if (modulus_ppa_init_zi() != 0) fb.hw_rotate = &ppaRotate;
    // Borrowed DPI back buffer — dual FB flips via draw_bitmap (tear-free).
    const eng = Engine.createHeap(psram_allocator, .{ .panel_pixels = scanout }) catch return 0;
    eng.now_us_sink = nowUs;
    eng.cnc_override_sink = overrideSink;
    eng.cnc_mpg_sink = mpgSink;
    eng.cnc_wcs_sink = wcsSink;
    eng.cnc_ui_sink = uiSink;
    // Clear host demo DRO — first mirror fills from the driver.
    eng.cnc.dro.work_um = .{0} ** dro_widget.max_axes;
    eng.cnc.dro.mach_um = .{0} ** dro_widget.max_axes;
    eng.cnc.sd_percent = 0;
    eng.cnc.job_progress = 0;
    eng.cnc.job_progress_vis = 0;
    // Drop host stub SoC (78%) before first paint — INA mirror fills next.
    eng.cnc.battery_pct = 0;
    eng.prefs.power_tel.bat_pct = 0;
    eng.prefs.power_tel.ina_ok = false;
    eng.cnc.connected = false;
    eng.cnc.session = 0;
    eng.cnc.job_name = "";
    @memset(&eng.cnc.clock_buf, 0);
    @memcpy(eng.cnc.clock_buf[0..5], "--:--");
    device_ui_bridge.install(eng);
    device_ui_bridge.mirrorBatteryClock(eng);
    // Prefs/theme may have changed — splash must match final theme before light.
    eng.screen = .boot;
    eng.presentBootSplash();
    g_eng = eng;
    return 1;
}

export fn modulus_zig_ui_arm_boot_hold() void {
    const eng = g_eng orelse return;
    // Reset dt baseline so the hold isn't burned by createHeap wall time.
    g_last_frame_us = esp_timer_get_time();
    eng.armBootHold();
}

export fn modulus_zig_ui_install_late() void {
    const eng = g_eng orelse return;
    device_ui_bridge.installLate(eng);
}

export fn modulus_zig_ui_frame() void {
    const eng = g_eng orelse return;
    feedTouch(eng, true);

    g_poll += 1;
    if (g_poll < polls_per_frame) return;
    g_poll = 0;

    // Boot hold: skip heavy I/O so the splash timer tracks wall time.
    if (eng.screen != .boot) {
        mirrorLiveTelemetry(eng);
        mirrorCncStatus(eng);
        mirrorJobStatus(eng);
        device_ui_bridge.drainConsole(eng);
        device_ui_bridge.pollPrefsFlush(eng);
        device_ui_bridge.applyBrightVol(&eng.prefs);
        device_ui_bridge.wirelessPoll(eng);
        device_ui_bridge.pollPinLock(eng);
        device_ui_bridge.mirrorC6Sdio(eng);
        if (eng.probe_pin_sink) |pin| {
            eng.qs_probe_trig = pin();
        }
        eng.cnc.perf_hud = eng.prefs.system.perf_hud;
        eng.cnc.perf_fps_x10 = g_fps_x10;
        eng.cnc.perf_paint_us = g_last_paint_us;
        eng.cnc.perf_rotate_us = g_last_rotate_us;
        eng.cnc.perf_dirty_kpx = g_last_dirty_kpx;
    }
    const now_us = esp_timer_get_time();
    const dt = safeDtSec(now_us);
    // Freshest sample immediately before paint — cuts one poll-period of lag.
    // One-frame prediction welds drag to the finger under the paint budget.
    feedTouch(eng, true);
    if (g_was_pressed and (g_vx != 0 or g_vy != 0)) {
        eng.handlePointerDrag(g_last_x + g_vx, g_last_y + g_vy);
    }
    const t0 = esp_timer_get_time();
    const metrics = eng.tick(dt);
    const elapsed: u32 = @intCast(@max(esp_timer_get_time() - t0, 0));
    g_last_paint_us = elapsed;
    g_last_rotate_us = metrics.rotate_us;
    g_last_dirty_kpx = @intCast(@min(metrics.dirty_px / 1024, 65535));
    eng.metrics.paint_us = elapsed;
    if (elapsed > 0) {
        const inst: u32 = @min(10000, 10_000_000 / elapsed);
        g_fps_x10 = @intCast((@as(u32, g_fps_x10) * 7 + inst * 3) / 10);
    }
    eng.metrics.fps_x10 = g_fps_x10;
    feedTouch(eng, true);
}

export fn modulus_zig_ui_is_ready() c_int {
    return if (g_eng != null) @as(c_int, 1) else 0;
}

/// Dirty-set cap overflows since boot. Each one collapses the damage list to a
/// single AABB — usually the full frame — so a rising count means `dirty_cap`
/// is too small for the busiest screen. Surfaced in the zig_ui health line.
export fn modulus_zig_dirty_merge_all_count() u32 {
    return ui_engine.geom.merge_all_events;
}

/// Pixels rotated on the last painted frame. `flush_last_px` cannot be used for
/// this: flush_flip overwrites it with the whole panel on every flip, so it
/// always read 921600 regardless of how little actually changed.
export fn modulus_zig_last_dirty_px() u32 {
    const eng = g_eng orelse return 0;
    return eng.metrics.rotate_px;
}
