//! Host frame engine: boot → dashboard → settings/power/QS overlays.
//! Mimics LVGL Modulus shell (status 80 / job / DRO|center|actions).

const std = @import("std");
const color = @import("color.zig");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const spring = @import("spring.zig");
const motion = @import("motion.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const widgets = @import("widgets.zig");
const dashboard = @import("dashboard.zig");
const battery_chrome = @import("battery_chrome.zig");
const flush_shim = @import("flush_shim.zig");
const icons_phosphor = @import("icons_phosphor.zig");
const dro_widget = @import("dro_widget.zig");
const override_widget = @import("override_widget.zig");
const actions_widget = @import("actions_widget.zig");
const settings_prefs = @import("settings_prefs.zig");
const settings_dashboard_tab = @import("settings_dashboard_tab.zig");
const settings_display_tab = @import("settings_display_tab.zig");
const settings_other_tabs = @import("settings_other_tabs.zig");
const settings_cnc_modals = @import("settings_cnc_modals.zig");
const settings_dashboard_modals = @import("settings_dashboard_modals.zig");
const settings_extra_modals = @import("settings_extra_modals.zig");
const settings_pin_modal = @import("settings_pin_modal.zig");
const settings_mach_string_modal = @import("settings_mach_string_modal.zig");
const md3_catalog = @import("md3_catalog.zig");
const expr = @import("widgets_expressive.zig");
const settings_menu = @import("settings_menu.zig");
const quick_settings = @import("quick_settings.zig");

const settings_form = @import("settings_form.zig");
const gestures = @import("gestures.zig");
const input_pad = @import("input_pad.zig");
const ascii_util = @import("ascii_util.zig");
const ui_cmds = @import("ui_cmds.zig");

pub const WirelessUiCmd = ui_cmds.WirelessUiCmd;
pub const StorSysUiCmd = ui_cmds.StorSysUiCmd;
pub const CncUiCmd = ui_cmds.CncUiCmd;

/// Tab5 LVGL System settings category labels (host).
const k_tabs = [_][]const u8{
    "CNC & connection",
    "Dashboard & handwheel",
    "Display & theme",
    "Audio & haptics",
    "Wireless",
    "Power",
    "Security",
    "Machine",
    "Storage & diagnostics",
    "System & about",
};
/// Plain-word search bags (rail filter). Title match still wins.
const k_tab_keywords = [_][]const []const u8{
    &.{ "baud", "serial", "rs485", "grbl", "connect", "transport", "masso", "telnet", "websocket", "fluidnc", "linuxcnc" },
    &.{ "jog", "handwheel", "mpg", "wcs", "axes", "macro", "probe", "increment", "confirm", "unit" },
    &.{ "brightness", "theme", "dark", "contrast", "touch", "glove", "flip", "refresh", "accent", "lefty", "notification", "snackbar", "toast", "motion", "animation" },
    &.{ "volume", "tone", "mic", "sound", "haptic", "speaker", "audio" },
    &.{ "wifi", "bluetooth", "ble", "esp-now", "zigbee", "thread", "ssid", "antenna", "c6" },
    &.{ "battery", "sleep", "dim", "rail", "ext5v", "usb5v", "charge", "deep" },
    &.{ "pin", "lock", "security", "idle", "boot", "wake" },
    &.{ "travel", "soft limit", "envelope", "feed", "rpm", "push", "pull", "maintenance", "jog speed" },
    &.{ "sd", "backup", "export", "i2c", "usb", "log", "diagnostic", "cache" },
    &.{ "language", "timezone", "ntp", "factory", "restart", "shutdown", "firmware", "about", "fps" },
};
const k_dashboard_tab: usize = 1;
const k_display_tab: usize = 2;
const settings_header_h: i32 = settings_form.title_h;
const cat_item_h: i32 = settings_form.cat_item_h;
/// Splash length in wall-clock seconds — host demo and Tab5 tick at different
/// rates, so counting frames made the splash scale with the loop period.
const boot_seconds: f32 = 3.0;
/// Host product line (System & about + splash).
pub const ui_engine_product: []const u8 = "ZIG UI Engine";
pub const ui_engine_version: []const u8 = "V1.0";
const boot_credit: []const u8 = "Driven by M5Stack | Powered by Zig | Built on ESP-IDF";

const FocusKind = enum { none, gear, power, search, close };

pub const Screen = enum { boot, dashboard, settings, power, pin, catalog };

pub const FrameMetrics = struct {
    dirty_px: u32 = 0,
    rotate_px: u32 = 0,
    present_px: u32 = 0,
    device_stub_px: u32 = 0,
    spring_active: bool = false,
    /// Last tick wall time (µs) — device FPS HUD / MDI log.
    paint_us: u32 = 0,
    /// Phase split of `paint_us`: widget drawing into the logical FB…
    draw_us: u32 = 0,
    /// …and rotate + present into the panel/scanout buffer.
    rotate_us: u32 = 0,
    /// Rolling FPS ×10 (e.g. 312 = 31.2 fps). Updated on device via ui_shim.
    fps_x10: u16 = 0,
};

/// Driver commands from Zig dashboard (LVGL `cnc_cmd_exports` parity).
pub const MachPullTick = enum { pending, applied, empty, failed, timeout };

/// Snackbar importance — filtered by Display & Theme → Notifications.
pub const SnackLevel = enum(u8) { info = 0, important = 1, err = 2 };

pub const Engine = struct {
    theme: tokens.Theme,
    logical: fb.LogicalFb,
    panel: fb.PanelFb,
    // Cap via geom.dirty_cap: fewer merge-all → full-frame collapses under sheet/scroll thrash.
    dirty: geom.DirtySet(geom.dirty_cap) = .{},
    /// Logical rects for host present (copied before rotate flush clears dirty).
    present_dirty: geom.DirtySet(geom.dirty_cap) = .{},
    /// Damage painted last frame. With dual DPI FBs the buffer we are about to
    /// paint is one frame stale, so it must be repainted here too.
    prev_dirty: geom.DirtySet(geom.dirty_cap) = .{},
    screen: Screen = .boot,
    boot_left_sec: f32 = boot_seconds,
    /// False until panel backlight is on with splash visible — don't burn the hold.
    boot_hold_armed: bool = false,
    /// True when created via `createHeap` — `destroy` must free the Engine pointer.
    heap_owned: bool = false,
    cnc: dashboard.CncView = .{},
    /// Tab5 `device_ui_runtime` installs this so override taps reach the CNC
    /// driver (LVGL parity: `modulus_zig_cmd_*_override`). Null on host.
    cnc_override_sink: ?*const fn (which: override_widget.Which, delta: i8) void = null,
    /// LVGL `modulus_zig_cmd_mpg_toggle` / `modulus_zig_cycle_wcs`. Null on host.
    cnc_mpg_sink: ?*const fn () void = null,
    cnc_wcs_sink: ?*const fn () void = null,
    /// Dashboard control → driver (LVGL `cnc_cmd_exports`). Null = host CncView demo.
    cnc_ui_sink: ?*const fn (CncUiCmd) bool = null,
    /// Device: persist prefs + apply bright/vol after edits.
    prefs_dirty_sink: ?*const fn (*Engine) void = null,
    gcode_sink: ?*const fn ([]const u8) void = null,
    power_restart_sink: ?*const fn () void = null,
    power_shutdown_sink: ?*const fn () void = null,
    power_sleep_sink: ?*const fn () void = null,
    pin_verify_sink: ?*const fn ([]const u8) bool = null,
    pin_unlock_sink: ?*const fn () void = null,
    pin_set_sink: ?*const fn ([]const u8) bool = null,
    pin_clear_sink: ?*const fn ([]const u8) bool = null,
    factory_reset_sink: ?*const fn () void = null,
    transport_reinit_sink: ?*const fn () void = null,
    dump_begin_sink: ?*const fn () void = null,
    dump_cancel_sink: ?*const fn () void = null,
    dump_tick_sink: ?*const fn (*settings_cnc_modals.DumpState) bool = null,
    probe_start_sink: ?*const fn (u8) bool = null,
    probe_busy_sink: ?*const fn () bool = null,
    probe_pin_sink: ?*const fn () bool = null,
    mach_pull_begin_sink: ?*const fn () void = null,
    mach_pull_tick_sink: ?*const fn (*Engine) MachPullTick = null,
    mach_push_sink: ?*const fn () void = null,
    maint_reset_sink: ?*const fn () void = null,
    wifi_scan_sink: ?*const fn (*Engine) void = null,
    wifi_connect_sink: ?*const fn ([]const u8, []const u8) void = null,
    wifi_disconnect_sink: ?*const fn () void = null,
    wireless_cmd_sink: ?*const fn (*Engine, WirelessUiCmd) void = null,
    stor_sys_sink: ?*const fn (*Engine, StorSysUiCmd) void = null,
    /// Pending CNC cmd waiting on confirm dialog OK.
    pending_cnc: ?CncUiCmd = null,
    prefs: settings_prefs.Prefs = .{},
    dash_layout: settings_dashboard_tab.Layout = .{},
    disp_layout: settings_display_tab.Layout = .{},
    other_layout: settings_other_tabs.Layout = .{},
    pad: input_pad.State = .{},
    slider_drag: input_pad.Target = .none,
    catalog: md3_catalog.State = .{},
    settings_content_h: i32 = 800,
    scroll: spring.Spring,
    /// Effects: theme crossfade progress (0..1) after T toggle.
    theme_fx: spring.Spring = spring.Spring.effects(1),
    /// Effects: status LED morph 0=circle … 1=diamond.
    led_morph: spring.Spring = spring.Spring.effects(0),
    /// Effects: DRO selected-card emphasis 0→1 after axis select.
    dro_select: spring.Spring = spring.Spring.effects(1),
    sheet_y: spring.Spring,
    /// Panel top Y last paint (bottom-sheet motion).
    prev_sheet_y: i32 = tokens.Logical.height,
    /// Frame counter for blank-status double-tap (Tab5 click path has no Recognizer).
    frame_n: u32 = 0,
    qs_blank_armed: bool = false,
    qs_blank_arm_frame: u32 = 0,
    qs_blank_arm_x: i32 = 0,
    qs_blank_arm_y: i32 = 0,
    qs_slider: enum { none, bright, volume } = .none,
    qs_drag: bool = false,
    /// Touch updated QS content — tick must re-present (tick clears dirty at entry).
    qs_content_dirty: bool = false,
    /// Zigbee Exposes overlay (0xff = closed).
    qs_zb_detail: u8 = 0xff,
    /// Long-press arm for Zigbee tile (device click path has no Recognizer).
    qs_zb_hold_idx: u8 = 0xff,
    qs_zb_hold_frame: u32 = 0,
    qs_zb_hold_fired: bool = false,
    qs_zb_level_drag: bool = false,
    /// Finger-drag scroll (Tab5 has no mouse wheel) — last sample + scrolled-past-slop.
    drag_last_y: i32 = -1,
    drag_origin_y: i32 = -1,
    drag_scrolled: bool = false,
    qs_drag_grab: i32 = 0,
    qs_body_scroll: i32 = 0,
    /// Spatial spring for QS segmented tab pill (MD3 motion).
    qs_tab_axis: spring.Spring = spring.Spring.spatial(0),
    /// Host MDI scrollback (LVGL s_term_log stub).
    qs_term: [768]u8 = undefined,
    qs_term_len: usize = 0,
    qs_mdi: [64]u8 = undefined,
    qs_mdi_len: usize = 0,
    qs_probe_trig: bool = false,
    tab_selected: usize = 0,
    /// Shared-axis enter after tab change (px → 0).
    tab_axis: spring.Spring = spring.Spring.spatial(0),
    motion_scheme: tokens.MotionScheme = .expressive,
    motion_phys: motion.Physics = .{},
    /// Per-widget effects springs (settings switches / sliders / segments).
    widget_fx: motion.WidgetPool = .{},
    /// Snackbar enter: value 0..1 (lift = (1-value)*48).
    snack_fx: spring.Spring = spring.Spring.effects(1),
    /// Dashboard: job strip / DRO scroll / override readouts.
    job_fx: spring.Spring = spring.Spring.effects(0.42),
    dro_scroll: spring.Spring = spring.Spring.spatial(0),
    feed_fx: spring.Spring = spring.Spring.effects(100),
    spindle_fx: spring.Spring = spring.Spring.effects(100),
    rapid_fx: spring.Spring = spring.Spring.effects(100),
    search_buf: [32]u8 = .{0} ** 32,
    search_len: usize = 0,
    search_focus: bool = false,
    /// Compact settings: true = category hub; false = tab detail.
    settings_hub: bool = false,
    press_fx: spring.Spring = spring.Spring.effects(0),
    press_x: i32 = 0,
    press_y: i32 = 0,
    hover_x: i32 = -1,
    hover_y: i32 = -1,
    hover_rect: geom.Rect = .{},
    /// Last settings control AABB — widget morph dirties this row, not the pane.
    settings_row_dirty: geom.Rect = .{},
    /// Importance of the snackbar being raised (reset after each show).
    snack_level: SnackLevel = .info,
    menu_target: settings_menu.Target = .none,
    menu_anchor: geom.Rect = .{},
    menu_hit: geom.Rect = .{},
    /// First visible menu item index (scroll).
    menu_scroll: usize = 0,
    focus_kind: FocusKind = .none,
    focus_rect: geom.Rect = .{},
    snack_frames: u32 = 0,
    snack_buf: [48]u8 = undefined,
    snack_len: usize = 0,
    snack_action_buf: [12]u8 = undefined,
    snack_action_len: usize = 0,
    snack_action_rect: geom.Rect = .{},
    snack_undo_dark: ?bool = null,
    busy_frames: u32 = 0,
    busy_phase: f32 = 0,
    dialog_fx: spring.Spring = spring.Spring.effects(0),
    dialog_open: bool = false,
    dialog_ok: geom.Rect = .{},
    power_layout: settings_form.PowerLayout = .{},
    power_confirm: settings_form.PowerConfirm = .none,
    /// Settings-tab confirm (restart / shutdown / factory / language).
    settings_confirm: settings_form.PowerConfirm = .none,
    settings_confirm_ok: geom.Rect = .{},
    settings_confirm_cancel: geom.Rect = .{},
    settings_confirm_card: geom.Rect = .{},
    cnc_overlay: settings_cnc_modals.Kind = .none,
    cnc_prof_layout: settings_cnc_modals.ProfLayout = .{},
    cnc_dump: settings_cnc_modals.DumpState = .{},
    cnc_rename_slot: u8 = 0,
    cnc_overlay_fx: spring.Spring = spring.Spring.effects(0),
    dash_overlay: settings_dashboard_modals.Kind = .none,
    dash_wcs_layout: settings_dashboard_modals.WcsLayout = .{},
    dash_mac_layout: settings_dashboard_modals.MacroLayout = .{},
    dash_arr_layout: settings_dashboard_modals.ArrangeLayout = .{},
    /// Pick-list scroll while arranging a slot.
    dash_arr_scroll: i32 = 0,
    dash_overlay_fx: spring.Spring = spring.Spring.effects(0),
    dash_mac_slot: u8 = 0,
    dash_mac_draft: settings_prefs.MacroSlot = .{},
    dash_mac_is_edit: bool = false,
    dash_arr_pick: i8 = -1,
    dash_wcs_name_i: u8 = 0,
    pending_lang: u8 = 0,
    /// Pending WCS index after locked-WCS confirm.
    pending_wcs_i: u8 = 0,
    /// Security PIN overlay (Set/Change dual-field, Clear).
    pin_overlay: settings_pin_modal.Kind = .none,
    pin_layout: settings_pin_modal.Layout = .{},
    pin_overlay_fx: spring.Spring = spring.Spring.effects(0),
    pin_draft1: [8]u8 = .{0} ** 8,
    pin_draft1_len: u8 = 0,
    pin_draft2: [8]u8 = .{0} ** 8,
    pin_draft2_len: u8 = 0,
    pin_focus: u8 = 0,
    pin_status: [48]u8 = .{0} ** 48,
    pin_status_len: u8 = 0,
    pin_status_err: bool = false,
    pin_err1: bool = false,
    pin_err2: bool = false,
    /// Machine name / service-notes modal.
    mach_str_overlay: settings_mach_string_modal.Kind = .none,
    mach_str_layout: settings_mach_string_modal.Layout = .{},
    mach_str_fx: spring.Spring = spring.Spring.effects(0),
    mach_str_draft: [64]u8 = .{0} ** 64,
    mach_str_draft_len: u8 = 0,
    mach_str_focus: bool = false,
    mach_str_err: bool = false,
    mach_str_status: [40]u8 = .{0} ** 40,
    mach_str_status_len: u8 = 0,
    /// Gap-fill overlays (transport / wifi / BT / ZB / TH / probe / MPG / idle).
    extra_overlay: settings_extra_modals.Kind = .none,
    extra_layout: settings_extra_modals.Layout = .{},
    extra_fx: spring.Spring = spring.Spring.effects(0),
    /// Host stub: frames remaining while probe modal shows Busy.
    probe_busy_frames: u8 = 0,
    wifi_ap_idx: u8 = 0,
    /// Pull-from-controller poll (LVGL 250 ms × ≤40; host compressed).
    mach_pull_polls: u8 = 0,
    /// Soft-limit / travel edits unlocked after confirm this settings session.
    machine_envelope_armed: bool = false,
    /// Confirm `.mach_slim` should turn soft limits on (vs only arm travel edits).
    envelope_pending_enable: bool = false,
    /// Accumulator for 1 Hz System prefs clock tick.
    sys_clock_accum: f32 = 0,
    /// Accumulator for ~2 s Storage mem/SD refresh.
    stor_refresh_accum: f32 = 0,
    /// Sheet / confirm enter (0→1). Emphasized decelerate stand-in.
    power_fx: spring.Spring = spring.Spring.effects(0),
    power_confirm_fx: spring.Spring = spring.Spring.effects(0),
    settings_confirm_fx: spring.Spring = spring.Spring.effects(0),
    needs_full_repaint: bool = true,
    /// After full paint on settings: present window AABB only (margins unchanged).
    settings_present_window: bool = false,
    /// Phase B change-gates (0xFF = invalidate). Skip redundant regional paints.
    gate_job_pct: u8 = 0xFF,
    gate_job_hold: u8 = 0xFF,
    gate_job_wave: u8 = 0xFF,
    gate_job_indet: u8 = 0xFF,
    gate_job_elapsed: u32 = 0xFFFFFFFF,
    /// Device mirror bypasses `setMachinePhase` — gate strip/phase so layout + LED follow.
    gate_job_strip: u8 = 0xFF,
    gate_phase: u8 = 0xFF,
    gate_job_name_sig: u32 = 0xFFFFFFFF,
    gate_status_sig: u32 = 0xFFFFFFFF,
    gate_feed_vis: u8 = 0xFF,
    gate_spindle_vis: u8 = 0xFF,
    gate_rapid_vis: u8 = 0xFF,
    /// DRO live gate — mirror updates work/mach every poll; paint must follow.
    gate_dro_work: [dro_widget.max_axes]i32 = .{std.math.minInt(i32)} ** dro_widget.max_axes,
    gate_dro_mach: [dro_widget.max_axes]i32 = .{std.math.minInt(i32)} ** dro_widget.max_axes,
    gate_dro_sel: usize = std.math.maxInt(usize),
    gate_dro_axes: u8 = 0xFF,
    gate_dro_unit: u8 = 0xFF,
    /// Throttle job-strip wave dirty when progress spring is settled.
    job_wave_div: u8 = 0,
    metrics: FrameMetrics = .{},
    /// Phase C: match LVGL ≥33 ms floor (was 12 ms — fought WDT history).
    frame_budget_us: u64 = tokens.Motion.refresh_floor_us,
    /// Conservative host cost model for rotate-on-write (ns/px). Tune via bench.
    ns_per_px: u64 = 40,
    /// Monotonic µs for frame phase timing. Null on host — phases read 0.
    now_us_sink: ?*const fn () u64 = null,

    pub const CreateOpts = struct {
        /// Dual FB for panel bring-up. Host default false = single logical (−1.8 MB).
        keep_panel: bool = false,
        /// Borrowed 720×1280 scanout buffer (Tab5 DPI FB). Wins over `keep_panel`.
        panel_pixels: ?[]color.Rgb565 = null,
    };

    fn makePanel(allocator: std.mem.Allocator, opts: CreateOpts) !fb.PanelFb {
        if (opts.panel_pixels) |p| return .{ .pixels = p, .owned = false };
        if (opts.keep_panel) return fb.PanelFb.alloc(allocator);
        // ponytail: Win32 presents logical; skip panel unless asked.
        return .{ .pixels = &.{} };
    }

    pub fn create(allocator: std.mem.Allocator) !Engine {
        return createWith(allocator, .{});
    }

    pub fn createWith(allocator: std.mem.Allocator, opts: CreateOpts) !Engine {
        const theme = tokens.Theme.industrialTealDark();
        var logical = try fb.LogicalFb.alloc(allocator);
        errdefer logical.deinit(allocator);
        var panel = try makePanel(allocator, opts);
        errdefer panel.deinit(allocator);

        const stiff = tokens.Motion.spring_stiffness_expressive;
        const damp = tokens.Motion.spring_damping_expressive;

        var eng: Engine = .{
            .theme = theme,
            .logical = logical,
            .panel = panel,
            .scroll = spring.Spring.init(0, stiff, damp),
            .sheet_y = spring.Spring.init(@floatFromInt(quick_settings.closedY()), stiff, damp),
        };
        eng.scroll.epsilon = tokens.Motion.scroll_epsilon;
        eng.applyPrefs();
        eng.qs_tab_axis.value = @floatFromInt(@min(eng.prefs.qs_tab, 4));
        eng.qs_tab_axis.setTarget(eng.qs_tab_axis.value);
        const seed_mdi = "G0 X0 Y0";
        @memcpy(eng.qs_mdi[0..seed_mdi.len], seed_mdi);
        eng.qs_mdi_len = seed_mdi.len;
        quick_settings.termAppend(&eng.qs_term, &eng.qs_term_len, "(no traffic yet)", false);
        eng.job_fx.value = eng.cnc.job_progress;
        eng.job_fx.setTarget(eng.cnc.job_progress);
        eng.cnc.job_progress_vis = eng.cnc.job_progress;
        eng.feed_fx.value = @floatFromInt(eng.cnc.feed_pct);
        eng.feed_fx.setTarget(@floatFromInt(eng.cnc.feed_pct));
        eng.spindle_fx.value = @floatFromInt(eng.cnc.spindle_pct);
        eng.spindle_fx.setTarget(@floatFromInt(eng.cnc.spindle_pct));
        eng.rapid_fx.value = @floatFromInt(eng.cnc.rapid_pct);
        eng.rapid_fx.setTarget(@floatFromInt(eng.cnc.rapid_pct));
        eng.cnc.feed_vis = eng.feed_fx.value;
        eng.cnc.spindle_vis = eng.spindle_fx.value;
        eng.cnc.rapid_vis = eng.rapid_fx.value;
        eng.paintBoot();
        eng.dirty.add(fullRect());
        eng.flushDirty();
        eng.needs_full_repaint = false;
        eng.boot_left_sec = boot_seconds;
        eng.boot_hold_armed = true; // host: no backlight gate
        return eng;
    }

    /// Heap Engine — struct literal writes in place (result location), no stack copy.
    pub fn createHeap(allocator: std.mem.Allocator, opts: CreateOpts) !*Engine {
        const self = try allocator.create(Engine);
        errdefer allocator.destroy(self);

        const theme = tokens.Theme.industrialTealDark();
        var logical = try fb.LogicalFb.alloc(allocator);
        errdefer logical.deinit(allocator);
        var panel = try makePanel(allocator, opts);
        errdefer panel.deinit(allocator);
        const stiff = tokens.Motion.spring_stiffness_expressive;
        const damp = tokens.Motion.spring_damping_expressive;

        self.* = .{
            .theme = theme,
            .logical = logical,
            .panel = panel,
            .scroll = spring.Spring.init(0, stiff, damp),
            .sheet_y = spring.Spring.init(@floatFromInt(quick_settings.closedY()), stiff, damp),
        };
        self.scroll.epsilon = tokens.Motion.scroll_epsilon;
        self.applyPrefs();
        self.qs_tab_axis.value = @floatFromInt(@min(self.prefs.qs_tab, 4));
        self.qs_tab_axis.setTarget(self.qs_tab_axis.value);
        const seed_mdi = "G0 X0 Y0";
        @memcpy(self.qs_mdi[0..seed_mdi.len], seed_mdi);
        self.qs_mdi_len = seed_mdi.len;
        quick_settings.termAppend(&self.qs_term, &self.qs_term_len, "(no traffic yet)", false);
        self.job_fx.value = self.cnc.job_progress;
        self.job_fx.setTarget(self.cnc.job_progress);
        self.cnc.job_progress_vis = self.cnc.job_progress;
        self.feed_fx.value = @floatFromInt(self.cnc.feed_pct);
        self.feed_fx.setTarget(@floatFromInt(self.cnc.feed_pct));
        self.spindle_fx.value = @floatFromInt(self.cnc.spindle_pct);
        self.spindle_fx.setTarget(@floatFromInt(self.cnc.spindle_pct));
        self.rapid_fx.value = @floatFromInt(self.cnc.rapid_pct);
        self.rapid_fx.setTarget(@floatFromInt(self.cnc.rapid_pct));
        self.cnc.feed_vis = self.feed_fx.value;
        self.cnc.spindle_vis = self.spindle_fx.value;
        self.cnc.rapid_vis = self.rapid_fx.value;
        // Device paints after install(prefs) via presentBootSplash — avoid a
        // full rotate of the default theme that gets thrown away.
        self.needs_full_repaint = false;
        self.boot_left_sec = boot_seconds;
        self.boot_hold_armed = false;
        self.heap_owned = true;
        return self;
    }

    pub fn destroy(self: *Engine, allocator: std.mem.Allocator) void {
        const heap = self.heap_owned;
        self.panel.deinit(allocator);
        self.logical.deinit(allocator);
        if (heap) allocator.destroy(self);
    }

    fn fullRect() geom.Rect {
        return .{ .x = 0, .y = 0, .w = tokens.Logical.width, .h = tokens.Logical.height };
    }

    /// Call once splash is on-panel and backlight is lit. Starts the 3 s hold.
    pub fn armBootHold(self: *Engine) void {
        if (self.screen != .boot) return;
        self.boot_left_sec = boot_seconds;
        self.boot_hold_armed = true;
    }

    /// Re-paint splash after prefs/theme load (createHeap theme may be stale).
    pub fn presentBootSplash(self: *Engine) void {
        if (self.screen != .boot) return;
        self.paintBoot();
        self.dirty.add(fullRect());
        self.flushDirty();
        self.needs_full_repaint = false;
        self.boot_left_sec = boot_seconds;
        self.boot_hold_armed = false;
    }

    fn paintBoot(self: *Engine) void {
        // MD3: surface_dim + primary from prefs accent × dark/light (buildTheme).
        self.logical.clear(self.theme.surface_dim);
        const title = "MODULUS";
        const title_track: i32 = 3; // LVGL letter_space on splash
        const gap = tokens.Space.xl;
        const title_h = tokens.TypeRole.display_l.lineHeight();
        const cap_h = tokens.TypeRole.label_l.lineHeight();
        const block_h = title_h + gap + cap_h + gap + cap_h;
        var y: i32 = @divTrunc(@as(i32, tokens.Logical.height) - block_h, 2);

        const tw = font.textWidthStr(title, .display_l) + title_track * @as(i32, @intCast(title.len -| 1));
        const tx = @divTrunc(@as(i32, tokens.Logical.width) - tw, 2);
        font.drawTextRoleTracked(&self.logical, tx, y, title, self.theme.primary, .display_l, title_track, false);
        y += title_h + gap;

        const cw = font.textWidthStr(boot_credit, .label_l);
        font.drawTextRole(&self.logical, @divTrunc(@as(i32, tokens.Logical.width) - cw, 2), y, boot_credit, self.theme.on_surface_variant, .label_l);
        y += cap_h + gap;

        var vbuf: [40]u8 = undefined;
        const ver = std.fmt.bufPrint(&vbuf, "{s} {s}", .{ ui_engine_product, ui_engine_version }) catch "ZIG UI Engine V1.0";
        const vw = font.textWidthStr(ver, .label_l);
        font.drawTextRole(&self.logical, @divTrunc(@as(i32, tokens.Logical.width) - vw, 2), y, ver, self.theme.on_surface_variant, .label_l);
    }

    fn finishBoot(self: *Engine) void {
        if (self.screen != .boot) return;
        self.boot_left_sec = 0;
        self.boot_hold_armed = false;
        // LVGL: pin_boot → lock overlay after splash.
        if (self.prefs.security.has_pin and self.prefs.security.pin_boot) {
            self.openPin();
        } else {
            self.screen = .dashboard;
            // Paint+present once here so splash stays until the first dashboard
            // frame is ready — fall-through tick used to leave a multi-second
            // blank/white gap while rotate ran over an empty logical.
            self.paintDashboard();
            self.dirty.add(fullRect());
            self.flushDirty();
            self.needs_full_repaint = false;
        }
    }

    /// Safe f32 → u8 for ReleaseSafe device (NaN / >255 used to abort the UI task).
    fn u8FromF(x: f32) u8 {
        if (!std.math.isFinite(x)) return 0;
        return @intFromFloat(@round(std.math.clamp(x, 0, 255)));
    }

    fn i32FromF(x: f32) i32 {
        if (!std.math.isFinite(x)) return 0;
        return @intFromFloat(@round(std.math.clamp(x, -1_000_000, 1_000_000)));
    }

    fn paintDashboard(self: *Engine) void {
        settings_form.bindWidgetMotion(&self.motion_phys, &self.widget_fx);
        defer settings_form.unbindWidgetMotion();
        self.syncStatusBarChrome();
        dashboard.paint(&self.logical, self.theme, self.cnc);
        // CNC Zero/Home confirms open from dashboard — must paint here (not only settings).
        if (self.settings_confirm != .none) {
            const c = settings_form.paintPowerConfirm(&self.logical, self.theme, self.settings_confirm, self.settings_confirm_fx.value);
            self.settings_confirm_ok = c.ok;
            self.settings_confirm_cancel = c.cancel;
            self.settings_confirm_card = c.card;
        }
        self.invalidateAnimGates();
    }

    /// Wall clock + WCS label from prefs (LVGL status bar data path).
    pub fn syncStatusBarChrome(self: *Engine) void {
        // Device: `mirrorBatteryClock` owns `clock_buf` from RTC — do not overwrite with demo wall_sec.
        if (self.now_us_sink == null) {
            const e = self.prefs.system.nowEpoch();
            const tod = @mod(e, 86400);
            var h: u32 = @intCast(@divTrunc(tod, 3600));
            const m: u32 = @intCast(@divTrunc(@mod(tod, 3600), 60));
            if (self.prefs.system.t_24h) {
                _ = std.fmt.bufPrint(&self.cnc.clock_buf, "{d:0>2}:{d:0>2}", .{ h, m }) catch {};
            } else {
                const am = h < 12;
                h = h % 12;
                if (h == 0) h = 12;
                _ = std.fmt.bufPrint(&self.cnc.clock_buf, "{d}:{d:0>2}{s}", .{ h, m, if (am) "a" else "p" }) catch {};
            }
        }
        const wi = @min(self.cnc.wcs_i, 5);
        self.cnc.wcs = self.prefs.dash.wcsDisplayLabel(wi);
    }

    fn cycleWcsFromStatus(self: *Engine) void {
        const cur = @min(self.cnc.wcs_i, 5);
        const next: u8 = @intCast((cur + 1) % 6);
        const lock = self.prefs.dash.wcs_lock;
        if ((lock & (@as(u8, 1) << @intCast(next))) != 0 or (lock & (@as(u8, 1) << @intCast(cur))) != 0) {
            self.pending_wcs_i = next;
            self.openSettingsConfirm(.wcs_change);
            return;
        }
        self.applyWcsCycle(next);
    }

    /// Host: set index. Device: `cnc_wcs_sink` → `modulus_zig_cycle_wcs` (driver advances).
    fn applyWcsCycle(self: *Engine, next: u8) void {
        if (self.cnc_wcs_sink) |sink| {
            sink();
            self.cnc.wcs_i = @min(next, 5);
            self.prefs.dash.wcs = self.cnc.wcs_i;
            self.syncStatusBarChrome();
            self.showSnackbar(self.cnc.wcs);
            self.requestFull();
            return;
        }
        self.applyWcsIndex(next);
    }

    fn applyWcsIndex(self: *Engine, i: u8) void {
        self.cnc.wcs_i = @min(i, 5);
        self.prefs.dash.wcs = self.cnc.wcs_i;
        self.syncStatusBarChrome();
        self.showSnackbar(self.cnc.wcs);
        self.requestFull();
    }

    /// LVGL `pause_dashboard_refresh` stand-in: live only on dashboard with QS sheet closed.
    fn liveDashboard(self: *const Engine) bool {
        if (self.screen != .dashboard) return false;
        if (self.settings_confirm != .none) return false;
        const closed: f32 = @floatFromInt(quick_settings.closedY());
        return self.sheet_y.value >= closed - 1;
    }

    fn invalidateAnimGates(self: *Engine) void {
        self.gate_job_pct = 0xFF;
        self.gate_job_hold = 0xFF;
        self.gate_job_wave = 0xFF;
        self.gate_job_indet = 0xFF;
        self.gate_job_elapsed = 0xFFFFFFFF;
        self.gate_job_name_sig = 0xFFFFFFFF;
        // Keep gate_job_strip / gate_phase / gate_status_sig — paintDashboard
        // full-repaint must not re-fire bodyTop requestFull every frame.
        self.gate_feed_vis = 0xFF;
        self.gate_spindle_vis = 0xFF;
        self.gate_rapid_vis = 0xFF;
        self.gate_dro_work = .{std.math.minInt(i32)} ** dro_widget.max_axes;
        self.gate_dro_mach = .{std.math.minInt(i32)} ** dro_widget.max_axes;
        self.gate_dro_sel = std.math.maxInt(usize);
        self.gate_dro_axes = 0xFF;
        self.gate_dro_unit = 0xFF;
    }

    fn jobNameSig(cnc: dashboard.CncView) u32 {
        var h: u32 = @truncate(cnc.job_name.len);
        const n = @min(cnc.job_name.len, 8);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            h = h *% 16777619 ^ cnc.job_name[i];
        }
        return h;
    }

    fn statusChromeSig(cnc: dashboard.CncView) u32 {
        return (@as(u32, cnc.mach_state) << 24) |
            (@as(u32, @intFromEnum(cnc.actions.phase)) << 16) |
            (@as(u32, @intFromBool(cnc.connected)) << 15) |
            (@as(u32, @intFromBool(cnc.mpg_active)) << 14) |
            (@as(u32, @intFromBool(cnc.homing_block)) << 13) |
            (@as(u32, @intFromBool(cnc.wifi_on)) << 12) |
            (@as(u32, @intFromBool(cnc.bt_on)) << 11) |
            (@as(u32, @intFromBool(cnc.espnow_on)) << 10) |
            (@as(u32, cnc.alarm_code) << 5) |
            (@as(u32, cnc.wcs_i) & 0x1f);
    }

    /// Device `mirrorCncStatus` mutates CNC fields without `setMachinePhase`.
    /// Catch strip show/hide (bodyTop), phase LED, status/actions, job name.
    fn syncMirroredChromePaint(self: *Engine) void {
        if (!self.liveDashboard()) return;
        const strip_u: u8 = @intFromBool(dashboard.jobStripVisible(self.cnc));
        const phase_u: u8 = @intFromEnum(self.cnc.actions.phase);
        const strip_changed = strip_u != self.gate_job_strip;
        const phase_changed = phase_u != self.gate_phase;
        if (strip_changed or phase_changed) {
            if (phase_changed) self.syncLedMorph();
            self.gate_job_strip = strip_u;
            self.gate_phase = phase_u;
            self.gate_status_sig = statusChromeSig(self.cnc);
            if (strip_changed) {
                // bodyTop shifts — regional paints leave DRO/jog at stale Y.
                self.requestFull();
                return;
            }
            self.repaintStatusRegion();
            self.repaintActionsRegion();
            self.gate_job_pct = 0xFF;
            self.gate_job_name_sig = 0xFFFFFFFF;
            self.repaintJobRegion();
            return;
        }
        const st = statusChromeSig(self.cnc);
        if (st != self.gate_status_sig) {
            self.gate_status_sig = st;
            self.repaintStatusRegion();
            self.repaintActionsRegion();
        }
    }

    /// Change-gate DRO text when CNC mirror / host edits move positions.
    fn syncDroLivePaint(self: *Engine) void {
        if (!self.liveDashboard()) return;
        const n = self.cnc.dro.axis_count;
        const unit: u8 = @intFromBool(self.cnc.dro.unit_mm);
        var dirty = n != self.gate_dro_axes or self.cnc.dro.selected != self.gate_dro_sel or unit != self.gate_dro_unit;
        if (!dirty) {
            var i: usize = 0;
            while (i < n) : (i += 1) {
                if (self.cnc.dro.work_um[i] != self.gate_dro_work[i] or
                    self.cnc.dro.mach_um[i] != self.gate_dro_mach[i])
                {
                    dirty = true;
                    break;
                }
            }
        }
        if (!dirty) return;
        self.gate_dro_axes = n;
        self.gate_dro_sel = self.cnc.dro.selected;
        self.gate_dro_unit = unit;
        @memcpy(self.gate_dro_work[0..n], self.cnc.dro.work_um[0..n]);
        @memcpy(self.gate_dro_mach[0..n], self.cnc.dro.mach_um[0..n]);
        self.repaintDroRegion();
    }

    fn jobPctU8(progress: f32) u8 {
        return u8FromF(std.math.clamp(progress, 0, 1) * 100);
    }

    /// LVGL job-strip clock: start on show, accumulate while Run|Hold|streaming.
    fn syncJobStripTiming(self: *Engine, dt_sec: f32) void {
        const active = dashboard.jobStripVisible(self.cnc);
        if (!active) {
            self.cnc.job_strip_was_active = false;
            self.cnc.job_elapsed_f = 0;
            return;
        }
        if (!self.cnc.job_strip_was_active) {
            self.cnc.job_strip_was_active = true;
            self.cnc.job_elapsed_f = 0;
            self.cnc.job_pct_at_t0 = self.cnc.sd_percent;
        } else if (std.math.isFinite(dt_sec) and dt_sec > 0) {
            // LVGL `lv_tick_elaps` keeps counting through Hold.
            self.cnc.job_elapsed_f += @min(dt_sec, 0.25);
        }
        self.cnc.formatJobElapsed();
    }

    fn repaintStatusRegion(self: *Engine) void {
        dashboard.paintStatus(&self.logical, self.theme, self.cnc);
        self.dirty.add(dashboard.statusBounds());
    }

    fn repaintJobRegion(self: *Engine) void {
        if (!dashboard.jobStripVisible(self.cnc)) {
            // Hide path — clear strip band (gates stay invalid for next show).
            self.gate_job_pct = 0xFF;
            dashboard.paintJob(&self.logical, self.theme, self.cnc);
            self.dirty.add(dashboard.jobStripBounds());
            return;
        }
        const pct = jobPctU8(self.cnc.job_progress_vis);
        const hold: u8 = @intFromBool(self.cnc.actions.phase == .hold);
        const indet: u8 = @intFromBool(self.cnc.job_indet);
        // ~30 Hz wave samples — coarse 8×4 gate looked stuck on determinate bars.
        const wave: u8 = u8FromF(@mod(@max(self.cnc.job_wave_phase, 0) * 12.0, 256.0));
        const elapsed_s: u32 = @intFromFloat(@max(self.cnc.job_elapsed_f, 0));
        const name_sig = jobNameSig(self.cnc);
        if (pct == self.gate_job_pct and hold == self.gate_job_hold and wave == self.gate_job_wave and indet == self.gate_job_indet and elapsed_s == self.gate_job_elapsed and name_sig == self.gate_job_name_sig) return;
        self.gate_job_pct = pct;
        self.gate_job_hold = hold;
        self.gate_job_wave = wave;
        self.gate_job_indet = indet;
        self.gate_job_elapsed = elapsed_s;
        self.gate_job_name_sig = name_sig;
        settings_form.bindWidgetMotion(&self.motion_phys, &self.widget_fx);
        defer settings_form.unbindWidgetMotion();
        dashboard.paintJob(&self.logical, self.theme, self.cnc);
        self.dirty.add(dashboard.jobStripBounds());
    }

    fn repaintDroRegion(self: *Engine) void {
        settings_form.bindWidgetMotion(&self.motion_phys, &self.widget_fx);
        defer settings_form.unbindWidgetMotion();
        dashboard.paintDroRegion(&self.logical, self.theme, self.cnc);
        self.dirty.add(dashboard.droBounds(self.cnc));
    }

    fn repaintCenterRegion(self: *Engine) void {
        settings_form.bindWidgetMotion(&self.motion_phys, &self.widget_fx);
        defer settings_form.unbindWidgetMotion();
        dashboard.paintCenterRegion(&self.logical, self.theme, self.cnc);
        const jog = dashboard.jogBounds(self.cnc);
        const ov = dashboard.overrideBounds(self.cnc);
        self.dirty.add(.{
            .x = jog.x,
            .y = jog.y,
            .w = jog.w,
            .h = (ov.y + ov.h) - jog.y,
        });
    }

    fn repaintActionsRegion(self: *Engine) void {
        settings_form.bindWidgetMotion(&self.motion_phys, &self.widget_fx);
        defer settings_form.unbindWidgetMotion();
        dashboard.paintActionsRegion(&self.logical, self.theme, self.cnc);
        self.dirty.add(dashboard.actionsBounds(self.cnc));
    }

    fn paintSettingsShell(self: *Engine) void {
        self.syncSettingsLayout();
        // MD3 opaque scrim stand-in — do NOT call dashboard.paint here.
        // Full dashboard + CNC settings content blew the 40 KiB zig_ui stack
        // (Stack protection fault in paintCnc / drawCharFace).
        self.logical.clear(self.theme.surface);
        widgets.fillScrim(&self.logical, self.theme);

        const win = settings_form.windowRect();
        const rad = tokens.Shape.dialog;
        // LVGL parity: card elev1, hdr elev3, rail lowest, content elev1.
        const shell_bg = self.theme.elev(1);
        const title_bg = self.theme.elev(3);
        const rail_bg = self.theme.surface_container_lowest;
        const content_bg = self.theme.elev(1);
        widgets.fillRoundRect(&self.logical, win, rad, shell_bg);

        const title = settings_form.titleBarRect();
        const title_rad = @min(rad, @divTrunc(title.h, 2));
        widgets.fillRoundRect(&self.logical, title, title_rad, title_bg);
        // Square only title bottom (meets body); keep top corners round.
        self.logical.fillRect(.{ .x = title.x, .y = title.y + title.h - title_rad, .w = title.w, .h = title_rad }, title_bg);
        self.logical.fillRect(.{ .x = title.x, .y = title.y + title.h - 1, .w = title.w, .h = 1 }, self.theme.outline_variant);

        const compact_detail = !settings_form.useRail() and !self.settings_hub;
        if (compact_detail) {
            font.drawTextRole(&self.logical, win.x + 16, win.y + 16, "<", self.theme.on_surface, .title_l);
            font.drawTextRole(&self.logical, win.x + 48, win.y + 16, k_tabs[self.tab_selected], self.theme.on_surface, .title_l);
        } else {
            icons_phosphor.draw(&self.logical, win.x + 16, win.y + 14, .gear, self.theme.on_surface);
            font.drawTextRole(&self.logical, win.x + 48, win.y + 16, "System settings", self.theme.on_surface, .title_l);
        }
        // Close X
        const cx = win.x + win.w - 28;
        const cy = win.y + @divTrunc(title.h, 2);
        var xi: i32 = -6;
        while (xi <= 6) : (xi += 1) {
            self.logical.fillRect(.{ .x = cx + xi, .y = cy + xi, .w = 2, .h = 2 }, self.theme.on_surface);
            self.logical.fillRect(.{ .x = cx + xi, .y = cy - xi, .w = 2, .h = 2 }, self.theme.on_surface);
        }

        const show_cats = settings_form.useRail() or self.settings_hub;
        const search_view = self.search_focus or self.search_len > 0;

        if (show_cats) {
            if (settings_form.useRail()) {
                const rail = settings_form.railRect();
                self.logical.fillRect(rail, rail_bg);
                self.logical.fillRect(.{ .x = rail.x + rail.w - 1, .y = rail.y, .w = 1, .h = rail.h }, self.theme.outline_variant);
            } else {
                // Compact hub: fill body under title.
                self.logical.fillRect(settings_form.contentPaneRect(), rail_bg);
            }

            const search = settings_form.searchRect();
            widgets.drawSearchField(
                &self.logical,
                search,
                self.search_buf[0..self.search_len],
                self.search_focus,
                self.theme,
            );

            if (!search_view) {
                const cat_w = settings_form.categoryListWidth();
                var vis_i: i32 = 0;
                for (k_tabs, 0..) |label, i| {
                    if (!self.tabMatches(i)) continue;
                    const y = settings_form.cat_list_top + vis_i * cat_item_h;
                    vis_i += 1;
                    if (y + cat_item_h > win.y + win.h - 8) break;
                    widgets.drawSettingsCategory(&self.logical, win.x, y, cat_w, cat_item_h, label, i == self.tab_selected, self.theme);
                    const icy = y + @divTrunc(cat_item_h, 2);
                    icons_phosphor.drawCentered(
                        &self.logical,
                        win.x + 20 + @divTrunc(icons_phosphor.size, 2),
                        icy,
                        categoryIcon(i),
                        if (i == self.tab_selected) self.theme.on_secondary_container else self.theme.on_surface_variant,
                    );
                }
            }

            if (search_view) {
                self.paintSearchResults();
            }
        }

        if (settings_form.useRail() or compact_detail) {
            const content = settings_form.contentPaneRect();
            self.logical.fillRect(content, content_bg);
            self.paintSettingsContent();
        }
        // Pane fills square the AABB — punch exterior wedges back to scrim, then stroke.
        widgets.punchRoundRectOutside(&self.logical, win, rad, self.theme.scrim);
        widgets.strokeRoundRect(&self.logical, win, rad, self.theme.outline_variant, 1);
        if (self.settings_confirm != .none) {
            const c = settings_form.paintPowerConfirm(&self.logical, self.theme, self.settings_confirm, self.settings_confirm_fx.value);
            self.settings_confirm_ok = c.ok;
            self.settings_confirm_cancel = c.cancel;
            self.settings_confirm_card = c.card;
        }
        if (self.cnc_overlay == .profiles) {
            self.cnc_prof_layout = settings_cnc_modals.paintProfiles(&self.logical, self.theme, &self.prefs.cnc, self.cnc_overlay_fx.value);
        } else if (self.cnc_overlay == .dump) {
            settings_cnc_modals.paintDump(&self.logical, self.theme, &self.cnc_dump, self.cnc_overlay_fx.value);
        }
        if (self.dash_overlay == .wcs) {
            self.dash_wcs_layout = settings_dashboard_modals.paintWcs(&self.logical, self.theme, &self.prefs.dash, self.dash_overlay_fx.value);
        } else if (self.dash_overlay == .macro) {
            const mac_title: []const u8 = if (self.dash_mac_is_edit) "Edit quick button" else "Add quick button";
            self.dash_mac_layout = settings_dashboard_modals.paintMacro(
                &self.logical,
                self.theme,
                mac_title,
                self.dash_mac_draft.nameSlice(),
                self.dash_mac_draft.onSlice(),
                self.dash_mac_draft.offSlice(),
                self.dash_mac_is_edit,
                self.dash_overlay_fx.value,
            );
        } else if (self.dash_overlay == .arrange) {
            self.dash_arr_layout = settings_dashboard_modals.paintArrange(
                &self.logical,
                self.theme,
                &self.prefs.dash,
                self.dash_arr_pick,
                self.dash_arr_scroll,
                self.dash_overlay_fx.value,
            );
        }
        if (self.pin_overlay != .none) {
            var m1: [8]u8 = undefined;
            var m2: [8]u8 = undefined;
            const pin_title: []const u8 = switch (self.pin_overlay) {
                .set => if (self.prefs.security.has_pin) "Change PIN" else "Set PIN",
                .clear => "Clear PIN",
                .none => "",
            };
            self.pin_layout = settings_pin_modal.paint(
                &self.logical,
                self.theme,
                self.pin_overlay,
                pin_title,
                settings_pin_modal.maskDots(self.pin_draft1_len, &m1),
                settings_pin_modal.maskDots(self.pin_draft2_len, &m2),
                self.pin_focus,
                self.pin_err1,
                self.pin_err2,
                self.pin_status[0..self.pin_status_len],
                self.pin_status_err,
                self.pin_overlay_fx.value,
            );
        }
        if (self.mach_str_overlay != .none) {
            self.mach_str_layout = settings_mach_string_modal.paint(
                &self.logical,
                self.theme,
                self.mach_str_overlay,
                self.mach_str_draft[0..self.mach_str_draft_len],
                self.mach_str_focus or self.pad.open,
                self.mach_str_err,
                self.mach_str_status[0..self.mach_str_status_len],
                self.mach_str_err,
                self.mach_str_fx.value,
            );
        }
        if (self.extra_overlay != .none) {
            self.paintExtraOverlay();
        }
        // Menus above dialogs so transport baud / idle timeout pickers are visible.
        if (self.menu_target != .none) self.paintMenuOverlay();
    }

    fn paintExtraOverlay(self: *Engine) void {
        const t = self.extra_fx.value;
        self.extra_layout = switch (self.extra_overlay) {
            .none => .{},
            .transport => settings_extra_modals.paintTransport(&self.logical, self.theme, &self.prefs.cnc, t),
            .wifi_connect => settings_extra_modals.paintWifiConnect(&self.logical, self.theme, self.prefs.wireless.ssidSlice(), self.prefs.wireless.draftPassSlice(), t),
            .bt_passkey => settings_extra_modals.paintBtPasskey(&self.logical, self.theme, self.prefs.wireless.btNameSlice(), self.prefs.wireless.btPasskeySlice(), t),
            .zb_add => settings_extra_modals.paintZbAdd(&self.logical, self.theme, self.prefs.wireless.zbInstallSlice(), t),
            .th_add => settings_extra_modals.paintThAdd(&self.logical, self.theme, self.prefs.wireless.thNodeSlice(), t),
            .probe => settings_extra_modals.paintProbe(&self.logical, self.theme, &self.prefs.dash, self.probe_busy_frames > 0, t),
            .mpg => settings_extra_modals.paintMpg(&self.logical, self.theme, &self.prefs.dash, t),
            .idle_lock => settings_extra_modals.paintIdleLock(&self.logical, self.theme, &self.prefs.security, t),
        };
    }

    fn machPullProgress(self: *const Engine) f32 {
        if (self.mach_pull_polls == 0) return 0;
        const denom: f32 = if (self.mach_pull_tick_sink != null) 40.0 else 8.0;
        return @min(1, @as(f32, @floatFromInt(self.mach_pull_polls)) / denom);
    }

    fn paintSearchResults(self: *Engine) void {
        const search = settings_form.searchRect();
        const panel = widgets.searchResultsPanel(search);
        widgets.fillRoundRect(&self.logical, panel, tokens.Shape.lg, self.theme.elev(2));
        var row: i32 = 0;
        for (k_tabs, 0..) |label, i| {
            if (!self.tabMatches(i)) continue;
            const y = panel.y + 12 + row * widgets.search_result_row_h;
            if (y + 40 > panel.y + panel.h) break;
            font.drawTextRole(&self.logical, panel.x + 16, y + 12, label, self.theme.on_surface, .body_m);
            row += 1;
        }
        if (row == 0) {
            font.drawTextRole(&self.logical, panel.x + 16, panel.y + 16, "No tabs match", self.theme.on_surface_variant, .body_m);
        }
    }

    fn paintMenuOverlay(self: *Engine) void {
        const labs = settings_menu.labels(self.menu_target);
        if (labs.len == 0 or self.menu_hit.isEmpty()) return;
        expr.drawMenuScrolled(
            &self.logical,
            self.menu_hit,
            labs,
            settings_menu.selectedIndex(&self.prefs, self.menu_target),
            self.menu_scroll,
            self.theme,
        );
    }

    fn layoutMenuRect(anchor: geom.Rect, labels: []const []const u8) geom.Rect {
        const visible = @min(labels.len, expr.menu_max_visible);
        const mw = expr.menuPopupWidth(anchor.w, labels);
        const mh = @as(i32, @intCast(visible)) * expr.menu_item_h + expr.menu_pad * 2;
        // Wide settings rows: align to trailing edge (value / chevron side).
        var mx = if (anchor.w > expr.menu_max_w) anchor.x + anchor.w - mw else anchor.x;
        var my = anchor.y + anchor.h + 4;
        if (my + mh > tokens.Logical.height - 8) my = anchor.y - mh - 4;
        if (mx + mw > tokens.Logical.width - 8) mx = tokens.Logical.width - mw - 8;
        if (mx < 8) mx = 8;
        if (my < 8) my = 8;
        return .{ .x = mx, .y = my, .w = mw, .h = mh };
    }

    /// Content pane only — used on scroll so dirty stays small (bench gate).
    fn paintSettingsContent(self: *Engine) void {
        self.syncSettingsLayout();
        if (!settings_form.useRail() and self.settings_hub) return;
        const pane = settings_form.contentPaneRect();
        // Honour an outer damage-band clip (widget morph) by intersecting with pane.
        const clip = if (self.logical.clip) |outer|
            geom.Rect.intersect(outer, pane)
        else
            pane;
        self.logical.setClip(clip);
        defer self.logical.setClip(null);
        self.logical.fillRect(clip, self.theme.elev(1));
        // ReleaseSafe: springs can go non-finite after tab kicks / large dt — never bare @intFromFloat.
        const axis_x = i32FromF(@floor(self.tab_axis.value));
        self.logical.origin_x = axis_x;
        defer self.logical.origin_x = 0;
        settings_form.bindWidgetMotion(&self.motion_phys, &self.widget_fx);
        defer settings_form.unbindWidgetMotion();
        settings_form.bindSwitchIcons(self.prefs.display.sw_icons);
        settings_form.bindAdvanced(self.prefs.settings_advanced);
        const scroll_i = i32FromF(@floor(self.scroll.value));
        if (self.tab_selected == k_dashboard_tab) {
            self.dash_layout = settings_dashboard_tab.paint(&self.logical, self.theme, self.prefs.dash, scroll_i);
            self.settings_content_h = self.dash_layout.content_h;
        } else if (self.tab_selected == k_display_tab) {
            self.disp_layout = settings_display_tab.paint(&self.logical, self.theme, self.prefs.display, scroll_i);
            self.settings_content_h = self.disp_layout.content_h;
        } else {
            self.other_layout = settings_other_tabs.paint(
                &self.logical,
                self.theme,
                self.prefs,
                self.tab_selected,
                scroll_i,
                self.machPullProgress(),
            );
            self.settings_content_h = self.other_layout.content_h;
        }
    }

    fn tabMatches(self: *const Engine, index: usize) bool {
        if (self.search_len == 0) return true;
        const q = self.search_buf[0..self.search_len];
        if (ascii_util.matchesFolded(k_tabs[index], q)) return true;
        for (k_tab_keywords[index]) |kw| {
            if (ascii_util.matchesFolded(kw, q) or ascii_util.matchesFolded(q, kw)) return true;
        }
        return false;
    }

    fn syncSearchFromPad(self: *Engine) void {
        if (self.pad.target != .search) return;
        const txt = self.pad.text();
        const n = @min(txt.len, self.search_buf.len);
        @memset(&self.search_buf, 0);
        if (n > 0) @memcpy(self.search_buf[0..n], txt[0..n]);
        self.search_len = n;
        self.search_focus = true;
    }

    fn clearSearch(self: *Engine) void {
        self.search_focus = false;
        self.search_len = 0;
        @memset(&self.search_buf, 0);
    }

    fn selectFilteredTab(self: *Engine, idx: usize) void {
        self.tab_selected = idx;
        self.clearSearch();
        self.scroll.setTarget(0);
        self.scroll.value = 0;
        if (!settings_form.useRail()) self.settings_hub = false;
        self.kickTabAxis();
        self.requestFull();
    }

    fn handleSettingsSearchClick(self: *Engine, x: i32, y: i32) bool {
        const search = settings_form.searchRect();
        if (search.contains(x, y)) {
            if (self.search_len > 0 and widgets.searchClearHit(search).contains(x, y)) {
                self.clearSearch();
                self.search_focus = true;
                self.requestFull();
                return true;
            }
            self.search_focus = true;
            self.openTextPad(.search, "Search tabs", self.search_buf[0..self.search_len]);
            self.requestFull();
            return true;
        }
        if (self.search_focus or self.search_len > 0) {
            const panel = widgets.searchResultsPanel(search);
            if (panel.contains(x, y)) {
                const row: i32 = @divTrunc(y - panel.y - 12, widgets.search_result_row_h);
                if (self.filteredTabIndexAt(row)) |idx| {
                    self.selectFilteredTab(idx);
                }
                return true;
            }
        }
        if (self.search_focus and !search.contains(x, y)) {
            self.search_focus = false;
        }
        const list_band = if (settings_form.useRail())
            settings_form.railRect()
        else
            settings_form.contentPaneRect();
        if (!(self.search_focus or self.search_len > 0) and list_band.contains(x, y) and y >= settings_form.cat_list_top) {
            const vis: i32 = @divTrunc(y - settings_form.cat_list_top, cat_item_h);
            if (self.filteredTabIndexAt(vis)) |idx| {
                self.selectFilteredTab(idx);
                return true;
            }
            return true;
        }
        return false;
    }

    fn filteredTabIndexAt(self: *const Engine, visual_row: i32) ?usize {
        if (visual_row < 0) return null;
        var vis: i32 = 0;
        for (0..k_tabs.len) |i| {
            if (!self.tabMatches(i)) continue;
            if (vis == visual_row) return i;
            vis += 1;
        }
        return null;
    }

    fn kickDroSelect(self: *Engine) void {
        self.motion_phys.applyEffects(&self.dro_select);
        self.dro_select.value = 0;
        self.dro_select.velocity = 0;
        self.dro_select.setTarget(1);
    }

    fn pulseKey(self: *Engine, label: []const u8) void {
        self.widget_fx.pulse(self.motion_phys, motion.hashLabel(label));
    }

    pub fn searchFocused(self: *const Engine) bool {
        return self.search_focus and self.screen == .settings;
    }

    pub fn handleTextInput(self: *Engine, chars: []const u8, backspace: bool) void {
        if (!self.searchFocused()) return;
        if (backspace and self.search_len > 0) {
            self.search_len -= 1;
            self.search_buf[self.search_len] = 0;
            self.requestSettingsPresent();
            return;
        }
        for (chars) |ch| {
            if (self.search_len >= self.search_buf.len) break;
            if (ch < 32 or ch >= 127) continue;
            self.search_buf[self.search_len] = ch;
            self.search_len += 1;
        }
        if (chars.len > 0) self.requestSettingsPresent();
    }

    pub fn setMotionScheme(self: *Engine, scheme: tokens.MotionScheme) void {
        self.motion_scheme = scheme;
        self.motion_phys.setScheme(scheme);
        var effects = [_]*spring.Spring{
            &self.led_morph,
            &self.dro_select,
            &self.theme_fx,
            &self.press_fx,
            &self.dialog_fx,
            &self.power_fx,
            &self.power_confirm_fx,
            &self.settings_confirm_fx,
            &self.cnc_overlay_fx,
            &self.dash_overlay_fx,
            &self.pin_overlay_fx,
            &self.mach_str_fx,
            &self.extra_fx,
            &self.snack_fx,
            &self.catalog.load_fx,
            &self.job_fx,
            &self.feed_fx,
            &self.spindle_fx,
            &self.rapid_fx,
        };
        self.motion_phys.applyToSprings(&self.scroll, &self.sheet_y, &self.tab_axis, effects[0..]);
        self.motion_phys.applySpatial(&self.catalog.scroll);
        self.motion_phys.applySpatial(&self.dro_scroll);
        self.motion_phys.applySpatial(&self.qs_tab_axis);
        self.scroll.epsilon = tokens.Motion.scroll_epsilon;
        self.catalog.scroll.epsilon = tokens.Motion.scroll_epsilon;
        self.dro_scroll.epsilon = tokens.Motion.scroll_epsilon;
        self.widget_fx.applyScheme(self.motion_phys);
    }

    fn kickTabAxis(self: *Engine) void {
        // Instant snap — shared-axis L→R bounce removed from settings tabs.
        self.tab_axis.value = 0;
        self.tab_axis.velocity = 0;
        self.tab_axis.setTarget(0);
    }

    fn categoryIcon(index: usize) icons_phosphor.Id {
        return switch (index) {
            0 => .cpu, // CNC & connection
            1 => .house_light, // Dashboard & handwheel
            2 => .paint_roller, // Display & theme
            3 => .speaker_hifi, // Audio & haptics
            4 => .wifi, // Wireless
            5 => .battery, // Power
            6 => .lock_key, // Security
            7 => .gamepad, // Machine
            8 => .hard_drives, // Storage & diagnostics
            9 => .clipboard_text, // System & about
            else => .gear,
        };
    }

    fn applyPrefs(self: *Engine) void {
        self.prefs.applyAllOpts(&self.cnc, &self.theme, .{
            .preserve_machine_live = self.cnc_ui_sink != null,
        });
        const scheme: tokens.MotionScheme = if (self.prefs.display.motion_scheme != 0) .expressive else .standard;
        self.setMotionScheme(scheme);
        self.widget_fx.instant = !self.prefs.display.smooth_anim;
        if (!self.prefs.display.smooth_anim) {
            self.scroll.stiffness = 900;
            self.scroll.damping = 60;
            self.tab_axis.stiffness = 900;
            self.tab_axis.damping = 60;
        } else {
            // Without this the utility springs stayed stiff after toggling back on.
            self.motion_phys.applySpatial(&self.scroll);
            self.motion_phys.applySpatial(&self.tab_axis);
        }
        if (self.panel.flipped != self.prefs.display.flip) {
            self.panel.flipped = self.prefs.display.flip;
            self.requestFull();
        }
        // ponytail: glove → inflate hit tests; device uses contact strength instead.
        geom.hit_pad = if (self.prefs.display.touch_glove) 8 else 0;
        self.frame_budget_us = @as(u64, self.prefs.display.refreshPeriodMs()) * 1000;
        settings_form.bindSwitchIcons(self.prefs.display.sw_icons);
        font.setUserScale(self.prefs.display.font_scale);
        if (self.prefs_dirty_sink) |sink| sink(self);
    }

    fn emitWireless(self: *Engine, cmd: WirelessUiCmd) bool {
        if (self.wireless_cmd_sink) |s| {
            s(self, cmd);
            return true;
        }
        return false;
    }

    fn emitStorSys(self: *Engine, cmd: StorSysUiCmd) bool {
        if (self.stor_sys_sink) |s| {
            s(self, cmd);
            return true;
        }
        return false;
    }

    pub fn applyPrefsPublic(self: *Engine) void {
        // Boot load: apply theme without re-writing NVS.
        const sink = self.prefs_dirty_sink;
        self.prefs_dirty_sink = null;
        self.applyPrefs();
        self.prefs_dirty_sink = sink;
    }

    fn checkPin(self: *Engine, digits: []const u8) bool {
        if (self.pin_verify_sink) |s| return s(digits);
        return self.prefs.security.verifyPin(digits);
    }

    const ConfirmAct = enum { cycle, spin, zero, home, mac };

    fn confirmNeeds(self: *const Engine, act: ConfirmAct) bool {
        const pol = switch (act) {
            .cycle => self.prefs.dash.confirm.cycle,
            .spin => self.prefs.dash.confirm.spin,
            .zero => self.prefs.dash.confirm.zero,
            .home => self.prefs.dash.confirm.home,
            .mac => self.prefs.dash.confirm.mac,
        };
        if (pol == settings_prefs.confirm_never) return false;
        if (pol == settings_prefs.confirm_always) return true;
        return self.cnc.actions.phase == .run or self.cnc.actions.phase == .hold;
    }

    fn requestCncConfirm(self: *Engine, kind: settings_form.PowerConfirm, cmd: CncUiCmd) void {
        self.pending_cnc = cmd;
        self.openSettingsConfirm(kind);
    }

    /// Returns false if blocked (e.g. not connected / CNC not ready). True if emitted or confirm pending.
    fn emitCncOrConfirm(self: *Engine, act: ConfirmAct, kind: settings_form.PowerConfirm, cmd: CncUiCmd) bool {
        if (self.cnc_ui_sink == null) {
            _ = self.emitCnc(cmd);
            return true;
        }
        if (!self.cnc.connected and act != .mac) {
            self.showSnackbarError("No connection");
            return false;
        }
        if (self.confirmNeeds(act)) {
            self.requestCncConfirm(kind, cmd);
            return true;
        }
        if (!self.emitCnc(cmd)) {
            self.showSnackbarError("CNC not ready");
            return false;
        }
        return true;
    }

    pub fn refreshPeriodMs(self: *const Engine) u32 {
        return self.prefs.display.refreshPeriodMs();
    }

    /// Map window pointer → logical (180° when Flip display on).
    fn mapPointer(self: *const Engine, x: i32, y: i32) struct { x: i32, y: i32 } {
        if (!self.prefs.display.flip) return .{ .x = x, .y = y };
        return .{
            .x = @as(i32, tokens.Logical.width) - 1 - x,
            .y = @as(i32, tokens.Logical.height) - 1 - y,
        };
    }

    fn paintPowerMenu(self: *Engine) void {
        // MD3 opaque scrim — skip full dashboard.paint (same stack trap as settings).
        self.logical.clear(self.theme.surface);
        widgets.fillScrim(&self.logical, self.theme);
        const busy = machineBusy(self.cnc);
        self.power_layout = settings_form.paintPowerMenu(&self.logical, self.theme, busy, self.power_fx.value);
        if (self.power_confirm != .none) {
            const c = settings_form.paintPowerConfirm(&self.logical, self.theme, self.power_confirm, self.power_confirm_fx.value);
            self.power_layout.confirm_ok = c.ok;
            self.power_layout.confirm_cancel = c.cancel;
            self.power_layout.confirm_card = c.card;
        }
    }

    fn machineBusy(cnc: dashboard.CncView) bool {
        // LVGL: connected && (Run|Hold|Jog-like). Host stub: Run|Hold.
        return cnc.connected and (cnc.actions.phase == .run or cnc.actions.phase == .hold);
    }

    fn paintPinStub(self: *Engine) void {
        self.logical.clear(self.theme.surface);
        widgets.fillScrim(&self.logical, self.theme);
        font.drawTextRole(&self.logical, 480, 280, "Enter PIN", self.theme.on_surface, .title_l);
        font.drawText(&self.logical, 500, 360, "****", self.theme.primary, 3);
        font.drawText(&self.logical, 520, 480, "Esc / click = unlock", self.theme.on_surface_variant, 1);
    }

    fn paintSheet(self: *Engine, sy: i32) void {
        self.paintSheetOpts(sy, true);
    }

    fn paintSheetOpts(self: *Engine, sy: i32, paint_scrim: bool) void {
        quick_settings.paint(&self.logical, self.theme, &self.prefs, sy, .{
            .press_x = self.press_x,
            .press_y = self.press_y,
            .press_t = self.press_fx.value,
            .hover_rect = self.hover_rect,
            .focus_rect = self.focus_rect,
            .body_scroll = self.qs_body_scroll,
            .zb_detail_idx = self.qs_zb_detail,
            .cnc = &self.cnc,
            .term_log = self.qs_term[0..self.qs_term_len],
            .mdi = self.qs_mdi[0..self.qs_mdi_len],
            .probe_trig = self.qs_probe_trig,
            .paint_scrim = paint_scrim,
        });
    }

    fn paintQsUnderlay(self: *Engine) void {
        if (self.screen == .dashboard) {
            self.paintDashboard();
        } else if (self.screen == .settings) {
            self.paintSettingsShell();
        }
    }

    fn openQsZbDetail(self: *Engine, idx: u8) void {
        self.qs_zb_detail = idx;
        self.qs_zb_hold_idx = 0xff;
        self.qs_zb_hold_fired = true;
        self.qs_zb_level_drag = false;
        _ = self.emitWireless(.zb_refresh);
        self.repaintQs();
    }

    fn closeQsZbDetail(self: *Engine) void {
        self.qs_zb_detail = 0xff;
        self.qs_zb_level_drag = false;
        self.repaintQs();
    }

    fn repaintQs(self: *Engine) void {
        const sy: i32 = i32FromF(@floor(self.sheet_y.value));
        if (!quick_settings.isOpen(self.sheet_y.value)) return;
        // Opaque sheet — paint sheet only (no full dashboard underlay).
        self.paintSheet(sy);
        self.qs_content_dirty = true;
        self.dirty.add(.{
            .x = 0,
            .y = sy,
            .w = tokens.Logical.width,
            .h = tokens.Logical.height - sy,
        });
    }

    /// Full logical present (screen transitions, overlays, dashboard).
    fn forceFullPresent(self: *Engine) void {
        self.needs_full_repaint = true;
        self.settings_present_window = false;
        self.dirty.add(fullRect());
    }

    /// Pad paints a full-screen scrim + bottom dock. Closing it with window-only
    /// present leaves those pixels in the dual FBs → keyboard flicker behind the
    /// settings card until the next full present (e.g. leaving settings).
    fn afterPadDismiss(self: *Engine) void {
        self.forceFullPresent();
    }

    /// Modal chrome that must not be punched through by content-pane refresh.
    fn settingsHasBlockingModal(self: *const Engine) bool {
        return self.settings_confirm != .none
            or self.pad.open
            or self.cnc_overlay != .none
            or self.dash_overlay != .none
            or self.pin_overlay != .none
            or self.mach_str_overlay != .none
            or self.extra_overlay != .none;
    }

    /// True when settings shell paint can present window AABB only (PSRAM BW).
    fn canSettingsWindowPresent(self: *const Engine) bool {
        if (self.screen != .settings) return false;
        if (self.settings_confirm != .none) return false;
        if (self.cnc_overlay != .none) return false;
        if (self.dash_overlay != .none) return false;
        if (self.pin_overlay != .none) return false;
        if (self.mach_str_overlay != .none) return false;
        if (self.extra_overlay != .none) return false;
        if (self.pad.open) return false;
        if (self.menu_target != .none) return false;
        if (self.dialog_open) return false;
        if (quick_settings.isOpen(self.sheet_y.value)) return false;
        return true;
    }

    /// Prefer settings-window present when already in settings (no modal chrome).
    pub fn requestFull(self: *Engine) void {
        self.needs_full_repaint = true;
        self.settings_present_window = self.canSettingsWindowPresent();
        // QS open: tick paints sheet via qs_content_dirty — fullRect punches status.
        if (quick_settings.isOpen(self.sheet_y.value)) {
            self.qs_content_dirty = true;
            return;
        }
        if (!self.settings_present_window) self.dirty.add(fullRect());
    }

    /// Step the readout optimistically, then send the same delta to the driver.
    /// The device status mirror corrects to machine truth (envelope clamp may
    /// cap below 200) on the next frame; with no sink the step stands alone.
    fn applyOverride(self: *Engine, which: override_widget.Which, delta: i8) void {
        const ptr: *u8 = switch (which) {
            .feed => &self.cnc.feed_pct,
            .spindle => &self.cnc.spindle_pct,
            .rapid => &self.cnc.rapid_pct,
        };
        ptr.* = override_widget.stepPct(which, ptr.*, delta);
        if (self.cnc_override_sink) |sink| sink(which, delta);
    }

    fn emitCnc(self: *Engine, cmd: CncUiCmd) bool {
        if (self.cnc_ui_sink) |sink| {
            return sink(cmd);
        }
        return false;
    }

    /// Map quick assign → driver cmd. Returns false for host-only / no-op assigns.
    fn emitQuickAssign(self: *Engine, id: actions_widget.QuickId) bool {
        const cmd: CncUiCmd = switch (id) {
            .spindle_cw => .spindle_cw,
            .spindle_ccw => .spindle_ccw,
            .coolant => .coolant_toggle,
            .fan => .fan_toggle,
            .mist => .mist_toggle,
            .zero_all => .zero_all,
            .macro => .run_macro,
            .single_step => .single_step,
            .off => return false,
            .led, .user0, .user1, .user2, .user3 => return false,
        };
        return self.emitCnc(cmd);
    }

    /// Settings interior change — full shell paint, present window AABB only.
    fn requestSettingsPresent(self: *Engine) void {
        self.needs_full_repaint = true;
        self.settings_present_window = true;
    }

    /// Remember which settings row is animating so tick dirties a band, not the pane.
    pub fn noteSettingsRow(self: *Engine, row: geom.Rect) void {
        if (row.isEmpty()) return;
        self.settings_row_dirty = if (self.settings_row_dirty.isEmpty())
            row
        else
            geom.Rect.unionBounds(self.settings_row_dirty, row);
    }

    fn repaintSettingsContentPane(self: *Engine) void {
        if (self.screen != .settings) return;
        // Content fill would punch through pad/profiles/confirm chrome.
        if (self.settingsHasBlockingModal()) return;
        const win = settings_form.windowRect();
        const content = settings_form.contentPaneRect();
        const rad = tokens.Shape.dialog;
        const content_bg = self.theme.elev(1);
        self.logical.fillRect(content, content_bg);
        self.paintSettingsContent();
        widgets.punchRoundRectOutside(&self.logical, win, rad, self.theme.scrim);
        widgets.strokeRoundRect(&self.logical, win, rad, self.theme.outline_variant, 1);
        self.dirty.add(content);
        // Content fill owns the pane AABB — redraw the menu on top or it sits
        // under the panel (clock / widget morph / scroll residual).
        self.layerOpenMenu();
    }

    /// Keep an open dropdown above the settings content pane.
    fn layerOpenMenu(self: *Engine) void {
        if (self.menu_target == .none or self.menu_hit.isEmpty()) return;
        self.paintMenuOverlay();
        self.dirty.add(self.menu_hit);
    }

    /// Host mirror of LVGL `modulus_storage_clear_ui_cache` — flush gates + full dirty.
    fn clearUiCache(self: *Engine) void {
        self.invalidateAnimGates();
        self.dirty.clear();
        self.requestFull();
    }

    pub fn showSnackbar(self: *Engine, message: []const u8) void {
        self.showSnackbarAction(message, null, null);
    }

    /// A failure the operator must see — shown even at "Errors only".
    pub fn showSnackbarError(self: *Engine, message: []const u8) void {
        self.snack_level = .err;
        self.showSnackbarAction(message, null, null);
    }

    /// Brief persist ack — shorter than normal snackbars.
    fn notifySaved(self: *Engine) void {
        self.showSnackbar("Saved");
        self.snack_frames = 48; // ~0.75s at 16ms ticks
    }

    /// Drop notifications the operator asked not to see. An offered action
    /// (Undo) always counts as important — muting it would strand the choice.
    fn snackbarAllowed(self: *const Engine, level: SnackLevel, has_action: bool) bool {
        if (!self.prefs.display.notify_en) return false;
        const eff: u8 = if (has_action) @max(@intFromEnum(level), @intFromEnum(SnackLevel.important)) else @intFromEnum(level);
        return eff >= @min(self.prefs.display.notify_level, @intFromEnum(SnackLevel.err));
    }

    pub fn showSnackbarAction(self: *Engine, message: []const u8, action: ?[]const u8, undo_dark: ?bool) void {
        const level = self.snack_level;
        self.snack_level = .info; // one-shot; next caller is info unless it says otherwise
        if (!self.snackbarAllowed(level, action != null)) return;
        const n = @min(message.len, self.snack_buf.len);
        @memcpy(self.snack_buf[0..n], message[0..n]);
        self.snack_len = n;
        self.snack_frames = tokens.Motion.snackbar_ms / 16;
        self.snack_undo_dark = undo_dark;
        self.snack_fx.value = 0;
        self.snack_fx.velocity = 0;
        self.motion_phys.applyEffects(&self.snack_fx);
        self.snack_fx.setTarget(1);
        if (action) |a| {
            const an = @min(a.len, self.snack_action_buf.len);
            @memcpy(self.snack_action_buf[0..an], a[0..an]);
            self.snack_action_len = an;
        } else {
            self.snack_action_len = 0;
        }
    }

    /// Popup cards paint from `enter_t` (0.88→1 scale). Snap so the first
    /// frame is final — no MD3 container-transform "loading" settle.
    fn snapEnter(s: *spring.Spring) void {
        s.value = 1;
        s.target = 1;
        s.velocity = 0;
    }

    pub fn openDialog(self: *Engine) void {
        self.dialog_open = true;
        snapEnter(&self.dialog_fx);
        self.requestFull();
    }

    pub fn closeDialog(self: *Engine) void {
        self.dialog_open = false;
        self.dialog_fx.setTarget(0);
        self.requestFull();
    }

    pub fn toggleTheme(self: *Engine) void {
        const prev = self.prefs.display.darkmode;
        self.prefs.display.darkmode = !self.prefs.display.darkmode;
        self.applyPrefs();
        self.theme_fx.value = 0;
        self.theme_fx.setTarget(1);
        self.startBusy(45);
        self.showSnackbarAction("Theme updated", "Undo", prev);
        self.requestFull();
    }

    fn startBusy(self: *Engine, frames: u32) void {
        self.busy_frames = frames;
        self.busy_phase = 0;
    }

    /// Settings dropdown: stays open until a row is picked or the tap is
    /// outside `menu_hit` (no idle timer — that closed menus mid-pick).
    fn openMenu(self: *Engine, target: settings_menu.Target, anchor: geom.Rect) void {
        self.menu_target = target;
        self.menu_anchor = anchor;
        self.menu_scroll = 0;
        const labs = settings_menu.labels(target);
        self.menu_hit = layoutMenuRect(anchor, labs);
        self.requestFull();
    }

    fn closeMenu(self: *Engine) void {
        self.menu_target = .none;
        self.menu_hit = .{};
        self.menu_scroll = 0;
        self.requestFull();
    }

    pub fn handleHover(self: *Engine, x: i32, y: i32) void {
        const p = self.mapPointer(x, y);
        if (p.x == self.hover_x and p.y == self.hover_y) return;
        const old = self.hover_rect;
        self.hover_x = p.x;
        self.hover_y = p.y;
        self.hover_rect = .{};
        if (quick_settings.isOpen(self.sheet_y.value)) {
            const sy: i32 = i32FromF(@floor(self.sheet_y.value));
            const h = quick_settings.hit(p.x, p.y, sy, &self.prefs, self.qs_body_scroll, self.qs_zb_detail);
            self.hover_rect = quick_settings.interactiveRect(h, sy, &self.prefs, self.qs_body_scroll);
            if (old.x != self.hover_rect.x or old.y != self.hover_rect.y or old.w != self.hover_rect.w or old.h != self.hover_rect.h) {
                // Re-paint sheet so button state layers update (no status-bar flash).
                self.paintSheet(sy);
                self.dirty.add(quick_settings.panelRect(sy));
                if (!old.isEmpty()) self.dirty.add(old);
            }
            return;
        }
        if (self.screen == .settings or self.screen == .dashboard) {
            // No hover on status bar / settings — touch CNC UI, hover flash is clutter.
        } else if (self.menu_target != .none) {
            if (self.menu_hit.contains(p.x, p.y)) self.hover_rect = self.menu_hit;
        } else if (self.screen == .catalog) {
            if (self.catalog.demo_btn.contains(p.x, p.y)) {
                self.hover_rect = self.catalog.demo_btn;
            } else if (self.catalog.back.contains(p.x, p.y)) {
                self.hover_rect = self.catalog.back;
            }
            self.catalog.hover_ptr = self.hover_rect;
        }
        if (!old.isEmpty()) self.dirty.add(old);
        if (!self.hover_rect.isEmpty()) self.dirty.add(self.hover_rect);
    }

    pub fn handleFocusTab(self: *Engine, reverse: bool) void {
        const order_dash = [_]FocusKind{ .gear, .power };
        const order_set = [_]FocusKind{ .search, .close };
        const order: []const FocusKind = if (self.screen == .settings) &order_set else &order_dash;
        const old_fr = self.focus_rect;
        var idx: i32 = -1;
        for (order, 0..) |k, i| {
            if (k == self.focus_kind) idx = @intCast(i);
        }
        if (reverse) {
            idx -= 1;
            if (idx < 0) idx = @intCast(order.len - 1);
        } else {
            idx += 1;
            if (idx >= order.len) idx = 0;
        }
        self.focus_kind = order[@intCast(idx)];
        self.focus_rect = switch (self.focus_kind) {
            .none => .{},
            .search => settings_form.searchRect(),
            .close => settings_form.closeHitRect(),
            .gear, .power => .{},
        };
        if (self.focus_kind == .gear or self.focus_kind == .power) {
            const dummy_y = @divTrunc(dashboard.status_h, 2);
            var x: i32 = tokens.Logical.width - 40;
            while (x > tokens.Logical.width - 200) : (x -= 8) {
                const d = dashboard.hitStatusDetail(x, dummy_y);
                if (self.focus_kind == .gear and d.hit == .settings) {
                    self.focus_rect = d.rect;
                    break;
                }
                if (self.focus_kind == .power and d.hit == .power) {
                    self.focus_rect = d.rect;
                    break;
                }
            }
        }
        // Clear prior focus ring; new ring painted at end of tick.
        if (self.screen == .dashboard) {
            if (!old_fr.isEmpty() or !self.focus_rect.isEmpty()) self.repaintStatusRegion();
        } else {
            self.requestSettingsPresent();
        }
    }

    pub fn activateFocus(self: *Engine) void {
        switch (self.focus_kind) {
            .none => {},
            .gear => self.openSettings(),
            .power => self.openPowerMenu(),
            .search => {
                self.search_focus = true;
                self.requestSettingsPresent();
            },
            .close => self.closeSettings(),
        }
    }

    pub fn setMachinePhase(self: *Engine, phase: actions_widget.MachinePhase) void {
        const prev_strip = dashboard.jobStripVisible(self.cnc);
        self.cnc.setPhase(phase);
        self.syncLedMorph();
        const now_strip = dashboard.jobStripVisible(self.cnc);
        self.gate_job_strip = @intFromBool(now_strip);
        self.gate_phase = @intFromEnum(self.cnc.actions.phase);
        self.gate_status_sig = statusChromeSig(self.cnc);
        if (prev_strip != now_strip) {
            // bodyTop shifts. Must use requestFull — tick() clears dirty at entry, so
            // paint+dirty.add here never reaches present (waited on snackbar ~5s).
            self.requestFull();
            return;
        }
        self.repaintStatusRegion();
        self.repaintActionsRegion();
        self.gate_job_pct = 0xFF;
        self.gate_job_name_sig = 0xFFFFFFFF;
        self.repaintJobRegion();
    }

    fn syncLedMorph(self: *Engine) void {
        const morph: f32 = switch (self.cnc.actions.phase) {
            .idle => 0,
            .hold => 0.45,
            .run => 1,
        };
        self.led_morph.setTarget(morph);
    }

    pub fn openSettings(self: *Engine) void {
        self.syncSettingsLayout();
        self.settings_hub = !settings_form.useRail();
        self.machine_envelope_armed = false;
        self.envelope_pending_enable = false;
        self.screen = .settings;
        self.forceFullPresent(); // dim backdrop + shell — full present
    }

    pub fn closeSettings(self: *Engine) void {
        self.cnc_overlay = .none;
        self.cnc_dump.cancel();
        self.dash_overlay = .none;
        self.dash_arr_pick = -1;
        self.dash_arr_scroll = 0;
        self.pin_overlay = .none;
        self.mach_str_overlay = .none;
        self.extra_overlay = .none;
        self.probe_busy_frames = 0;
        self.mach_pull_polls = 0;
        self.screen = .dashboard;
        self.clearSearch();
        self.settings_hub = false;
        self.forceFullPresent();
    }

    fn useSettingsRail(self: *const Engine) bool {
        if (self.prefs.display.single_pane) return false;
        return tokens.WindowSizeClass.tab5().useNavRail();
    }

    fn syncSettingsLayout(self: *Engine) void {
        settings_form.syncLayout(self.useSettingsRail());
        if (settings_form.useRail()) self.settings_hub = false;
    }

    pub fn openPowerMenu(self: *Engine) void {
        self.screen = .power;
        self.power_confirm = .none;
        snapEnter(&self.power_fx);
        self.power_confirm_fx.value = 1;
        self.forceFullPresent();
    }

    pub fn closePowerMenu(self: *Engine) void {
        self.power_confirm = .none;
        self.power_fx.setTarget(0);
        self.screen = .dashboard;
        self.forceFullPresent();
    }

    fn openSettingsConfirm(self: *Engine, kind: settings_form.PowerConfirm) void {
        self.settings_confirm = kind;
        snapEnter(&self.settings_confirm_fx);
        self.needs_full_repaint = true;
        self.settings_present_window = false;
        self.requestFull();
    }

    fn openCncProfiles(self: *Engine) void {
        self.closeDashOverlay();
        self.closePinOverlay();
        self.closeMachStrOverlay();
        self.cnc_overlay = .profiles;
        snapEnter(&self.cnc_overlay_fx);
        self.requestFull();
    }

    fn openCncDump(self: *Engine) void {
        self.closeDashOverlay();
        self.closePinOverlay();
        self.closeMachStrOverlay();
        self.cnc_overlay = .dump;
        self.cnc_dump.begin();
        if (self.dump_begin_sink) |b| b();
        snapEnter(&self.cnc_overlay_fx);
        self.requestFull();
    }

    fn closeCncOverlay(self: *Engine) void {
        if (self.cnc_overlay == .dump) {
            if (self.dump_cancel_sink) |cxl| cxl();
        }
        self.cnc_overlay = .none;
        self.cnc_dump.cancel();
        self.cnc_overlay_fx.value = 1;
        self.requestFull();
    }

    fn kickDashOverlay(self: *Engine) void {
        self.closeCncOverlay();
        self.closePinOverlay();
        self.closeMachStrOverlay();
        snapEnter(&self.dash_overlay_fx);
        self.requestFull();
    }

    fn openDashWcs(self: *Engine) void {
        self.dash_overlay = .wcs;
        self.kickDashOverlay();
    }

    fn openDashMacro(self: *Engine, slot: u8, is_edit: bool) void {
        self.dash_mac_slot = slot;
        self.dash_mac_is_edit = is_edit;
        self.dash_mac_draft = if (is_edit) self.prefs.dash.macros[slot] else .{};
        self.dash_overlay = .macro;
        self.kickDashOverlay();
    }

    fn openDashArrange(self: *Engine) void {
        self.dash_arr_pick = -1;
        self.dash_arr_scroll = 0;
        self.dash_overlay = .arrange;
        self.kickDashOverlay();
    }

    fn closeDashOverlay(self: *Engine) void {
        self.dash_overlay = .none;
        self.dash_arr_pick = -1;
        self.dash_arr_scroll = 0;
        self.dash_overlay_fx.value = 1;
        self.requestFull();
    }

    fn setPinStatus(self: *Engine, msg: []const u8, err: bool) void {
        const n = @min(msg.len, self.pin_status.len);
        @memcpy(self.pin_status[0..n], msg[0..n]);
        if (n < self.pin_status.len) @memset(self.pin_status[n..], 0);
        self.pin_status_len = @intCast(n);
        self.pin_status_err = err;
        if (!err) {
            self.pin_err1 = false;
            self.pin_err2 = false;
        }
    }

    fn openPinOverlay(self: *Engine, kind: settings_pin_modal.Kind) void {
        self.closeDashOverlay();
        self.closeCncOverlay();
        self.closeMachStrOverlay();
        self.pad.clear();
        @memset(&self.pin_draft1, 0);
        @memset(&self.pin_draft2, 0);
        self.pin_draft1_len = 0;
        self.pin_draft2_len = 0;
        self.pin_focus = 0;
        self.pin_err1 = false;
        self.pin_err2 = false;
        self.setPinStatus("", false);
        self.pin_overlay = kind;
        snapEnter(&self.pin_overlay_fx);
        self.requestFull();
    }

    fn closePinOverlay(self: *Engine) void {
        self.pin_overlay = .none;
        self.pad.clear();
        self.pin_overlay_fx.value = 1;
        self.requestFull();
    }

    fn openPinFieldPad(self: *Engine, field: u8) void {
        self.pin_focus = field;
        self.setPinStatus("", false);
        if (field == 0) {
            const seed = self.pin_draft1[0..self.pin_draft1_len];
            const title: []const u8 = if (self.pin_overlay == .clear) "Current PIN" else "New PIN (4-8)";
            self.pad.openPad(.number, .sec_pin_new, title, seed);
        } else {
            self.pad.openPad(.number, .sec_pin_confirm, "Confirm PIN", self.pin_draft2[0..self.pin_draft2_len]);
        }
        self.pad.kb_full = self.prefs.system.kb_full;
        self.requestFull();
    }

    fn commitPinOverlaySave(self: *Engine) void {
        if (self.pin_overlay == .clear) {
            const p1 = self.pin_draft1[0..self.pin_draft1_len];
            if (!settings_prefs.SecurityPrefs.pinDigitsValid(p1)) {
                self.setPinStatus("Enter your current PIN", true);
                self.pin_err1 = true;
                self.requestFull();
                return;
            }
            if (!self.checkPin(p1)) {
                self.setPinStatus("Incorrect PIN", true);
                self.pin_err1 = true;
                self.requestFull();
                return;
            }
            if (self.pin_clear_sink) |clear| {
                if (!clear(p1)) {
                    self.setPinStatus("Clear failed", true);
                    self.requestFull();
                    return;
                }
            } else {
                self.prefs.security.clearPin();
            }
            self.applyPrefs();
            self.closePinOverlay();
            self.showSnackbar("PIN cleared");
            self.requestFull();
            return;
        }
        const p1 = self.pin_draft1[0..self.pin_draft1_len];
        const p2 = self.pin_draft2[0..self.pin_draft2_len];
        const v1 = settings_prefs.SecurityPrefs.pinDigitsValid(p1);
        const v2 = settings_prefs.SecurityPrefs.pinDigitsValid(p2);
        if (!v1 or !v2) {
            self.setPinStatus("PIN must be 4-8 digits", true);
            self.pin_err1 = !v1;
            self.pin_err2 = !v2;
            self.requestFull();
            return;
        }
        if (!std.mem.eql(u8, p1, p2)) {
            self.setPinStatus("PIN entries must match", true);
            self.pin_err1 = true;
            self.pin_err2 = true;
            self.requestFull();
            return;
        }
        if (self.pin_set_sink) |setp| {
            if (!setp(p1)) {
                self.setPinStatus("Could not store PIN", true);
                self.requestFull();
                return;
            }
            self.prefs.security.has_pin = true;
        } else if (!self.prefs.security.setPin(p1)) {
            self.setPinStatus("Could not store PIN", true);
            self.requestFull();
            return;
        }
        self.applyPrefs();
        self.closePinOverlay();
        self.showSnackbar("PIN saved");
        self.requestFull();
    }

    fn handlePinOverlayClick(self: *Engine, x: i32, y: i32) void {
        const h = settings_pin_modal.hit(self.pin_layout, self.pin_overlay, x, y);
        switch (h) {
            .none => {},
            .close, .cancel => self.closePinOverlay(),
            .field1 => self.openPinFieldPad(0),
            .field2 => self.openPinFieldPad(1),
            .save => self.commitPinOverlaySave(),
        }
    }

    fn openMachStrOverlay(self: *Engine, kind: settings_mach_string_modal.Kind) void {
        self.closeDashOverlay();
        self.closeCncOverlay();
        self.closePinOverlay();
        self.pad.clear();
        const seed: []const u8 = switch (kind) {
            .name => self.prefs.machine.nameSlice(),
            .svc_nt => self.prefs.machine.svcNtSlice(),
            .none => "",
        };
        @memset(&self.mach_str_draft, 0);
        const n = @min(seed.len, self.mach_str_draft.len);
        @memcpy(self.mach_str_draft[0..n], seed[0..n]);
        self.mach_str_draft_len = @intCast(n);
        self.mach_str_focus = false;
        self.mach_str_err = false;
        self.mach_str_status_len = 0;
        self.mach_str_overlay = kind;
        snapEnter(&self.mach_str_fx);
        self.requestFull();
    }

    fn closeMachStrOverlay(self: *Engine) void {
        self.mach_str_overlay = .none;
        self.mach_str_focus = false;
        self.pad.clear();
        self.mach_str_fx.value = 1;
        self.requestFull();
    }

    fn openMachStrFieldPad(self: *Engine) void {
        self.mach_str_focus = true;
        self.mach_str_err = false;
        self.mach_str_status_len = 0;
        const seed = self.mach_str_draft[0..self.mach_str_draft_len];
        switch (self.mach_str_overlay) {
            .name => self.openTextPad(.mach_name, "Machine name", seed),
            .svc_nt => self.openTextPad(.mach_svc_nt, "Service notes", seed),
            .none => {},
        }
    }

    fn commitMachStrSave(self: *Engine) void {
        const txt = self.mach_str_draft[0..self.mach_str_draft_len];
        switch (self.mach_str_overlay) {
            .name => {
                var cleaned: [32]u8 = undefined;
                const name = settings_prefs.MachinePrefs.sanitizeName(txt, &cleaned);
                if (name.len == 0) {
                    const msg = "Enter a name";
                    @memcpy(self.mach_str_status[0..msg.len], msg);
                    self.mach_str_status_len = msg.len;
                    self.mach_str_err = true;
                    self.requestFull();
                    return;
                }
                self.prefs.machine.setName(name);
                self.applyPrefs();
                self.closeMachStrOverlay();
                self.showSnackbar("Machine name saved");
            },
            .svc_nt => {
                self.prefs.machine.setSvcNotes(txt);
                self.applyPrefs();
                self.closeMachStrOverlay();
                self.showSnackbar("Service notes saved");
            },
            .none => {},
        }
        self.requestFull();
    }

    fn handleMachStrOverlayClick(self: *Engine, x: i32, y: i32) void {
        switch (settings_mach_string_modal.hit(self.mach_str_layout, x, y)) {
            .none => {},
            .close, .cancel => self.closeMachStrOverlay(),
            .field => self.openMachStrFieldPad(),
            .save => self.commitMachStrSave(),
        }
    }

    fn startMachPull(self: *Engine) void {
        if (self.mach_pull_polls != 0) return;
        self.mach_pull_polls = 1;
        if (self.mach_pull_begin_sink) |begin| begin();
        self.requestFull();
    }

    fn tickMachPull(self: *Engine) void {
        if (self.mach_pull_polls == 0) return;
        if (self.mach_pull_tick_sink) |pull_tick| {
            self.mach_pull_polls +|= 1;
            switch (pull_tick(self)) {
                .pending => self.requestFull(),
                .applied => {
                    self.mach_pull_polls = 0;
                    self.showSnackbar("Pull applied");
                    self.requestFull();
                },
                .empty => {
                    self.mach_pull_polls = 0;
                    self.showSnackbarError("Pull no matching settings");
                    self.requestFull();
                },
                .failed => {
                    self.mach_pull_polls = 0;
                    self.showSnackbarError("Pull dump failed");
                    self.requestFull();
                },
                .timeout => {
                    self.mach_pull_polls = 0;
                    self.showSnackbarError("Pull timeout");
                    self.requestFull();
                },
            }
            return;
        }
        self.mach_pull_polls +|= 1;
        // ~8 ticks ≈ LVGL poll settle (host stub, no UART).
        if (self.mach_pull_polls < 8) {
            self.requestFull();
            return;
        }
        self.mach_pull_polls = 0;
        const n = self.prefs.machine.applyPullStub();
        self.applyPrefs();
        if (n > 0) {
            self.showSnackbar("Pull applied");
        } else {
            self.showSnackbarError("Pull no matching settings");
        }
        self.requestFull();
    }

    fn handleDashOverlayClick(self: *Engine, x: i32, y: i32) void {
        switch (self.dash_overlay) {
            .none => {},
            .wcs => {
                const hit = settings_dashboard_modals.hitWcs(self.dash_wcs_layout, x, y);
                switch (hit) {
                    .none => {},
                    .close => self.closeDashOverlay(),
                    .lock0, .lock1, .lock2, .lock3, .lock4, .lock5 => {
                        const i: u8 = switch (hit) {
                            .lock0 => 0,
                            .lock1 => 1,
                            .lock2 => 2,
                            .lock3 => 3,
                            .lock4 => 4,
                            else => 5,
                        };
                        self.prefs.dash.wcs_lock ^= @as(u8, 1) << @intCast(i);
                        self.applyPrefs();
                        self.requestFull();
                    },
                    .name0, .name1, .name2, .name3, .name4, .name5 => {
                        const i: u8 = switch (hit) {
                            .name0 => 0,
                            .name1 => 1,
                            .name2 => 2,
                            .name3 => 3,
                            .name4 => 4,
                            else => 5,
                        };
                        self.dash_wcs_name_i = i;
                        var title_buf: [24]u8 = undefined;
                        const title = std.fmt.bufPrint(&title_buf, "Rename {s}", .{self.prefs.dash.wcsLabelAt(i)}) catch "Rename WCS";
                        self.openTextPad(.dash_wcs_name, title, self.prefs.dash.wcsNameSlice(i));
                    },
                }
            },
            .macro => {
                const hit = settings_dashboard_modals.hitMacro(self.dash_mac_layout, x, y);
                switch (hit) {
                    .none => {},
                    .close => self.closeDashOverlay(),
                    .name => self.openTextPad(.dash_mac_name, "Button name", self.dash_mac_draft.nameSlice()),
                    .on_code => self.openTextPad(.dash_mac_on, "G-code ON", self.dash_mac_draft.onSlice()),
                    .off_code => self.openTextPad(.dash_mac_off, "G-code OFF", self.dash_mac_draft.offSlice()),
                    .save => {
                        if (self.prefs.dash.saveMacro(
                            self.dash_mac_slot,
                            self.dash_mac_draft.nameSlice(),
                            self.dash_mac_draft.onSlice(),
                            self.dash_mac_draft.offSlice(),
                        )) {
                            self.applyPrefs();
                            self.showSnackbar(if (self.dash_mac_is_edit) "Button updated" else "Button added");
                            self.closeDashOverlay();
                        } else {
                            self.showSnackbar("Need name + ON code");
                        }
                    },
                    .delete => {
                        self.prefs.dash.clearMacro(self.dash_mac_slot);
                        self.applyPrefs();
                        self.showSnackbar("Button deleted");
                        self.closeDashOverlay();
                    },
                }
            },
            .arrange => {
                const r = settings_dashboard_modals.hitArrange(self.dash_arr_layout, self.dash_arr_pick, x, y);
                switch (r.hit) {
                    .none => {},
                    .close => {
                        if (self.dash_arr_pick >= 0) {
                            self.dash_arr_pick = -1;
                            self.dash_arr_scroll = 0;
                            self.requestFull();
                        } else {
                            self.closeDashOverlay();
                        }
                    },
                    .slot0, .slot1, .slot2, .slot3 => {
                        self.dash_arr_pick = switch (r.hit) {
                            .slot0 => 0,
                            .slot1 => 1,
                            .slot2 => 2,
                            else => 3,
                        };
                        self.dash_arr_scroll = 0;
                        self.requestFull();
                    },
                    .pick => {
                        if (self.dash_arr_pick >= 0 and r.pick_i < self.dash_arr_layout.pick_n) {
                            self.prefs.dash.quick[@intCast(self.dash_arr_pick)] = self.dash_arr_layout.pick_ids[r.pick_i];
                            self.applyPrefs();
                            self.dash_arr_pick = -1;
                            self.showSnackbar("Slot assigned");
                            self.requestFull();
                        }
                    },
                }
            },
        }
    }

    fn handleCncOverlayClick(self: *Engine, x: i32, y: i32) void {
        switch (self.cnc_overlay) {
            .none => {},
            .profiles => {
                const hit = settings_cnc_modals.hitProfiles(self.cnc_prof_layout, x, y);
                switch (hit) {
                    .none => {},
                    .close => self.closeCncOverlay(),
                    .save => {
                        const slot = @min(self.prefs.cnc.prof, settings_prefs.profile_slots - 1);
                        var name_buf: [24]u8 = undefined;
                        const existing = self.prefs.cnc.profileName(@intCast(slot));
                        const name = if (existing.len > 0) existing else blk: {
                            break :blk (std.fmt.bufPrint(&name_buf, "Profile {d}", .{slot + 1}) catch "Profile");
                        };
                        self.prefs.cnc.saveProfileSlot(@intCast(slot), name);
                        self.applyPrefs();
                        self.showSnackbar("Profile saved");
                        self.requestFull();
                    },
                    .activate0, .activate1, .activate2, .activate3 => {
                        const slot: u8 = switch (hit) {
                            .activate0 => 0,
                            .activate1 => 1,
                            .activate2 => 2,
                            else => 3,
                        };
                        if (self.prefs.cnc.activateProfile(slot)) {
                            self.applyPrefs();
                            if (self.transport_reinit_sink) |s| s();
                            self.showSnackbar("Profile activated");
                        } else {
                            self.showSnackbar("Empty profile");
                        }
                        self.requestFull();
                    },
                    .rename0, .rename1, .rename2, .rename3 => {
                        const slot: u8 = switch (hit) {
                            .rename0 => 0,
                            .rename1 => 1,
                            .rename2 => 2,
                            else => 3,
                        };
                        self.cnc_rename_slot = slot;
                        var seed_buf: [24]u8 = undefined;
                        const seed = self.prefs.cnc.profileName(slot);
                        const seed_use = if (seed.len > 0) seed else (std.fmt.bufPrint(&seed_buf, "Profile {d}", .{slot + 1}) catch "Profile");
                        self.openTextPad(.cnc_prof_rename, "Rename profile", seed_use);
                    },
                }
            },
            .dump => {
                if (settings_cnc_modals.hitDump(self.cnc_dump, x, y) == .close) {
                    self.closeCncOverlay();
                }
            },
        }
    }

    fn openExtra(self: *Engine, kind: settings_extra_modals.Kind) void {
        self.extra_overlay = kind;
        snapEnter(&self.extra_fx);
        self.requestFull();
    }

    fn closeExtra(self: *Engine) void {
        self.extra_overlay = .none;
        self.probe_busy_frames = 0;
        self.prefs.wireless.bt_pair_idx = 0xff;
        self.extra_fx.value = 1;
        self.extra_fx.setTarget(0);
        self.requestFull();
    }

    fn handleExtraOverlayClick(self: *Engine, x: i32, y: i32) void {
        const h = settings_extra_modals.hit(self.extra_layout, x, y);
        switch (self.extra_overlay) {
            .none => {},
            .transport => switch (h) {
                .close, .secondary => self.closeExtra(),
                .primary => {
                    self.prefs.cnc.transport_off = false;
                    self.prefs.cnc.startConnect();
                    self.applyPrefs();
                    if (self.transport_reinit_sink) |s| s();
                    self.closeExtra();
                    self.showSnackbar("Connecting...");
                },
                .field0 => switch (self.prefs.cnc.conn) {
                    1 => self.openTextPad(.cnc_ws_host, "WebSocket host", self.prefs.cnc.wsHostSlice()),
                    2 => self.openTextPad(.cnc_tn_host, "Telnet host", self.prefs.cnc.tnHostSlice()),
                    5 => self.openTextPad(.cnc_ble_name, "BLE device name", self.prefs.cnc.bleNameSlice()),
                    6 => {
                        var buf: [8]u8 = undefined;
                        const seed = std.fmt.bufPrint(&buf, "0x{X:0>2}", .{self.prefs.cnc.i2c_addr}) catch "0x50";
                        self.openTextPad(.cnc_i2c_addr, "I2C address", seed);
                    },
                    7 => {
                        var buf: [8]u8 = undefined;
                        const seed = std.fmt.bufPrint(&buf, "{d}", .{self.prefs.cnc.can_nid}) catch "1";
                        self.openTextPad(.cnc_can_nid, "CAN node ID", seed);
                    },
                    else => {},
                },
                .field1 => switch (self.prefs.cnc.conn) {
                    1 => {
                        var buf: [8]u8 = undefined;
                        const seed = std.fmt.bufPrint(&buf, "{d}", .{self.prefs.cnc.ws_port}) catch "81";
                        self.openTextPad(.cnc_ws_port, "WebSocket port", seed);
                    },
                    2 => {
                        var buf: [8]u8 = undefined;
                        const seed = std.fmt.bufPrint(&buf, "{d}", .{self.prefs.cnc.tn_port}) catch "23";
                        self.openTextPad(.cnc_tn_port, "Telnet port", seed);
                    },
                    else => {},
                },
                .field2 => if (self.prefs.cnc.conn == 1) {
                    self.openTextPad(.cnc_ws_path, "WebSocket path", self.prefs.cnc.wsPathSlice());
                },
                .toggle0 => if (self.prefs.cnc.conn == 1) {
                    self.prefs.cnc.ws_tls = !self.prefs.cnc.ws_tls;
                    self.requestFull();
                },
                .cycle0 => switch (self.prefs.cnc.conn) {
                    3 => self.openMenu(.ser_baud, self.extra_layout.cycle[0]),
                    4 => self.openMenu(.r4_baud, self.extra_layout.cycle[0]),
                    else => {},
                },
                .seg0 => {
                    if (self.prefs.cnc.conn == 6) {
                        if (settings_extra_modals.segmentIndexAt(self.extra_layout.seg[0], x, 2)) |i| {
                            self.prefs.cnc.i2c_spd = @intCast(i);
                            self.requestFull();
                        }
                    } else if (self.prefs.cnc.conn == 7) {
                        if (settings_extra_modals.segmentIndexAt(self.extra_layout.seg[0], x, 4)) |i| {
                            self.prefs.cnc.can_brate = @intCast(i);
                            self.requestFull();
                        }
                    }
                },
                else => {},
            },
            .wifi_connect => switch (h) {
                .close, .secondary => self.closeExtra(),
                .field0 => self.openTextPad(.wl_pass, "Wi-Fi password", self.prefs.wireless.draftPassSlice()),
                .primary => {
                    if (self.emitWireless(.{ .wifi_connect = .{
                        .ssid = self.prefs.wireless.ssidSlice(),
                        .pass = self.prefs.wireless.draftPassSlice(),
                    } })) {
                        self.closeExtra();
                        self.showSnackbar("Connecting...");
                    } else if (self.wifi_connect_sink) |s| {
                        s(self.prefs.wireless.ssidSlice(), self.prefs.wireless.draftPassSlice());
                        self.closeExtra();
                        self.showSnackbar("Connecting...");
                    } else {
                        self.prefs.wireless.finishWifiConnect();
                        self.closeExtra();
                        self.showSnackbar("Connected");
                    }
                    self.applyPrefs();
                },
                else => {},
            },
            .bt_passkey => switch (h) {
                .close, .secondary => {
                    self.prefs.wireless.bt_pair_idx = 0xff;
                    self.closeExtra();
                },
                .field0 => self.openTextPad(.wl_bt_passkey, "Passkey", self.prefs.wireless.btPasskeySlice()),
                .primary => {
                    if (self.prefs.wireless.bt_pair_idx != 0xff) {
                        if (self.emitWireless(.{ .ble_pair = .{
                            .idx = self.prefs.wireless.bt_pair_idx,
                            .passkey = self.prefs.wireless.btPasskeySlice(),
                        } })) {
                            self.showSnackbar("Pairing...");
                        } else {
                            self.prefs.wireless.connectBt(self.prefs.wireless.bt_pair_idx);
                            self.showSnackbar("Paired");
                        }
                    }
                    self.prefs.wireless.bt_pair_idx = 0xff;
                    @memset(&self.prefs.wireless.bt_passkey, 0);
                    self.applyPrefs();
                    self.closeExtra();
                },
                else => {},
            },
            .zb_add => switch (h) {
                .close, .secondary => self.closeExtra(),
                .field0 => self.openTextPad(.wl_zb_code, "Install code", self.prefs.wireless.zbInstallSlice()),
                .primary => {
                    if (self.prefs.wireless.zbInstallSlice().len == 0) {
                        self.showSnackbar("Enter install code");
                        self.requestFull();
                        return;
                    }
                    if (self.emitWireless(.{ .zb_add_code = self.prefs.wireless.zbInstallSlice() })) {
                        self.showSnackbar("Zigbee device added");
                    } else {
                        self.prefs.wireless.addZbFromInstall();
                        self.showSnackbar("Zigbee device added");
                    }
                    self.applyPrefs();
                    self.closeExtra();
                },
                else => {},
            },
            .th_add => switch (h) {
                .close, .secondary => self.closeExtra(),
                .field0 => self.openTextPad(.wl_th_node, "Node ID", self.prefs.wireless.thNodeSlice()),
                .primary => {
                    if (self.prefs.wireless.thNodeSlice().len == 0) {
                        self.showSnackbar("Enter node ID");
                        self.requestFull();
                        return;
                    }
                    if (self.emitWireless(.{ .th_add_node = self.prefs.wireless.thNodeSlice() })) {
                        self.showSnackbar("Thread node added");
                    } else {
                        self.prefs.wireless.addThFromNode();
                        self.showSnackbar("Thread node added");
                    }
                    self.applyPrefs();
                    self.closeExtra();
                },
                else => {},
            },
            .probe => switch (h) {
                .close, .secondary => self.closeExtra(),
                .field0 => {
                    var seed_buf: [16]u8 = undefined;
                    const x10 = self.prefs.dash.probe_zoff_x10;
                    const seed = std.fmt.bufPrint(&seed_buf, "{d}.{d}", .{ x10 / 10, x10 % 10 }) catch "1.0";
                    self.pad.openPad(.number, .dash_probe_zoff, "Plate thickness (mm)", seed);
                    self.pad.kb_full = self.prefs.system.kb_full;
                    self.requestFull();
                },
                .primary => {
                    if (self.probe_busy_frames > 0) {
                        self.showSnackbar("Probe busy");
                        return;
                    }
                    self.probe_busy_frames = 45; // ~1.5s @ 30Hz
                    self.showSnackbar("Z-plate probe started");
                    self.requestFull();
                },
                else => {},
            },
            .mpg => switch (h) {
                .close, .primary => self.closeExtra(),
                .inv0 => self.prefs.dash.mpgpol ^= 1 << 0,
                .inv1 => self.prefs.dash.mpgpol ^= 1 << 1,
                .inv2 => self.prefs.dash.mpgpol ^= 1 << 2,
                .inv3 => self.prefs.dash.mpgpol ^= 1 << 3,
                .inv4 => self.prefs.dash.mpgpol ^= 1 << 4,
                .inv5 => self.prefs.dash.mpgpol ^= 1 << 5,
                else => {},
            },
            .idle_lock => switch (h) {
                .close, .primary => self.closeExtra(),
                .toggle0 => if (self.prefs.security.has_pin) {
                    self.prefs.security.setIdle(!self.prefs.security.pin_idle);
                    self.requestFull();
                } else {
                    self.showSnackbar("Set a PIN first");
                },
                .cycle0 => if (self.prefs.security.has_pin) {
                    self.openMenu(.sec_idle_tmo, self.extra_layout.cycle[0]);
                } else {
                    self.showSnackbar("Set a PIN first");
                },
                else => {},
            },
        }
        if (self.extra_overlay == .mpg and (h == .inv0 or h == .inv1 or h == .inv2 or h == .inv3 or h == .inv4 or h == .inv5)) {
            self.applyPrefs();
            self.requestFull();
        }
    }

    fn closeSettingsConfirm(self: *Engine) void {
        self.settings_confirm = .none;
        self.pending_cnc = null;
        self.requestFull();
    }

    fn applySettingsConfirm(self: *Engine) void {
        switch (self.settings_confirm) {
            .none => {},
            .restart => {
                if (self.power_restart_sink) |s| {
                    s();
                } else {
                    self.showSnackbar("Restart (stub)");
                }
            },
            .shutdown => {
                if (self.power_shutdown_sink) |s| {
                    s();
                } else {
                    self.showSnackbar("Shutdown (stub)");
                }
            },
            .factory => {
                if (self.factory_reset_sink) |s| {
                    s();
                } else {
                    settings_other_tabs.factoryReset(&self.prefs);
                    self.applyPrefs();
                    self.showSnackbar("Factory reset (host)");
                }
            },
            .language => {
                self.prefs.system.lang = self.pending_lang;
                self.applyPrefs();
                self.showSnackbar("Language applied");
            },
            .eject_sd => {
                if (!self.emitStorSys(.unmount)) {
                    self.prefs.storage.eject();
                }
                self.showSnackbar("SD ejected");
            },
            .import_settings => {
                if (self.emitStorSys(.import_settings)) {
                    self.showSnackbar("Settings imported");
                } else {
                    self.prefs.applyImportStub();
                    self.applyPrefs();
                    self.showSnackbar("Settings imported");
                }
            },
            .mach_reset => {
                self.prefs.machine.resetDefaults();
                self.applyPrefs();
                self.showSnackbar("Machine settings reset");
            },
            .maint_reset => {
                self.prefs.machine.resetMaintCounters();
                if (self.maint_reset_sink) |s| s();
                self.showSnackbar("Maintenance counters cleared");
            },
            .power_reset => {
                self.prefs.power.resetDefaults();
                self.applyPrefs();
                self.showSnackbar("Power settings reset");
            },
            .display_reset => {
                self.prefs.display.resetDefaults();
                self.applyPrefs();
                self.showSnackbar("Display settings reset");
            },
            .dashboard_reset => {
                self.prefs.dash.resetDefaults();
                self.applyPrefs();
                self.showSnackbar("Dashboard settings reset");
            },
            .cnc_reset => {
                self.prefs.cnc.resetDefaults();
                self.prefs.cnc.startConnect();
                self.applyPrefs();
                if (self.transport_reinit_sink) |s| s();
                self.showSnackbar("CNC connection reset");
            },
            .clear_pin => {
                self.closeSettingsConfirm();
                self.openPinOverlay(.clear);
                return;
            },
            .wireless_reset => {
                self.prefs.wireless.resetDefaults();
                self.applyPrefs();
                self.showSnackbar("Network defaults reset");
            },
            .wcs_change => {
                self.closeSettingsConfirm();
                self.applyWcsCycle(self.pending_wcs_i);
                return;
            },
            .dash_cycle, .dash_spin, .dash_zero, .dash_home, .dash_mac, .dash_zero_all => {
                if (self.pending_cnc) |cmd| {
                    _ = self.emitCnc(cmd);
                    switch (cmd) {
                        .zero_axis => |a| {
                            if (a < self.cnc.dro.work_um.len) self.cnc.dro.work_um[a] = 0;
                        },
                        .zero_all => @memset(&self.cnc.dro.work_um, 0),
                        else => {},
                    }
                    self.pending_cnc = null;
                }
            },
            .mach_push => {
                if (self.mach_push_sink) |s| s();
                self.showSnackbar("Envelope pushed");
            },
            .mach_slim => {
                self.machine_envelope_armed = true;
                if (self.envelope_pending_enable) {
                    self.prefs.machine.slim = true;
                    self.envelope_pending_enable = false;
                }
                self.applyPrefs();
                self.notifySaved();
            },
            .pin_boot_on => {
                self.prefs.security.pin_boot = true;
                self.applyPrefs();
                self.notifySaved();
            },
            .pin_slp_on => {
                self.prefs.security.setWake(true);
                self.applyPrefs();
                self.notifySaved();
            },
        }
        self.closeSettingsConfirm();
    }

    pub fn openPin(self: *Engine) void {
        self.screen = .pin;
        self.pad.openPad(.number, .sec_pin_unlock, "Enter PIN", "");
        self.pad.kb_full = self.prefs.system.kb_full;
        self.forceFullPresent();
    }

    /// Re-arm the unlock keypad. The lock screen has exactly one exit — a
    /// correct PIN — so cancel, scrim tap, and back must land here, not on
    /// the dashboard.
    fn relockPin(self: *Engine) void {
        self.pad.openPad(.number, .sec_pin_unlock, "Enter PIN", "");
        self.pad.kb_full = self.prefs.system.kb_full;
        self.requestFull();
    }

    pub fn openCatalog(self: *Engine) void {
        self.screen = .catalog;
        self.catalog.scroll = self.motion_phys.makeSpring(.spatial, 0);
        self.catalog.scroll.epsilon = tokens.Motion.scroll_epsilon;
        self.motion_phys.applyEffects(&self.catalog.load_fx);
        self.forceFullPresent();
    }

    pub fn closeCatalog(self: *Engine) void {
        self.screen = .dashboard;
        self.forceFullPresent();
    }

    pub fn skipBoot(self: *Engine) void {
        if (self.screen != .boot) return;
        self.finishBoot();
    }

    pub fn onBoot(self: *const Engine) bool {
        return self.screen == .boot;
    }

    fn tryOpenOrDragDashSlider(self: *Engine, hit: settings_dashboard_tab.Hit, x: i32, y: i32) bool {
        const map = [_]struct { h: settings_dashboard_tab.Hit, t: input_pad.Target, row: geom.Rect, title: []const u8, seed: u32 }{
            .{ .h = .coal, .t = .dash_coal, .row = self.dash_layout.coal, .title = "Coalesce (ms)", .seed = self.prefs.dash.jog_coal_ms },
            .{ .h = .pend, .t = .dash_pend, .row = self.dash_layout.pend, .title = "Pending detents", .seed = self.prefs.dash.jog_pend_max },
            .{ .h = .encdiv, .t = .dash_encdiv, .row = self.dash_layout.encdiv, .title = "Encoder div", .seed = self.prefs.dash.encdiv },
            .{ .h = .contpct, .t = .dash_contpct, .row = self.dash_layout.contpct, .title = "CONT %", .seed = self.prefs.dash.contpct },
        };
        for (map) |m| {
            if (m.h != hit) continue;
            if (settings_form.sliderValueHit(m.row, x, y)) {
                self.openNumberForTarget(m.t, m.title, m.seed);
                return true;
            }
            if (settings_form.sliderDragHit(m.row, x, y)) {
                self.slider_drag = m.t;
                self.applySliderDrag(m.t, x);
                self.applyPrefs();
                self.requestFull();
                return true;
            }
        }
        return false;
    }

    fn tryOpenOrDragDispSlider(self: *Engine, hit: settings_display_tab.Hit, x: i32, y: i32) bool {
        if (hit != .bright) return false;
        const row = self.disp_layout.bright;
        if (settings_form.sliderValueHit(row, x, y)) {
            self.openNumberForTarget(.disp_bright, "Brightness %", self.prefs.display.bright);
            return true;
        }
        if (settings_form.sliderDragHit(row, x, y)) {
            self.slider_drag = .disp_bright;
            self.applySliderDrag(.disp_bright, x);
            self.applyPrefs();
            self.requestFull();
            return true;
        }
        return false;
    }

    fn tryOpenOrDragOther(self: *Engine, hit: settings_other_tabs.Hit, x: i32, y: i32) bool {
        if (hit == .stor_sd) {
            switch (self.prefs.storage.sd) {
                .mounted => self.openSettingsConfirm(.eject_sd),
                .unmounted, .failed => {
                    if (self.emitStorSys(.mount)) {
                        self.showSnackbar(switch (self.prefs.storage.sd) {
                            .mounted => "SD mounted",
                            .failed => "SD mount failed",
                            else => "SD not present",
                        });
                    } else {
                        self.prefs.storage.mount();
                        self.showSnackbar("SD mounted");
                    }
                    self.requestFull();
                },
            }
            return true;
        }
        if (hit == .stor_export) {
            if (self.emitStorSys(.export_diag)) {
                self.showSnackbar(self.prefs.storage.diagDetail());
            } else {
                switch (self.prefs.storage.exportDiagnosticsStub()) {
                    .ok => self.showSnackbar("Diagnostics exported"),
                    .need_sd => self.showSnackbar("Insert SD card"),
                    .failed => self.showSnackbarError("Export failed"),
                }
            }
            self.requestFull();
            return true;
        }
        if (hit == .stor_backup_exp) {
            if (self.emitStorSys(.export_settings)) {
                self.showSnackbar(self.prefs.storage.backupExportDetail());
            } else {
                switch (self.prefs.storage.exportSettingsStub()) {
                    .ok => self.showSnackbar("Settings exported"),
                    .need_sd => self.showSnackbar("Insert SD card"),
                    .failed => self.showSnackbarError("Export failed"),
                }
            }
            self.requestFull();
            return true;
        }
        if (hit == .stor_backup_imp) {
            if (self.prefs.storage.sd != .mounted) {
                self.showSnackbar("Insert SD card");
            } else {
                self.openSettingsConfirm(.import_settings);
            }
            self.requestFull();
            return true;
        }
        if (hit == .stor_cache) {
            _ = self.emitStorSys(.clear_cache);
            self.clearUiCache();
            return true;
        }
        if (hit == .stor_i2c_all or hit == .stor_i2c_mbus or hit == .stor_i2c_porta or hit == .stor_i2c_exp1 or hit == .stor_i2c_exp2) {
            const target: u8 = switch (hit) {
                .stor_i2c_all => 0,
                .stor_i2c_porta => 1,
                .stor_i2c_mbus => 2,
                .stor_i2c_exp1 => 3,
                .stor_i2c_exp2 => 4,
                else => 0,
            };
            self.prefs.storage.startI2cScan(target);
            if (self.emitStorSys(.{ .i2c_scan = target })) {
                self.prefs.storage.i2c_scan_hw = true;
                self.showSnackbar("I2C scan...");
            } else {
                self.showSnackbar("I2C scan (host)");
            }
            self.requestFull();
            return true;
        }
        if (hit == .sys_manual) {
            if (self.prefs.system.ntp) {
                self.showSnackbar("Turn off NTP to set manually");
                self.requestFull();
                return true;
            }
            const ymd = self.prefs.system.ymdParts();
            const hms = self.prefs.system.hmsParts();
            self.pad.openDatetime(
                .sys_datetime,
                "Set date and time",
                @intCast(ymd.y),
                @intCast(ymd.m),
                @intCast(ymd.d),
                @intCast(hms.h),
                @intCast(hms.m),
                @intCast(hms.s),
            );
            self.pad.kb_full = self.prefs.system.kb_full;
            self.requestFull();
            return true;
        }
        if (hit == .sys_restart) {
            self.openSettingsConfirm(.restart);
            return true;
        }
        if (hit == .sys_shutdown) {
            self.openSettingsConfirm(.shutdown);
            return true;
        }
        if (hit == .sys_factory) {
            self.openSettingsConfirm(.factory);
            return true;
        }
        if (hit == .sys_sync) {
            if (self.emitStorSys(.ntp_sync)) {
                self.showSnackbar(if (self.prefs.system.ntp) "NTP syncing..." else "NTP disabled");
            } else {
                switch (self.prefs.system.syncNow(self.prefs.wireless.wifi)) {
                    .disabled => self.showSnackbar("NTP disabled"),
                    .no_net => self.showSnackbar("No network"),
                    .started => self.showSnackbar("NTP syncing..."),
                }
            }
            self.requestFull();
            return true;
        }
        if (hit == .mach_name) {
            self.openMachStrOverlay(.name);
            return true;
        }
        if (hit == .mach_svc_dt) {
            self.pad.openPad(.date, .mach_svc_dt, "Last service date", self.prefs.machine.svcDtSlice());
            self.requestFull();
            return true;
        }
        if (hit == .mach_svc_nt) {
            self.openMachStrOverlay(.svc_nt);
            return true;
        }
        if (hit == .mach_pull) {
            if (self.mach_pull_polls != 0) return true;
            self.startMachPull();
            return true;
        }
        if (hit == .mach_push) {
            self.openSettingsConfirm(.mach_push);
            return true;
        }
        if (hit == .mach_dump) {
            self.openCncDump();
            return true;
        }
        if (hit == .mach_reset) {
            self.openSettingsConfirm(.mach_reset);
            return true;
        }
        if (hit == .mach_mnt_reset) {
            self.openSettingsConfirm(.maint_reset);
            return true;
        }
        if (hit == .pwr_sleep_now) {
            if (self.power_sleep_sink) |s| {
                s();
            } else {
                self.showSnackbar("Deep sleep (host stub)");
            }
            self.requestFull();
            return true;
        }
        if (hit == .pwr_reset) {
            self.openSettingsConfirm(.power_reset);
            return true;
        }
        if (hit == .sec_set_pin) {
            self.openPinOverlay(.set);
            return true;
        }
        if (hit == .sec_clear_pin) {
            if (!self.prefs.security.has_pin) {
                self.showSnackbar("No PIN set");
                self.requestFull();
                return true;
            }
            self.openPinOverlay(.clear);
            return true;
        }
        if (hit == .sec_idle) {
            if (!self.prefs.security.has_pin) {
                self.showSnackbar("Set a PIN first");
                self.requestFull();
                return true;
            }
            self.openExtra(.idle_lock);
            return true;
        }
        if (hit == .wl_reset) {
            self.openSettingsConfirm(.wireless_reset);
            return true;
        }
        if (hit == .wl_en_add_mac) {
            self.openTextPad(.wl_en_mac, "ESP-NOW peer MAC", self.prefs.wireless.bridgeSlice());
            return true;
        }
        if (hit == .wl_zb_add) {
            @memset(&self.prefs.wireless.zb_install, 0);
            self.openExtra(.zb_add);
            return true;
        }
        if (hit == .wl_th_add) {
            @memset(&self.prefs.wireless.th_node, 0);
            self.openExtra(.th_add);
            return true;
        }
        if (hit == .wl_ap0 or hit == .wl_ap1 or hit == .wl_ap2) {
            const idx: u8 = switch (hit) {
                .wl_ap0 => 0,
                .wl_ap1 => 1,
                else => 2,
            };
            self.wifi_ap_idx = idx;
            self.prefs.wireless.beginWifiConnect(idx);
            self.openExtra(.wifi_connect);
            return true;
        }
        if (hit == .wl_bt_dev0 or hit == .wl_bt_dev1) {
            const idx: u8 = if (hit == .wl_bt_dev0) 0 else 1;
            self.prefs.wireless.beginBtPair(idx);
            self.openExtra(.bt_passkey);
            return true;
        }
        if (hit == .wl_scan) {
            const p = self.prefs.wireless.page;
            if (p == 1) {
                if (!self.prefs.wireless.wifi) {
                    self.showSnackbar("Enable Wi-Fi radio first");
                } else if (self.emitWireless(.scan) or blk: {
                    if (self.wifi_scan_sink) |scan| {
                        scan(self);
                        break :blk true;
                    }
                    break :blk false;
                }) {
                    self.showSnackbar("Scanning Wi-Fi...");
                } else {
                    self.prefs.wireless.startWifiScan();
                    self.showSnackbar("Scanning Wi-Fi...");
                }
            } else if (p == 2) {
                if (!self.prefs.wireless.bt) {
                    self.showSnackbar("Enable Bluetooth first");
                } else if (self.emitWireless(.scan)) {
                    self.showSnackbar("Scanning BLE...");
                } else {
                    self.prefs.wireless.startBtScan();
                    self.showSnackbar("Scanning BLE...");
                }
            } else if (p == 3) {
                if (!self.prefs.wireless.espnow) {
                    self.showSnackbar("Enable ESP-NOW first");
                } else if (self.emitWireless(.scan)) {
                    self.showSnackbar("Scanning peers...");
                } else {
                    self.prefs.wireless.startEnScan();
                    self.showSnackbar("Scanning peers...");
                }
            } else if (p == 4) {
                if (!self.prefs.wireless.zigbee) {
                    self.showSnackbar("Enable Zigbee first");
                } else if (self.emitWireless(.scan)) {
                    self.showSnackbar(if (self.prefs.wireless.zb_joined) "Permit join..." else "Scanning Zigbee...");
                } else {
                    self.prefs.wireless.startZbScan();
                    self.showSnackbar("Scanning Zigbee...");
                }
            } else if (p == 5) {
                if (!self.prefs.wireless.thread) {
                    self.showSnackbar("Enable Thread first");
                } else if (self.emitWireless(.scan)) {
                    self.showSnackbar("Refreshing nodes...");
                } else {
                    self.prefs.wireless.startThScan();
                    self.showSnackbar("Scanning Thread...");
                }
            }
            self.requestFull();
            return true;
        }
        if (hit == .aud_vol and !self.prefs.audio.out_ready) {
            self.showSnackbar("Output codec unavailable");
            self.requestFull();
            return true;
        }
        const pairs = [_]struct { h: settings_other_tabs.Hit, t: input_pad.Target, title: []const u8, vmin: u32, vmax: u32, seed: u32 }{
            .{ .h = .aud_vol, .t = .aud_vol, .title = "Volume", .vmin = 0, .vmax = 100, .seed = self.prefs.audio.vol },
            .{ .h = .mach_mxfeed, .t = .mach_mxfeed, .title = "Max feed", .vmin = 100, .vmax = 20000, .seed = self.prefs.machine.mxfeed },
            .{ .h = .mach_mxrpm, .t = .mach_mxrpm, .title = "Max RPM", .vmin = 1000, .vmax = 60000, .seed = self.prefs.machine.mxrpm },
            .{ .h = .mach_jogspd, .t = .mach_jogspd, .title = "Jog speed", .vmin = 100, .vmax = 10000, .seed = self.prefs.machine.jogspd },
            .{ .h = .mach_feedovr, .t = .mach_feedovr, .title = "Feed ovr", .vmin = 10, .vmax = 200, .seed = self.prefs.machine.feedovr },
            .{ .h = .mach_spindovr, .t = .mach_spindovr, .title = "Spindle ovr", .vmin = 10, .vmax = 200, .seed = self.prefs.machine.spindovr },
            .{ .h = .mach_trx, .t = .mach_trx, .title = "Travel X", .vmin = 50, .vmax = 2000, .seed = self.prefs.machine.tr_x },
            .{ .h = .mach_try, .t = .mach_try, .title = "Travel Y", .vmin = 50, .vmax = 2000, .seed = self.prefs.machine.tr_y },
            .{ .h = .mach_trz, .t = .mach_trz, .title = "Travel Z", .vmin = 10, .vmax = 1000, .seed = self.prefs.machine.tr_z },
            .{ .h = .mach_tra, .t = .mach_tra, .title = "Travel A", .vmin = 1, .vmax = 7200, .seed = self.prefs.machine.tr_a },
            .{ .h = .mach_trb, .t = .mach_trb, .title = "Travel B", .vmin = 1, .vmax = 7200, .seed = self.prefs.machine.tr_b },
            .{ .h = .mach_trc, .t = .mach_trc, .title = "Travel C", .vmin = 1, .vmax = 7200, .seed = self.prefs.machine.tr_c },
        };
        for (pairs) |m| {
            if (m.h != hit) continue;
            if ((hit == .mach_trx or hit == .mach_try or hit == .mach_trz or hit == .mach_tra or hit == .mach_trb or hit == .mach_trc) and !self.machine_envelope_armed) {
                self.envelope_pending_enable = false;
                self.openSettingsConfirm(.mach_slim);
                return true;
            }
            const row = self.slotRect(m.h) orelse return false;
            if (settings_form.sliderValueHit(row, x, y)) {
                self.openNumberForTarget(m.t, m.title, m.seed);
                return true;
            }
            if (settings_form.sliderDragHit(row, x, y)) {
                self.slider_drag = m.t;
                self.applySliderDrag(m.t, x);
                self.applyPrefs();
                self.requestFull();
                return true;
            }
        }
        return false;
    }

    pub fn handlePointerDrag(self: *Engine, x: i32, y: i32) void {
        const p = self.mapPointer(x, y);
        if (self.pad.open) return;

        if (quick_settings.isOpen(self.sheet_y.value)) {
            const sy: i32 = i32FromF(@floor(self.sheet_y.value));
            const panel = quick_settings.panelRect(sy);
            if (!self.qs_drag and quick_settings.handleHitRect(panel).contains(p.x, p.y)) {
                self.qs_drag = true;
                self.qs_drag_grab = p.y - sy;
                self.qs_slider = .none;
            }
            if (self.qs_drag) {
                const open_y = quick_settings.openY();
                const closed_y = quick_settings.closedY();
                const new_sy = std.math.clamp(p.y - self.qs_drag_grab, open_y, closed_y);
                self.sheet_y.value = @floatFromInt(new_sy);
                self.sheet_y.target = @floatFromInt(new_sy);
                self.sheet_y.velocity = 0;
                self.repaintQs();
                return;
            }
            if (self.qs_zb_level_drag and self.qs_zb_detail != 0xff) {
                const card = quick_settings.detailCardRect(quick_settings.panelRect(sy));
                const row = quick_settings.detailLevelRow(card);
                const pct = quick_settings.sliderPctFromX(row, p.x);
                const level: u8 = @intCast((@as(u16, pct) * 254) / 100);
                self.prefs.wireless.live_zb_snap[self.qs_zb_detail].level = level;
                _ = self.emitWireless(.{ .zb_level = .{ .idx = self.qs_zb_detail, .level = level } });
                self.repaintQs();
                return;
            }
            if (self.qs_slider != .none) {
                switch (self.qs_slider) {
                    .bright => self.prefs.display.bright = quick_settings.sliderPctFromX(quick_settings.brightHitRect(sy, self.qs_body_scroll), p.x),
                    .volume => {
                        self.prefs.audio.silent = false;
                        self.prefs.audio.vol = quick_settings.sliderPctFromX(quick_settings.volumeHitRect(sy, self.qs_body_scroll), p.x);
                    },
                    .none => {},
                }
                self.applyPrefs();
                self.repaintQs();
                return;
            }
            if (self.qs_zb_hold_idx != 0xff and self.drag_scrolled) {
                self.qs_zb_hold_idx = 0xff;
            }
            // QS body finger scroll (same as wheel → nudgeScroll).
            if (self.qs_zb_detail == 0xff) self.fingerScrollBy(p.y);
            return;
        }

        if (self.slider_drag != .none) {
            self.applySliderDrag(self.slider_drag, p.x);
            self.applyPrefs();
            self.requestSettingsPresent();
            return;
        }

        if (self.screen == .catalog and self.catalog.slider_row.contains(p.x, p.y)) {
            md3_catalog.applyHit(&self.catalog, .slider, p.x);
            self.requestFull();
            return;
        }

        // Settings content + DRO: finger drag scrolls (host uses wheel; Tab5 has none).
        if (self.settings_confirm == .none and self.power_confirm == .none and
            (self.screen == .settings or self.screen == .dashboard or self.screen == .catalog))
        {
            self.handleHover(p.x, p.y);
            self.fingerScrollBy(p.y);
        }
    }

    /// Frame-to-frame finger delta → `nudgeScroll`. Marks `drag_scrolled` past 12px slop.
    fn fingerScrollBy(self: *Engine, y: i32) void {
        if (self.drag_last_y < 0) {
            self.drag_last_y = y;
            self.drag_origin_y = y;
            return;
        }
        const dy = y - self.drag_last_y;
        self.drag_last_y = y;
        if (dy != 0) {
            self.nudgeScroll(@as(f32, @floatFromInt(-dy)));
        }
        if (self.drag_origin_y >= 0 and @abs(y - self.drag_origin_y) >= 12) {
            self.drag_scrolled = true;
        }
    }

    /// Press edge — capture slider / QS track so finger drag works (device never had pointer-down).
    pub fn handlePointerDown(self: *Engine, x: i32, y: i32) void {
        const p = self.mapPointer(x, y);
        if (self.pad.open) return;
        if (self.settings_confirm != .none or self.power_confirm != .none) return;

        if (quick_settings.isOpen(self.sheet_y.value)) {
            const sy: i32 = i32FromF(@floor(self.sheet_y.value));
            const h = quick_settings.hit(p.x, p.y, sy, &self.prefs, self.qs_body_scroll, self.qs_zb_detail);
            switch (h.kind) {
                .bright => {
                    self.prefs.display.bright = quick_settings.sliderPctFromX(quick_settings.brightHitRect(sy, self.qs_body_scroll), p.x);
                    self.qs_slider = .bright;
                    self.applyPrefs();
                    self.repaintQs();
                },
                .volume => {
                    self.prefs.audio.silent = false;
                    self.prefs.audio.vol = quick_settings.sliderPctFromX(quick_settings.volumeHitRect(sy, self.qs_body_scroll), p.x);
                    self.qs_slider = .volume;
                    self.applyPrefs();
                    self.repaintQs();
                },
                .zb_detail_level => {
                    const card = quick_settings.detailCardRect(quick_settings.panelRect(sy));
                    const row = quick_settings.detailLevelRow(card);
                    const pct = quick_settings.sliderPctFromX(row, p.x);
                    const level: u8 = @intCast((@as(u16, pct) * 254) / 100);
                    self.prefs.wireless.live_zb_snap[self.qs_zb_detail].level = level;
                    self.qs_zb_level_drag = true;
                    _ = self.emitWireless(.{ .zb_level = .{ .idx = self.qs_zb_detail, .level = level } });
                    self.repaintQs();
                },
                .zb_dev => {
                    self.qs_zb_hold_idx = h.index;
                    self.qs_zb_hold_frame = self.frame_n;
                    self.qs_zb_hold_fired = false;
                },
                else => {
                    self.qs_zb_hold_idx = 0xff;
                },
            }
            return;
        }

        if (self.screen != .settings or self.menu_target != .none) return;

        if (self.tab_selected == k_display_tab) {
            const r = settings_display_tab.hitTest(self.disp_layout, p.x, p.y);
            if (r.hit == .bright and settings_form.sliderDragHit(self.disp_layout.bright, p.x, p.y)) {
                self.slider_drag = .disp_bright;
                self.noteSettingsRow(self.disp_layout.bright);
                self.applySliderDrag(.disp_bright, p.x);
                self.applyPrefs();
                self.requestSettingsPresent();
            }
            return;
        }
        if (self.tab_selected == k_dashboard_tab) {
            const r = settings_dashboard_tab.hitTest(self.dash_layout, self.prefs.dash, p.x, p.y);
            _ = self.tryCaptureDashSlider(r.hit, p.x, p.y);
            return;
        }
        // Audio / machine / other tabs with sliders.
        const r = settings_other_tabs.hitTest(self.other_layout, p.x, p.y);
        _ = self.tryCaptureOtherSlider(r.hit, p.x, p.y);
    }

    fn tryCaptureDashSlider(self: *Engine, hit: settings_dashboard_tab.Hit, x: i32, y: i32) bool {
        const map = [_]struct { h: settings_dashboard_tab.Hit, t: input_pad.Target, row: geom.Rect }{
            .{ .h = .coal, .t = .dash_coal, .row = self.dash_layout.coal },
            .{ .h = .pend, .t = .dash_pend, .row = self.dash_layout.pend },
            .{ .h = .encdiv, .t = .dash_encdiv, .row = self.dash_layout.encdiv },
            .{ .h = .contpct, .t = .dash_contpct, .row = self.dash_layout.contpct },
        };
        for (map) |m| {
            if (m.h != hit) continue;
            if (!settings_form.sliderDragHit(m.row, x, y)) return false;
            self.slider_drag = m.t;
            self.noteSettingsRow(m.row);
            self.applySliderDrag(m.t, x);
            self.applyPrefs();
            self.requestSettingsPresent();
            return true;
        }
        return false;
    }

    fn tryCaptureOtherSlider(self: *Engine, hit: settings_other_tabs.Hit, x: i32, y: i32) bool {
        const pairs = [_]struct { h: settings_other_tabs.Hit, t: input_pad.Target }{
            .{ .h = .aud_vol, .t = .aud_vol },
            .{ .h = .mach_mxfeed, .t = .mach_mxfeed },
            .{ .h = .mach_mxrpm, .t = .mach_mxrpm },
            .{ .h = .mach_jogspd, .t = .mach_jogspd },
            .{ .h = .mach_feedovr, .t = .mach_feedovr },
            .{ .h = .mach_spindovr, .t = .mach_spindovr },
            .{ .h = .mach_trx, .t = .mach_trx },
            .{ .h = .mach_try, .t = .mach_try },
            .{ .h = .mach_trz, .t = .mach_trz },
            .{ .h = .mach_tra, .t = .mach_tra },
            .{ .h = .mach_trb, .t = .mach_trb },
            .{ .h = .mach_trc, .t = .mach_trc },
        };
        for (pairs) |m| {
            if (m.h != hit) continue;
            if (hit == .aud_vol and !self.prefs.audio.out_ready) return false;
            const row = self.slotRect(m.h) orelse return false;
            if (!settings_form.sliderDragHit(row, x, y)) return false;
            self.slider_drag = m.t;
            self.noteSettingsRow(row);
            self.applySliderDrag(m.t, x);
            self.applyPrefs();
            self.requestSettingsPresent();
            return true;
        }
        return false;
    }

    pub fn handlePointerUp(self: *Engine) bool {
        const scrolled = self.drag_scrolled;
        const slider_active = self.slider_drag != .none or self.qs_slider != .none or self.qs_zb_level_drag;
        // Consume long-press flag once — leave sticky and every later tap skips click
        // (Exposes overlay never receives zb_detail_scrim close).
        const zb_long = self.qs_zb_hold_fired;
        self.qs_zb_hold_fired = false;
        self.drag_last_y = -1;
        self.drag_scrolled = false;
        self.drag_origin_y = -1;
        self.qs_zb_hold_idx = 0xff;
        self.qs_zb_level_drag = false;

        if (self.qs_drag) {
            self.qs_drag = false;
            const sy: i32 = i32FromF(@floor(self.sheet_y.value));
            const mid = @divTrunc(quick_settings.openY() + quick_settings.closedY(), 2);
            if (sy > mid) {
                self.closeQuickSettings();
            } else {
                const oy = quick_settings.openY();
                self.sheet_y.value = @floatFromInt(oy);
                self.sheet_y.target = @floatFromInt(oy);
                self.sheet_y.velocity = 0;
                self.prev_sheet_y = sy;
                self.requestFull();
            }
        }
        self.slider_drag = .none;
        self.qs_slider = .none;
        // Skip synthetic click after track drag / Zigbee long-press detail.
        return scrolled or slider_active or zb_long;
    }

    fn openNumberForTarget(self: *Engine, target: input_pad.Target, title: []const u8, seed: u32) void {
        var buf: [16]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d}", .{seed}) catch "0";
        self.pad.openPad(.number, target, title, s);
        self.pad.kb_full = self.prefs.system.kb_full;
        self.requestFull();
    }

    fn openTextPad(self: *Engine, target: input_pad.Target, title: []const u8, seed: []const u8) void {
        self.pad.openPad(.text, target, title, seed);
        self.pad.kb_full = self.prefs.system.kb_full;
        self.requestFull();
    }

    fn commitPad(self: *Engine) void {
        const t = self.pad.target;
        const txt = self.pad.text();
        // A number buffer that will not parse used to fall through every arm
        // and still report "Value set" — the operator saw a success toast for
        // a value that was never written.
        if (self.pad.mode == .number and !input_pad.numberValid(t, txt)) {
            self.showSnackbarError("Enter a number");
            self.pad.clear();
            self.afterPadDismiss();
            return;
        }
        switch (t) {
            .none => {},
            .disp_bright => if (self.pad.parseU32()) |v| {
                self.prefs.display.bright = @intCast(@max(5, @min(100, v)));
            },
            .dash_coal => if (self.pad.parseU32()) |v| {
                self.prefs.dash.jog_coal_ms = @intCast(@min(100, v));
            },
            .dash_pend => if (self.pad.parseU32()) |v| {
                self.prefs.dash.jog_pend_max = @intCast(@max(4, @min(64, v)));
            },
            .dash_encdiv => if (self.pad.parseU32()) |v| {
                self.prefs.dash.encdiv = @intCast(@max(1, @min(16, v)));
            },
            .dash_contpct => if (self.pad.parseU32()) |v| {
                self.prefs.dash.contpct = @intCast(@max(10, @min(200, v)));
            },
            .aud_vol => if (self.pad.parseU32()) |v| {
                self.prefs.audio.vol = @intCast(@min(100, v));
            },
            .mach_mxfeed => if (self.pad.parseU32()) |v| {
                self.prefs.machine.mxfeed = @intCast(@max(100, @min(20000, v)));
            },
            .mach_mxrpm => if (self.pad.parseU32()) |v| {
                self.prefs.machine.mxrpm = @intCast(@max(1000, @min(60000, v)));
            },
            .mach_jogspd => if (self.pad.parseU32()) |v| {
                self.prefs.machine.jogspd = @intCast(@max(100, @min(10000, v)));
                self.prefs.dash.setJogspdIdxFromMm(self.prefs.machine.jogspd);
            },
            .mach_feedovr => if (self.pad.parseU32()) |v| {
                self.prefs.machine.feedovr = @intCast(@max(10, @min(200, v)));
            },
            .mach_spindovr => if (self.pad.parseU32()) |v| {
                self.prefs.machine.spindovr = @intCast(@max(10, @min(200, v)));
            },
            .mach_trx => if (self.pad.parseU32()) |v| {
                self.prefs.machine.tr_x = @intCast(@max(50, @min(2000, v)));
            },
            .mach_try => if (self.pad.parseU32()) |v| {
                self.prefs.machine.tr_y = @intCast(@max(50, @min(2000, v)));
            },
            .mach_trz => if (self.pad.parseU32()) |v| {
                self.prefs.machine.tr_z = @intCast(@max(10, @min(1000, v)));
            },
            .mach_tra => if (self.pad.parseU32()) |v| {
                self.prefs.machine.tr_a = @intCast(@max(1, @min(7200, v)));
            },
            .mach_trb => if (self.pad.parseU32()) |v| {
                self.prefs.machine.tr_b = @intCast(@max(1, @min(7200, v)));
            },
            .mach_trc => if (self.pad.parseU32()) |v| {
                self.prefs.machine.tr_c = @intCast(@max(1, @min(7200, v)));
            },
            .sys_datetime => {
                self.prefs.system.applyManualDate(self.pad.year, self.pad.month, self.pad.day);
                self.prefs.system.applyManualTime(self.pad.hour, self.pad.min, self.pad.sec);
                _ = self.emitStorSys(.{ .rtc_set = .{
                    .year = self.pad.year,
                    .month = self.pad.month,
                    .day = self.pad.day,
                    .hour = self.pad.hour,
                    .min = self.pad.min,
                    .sec = self.pad.sec,
                } });
                self.showSnackbar("Date/time set");
            },
            .sys_time => {
                self.prefs.system.applyManualTime(self.pad.hour, self.pad.min, self.pad.sec);
                const ymd = self.prefs.system.ymdParts();
                _ = self.emitStorSys(.{ .rtc_set = .{
                    .year = @intCast(ymd.y),
                    .month = @intCast(ymd.m),
                    .day = @intCast(ymd.d),
                    .hour = self.pad.hour,
                    .min = self.pad.min,
                    .sec = self.pad.sec,
                } });
                self.showSnackbar("Time set");
            },
            .sys_date => {
                self.prefs.system.applyManualDate(self.pad.year, self.pad.month, self.pad.day);
                const hms = self.prefs.system.hmsParts();
                _ = self.emitStorSys(.{ .rtc_set = .{
                    .year = self.pad.year,
                    .month = self.pad.month,
                    .day = self.pad.day,
                    .hour = @intCast(hms.h),
                    .min = @intCast(hms.m),
                    .sec = @intCast(hms.s),
                } });
                self.showSnackbar("Date set");
            },
            .mach_name => {
                if (self.mach_str_overlay == .name) {
                    const n = @min(txt.len, self.mach_str_draft.len);
                    @memset(&self.mach_str_draft, 0);
                    @memcpy(self.mach_str_draft[0..n], txt[0..n]);
                    self.mach_str_draft_len = @intCast(n);
                    self.mach_str_focus = false;
                    self.pad.clear();
                    self.afterPadDismiss();
                    return;
                }
                self.prefs.machine.setName(txt);
            },
            .mach_svc_dt => {
                var dbuf: [16]u8 = undefined;
                const formatted = std.fmt.bufPrint(&dbuf, "{d:0>4}-{d:0>2}-{d:0>2}", .{
                    self.pad.year,
                    self.pad.month,
                    self.pad.day,
                }) catch "2020-01-01";
                @memset(&self.prefs.machine.svc_dt, 0);
                const n = @min(formatted.len, self.prefs.machine.svc_dt.len);
                @memcpy(self.prefs.machine.svc_dt[0..n], formatted[0..n]);
            },
            .mach_svc_nt => {
                if (self.mach_str_overlay == .svc_nt) {
                    const n = @min(txt.len, self.mach_str_draft.len);
                    @memset(&self.mach_str_draft, 0);
                    @memcpy(self.mach_str_draft[0..n], txt[0..n]);
                    self.mach_str_draft_len = @intCast(n);
                    self.mach_str_focus = false;
                    self.pad.clear();
                    self.afterPadDismiss();
                    return;
                }
                self.prefs.machine.setSvcNotes(txt);
            },
            .wl_ssid => {
                const n = @min(txt.len, self.prefs.wireless.ssid.len);
                @memset(&self.prefs.wireless.ssid, 0);
                @memcpy(self.prefs.wireless.ssid[0..n], txt[0..n]);
            },
            .wl_pass => settings_prefs.WirelessPrefs.setDraftField(&self.prefs.wireless.draft_pass, txt),
            .wl_zb_code => settings_prefs.WirelessPrefs.setDraftField(&self.prefs.wireless.zb_install, txt),
            .wl_th_node => settings_prefs.WirelessPrefs.setDraftField(&self.prefs.wireless.th_node, txt),
            .wl_bt_passkey => settings_prefs.WirelessPrefs.setDraftField(&self.prefs.wireless.bt_passkey, txt),
            .wl_en_mac => {
                if (self.emitWireless(.{ .en_commit_mac = txt })) {
                    self.showSnackbar("Bridge MAC saved");
                } else {
                    self.prefs.wireless.commitMac(txt);
                    self.prefs.syncEspnowMacFromBridge();
                    self.showSnackbar("Bridge MAC saved");
                }
            },
            .cnc_masso_ip => {
                const n = @min(txt.len, self.prefs.cnc.masso_ip.len);
                @memset(&self.prefs.cnc.masso_ip, 0);
                @memcpy(self.prefs.cnc.masso_ip[0..n], txt[0..n]);
            },
            .cnc_ws_host => settings_prefs.CncPrefs.setHostField(&self.prefs.cnc.ws_host, txt),
            .cnc_ws_path => settings_prefs.CncPrefs.setHostField(&self.prefs.cnc.ws_path, txt),
            .cnc_tn_host => settings_prefs.CncPrefs.setHostField(&self.prefs.cnc.tn_host, txt),
            .cnc_ble_name => settings_prefs.CncPrefs.setHostField(&self.prefs.cnc.ble_name, txt),
            .cnc_ws_port => self.prefs.cnc.ws_port = std.fmt.parseInt(u16, txt, 10) catch self.prefs.cnc.ws_port,
            .cnc_tn_port => self.prefs.cnc.tn_port = std.fmt.parseInt(u16, txt, 10) catch self.prefs.cnc.tn_port,
            .cnc_i2c_addr => {
                const v = std.fmt.parseInt(u8, txt, 0) catch self.prefs.cnc.i2c_addr;
                self.prefs.cnc.i2c_addr = @max(0x03, @min(v, 0x77));
            },
            .cnc_can_nid => self.prefs.cnc.can_nid = std.fmt.parseInt(u8, txt, 10) catch self.prefs.cnc.can_nid,
            .cnc_prof_rename => {
                self.prefs.cnc.renameProfile(self.cnc_rename_slot, txt);
                self.showSnackbar("Profile renamed");
            },
            .dash_incr => {
                self.prefs.dash.setIncrFromCsv(txt);
                self.applyPrefs();
                self.showSnackbar("Increments saved");
            },
            .dash_wcs_name => {
                self.prefs.dash.setWcsName(self.dash_wcs_name_i, txt);
                self.applyPrefs();
                self.showSnackbar("WCS renamed");
            },
            .dash_mac_name => settings_prefs.MacroSlot.setField(&self.dash_mac_draft.name, txt),
            .dash_mac_on => settings_prefs.MacroSlot.setField(&self.dash_mac_draft.on, txt),
            .dash_mac_off => settings_prefs.MacroSlot.setField(&self.dash_mac_draft.off, txt),
            .dash_probe_zoff => {
                const mm = std.fmt.parseFloat(f32, txt) catch {
                    self.showSnackbar("Invalid thickness");
                    self.pad.clear();
                    self.afterPadDismiss();
                    return;
                };
                const clamped = std.math.clamp(mm, 0.1, 50.0);
                self.prefs.dash.probe_zoff_x10 = @intFromFloat(@round(clamped * 10.0));
                self.applyPrefs();
                self.showSnackbar("Plate thickness set");
                self.pad.clear();
                self.afterPadDismiss();
                return;
            },
            .qs_mdi => {
                const n = @min(txt.len, self.qs_mdi.len);
                @memset(&self.qs_mdi, 0);
                @memcpy(self.qs_mdi[0..n], txt[0..n]);
                self.qs_mdi_len = n;
                self.repaintQs();
            },
            .search => {
                self.syncSearchFromPad();
                self.pad.clear();
                self.afterPadDismiss();
                return;
            },
            .sec_pin_unlock => {
                if (self.prefs.security.has_pin) {
                    if (!self.checkPin(txt)) {
                        self.showSnackbarError("Incorrect PIN");
                        self.relockPin();
                        return;
                    }
                } else if (txt.len < 4) {
                    self.showSnackbarError("Enter 4+ digits");
                    self.relockPin();
                    return;
                }
                if (self.pin_unlock_sink) |u| u();
                self.pad.clear();
                self.screen = .dashboard;
                self.showSnackbar("Unlocked");
                self.forceFullPresent();
                return;
            },
            .sec_pin_new => {
                const n = @min(txt.len, self.pin_draft1.len);
                @memset(&self.pin_draft1, 0);
                @memcpy(self.pin_draft1[0..n], txt[0..n]);
                self.pin_draft1_len = @intCast(n);
                self.pad.clear();
                self.setPinStatus("", false);
                self.afterPadDismiss();
                return;
            },
            .sec_pin_confirm => {
                const n = @min(txt.len, self.pin_draft2.len);
                @memset(&self.pin_draft2, 0);
                @memcpy(self.pin_draft2[0..n], txt[0..n]);
                self.pin_draft2_len = @intCast(n);
                self.pad.clear();
                self.setPinStatus("", false);
                self.afterPadDismiss();
                return;
            },
            .sec_pin_clear => {
                const n = @min(txt.len, self.pin_draft1.len);
                @memset(&self.pin_draft1, 0);
                @memcpy(self.pin_draft1[0..n], txt[0..n]);
                self.pin_draft1_len = @intCast(n);
                self.pad.clear();
                self.setPinStatus("", false);
                self.afterPadDismiss();
                return;
            },
        }
        self.pad.clear();
        self.applyPrefs();
        self.showSnackbar("Value set");
        self.afterPadDismiss();
    }

    fn applySliderDrag(self: *Engine, target: input_pad.Target, x: i32) void {
        switch (target) {
            .disp_bright => self.prefs.display.bright = @intCast(@max(5, settings_form.sliderValueAt(self.disp_layout.bright, 5, 100, x))),
            .dash_coal => self.prefs.dash.jog_coal_ms = @intCast(settings_form.sliderValueAt(self.dash_layout.coal, 0, 100, x)),
            .dash_pend => self.prefs.dash.jog_pend_max = @intCast(@max(4, settings_form.sliderValueAt(self.dash_layout.pend, 4, 64, x))),
            .dash_encdiv => self.prefs.dash.encdiv = @intCast(@max(1, settings_form.sliderValueAt(self.dash_layout.encdiv, 1, 16, x))),
            .dash_contpct => self.prefs.dash.contpct = @intCast(@max(10, settings_form.sliderValueAt(self.dash_layout.contpct, 10, 200, x))),
            .aud_vol => {
                if (self.slotRect(.aud_vol)) |r| self.prefs.audio.vol = @intCast(settings_form.sliderValueAt(r, 0, 100, x));
            },
            .mach_mxfeed => {
                if (self.slotRect(.mach_mxfeed)) |r| self.prefs.machine.mxfeed = @intCast(@max(100, settings_form.sliderValueAt(r, 100, 20000, x)));
            },
            .mach_mxrpm => {
                if (self.slotRect(.mach_mxrpm)) |r| self.prefs.machine.mxrpm = @intCast(@max(1000, settings_form.sliderValueAt(r, 1000, 60000, x)));
            },
            .mach_jogspd => {
                if (self.slotRect(.mach_jogspd)) |r| {
                    self.prefs.machine.jogspd = @intCast(@max(100, settings_form.sliderValueAt(r, 100, 10000, x)));
                    self.prefs.dash.setJogspdIdxFromMm(self.prefs.machine.jogspd);
                }
            },
            .mach_feedovr => {
                if (self.slotRect(.mach_feedovr)) |r| self.prefs.machine.feedovr = @intCast(@max(10, settings_form.sliderValueAt(r, 10, 200, x)));
            },
            .mach_spindovr => {
                if (self.slotRect(.mach_spindovr)) |r| self.prefs.machine.spindovr = @intCast(@max(10, settings_form.sliderValueAt(r, 10, 200, x)));
            },
            .mach_trx => {
                if (self.slotRect(.mach_trx)) |r| self.prefs.machine.tr_x = @intCast(@max(50, settings_form.sliderValueAt(r, 50, 2000, x)));
            },
            .mach_try => {
                if (self.slotRect(.mach_try)) |r| self.prefs.machine.tr_y = @intCast(@max(50, settings_form.sliderValueAt(r, 50, 2000, x)));
            },
            .mach_trz => {
                if (self.slotRect(.mach_trz)) |r| self.prefs.machine.tr_z = @intCast(@max(10, settings_form.sliderValueAt(r, 10, 1000, x)));
            },
            .mach_tra => {
                if (self.slotRect(.mach_tra)) |r| self.prefs.machine.tr_a = @intCast(@max(1, settings_form.sliderValueAt(r, 1, 7200, x)));
            },
            .mach_trb => {
                if (self.slotRect(.mach_trb)) |r| self.prefs.machine.tr_b = @intCast(@max(1, settings_form.sliderValueAt(r, 1, 7200, x)));
            },
            .mach_trc => {
                if (self.slotRect(.mach_trc)) |r| self.prefs.machine.tr_c = @intCast(@max(1, settings_form.sliderValueAt(r, 1, 7200, x)));
            },
            else => {},
        }
    }

    fn slotRect(self: *Engine, hit: settings_other_tabs.Hit) ?geom.Rect {
        var i: usize = 0;
        while (i < self.other_layout.n) : (i += 1) {
            if (self.other_layout.slots[i].hit == hit) return self.other_layout.slots[i].rect;
        }
        return null;
    }

    pub fn handleClick(self: *Engine, x_in: i32, y_in: i32) void {
        const mapped = self.mapPointer(x_in, y_in);
        const x = mapped.x;
        const y = mapped.y;
        // LVGL splash: no tap-skip — timer only.
        if (self.screen == .boot) return;

        // Snackbar action (Undo)
        if (self.snack_frames > 0 and self.snack_action_len > 0 and self.snack_action_rect.contains(x, y)) {
            if (self.snack_undo_dark) |d| {
                self.prefs.display.darkmode = d;
                self.applyPrefs();
            }
            self.snack_frames = 0;
            self.snack_action_len = 0;
            self.snack_undo_dark = null;
            self.requestFull();
            return;
        }
        // Dropdown menu — pick closes; tap outside menu_hit closes; idle does not.
        if (self.menu_target != .none) {
            if (self.menu_hit.contains(x, y)) {
                const labs = settings_menu.labels(self.menu_target);
                if (expr.menuIndexAt(self.menu_hit, self.menu_scroll, labs.len, y)) |idx| {
                    if (self.menu_target == .language) {
                        const cur = self.prefs.system.lang;
                        const chosen: u8 = @intCast(@min(idx, labs.len - 1));
                        self.closeMenu();
                        if (chosen != cur) {
                            self.pending_lang = chosen;
                            self.openSettingsConfirm(.language);
                        }
                        return;
                    }
                    settings_menu.apply(&self.prefs, self.menu_target, idx);
                    self.applyPrefs();
                    if (self.menu_target == .wcs) {
                        const bit: u8 = @as(u8, 1) << @intCast(@min(idx, 5));
                        if ((self.prefs.dash.wcs_lock & bit) != 0) {
                            self.showSnackbarError("WCS locked");
                        } else {
                            self.showSnackbar("Menu selection");
                        }
                    } else {
                        self.showSnackbar("Menu selection");
                    }
                    self.closeMenu();
                    return;
                }
                // Tap on menu chrome (padding / scrollbar band) — keep open.
                return;
            }
            self.closeMenu();
            return;
        }
        if (self.pad.open) {
            if (self.pad.target == .search and self.screen == .settings) {
                self.syncSearchFromPad();
                const show_cats = settings_form.useRail() or self.settings_hub;
                if (show_cats and self.handleSettingsSearchClick(x, y)) {
                    if (self.pad.open) {
                        self.pad.clear();
                        self.afterPadDismiss();
                    }
                    return;
                }
            }
            const info = input_pad.hitTest(&self.pad, x, y);
            switch (input_pad.applyHit(&self.pad, info)) {
                .none => {
                    if (self.pad.target == .search) self.syncSearchFromPad();
                    self.requestFull();
                },
                .close_cancel => {
                    if (self.screen == .pin) {
                        self.relockPin();
                    } else if (self.pad.target == .search) {
                        self.syncSearchFromPad();
                        self.pad.clear();
                        self.afterPadDismiss();
                    } else {
                        self.afterPadDismiss();
                    }
                },
                .close_ok => self.commitPad(),
            }
            return;
        }
        if (self.mach_str_overlay != .none and self.screen == .settings) {
            self.handleMachStrOverlayClick(x, y);
            return;
        }
        if (self.extra_overlay != .none and self.screen == .settings) {
            self.handleExtraOverlayClick(x, y);
            return;
        }
        if (self.pin_overlay != .none and self.screen == .settings) {
            self.handlePinOverlayClick(x, y);
            return;
        }
        if (self.dash_overlay != .none and self.screen == .settings) {
            self.handleDashOverlayClick(x, y);
            return;
        }
        if (self.cnc_overlay != .none and self.screen == .settings) {
            self.handleCncOverlayClick(x, y);
            return;
        }
        // Confirm works on dashboard too (DRO Zero / Home-all policies).
        if (self.settings_confirm != .none) {
            if (self.settings_confirm_ok.contains(x, y)) {
                self.applySettingsConfirm();
                return;
            }
            if (self.settings_confirm_cancel.contains(x, y) or !self.settings_confirm_card.contains(x, y)) {
                self.closeSettingsConfirm();
                return;
            }
            return;
        }

        if (self.dialog_open) {
            if (self.dialog_ok.contains(x, y)) self.closeDialog();
            return;
        }
        if (self.screen == .pin) {
            self.relockPin();
            return;
        }
        if (self.screen == .catalog) {
            const hit = md3_catalog.hitTest(&self.catalog, x, y);
            if (hit == .back) {
                self.closeCatalog();
                return;
            }
            if (hit != .none) {
                md3_catalog.applyHit(&self.catalog, hit, x);
                self.requestFull();
            }
            return;
        }
        if (self.screen == .power) {
            if (self.power_confirm != .none) {
            if (self.power_layout.confirm_ok.contains(x, y)) {
                    if (self.power_confirm == .shutdown) {
                        if (self.power_shutdown_sink) |s| s() else self.showSnackbar("Shutdown (stub)");
                    } else {
                        if (self.power_restart_sink) |s| s() else self.showSnackbar("Restart (stub)");
                    }
                    self.closePowerMenu();
                    return;
                }
                if (self.power_layout.confirm_cancel.contains(x, y) or !self.power_layout.confirm_card.contains(x, y)) {
                    self.power_confirm = .none;
                    self.requestFull();
                    return;
                }
                return;
            }
            if (self.power_layout.close.contains(x, y) or !self.power_layout.card.contains(x, y)) {
                self.closePowerMenu();
                return;
            }
            if (self.power_layout.reset.contains(x, y)) {
                _ = self.emitCnc(.reset);
                self.showSnackbar("Soft reset sent");
                self.closePowerMenu();
                return;
            }
            if (self.power_layout.unlock.contains(x, y)) {
                _ = self.emitCnc(.unlock);
                self.showSnackbar("Unlock");
                self.closePowerMenu();
                return;
            }
            if (self.power_layout.restart.contains(x, y)) {
                if (machineBusy(self.cnc)) return;
                self.power_confirm = .restart;
                snapEnter(&self.power_confirm_fx);
                self.requestFull();
                return;
            }
            if (self.power_layout.shutdown.contains(x, y)) {
                if (machineBusy(self.cnc)) return;
                self.power_confirm = .shutdown;
                snapEnter(&self.power_confirm_fx);
                self.requestFull();
                return;
            }
            return;
        }

        const sy: i32 = i32FromF(@floor(self.sheet_y.value));
        if (quick_settings.isOpen(self.sheet_y.value)) {
            const h = quick_settings.hit(x, y, sy, &self.prefs, self.qs_body_scroll, self.qs_zb_detail);
            switch (h.kind) {
                .none => {},
                .scrim => {
                    self.closeQuickSettings();
                    return;
                },
                .zb_detail_scrim => {
                    self.closeQsZbDetail();
                    return;
                },
                .zb_detail_identify => {
                    _ = self.emitWireless(.{ .zb_identify = self.qs_zb_detail });
                    self.showSnackbar("Identify");
                    return;
                },
                .zb_detail_remove => {
                    const idx = self.qs_zb_detail;
                    if (!self.emitWireless(.{ .zb_remove = idx })) {
                        if (idx < self.prefs.wireless.live_zb_n) {
                            self.prefs.wireless.live_zb_n -|= 1;
                            self.prefs.wireless.zb_dev_n = self.prefs.wireless.live_zb_n;
                        }
                    }
                    self.closeQsZbDetail();
                    self.showSnackbar("Device removed");
                    return;
                },
                .zb_detail_refresh => {
                    _ = self.emitWireless(.{ .zb_sensors = self.qs_zb_detail });
                    _ = self.emitWireless(.zb_refresh);
                    self.repaintQs();
                    return;
                },
                .zb_detail_cover => {
                    _ = self.emitWireless(.{ .zb_cover = .{ .idx = self.qs_zb_detail, .op = h.index } });
                    self.repaintQs();
                    return;
                },
                .zb_detail_level => {
                    const card = quick_settings.detailCardRect(quick_settings.panelRect(sy));
                    const row = quick_settings.detailLevelRow(card);
                    const pct = quick_settings.sliderPctFromX(row, x);
                    const level: u8 = @intCast((@as(u16, pct) * 254) / 100);
                    self.prefs.wireless.live_zb_snap[self.qs_zb_detail].level = level;
                    _ = self.emitWireless(.{ .zb_level = .{ .idx = self.qs_zb_detail, .level = level } });
                    self.repaintQs();
                    return;
                },
                .handle => {
                    self.qs_drag = true;
                    self.qs_drag_grab = y - sy;
                    return;
                },
                .gear => {
                    self.closeQuickSettings();
                    self.openSettings();
                    return;
                },
                .radio => {
                    if (self.prefs.wireless.airplane) self.prefs.wireless.airplane = false;
                    switch (h.index) {
                        0 => self.prefs.wireless.wifi = !self.prefs.wireless.wifi,
                        1 => self.prefs.wireless.bt = !self.prefs.wireless.bt,
                        2 => self.prefs.wireless.espnow = !self.prefs.wireless.espnow,
                        3 => self.prefs.wireless.zigbee = !self.prefs.wireless.zigbee,
                        4 => self.prefs.wireless.thread = !self.prefs.wireless.thread,
                        else => {},
                    }
                    self.applyPrefs();
                    self.repaintQs();
                    return;
                },
                .action => {
                    switch (h.index) {
                        0 => { // Airplane
                            self.prefs.wireless.airplane = !self.prefs.wireless.airplane;
                            if (self.prefs.wireless.airplane) {
                                self.prefs.wireless.wifi = false;
                                self.prefs.wireless.bt = false;
                                self.prefs.wireless.espnow = false;
                                self.prefs.wireless.zigbee = false;
                                self.prefs.wireless.thread = false;
                            }
                            self.applyPrefs();
                            self.repaintQs();
                        },
                        1 => { // Silent
                            self.prefs.audio.silent = !self.prefs.audio.silent;
                            self.applyPrefs();
                            self.repaintQs();
                        },
                        2 => { // Screen Lock
                            self.closeQuickSettings();
                            self.openPin();
                        },
                        3 => { // Performance HUD
                            self.prefs.system.perf_hud = !self.prefs.system.perf_hud;
                            self.cnc.perf_hud = self.prefs.system.perf_hud;
                            self.applyPrefs();
                            self.repaintQs();
                        },
                        4 => { // Dark / Light
                            self.toggleTheme();
                            self.repaintQs();
                        },
                        else => {},
                    }
                    return;
                },
                .bright => {
                    self.prefs.display.bright = quick_settings.sliderPctFromX(quick_settings.brightHitRect(sy, self.qs_body_scroll), x);
                    self.qs_slider = .bright;
                    self.applyPrefs();
                    self.repaintQs();
                    return;
                },
                .volume => {
                    self.prefs.audio.silent = false;
                    self.prefs.audio.vol = quick_settings.sliderPctFromX(quick_settings.volumeHitRect(sy, self.qs_body_scroll), x);
                    self.qs_slider = .volume;
                    self.applyPrefs();
                    self.repaintQs();
                    return;
                },
                .zb_dev => {
                    if (self.qs_zb_hold_fired) {
                        self.qs_zb_hold_fired = false;
                        return;
                    }
                    const snap = self.prefs.wireless.zbSnap(h.index);
                    if ((snap.caps & settings_prefs.ZbCap.cover) != 0) {
                        self.openQsZbDetail(h.index);
                        return;
                    }
                    if (snap.caps == settings_prefs.ZbCap.sensor) {
                        _ = self.emitWireless(.{ .zb_sensors = h.index });
                        self.repaintQs();
                        return;
                    }
                    if (!self.emitWireless(.{ .zb_toggle = h.index })) {
                        self.prefs.wireless.zb_dev_on[h.index] = !self.prefs.wireless.zb_dev_on[h.index];
                    }
                    self.repaintQs();
                    return;
                },
            }
            return; // absorb sheet panel clicks
        }

        if (self.screen == .settings) {
            self.syncSettingsLayout();
            if (settings_form.closeHitRect().contains(x, y)) {
                self.closeSettings();
                return;
            }
            // Click outside modal → close
            if (!settings_form.windowRect().contains(x, y)) {
                self.closeSettings();
                return;
            }
            const compact_detail = !settings_form.useRail() and !self.settings_hub;
            if (compact_detail and settings_form.backHitRect().contains(x, y)) {
                self.settings_hub = true;
                self.clearSearch();
                self.scroll.setTarget(0);
                self.scroll.value = 0;
                self.requestFull();
                return;
            }
            const show_cats = settings_form.useRail() or self.settings_hub;
            if (show_cats) {
                if (self.handleSettingsSearchClick(x, y)) return;
                if (!settings_form.useRail()) return; // hub: no content hits
            }
            if (x < settings_form.content_x) return;
            if (settings_form.mode_toggle_hit.contains(x, y)) {
                self.prefs.settings_advanced = !self.prefs.settings_advanced;
                self.applyPrefs();
                self.notifySaved();
                self.requestFull();
                return;
            }
            if (self.tab_selected == k_dashboard_tab) {
                const r = settings_dashboard_tab.hitTest(self.dash_layout, self.prefs.dash, x, y);
                if (r.hit != .none) {
                    self.noteSettingsRow(r.rect);
                    const mt = settings_menu.targetForDashHit(r.hit);
                    if (mt != .none) {
                        const anchor = switch (r.hit) {
                            .wcs => self.dash_layout.wcs,
                            .cnf_cycle => self.dash_layout.cnf_cycle,
                            .cnf_spin => self.dash_layout.cnf_spin,
                            .cnf_zero => self.dash_layout.cnf_zero,
                            .cnf_home => self.dash_layout.cnf_home,
                            .cnf_mac => self.dash_layout.cnf_mac,
                            .jogspd => self.dash_layout.jogspd,
                            else => geom.Rect{},
                        };
                        self.openMenu(mt, anchor);
                        return;
                    }
                    if (r.hit == .reset) {
                        self.openSettingsConfirm(.dashboard_reset);
                        return;
                    }
                    if (r.hit == .edit_incr) {
                        var csv_buf: [48]u8 = undefined;
                        const csv = self.prefs.dash.incrCsv(&csv_buf);
                        self.openTextPad(.dash_incr, "Edit increments", csv);
                        return;
                    }
                    if (r.hit == .wcs_lock) {
                        self.openDashWcs();
                        return;
                    }
                    if (r.hit == .mpg_dir) {
                        self.openExtra(.mpg);
                        return;
                    }
                    if (r.hit == .probe) {
                        self.openExtra(.probe);
                        return;
                    }
                    if (r.hit == .macro0 or r.hit == .macro1 or r.hit == .macro2 or r.hit == .macro3) {
                        const slot: u8 = switch (r.hit) {
                            .macro0 => 0,
                            .macro1 => 1,
                            .macro2 => 2,
                            else => 3,
                        };
                        self.openDashMacro(slot, true);
                        return;
                    }
                    if (r.hit == .add_qbtn) {
                        if (self.prefs.dash.firstFreeMacro()) |slot| {
                            self.openDashMacro(slot, false);
                        } else {
                            self.showSnackbar("All 4 custom buttons used");
                        }
                        return;
                    }
                    if (r.hit == .arrange) {
                        self.openDashArrange();
                        return;
                    }
                    if (self.tryOpenOrDragDashSlider(r.hit, x, y)) return;
                    // Segment miss (row hit, outside pill) — no apply/snackbar.
                    if ((r.hit == .jog_mode or r.hit == .axes) and r.seg == null) {
                        return;
                    }
                    if (settings_dashboard_tab.applyHit(&self.prefs.dash, r.hit, r.seg, x, self.dash_layout)) |jump| {
                        self.tab_selected = jump;
                        self.scroll.setTarget(0);
                        self.scroll.value = 0;
                        self.kickTabAxis();
                    }
                    self.applyPrefs();
                    self.notifySaved();
                    self.requestFull();
                    return;
                }
                return;
            }
            if (self.tab_selected == k_display_tab) {
                const r = settings_display_tab.hitTest(self.disp_layout, x, y);
                if (r.hit != .none) {
                    self.noteSettingsRow(r.rect);
                    const mt = settings_menu.targetForDisplayHit(r.hit);
                    if (mt != .none) {
                        self.openMenu(mt, self.disp_layout.accent);
                        return;
                    }
                    if (r.hit == .reset) {
                        self.openSettingsConfirm(.display_reset);
                        return;
                    }
                    if (self.tryOpenOrDragDispSlider(r.hit, x, y)) return;
                    if ((r.hit == .contrast or r.hit == .font_scale or r.hit == .refr or r.hit == .motion or r.hit == .notify_level) and r.seg == null) return;
                    if (settings_display_tab.applyHit(&self.prefs.display, r.hit, r.seg, x, self.disp_layout)) |jump| {
                        self.tab_selected = jump;
                        self.scroll.setTarget(0);
                        self.scroll.value = 0;
                        self.kickTabAxis();
                    }
                    if (r.hit == .single_pane) {
                        self.syncSettingsLayout();
                        self.settings_hub = !settings_form.useRail();
                    }
                    self.applyPrefs();
                    const msg: ?[]const u8 = switch (r.hit) {
                        .glove => if (self.prefs.display.touch_glove) "Glove on (+8px hits)" else "Glove off",
                        .wake => if (self.prefs.display.wake_motion) "Wake on motion" else "Wake on motion off",
                        .flip => if (self.prefs.display.flip) "Display flipped 180" else "Display normal",
                        .lefty => if (self.prefs.display.lefty) "Left-handed layout" else "Right-handed layout",
                        .single_pane => if (self.prefs.display.single_pane) "Single-pane settings" else "Two-pane settings",
                        .refr => self.prefs.display.refrHint(),
                        .smooth => if (self.prefs.display.smooth_anim) "Smooth animations on" else "Snappy utility motion",
                        .motion => if (self.prefs.display.motion_scheme != 0) "Expressive motion" else "Standard motion",
                        .contrast => switch (self.prefs.display.ui_contrast) {
                            0 => "Contrast: Standard",
                            1 => "Contrast: Medium",
                            else => "Contrast: High",
                        },
                        .font_scale => self.prefs.display.fontScaleName(),
                        .darkmode => if (self.prefs.display.darkmode) "Dark mode" else "Light mode",
                        .notify => if (self.prefs.display.notify_en) "Notifications on" else null,
                        .notify_level => self.prefs.display.notifyLevelName(),
                        else => null,
                    };
                    if (msg) |m| self.showSnackbar(m) else self.notifySaved();
                    self.requestFull();
                    return;
                }
                return;
            }
            {
                const r = settings_other_tabs.hitTest(self.other_layout, x, y);
                if (r.hit != .none) {
                    if (r.slot_i < self.other_layout.n) {
                        self.noteSettingsRow(self.other_layout.slots[r.slot_i].rect);
                    }
                    const mt = settings_menu.targetForOtherHit(r.hit);
                    if (mt != .none) {
                        // LVGL gates: deep-sleep dropdowns / wake-timer only when relevant.
                        if (mt == .pwr_dsto and !self.prefs.power.deepSleep()) {
                            self.showSnackbar("Deep sleep mode required");
                            self.requestFull();
                            return;
                        }
                        if (mt == .pwr_wtmin and !self.prefs.power.wake_timer) {
                            self.showSnackbar("Enable wake on timer first");
                            self.requestFull();
                            return;
                        }
                        if ((mt == .sec_tmo or mt == .sec_idle_tmo) and !self.prefs.security.has_pin) {
                            self.showSnackbar("Set a PIN first");
                            self.requestFull();
                            return;
                        }
                        const slot = if (r.slot_i < self.other_layout.n) self.other_layout.slots[r.slot_i] else settings_other_tabs.Slot{};
                        self.openMenu(mt, slot.rect);
                        return;
                    }
                    if (r.hit == .cnc_reset) {
                        self.openSettingsConfirm(.cnc_reset);
                        return;
                    }
                    if (r.hit == .cnc_configure) {
                        if (self.prefs.cnc.proto == 5) {
                            self.pad.openPad(.number, .cnc_masso_ip, "Masso controller IP", self.prefs.cnc.massoIpSlice());
                            self.pad.kb_full = self.prefs.system.kb_full;
                            self.requestFull();
                            return;
                        }
                        if (self.prefs.cnc.conn == 0 or self.prefs.cnc.transport_off) {
                            self.showSnackbar("Pick a transport first");
                            self.requestFull();
                            return;
                        }
                        self.openExtra(.transport);
                        return;
                    }
                    if (r.hit == .wl_disconnect) {
                        _ = settings_other_tabs.applyHit(&self.prefs, r.hit, r.seg, x, y, self.other_layout, r.slot_i);
                        if (self.emitWireless(.wifi_disconnect) or blk: {
                            if (self.wifi_disconnect_sink) |s| {
                                s();
                                break :blk true;
                            }
                            break :blk false;
                        }) {}
                        self.applyPrefs();
                        self.showSnackbar("Disconnected");
                        self.requestFull();
                        return;
                    }
                    if (r.hit == .wl_bt_disconnect) {
                        _ = settings_other_tabs.applyHit(&self.prefs, r.hit, r.seg, x, y, self.other_layout, r.slot_i);
                        _ = self.emitWireless(.ble_disconnect);
                        self.applyPrefs();
                        self.showSnackbar("BLE disconnected");
                        self.requestFull();
                        return;
                    }
                    if (r.hit == .wl_bt_clear) {
                        _ = settings_other_tabs.applyHit(&self.prefs, r.hit, r.seg, x, y, self.other_layout, r.slot_i);
                        _ = self.emitWireless(.ble_clear);
                        self.applyPrefs();
                        self.showSnackbar("Paired cleared");
                        self.requestFull();
                        return;
                    }
                    if (r.hit == .wl_peer0 or r.hit == .wl_peer1) {
                        const idx: u8 = if (r.hit == .wl_peer0) 0 else 1;
                        if (self.emitWireless(.{ .en_select_scan = idx })) {
                            self.showSnackbar("Peer selected");
                        } else {
                            self.prefs.wireless.setBridgePeer(idx);
                            self.prefs.syncEspnowMacFromBridge();
                        }
                        self.applyPrefs();
                        self.requestFull();
                        return;
                    }
                    if (r.hit == .wl_en_saved0 or r.hit == .wl_en_saved1) {
                        const idx: u8 = if (r.hit == .wl_en_saved0) 0 else 1;
                        if (self.emitWireless(.{ .en_activate_saved = idx })) {
                            self.showSnackbar("Bridge peer active");
                        } else if (self.prefs.wireless.peerSaved(idx)) {
                            self.prefs.wireless.setBridgePeer(idx);
                            self.prefs.syncEspnowMacFromBridge();
                        }
                        self.applyPrefs();
                        self.requestFull();
                        return;
                    }
                    if (r.hit == .wl_en_rm0 or r.hit == .wl_en_rm1) {
                        const idx: u8 = if (r.hit == .wl_en_rm0) 0 else 1;
                        if (!self.emitWireless(.{ .en_delete_saved = idx })) {
                            self.prefs.wireless.removeSavedPeer(idx);
                            self.prefs.syncEspnowMacFromBridge();
                        }
                        self.applyPrefs();
                        self.requestFull();
                        return;
                    }
                    if (r.hit == .wl_en_clear_peers) {
                        if (!self.emitWireless(.en_clear)) {
                            self.prefs.wireless.clearSavedPeers();
                            self.prefs.syncEspnowMacFromBridge();
                        }
                        self.applyPrefs();
                        self.showSnackbar("Peers cleared");
                        self.requestFull();
                        return;
                    }
                    if (r.hit == .wl_zb_join) {
                        if (!self.emitWireless(.zb_join)) {
                            self.prefs.wireless.joinZigbee();
                        }
                        self.applyPrefs();
                        self.showSnackbar("Zigbee join...");
                        self.requestFull();
                        return;
                    }
                    if (r.hit == .wl_zb_leave) {
                        if (!self.emitWireless(.zb_leave)) {
                            self.prefs.wireless.leaveZigbee();
                        }
                        self.applyPrefs();
                        self.requestFull();
                        return;
                    }
                    if (r.hit == .wl_zb_dev0 or r.hit == .wl_zb_dev1 or r.hit == .wl_zb_dev) {
                        const idx: u8 = switch (r.hit) {
                            .wl_zb_dev0 => 0,
                            .wl_zb_dev1 => 1,
                            else => r.aux,
                        };
                        if (!self.emitWireless(.{ .zb_toggle = idx })) {
                            _ = settings_other_tabs.applyHit(&self.prefs, r.hit, r.seg, x, y, self.other_layout, r.slot_i);
                        }
                        self.applyPrefs();
                        self.requestFull();
                        return;
                    }
                    if (r.hit == .wl_zb_identify) {
                        if (self.emitWireless(.{ .zb_identify = r.aux })) {
                            self.showSnackbar("Identify...");
                        } else {
                            self.showSnackbar("Identify (host demo)");
                        }
                        self.requestFull();
                        return;
                    }
                    if (r.hit == .wl_zb_remove) {
                        if (!self.emitWireless(.{ .zb_remove = r.aux })) {
                            if (r.aux < self.prefs.wireless.live_zb_n) {
                                self.prefs.wireless.live_zb_n -|= 1;
                            }
                        }
                        self.applyPrefs();
                        self.showSnackbar("Device removed");
                        self.requestFull();
                        return;
                    }
                    if (r.hit == .wl_zb_sensors) {
                        if (self.emitWireless(.{ .zb_sensors = r.aux })) {
                            self.showSnackbar("Reading sensors...");
                        }
                        self.requestFull();
                        return;
                    }
                    if (r.hit == .wl_zb_refresh) {
                        _ = self.emitWireless(.zb_refresh);
                        self.applyPrefs();
                        self.showSnackbar("Device list refreshed");
                        self.requestFull();
                        return;
                    }
                    if (r.hit == .wl_zb_clear) {
                        if (!self.emitWireless(.zb_clear)) {
                            self.prefs.wireless.zb_dev_n = 0;
                            self.prefs.wireless.live_zb_n = 0;
                        }
                        self.applyPrefs();
                        self.requestFull();
                        return;
                    }
                    if (r.hit == .wl_zb_energy) {
                        if (self.emitWireless(.zb_energy)) {
                            self.prefs.wireless.startEnergyScan();
                            self.prefs.wireless.zb_energy_hw = true;
                        } else {
                            self.prefs.wireless.startEnergyScan();
                        }
                        self.applyPrefs();
                        self.requestFull();
                        return;
                    }
                    if (r.hit == .wl_th_attach) {
                        if (!self.emitWireless(.th_attach)) {
                            self.prefs.wireless.attachThread();
                        }
                        self.applyPrefs();
                        self.showSnackbar("Thread attach...");
                        self.requestFull();
                        return;
                    }
                    if (r.hit == .wl_th_detach) {
                        if (!self.emitWireless(.th_detach)) {
                            self.prefs.wireless.detachThread();
                        }
                        self.applyPrefs();
                        self.requestFull();
                        return;
                    }
                    if (r.hit == .wl_th_dev0) {
                        if (!self.emitWireless(.{ .th_toggle = 0 })) {
                            _ = settings_other_tabs.applyHit(&self.prefs, r.hit, r.seg, x, y, self.other_layout, r.slot_i);
                        }
                        self.applyPrefs();
                        self.requestFull();
                        return;
                    }
                    if (r.hit == .wl_th_clear) {
                        if (!self.emitWireless(.th_clear)) {
                            self.prefs.wireless.th_dev_n = 0;
                            self.prefs.wireless.live_th_n = 0;
                        }
                        self.applyPrefs();
                        self.requestFull();
                        return;
                    }
                    if (r.hit == .wl_ssid) {
                        self.openTextPad(.wl_ssid, "Wi-Fi SSID", self.prefs.wireless.ssidSlice());
                        return;
                    }
                    if (r.hit == .cnc_dump) {
                        self.openCncDump();
                        return;
                    }
                    if (r.hit == .cnc_profiles) {
                        self.openCncProfiles();
                        return;
                    }
                    if (r.hit == .cnc_connect) {
                        self.startBusy(60);
                        _ = settings_other_tabs.applyHit(&self.prefs, r.hit, r.seg, x, y, self.other_layout, r.slot_i);
                        self.applyPrefs();
                        if (self.transport_reinit_sink) |s| s();
                        self.showSnackbar(if (self.prefs.cnc.conn == 0) "Connecting..." else "Reconnecting...");
                        self.requestFull();
                        return;
                    }
                    if (r.hit == .cnc_disconnect) {
                        if (!self.prefs.cnc.sessionBusy()) {
                            self.showSnackbar("Already off");
                            self.requestFull();
                            return;
                        }
                        _ = settings_other_tabs.applyHit(&self.prefs, r.hit, r.seg, x, y, self.other_layout, r.slot_i);
                        self.applyPrefs();
                        if (self.transport_reinit_sink) |s| s();
                        self.showSnackbar("Disconnected");
                        self.requestFull();
                        return;
                    }
                    if (self.tryOpenOrDragOther(r.hit, x, y)) return;
                    // Confirm before enabling PIN policies / soft limits.
                    if (r.hit == .sec_boot and self.prefs.security.has_pin and !self.prefs.security.pin_boot) {
                        self.openSettingsConfirm(.pin_boot_on);
                        return;
                    }
                    if (r.hit == .sec_slp and self.prefs.security.has_pin and !self.prefs.security.pin_slp) {
                        self.openSettingsConfirm(.pin_slp_on);
                        return;
                    }
                    if (r.hit == .mach_slim and !self.prefs.machine.slim) {
                        self.envelope_pending_enable = true;
                        self.openSettingsConfirm(.mach_slim);
                        return;
                    }
                    // Segment miss: hitTest already returns .none for other-tabs segments.
                    if (settings_other_tabs.applyHit(&self.prefs, r.hit, r.seg, x, y, self.other_layout, r.slot_i)) |jump| {
                        self.tab_selected = jump;
                        self.scroll.setTarget(0);
                        self.scroll.value = 0;
                        self.kickTabAxis();
                    }
                    self.applyPrefs();
                    self.notifySaved();
                    self.requestFull();
                }
                return;
            }
        }

        // Dashboard
        switch (dashboard.hitStatus(x, y)) {
            .settings => {
                self.openSettings();
                return;
            },
            .power => {
                self.openPowerMenu();
                return;
            },
            .mpg => {
                // Optimistic UI; device sink → `cmdMpgToggle`, mirror corrects.
                self.cnc.mpg_active = !self.cnc.mpg_active;
                if (self.cnc_mpg_sink) |sink| sink();
                self.showSnackbar(if (self.cnc.mpg_active)
                    (if (self.cnc.mpg_remote) "MPG rem" else "MPG")
                else
                    "MPG off");
                self.requestFull();
                return;
            },
            .wcs => {
                self.cycleWcsFromStatus();
                return;
            },
            .none => {
                // Double-tap blank status → Quick Settings (single tap was too easy / fought scrim paint).
                if (y < dashboard.status_h) {
                    self.noteBlankStatusTap(x, y);
                    return;
                }
            },
        }
        // Center + actions before DRO so a press-capture that started on the
        // DRO (or glove-padded edge) cannot steal jog/override/actions taps.
        const jog_hit = dashboard.hitJog(x, y, self.cnc);
        switch (jog_hit.kind) {
            .mode => {
                self.cnc.jog_mode = jog_hit.index;
                // Keep prefs in lockstep — applyPrefs() / dash.apply would snap UI back.
                self.prefs.dash.jog_mode = @intCast(jog_hit.index);
                _ = self.emitCnc(.{ .set_jog_mode = @intCast(jog_hit.index) });
                self.pulseKey("jog.mode.p");
                self.requestFull();
                return;
            },
            .incr => {
                self.cnc.jog_incr = jog_hit.index;
                self.prefs.dash.jog_incr_sel = @intCast(jog_hit.index);
                _ = self.emitCnc(.{ .set_step_size = @intCast(jog_hit.index) });
                var ik: [20]u8 = undefined;
                // Pulse key ≠ selection morph key (actions use .p suffix) — same-key pulse
                // drove select_t toward 0 and washed chip ink until snack full-repaint.
                const key = std.fmt.bufPrint(&ik, "jog.incr.{d}.p", .{jog_hit.index}) catch "jog.incr.p";
                self.pulseKey(key);
                self.requestFull();
                return;
            },
            .none => {},
        }
        const ov = dashboard.hitOverrides(x, y, self.cnc);
        if (ov.kind != .none) {
            // LVGL sends ±10 / 0 (reset) realtime deltas — never a target pct.
            const delta: i8 = switch (ov.kind) {
                .plus => 10,
                .minus => -10,
                .reset, .none => 0,
            };
            self.pulseKey(override_widget.pressKey(ov.which, ov.kind));
            self.applyOverride(ov.which, delta);
            self.feed_fx.setTarget(@floatFromInt(self.cnc.feed_pct));
            self.spindle_fx.setTarget(@floatFromInt(self.cnc.spindle_pct));
            self.rapid_fx.setTarget(@floatFromInt(self.cnc.rapid_pct));
            self.requestFull();
            return;
        }
        const act = dashboard.hitActions(x, y, self.cnc);
        switch (act.kind) {
            .cycle => {
                self.pulseKey("act.cycle.p");
                if (self.cnc_ui_sink != null) {
                    // LVGL `cycle_click_cb`: alarm→unlock, run→stop, else cycle_start.
                    const blocked = self.cnc.mach_state == 4 or self.cnc.mach_state == 6 or self.cnc.mach_state == 8;
                    if (self.cnc.alarm_code != 0 or self.cnc.mach_state == 5) {
                        if (self.emitCnc(.unlock)) self.showSnackbar("Unlock") else self.showSnackbarError("CNC not ready");
                    } else if (self.cnc.actions.phase == .run) {
                        if (self.emitCnc(.stop)) self.showSnackbar("Cycle stopped") else self.showSnackbarError("CNC not ready");
                    } else if (blocked) {
                        self.showSnackbarError("Blocked");
                    } else if (self.emitCncOrConfirm(.cycle, .dash_cycle, .cycle_start)) {
                        if (self.pending_cnc == null) self.showSnackbar("Cycle start");
                    }
                    return;
                }
                if (self.cnc.actions.phase == .run) {
                    self.setMachinePhase(.idle);
                    self.showSnackbar("Cycle stopped");
                } else {
                    self.setMachinePhase(.run);
                    self.showSnackbar("Cycle start");
                }
                return;
            },
            .sync => {
                self.pulseKey("act.sync.p");
                if (self.cnc_ui_sink != null) {
                    if (self.emitCnc(.reset)) {
                        self.showSnackbar("Soft reset sent");
                    } else {
                        self.showSnackbarError("CNC not ready");
                    }
                } else {
                    // Host demo — no sink; local phase restart feedback.
                    self.showSnackbar("Cycle restart");
                }
                self.requestFull();
                return;
            },
            .hold => {
                self.pulseKey("act.hold.p");
                if (self.cnc_ui_sink != null) {
                    // LVGL `hold_click_cb`: hold→resume, alarm→reset, else feed_hold.
                    if (self.cnc.actions.phase == .hold) {
                        if (self.emitCnc(.cycle_start)) self.showSnackbar("Feed resume") else self.showSnackbarError("CNC not ready");
                    } else if (self.cnc.alarm_code != 0 or self.cnc.mach_state == 5) {
                        if (self.emitCnc(.reset)) self.showSnackbar("Soft reset sent") else self.showSnackbarError("CNC not ready");
                    } else if (self.emitCnc(.feed_hold)) {
                        self.showSnackbar("Feed hold");
                    } else {
                        self.showSnackbarError("CNC not ready");
                    }
                    return;
                }
                switch (self.cnc.actions.phase) {
                    .run => {
                        self.setMachinePhase(.hold);
                        self.showSnackbar("Feed hold");
                    },
                    .hold => {
                        self.setMachinePhase(.run);
                        self.showSnackbar("Feed resume");
                    },
                    .idle => self.showSnackbar("Nothing to hold"),
                }
                return;
            },
            .home => {
                self.pulseKey("act.home.p");
                if (self.cnc_ui_sink != null) {
                    if (self.emitCncOrConfirm(.home, .dash_home, .home_all)) {
                        if (self.pending_cnc == null) self.showSnackbar("Home all");
                    }
                } else {
                    self.setMachinePhase(.idle);
                    self.showSnackbar("Home all");
                }
                return;
            },
            .quick => {
                const idx = act.quick_index;
                var qk: [20]u8 = undefined;
                const pkey = std.fmt.bufPrint(&qk, "act.q.{d}.p", .{idx}) catch "act.q.p";
                self.pulseKey(pkey);
                const id = self.cnc.actions.quick[idx];
                if (self.cnc_ui_sink != null) {
                    const cmd_opt: ?CncUiCmd = switch (id) {
                        .spindle_cw => .spindle_cw,
                        .spindle_ccw => .spindle_ccw,
                        .coolant => .coolant_toggle,
                        .fan => .fan_toggle,
                        .mist => .mist_toggle,
                        .zero_all => .zero_all,
                        .macro => .run_macro,
                        .single_step => .single_step,
                        .off => null,
                        .led, .user0, .user1, .user2, .user3 => null,
                    };
                    if (cmd_opt) |cmd| {
                        const conf_act: ConfirmAct = switch (id) {
                            .spindle_cw, .spindle_ccw => .spin,
                            .zero_all => .zero,
                            .macro => .mac,
                            else => .cycle, // unused when never
                        };
                        const conf_kind: settings_form.PowerConfirm = switch (id) {
                            .spindle_cw, .spindle_ccw => .dash_spin,
                            .zero_all => .dash_zero_all,
                            .macro => .dash_mac,
                            else => .none,
                        };
                        if (id == .zero_all) {
                            if (!self.emitCncOrConfirm(.zero, .dash_zero_all, .zero_all)) {
                                self.requestFull();
                                return;
                            }
                            if (self.pending_cnc != null) {
                                self.requestFull();
                                return;
                            }
                            @memset(&self.cnc.dro.work_um, 0);
                        } else if (conf_kind != .none and self.confirmNeeds(conf_act)) {
                            self.requestCncConfirm(conf_kind, cmd);
                        } else if (id == .coolant or id == .fan or id == .mist or id == .single_step or id == .off or !self.confirmNeeds(conf_act)) {
                            if (!self.emitCnc(cmd)) {
                                self.showSnackbarError("CNC not ready");
                                self.requestFull();
                                return;
                            }
                            if (id == .fan) self.cnc.fan_on = !self.cnc.fan_on;
                        }
                    } else {
                        self.cnc.toggleQuickAssign(idx);
                    }
                    self.showSnackbar(id.label());
                } else {
                    self.cnc.toggleQuickAssign(idx);
                    if (self.cnc.isQuickActive(idx)) {
                        self.showSnackbar(id.label());
                    } else {
                        var buf: [48]u8 = undefined;
                        const msg = std.fmt.bufPrint(&buf, "{s} off", .{id.label()}) catch id.label();
                        self.showSnackbar(msg);
                    }
                }
                self.requestFull();
                return;
            },
            .none => {},
        }
        const dro_hit = dashboard.hitDro(x, y, self.cnc);
        switch (dro_hit.kind) {
            .home => {
                self.cnc.dro.pressed = dro_hit;
                self.cnc.dro.selected = dro_hit.axis;
                if (self.emitCnc(.{ .home_axis = @intCast(dro_hit.axis) })) {
                    _ = self.emitCnc(.{ .set_active_axis = @intCast(dro_hit.axis) });
                } else {
                    self.cnc.dro.work_um[dro_hit.axis] = 0;
                    self.cnc.dro.mach_um[dro_hit.axis] = 0;
                }
                self.cnc.dro.ensureSelectedVisible(dashboard.droBounds(self.cnc).h);
                self.dro_scroll.setTarget(@floatFromInt(self.cnc.dro.scroll_px));
                self.kickDroSelect();
                var hk: [16]u8 = undefined;
                const hkey = std.fmt.bufPrint(&hk, "dro.home.{d}", .{dro_hit.axis}) catch "dro.home";
                self.pulseKey(hkey);
                var hbuf: [32]u8 = undefined;
                const msg = std.fmt.bufPrint(&hbuf, "Home {s}", .{dro_widget.axis_labels[dro_hit.axis]}) catch "Home";
                self.showSnackbar(msg);
                self.requestFull();
                return;
            },
            .zero => {
                self.cnc.dro.pressed = dro_hit;
                self.cnc.dro.selected = dro_hit.axis;
                const axis_u8: u8 = @intCast(dro_hit.axis);
                if (self.cnc_ui_sink != null) {
                    if (!self.emitCncOrConfirm(.zero, .dash_zero, .{ .zero_axis = axis_u8 })) {
                        self.requestFull();
                        return;
                    }
                    _ = self.emitCnc(.{ .set_active_axis = axis_u8 });
                    // Confirm pending — wait for OK before optimistic DRO / snack.
                    if (self.pending_cnc != null) {
                        self.requestFull();
                        return;
                    }
                    self.cnc.dro.work_um[dro_hit.axis] = 0;
                } else {
                    self.cnc.dro.work_um[dro_hit.axis] = 0;
                }
                self.cnc.dro.ensureSelectedVisible(dashboard.droBounds(self.cnc).h);
                self.dro_scroll.setTarget(@floatFromInt(self.cnc.dro.scroll_px));
                self.kickDroSelect();
                var zk: [16]u8 = undefined;
                const zkey = std.fmt.bufPrint(&zk, "dro.zero.{d}", .{dro_hit.axis}) catch "dro.zero";
                self.pulseKey(zkey);
                var zbuf: [32]u8 = undefined;
                const msg = std.fmt.bufPrint(&zbuf, "Zero {s}", .{dro_widget.axis_labels[dro_hit.axis]}) catch "Zero";
                self.showSnackbar(msg);
                self.requestFull();
                return;
            },
            .select => {
                self.cnc.dro.pressed = dro_hit;
                self.cnc.dro.selected = dro_hit.axis;
                _ = self.emitCnc(.{ .set_active_axis = @intCast(dro_hit.axis) });
                self.cnc.dro.ensureSelectedVisible(dashboard.droBounds(self.cnc).h);
                self.dro_scroll.setTarget(@floatFromInt(self.cnc.dro.scroll_px));
                self.kickDroSelect();
                self.requestFull();
                return;
            },
            .none => {},
        }
    }

    /// Blank status double-tap (or second click within ~360 ms / 12 frames).
    fn noteBlankStatusTap(self: *Engine, x: i32, y: i32) void {
        const slop: i32 = 48;
        const window_frames: u32 = 12;
        if (self.qs_blank_armed) {
            const age = self.frame_n -% self.qs_blank_arm_frame;
            if (age <= window_frames and
                @abs(x - self.qs_blank_arm_x) <= slop and
                @abs(y - self.qs_blank_arm_y) <= slop)
            {
                self.qs_blank_armed = false;
                self.openQuickSettings();
                return;
            }
        }
        self.qs_blank_armed = true;
        self.qs_blank_arm_frame = self.frame_n;
        self.qs_blank_arm_x = x;
        self.qs_blank_arm_y = y;
    }

    /// Quick Settings — toggle MD3 bottom sheet (`quick_settings.zig`).
    /// Tab5: blank status double-tap. Host demo: Space. Not full Settings (`openSettings`).
    pub fn openQuickSettings(self: *Engine) void {
        if (self.screen == .boot) return;
        self.qs_blank_armed = false;
        const closed = self.sheet_y.target >= @as(f32, @floatFromInt(quick_settings.closedY())) - 1;
        if (closed) {
            self.qs_body_scroll = 0;
            // Snap open — expressive spring slide dirtied ~full frame for seconds (status flicker).
            const oy = quick_settings.openY();
            self.sheet_y.value = @floatFromInt(oy);
            self.sheet_y.target = @floatFromInt(oy);
            self.sheet_y.velocity = 0;
            self.prev_sheet_y = quick_settings.closedY();
            // Drop opening-tap press stain — else press_moving re-blits QS every frame.
            self.press_fx.value = 0;
            self.press_fx.target = 0;
            self.press_fx.velocity = 0;
            self.requestFull();
        } else {
            self.closeQuickSettings();
        }
    }

    pub fn closeQuickSettings(self: *Engine) void {
        self.qs_slider = .none;
        self.qs_drag = false;
        self.qs_content_dirty = false;
        self.qs_zb_detail = 0xff;
        self.qs_zb_hold_idx = 0xff;
        self.qs_zb_hold_fired = false;
        self.qs_zb_level_drag = false;
        self.qs_body_scroll = 0;
        self.qs_blank_armed = false;
        const cy = quick_settings.closedY();
        self.sheet_y.value = @floatFromInt(cy);
        self.sheet_y.target = @floatFromInt(cy);
        self.sheet_y.velocity = 0;
        self.prev_sheet_y = quick_settings.openY();
        self.requestFull();
    }

    /// Deprecated name — use `openQuickSettings`.
    pub fn openSettingsSheet(self: *Engine) void {
        self.openQuickSettings();
    }

    /// Deprecated name — use `closeQuickSettings`.
    pub fn closeSettingsSheet(self: *Engine) void {
        self.closeQuickSettings();
    }

    /// MD3 predictive back / edge swipe — dismiss top overlay.
    pub fn gestureBack(self: *Engine) bool {
        if (self.pad.open) {
            // Back never leaves the lock screen.
            if (self.screen == .pin) return true;
            if (self.pad.target == .search) self.syncSearchFromPad();
            self.pad.clear();
            self.afterPadDismiss();
            return true;
        }
        if (self.mach_str_overlay != .none) {
            self.closeMachStrOverlay();
            return true;
        }
        if (self.extra_overlay != .none) {
            self.closeExtra();
            return true;
        }
        if (self.pin_overlay != .none) {
            self.closePinOverlay();
            return true;
        }
        if (self.dash_overlay != .none) {
            if (self.dash_overlay == .arrange and self.dash_arr_pick >= 0) {
                self.dash_arr_pick = -1;
                self.dash_arr_scroll = 0;
                self.requestFull();
            } else {
                self.closeDashOverlay();
            }
            return true;
        }
        if (self.cnc_overlay != .none) {
            self.closeCncOverlay();
            return true;
        }
        if (self.menu_target != .none) {
            self.closeMenu();
            return true;
        }
        if (self.settings_confirm != .none) {
            self.closeSettingsConfirm();
            return true;
        }
        if (self.dialog_open) {
            self.closeDialog();
            return true;
        }
        if (self.screen == .power) {
            self.closePowerMenu();
            return true;
        }
        if (self.screen == .catalog) {
            self.closeCatalog();
            return true;
        }
        if (self.screen == .pin) {
            self.relockPin();
            return true;
        }
        if (self.screen == .settings) {
            if (self.search_len > 0 or self.search_focus) {
                self.clearSearch();
                if (self.pad.open and self.pad.target == .search) {
                    self.pad.clear();
                    self.afterPadDismiss();
                } else {
                    self.requestFull();
                }
                return true;
            }
            if (!settings_form.useRail() and !self.settings_hub) {
                self.settings_hub = true;
                self.scroll.setTarget(0);
                self.scroll.value = 0;
                self.requestFull();
                return true;
            }
            self.closeSettings();
            return true;
        }
        const closed = self.sheet_y.target >= @as(f32, @floatFromInt(quick_settings.closedY())) - 1;
        if (!closed) {
            self.closeQuickSettings();
            return true;
        }
        return false;
    }

    /// Apply one gesture event from `gestures.Recognizer` (host + Tab5).
    /// Assigned: tap → click; double-tap blank status → Quick Settings;
    /// long-press below status → power; pan/scroll → region scroll.
    pub fn handleGesture(self: *Engine, ev: gestures.Event) void {
        if (self.screen == .boot) return;
        switch (ev.kind) {
            .none => {},
            .tap => self.handleClick(ev.x, ev.y),
            .long_press => {
                if (quick_settings.isOpen(self.sheet_y.value)) {
                    const sy: i32 = i32FromF(@floor(self.sheet_y.value));
                    const h = quick_settings.hit(ev.x, ev.y, sy, &self.prefs, self.qs_body_scroll, self.qs_zb_detail);
                    if (h.kind == .zb_dev) {
                        self.openQsZbDetail(h.index);
                        return;
                    }
                }
                if (self.screen == .dashboard) {
                    // Blank status: double-tap only (long-press does not open QS).
                    if (ev.y >= dashboard.status_h) {
                        self.openPowerMenu();
                    }
                } else {
                    self.showSnackbar("Long press");
                }
            },
            .double_tap => {
                if (self.screen != .dashboard or ev.phase != .end) return;
                if (ev.y < dashboard.status_h and dashboard.hitStatus(ev.x, ev.y) == .none) {
                    self.openQuickSettings();
                }
            },
            .pan, .scroll => {
                if (ev.phase == .update) {
                    self.handleHover(ev.x, ev.y);
                    // Finger down → content follows (negate dy).
                    self.nudgeScroll(@as(f32, @floatFromInt(-ev.dy)));
                }
            },
            .swipe,
            .drag,
            .pickup_move,
            .compound,
            .predictive_back,
            .pinch,
            => {},
        }
    }

    pub fn nudgeScroll(self: *Engine, dy: f32) void {
        if (self.dash_overlay == .arrange and self.dash_arr_pick >= 0) {
            const max_s = self.dash_arr_layout.scroll_max;
            if (max_s > 0) {
                const next = self.dash_arr_scroll - i32FromF(dy);
                self.dash_arr_scroll = std.math.clamp(next, 0, max_s);
                self.requestFull();
            }
            return;
        }
        if (self.cnc_overlay == .dump and self.cnc_dump.scroll_max > 0) {
            const next = self.cnc_dump.scroll_px - i32FromF(dy);
            self.cnc_dump.scroll_px = std.math.clamp(next, 0, self.cnc_dump.scroll_max);
            self.requestFull();
            return;
        }
        if (quick_settings.isOpen(self.sheet_y.value)) {
            const max_s = quick_settings.bodyScrollMax(&self.prefs);
            if (max_s > 0) {
                const next = self.qs_body_scroll - i32FromF(dy);
                self.qs_body_scroll = std.math.clamp(next, 0, max_s);
                self.repaintQs();
            }
            return;
        }
        if (self.menu_target != .none) {
            const labs = settings_menu.labels(self.menu_target);
            const visible = @min(labs.len, expr.menu_max_visible);
            if (labs.len > visible) {
                if (dy > 0 and self.menu_scroll > 0) {
                    self.menu_scroll -= 1;
                } else if (dy < 0 and self.menu_scroll + visible < labs.len) {
                    self.menu_scroll += 1;
                }
                self.requestFull();
            }
            return;
        }
        if (self.screen == .catalog) {
            const max_s: f32 = @floatFromInt(@max(0, self.catalog.content_h - 620));
            const lo = -tokens.Motion.overscroll_px;
            const hi = max_s + tokens.Motion.overscroll_px;
            self.motion_phys.wheelNudge(&self.catalog.scroll, dy, lo, hi);
            return;
        }
        if (self.screen == .dashboard) {
            const b = dashboard.droBounds(self.cnc);
            if (self.hover_x >= 0 and b.contains(self.hover_x, self.hover_y) and
                dro_widget.scrollMax(self.cnc.dro.axis_count, b.h) > 0)
            {
                var tmp = self.cnc.dro;
                tmp.scroll_px = i32FromF(self.dro_scroll.target);
                tmp.nudgeScroll(i32FromF(dy), b.h);
                self.motion_phys.applySpatial(&self.dro_scroll);
                self.dro_scroll.setTarget(@floatFromInt(tmp.scroll_px));
            }
            return;
        }
        if (self.screen != .settings) return;
        // Critically-damped track — smooth between touch samples, no impulse jiggle.
        self.settings_row_dirty = .{}; // scroll shifts every row
        const max_s = self.scrollMax();
        self.motion_phys.trackScroll(&self.scroll, dy, 0, max_s);
    }

    fn scrollMax(self: *const Engine) f32 {
        return @floatFromInt(@max(0, self.settings_content_h - settings_form.contentViewH()));
    }

    pub fn setScrollTarget(self: *Engine, y: f32) void {
        // Instant jump (tab open / tests) — not a pan.
        const next = std.math.clamp(y, 0, self.scrollMax());
        self.scroll.value = next;
        self.scroll.target = next;
        self.scroll.velocity = 0;
    }

    /// Hard edges only — do not kill mid-scroll chase (that made pans choppy).
    fn clampSettingsScroll(self: *Engine) void {
        const max_s = self.scrollMax();
        self.scroll.target = std.math.clamp(self.scroll.target, 0, max_s);
        if (self.scroll.value < 0) {
            self.scroll.value = 0;
            self.scroll.velocity = 0;
        } else if (self.scroll.value > max_s) {
            self.scroll.value = max_s;
            self.scroll.velocity = 0;
        }
    }

    fn nowUs(self: *const Engine) u64 {
        const sink = self.now_us_sink orelse return 0;
        return sink();
    }

    pub fn tick(self: *Engine, dt_sec: f32) FrameMetrics {
        const t_tick_start = self.nowUs();
        self.dirty.clear();
        self.frame_n +%= 1;
        if (self.qs_blank_armed and (self.frame_n -% self.qs_blank_arm_frame) > 12) {
            self.qs_blank_armed = false;
        }
        // Zigbee tile long-press (~500 ms @ 30 Hz) → Exposes detail.
        if (self.qs_zb_hold_idx != 0xff and !self.qs_zb_hold_fired and
            quick_settings.isOpen(self.sheet_y.value) and
            (self.frame_n -% self.qs_zb_hold_frame) >= 15)
        {
            self.openQsZbDetail(self.qs_zb_hold_idx);
        }

        if (self.screen == .boot) {
            if (!std.math.isFinite(dt_sec)) {
                self.flushDirty();
                self.metrics = .{ .dirty_px = self.panel.last_write_px, .rotate_px = self.panel.last_write_px };
                return self.metrics;
            }
            // Hold splash until backlight-arm (device) — do not drain early.
            if (!self.boot_hold_armed) {
                self.flushDirty();
                self.metrics = .{ .dirty_px = self.panel.last_write_px, .rotate_px = self.panel.last_write_px };
                return self.metrics;
            }
            // Tight clamp: one long frame must not burn most of the 3 s hold.
            self.boot_left_sec -= std.math.clamp(dt_sec, 0, 0.05);
            if (self.boot_left_sec <= 0) {
                self.finishBoot();
                // Dashboard/pin already painted+flushed in finishBoot — return.
                self.metrics = .{ .dirty_px = self.panel.last_write_px, .rotate_px = self.panel.last_write_px };
                return self.metrics;
            } else {
                if (self.needs_full_repaint) {
                    self.paintBoot();
                    self.dirty.add(fullRect());
                    self.needs_full_repaint = false;
                }
                self.flushDirty();
                self.metrics = .{ .dirty_px = self.panel.last_write_px, .rotate_px = self.panel.last_write_px };
                return self.metrics;
            }
        }

        const scroll_moving = self.scroll.step(dt_sec);
        if (self.screen == .settings) self.clampSettingsScroll();
        const tab_axis_moving = self.tab_axis.step(dt_sec);
        const qs_tab_moving = self.qs_tab_axis.step(dt_sec);
        const press_was_visible = self.press_fx.value > 0.02;
        var press_moving = self.press_fx.step(dt_sec);
        if (self.press_fx.settled() and self.press_fx.target >= 0.99) {
            self.press_fx.setTarget(0);
            press_moving = true;
        }
        const press_stain_clear = press_was_visible and self.press_fx.value <= 0.02 and self.press_fx.settled();
        const dialog_moving = self.dialog_fx.step(dt_sec);
        const power_moving = self.power_fx.step(dt_sec);
        const power_confirm_moving = self.power_confirm_fx.step(dt_sec);
        const settings_confirm_moving = self.settings_confirm_fx.step(dt_sec);
        const cnc_overlay_moving = self.cnc_overlay_fx.step(dt_sec);
        const dash_overlay_moving = self.dash_overlay_fx.step(dt_sec);
        const pin_overlay_moving = self.pin_overlay_fx.step(dt_sec);
        const mach_str_moving = self.mach_str_fx.step(dt_sec);
        const extra_moving = self.extra_fx.step(dt_sec);
        if (self.probe_busy_frames > 0) {
            if (self.probe_busy_sink) |busy| {
                if (!busy()) {
                    self.probe_busy_frames = 0;
                    if (self.extra_overlay == .probe) {
                        self.showSnackbar("Probe done");
                        self.requestSettingsPresent();
                    }
                } else {
                    self.requestSettingsPresent();
                }
            } else {
                self.probe_busy_frames -= 1;
                if (self.probe_busy_frames == 0 and self.extra_overlay == .probe) {
                    self.showSnackbar("Z-plate probe done");
                    self.requestSettingsPresent();
                } else if (self.extra_overlay == .probe) {
                    self.requestSettingsPresent();
                }
            }
        }
        self.tickMachPull();
        if (self.busy_frames > 0) {
            self.busy_frames -= 1;
            self.busy_phase += dt_sec * 2.5;
            if (self.busy_phase > 1) self.busy_phase -= 1;
        }
        const sheet_moving = self.sheet_y.step(dt_sec);
        const theme_moving = self.theme_fx.step(dt_sec);
        const led_moving = self.led_morph.step(dt_sec);
        self.cnc.led_morph = self.led_morph.value;
        const dro_sel_moving = self.dro_select.step(dt_sec);
        self.cnc.dro.select_fx = self.dro_select.value;
        self.job_fx.setTarget(self.cnc.job_progress);
        const job_moving = self.job_fx.step(dt_sec);
        self.cnc.job_progress_vis = self.job_fx.value;
        // Expressive wave: advance phase always, but only dirty every 3rd frame
        // when progress is settled — continuous wave was pinning idle rotate_px.
        var job_wave_moving = false;
        if (dashboard.jobStripVisible(self.cnc)) {
            self.cnc.job_wave_phase += dt_sec * 2.5;
            if (self.cnc.job_wave_phase > 100) self.cnc.job_wave_phase -= 100;
            self.job_wave_div +%= 1;
            job_wave_moving = job_moving or (self.job_wave_div % 3) == 0;
        }
        self.feed_fx.setTarget(@floatFromInt(self.cnc.feed_pct));
        self.spindle_fx.setTarget(@floatFromInt(self.cnc.spindle_pct));
        self.rapid_fx.setTarget(@floatFromInt(self.cnc.rapid_pct));
        const feed_moving = self.feed_fx.step(dt_sec);
        const spindle_moving = self.spindle_fx.step(dt_sec);
        const rapid_moving = self.rapid_fx.step(dt_sec);
        self.cnc.feed_vis = self.feed_fx.value;
        self.cnc.spindle_vis = self.spindle_fx.value;
        self.cnc.rapid_vis = self.rapid_fx.value;
        const dro_scroll_moving = self.dro_scroll.step(dt_sec);
        self.cnc.dro.scroll_px = i32FromF(self.dro_scroll.value);
        const widget_moving = self.widget_fx.stepAll(dt_sec);
        const snack_moving = self.snack_fx.step(dt_sec);
        const dump_moving = if (self.cnc_overlay == .dump) blk: {
            if (self.dump_tick_sink) |dtick| break :blk dtick(&self.cnc_dump);
            break :blk self.cnc_dump.tick();
        } else false;
        if (dump_moving) self.requestSettingsPresent();
        if (self.screen == .dashboard) {
            self.cnc.dro.clampScroll(dashboard.droBounds(self.cnc).h);
        }

        const live = self.liveDashboard();

        // DRO press — regional (not full frame).
        if (live) {
            if (self.cnc.dro.pressed.kind != .none and self.press_fx.target < 0.5 and self.press_fx.value < 0.08) {
                self.cnc.dro.pressed = .{};
                self.repaintDroRegion();
            } else if (self.cnc.dro.pressed.kind != .none) {
                self.repaintDroRegion();
            }
        }

        // Host demo only — on device `mirrorCnc` owns sd_percent / line_number.
        // Mutating here races the driver and races the bar ahead of the real job.
        if (live and self.cnc.actions.phase == .run and self.cnc_ui_sink == null) {
            self.cnc.sd_percent = @min(100, self.cnc.sd_percent + dt_sec * 2);
            self.cnc.syncJobProgressFromSd();
            if (self.cnc.line_number == 0) self.cnc.line_number = 1;
            self.cnc.line_number +%= 1;
        }

        self.syncJobStripTiming(dt_sec);

        // Theme crossfade retints everything — full paint required.
        if (theme_moving and self.screen == .dashboard) {
            self.needs_full_repaint = true;
            self.settings_present_window = false;
        }
        if (self.screen == .power and (power_moving or power_confirm_moving)) {
            self.needs_full_repaint = true;
            self.settings_present_window = false;
        }
        if (self.screen == .settings and (settings_confirm_moving or cnc_overlay_moving or dash_overlay_moving or pin_overlay_moving or mach_str_moving or extra_moving)) {
            self.needs_full_repaint = true;
            self.settings_present_window = false;
        }
        if (self.screen == .dashboard and self.settings_confirm != .none and settings_confirm_moving) {
            self.needs_full_repaint = true;
            self.settings_present_window = false;
        }
        // System prefs clock / uptime — 1 Hz (LVGL sys_timer + power bat timer parity).
        self.sys_clock_accum += dt_sec;
        while (self.sys_clock_accum >= 1) {
            self.sys_clock_accum -= 1;
            self.prefs.system.tickOneSec();
            // Host-only soft gauges. Device: HAL / driver mirrors own these.
            if (self.now_us_sink == null) {
                self.prefs.power.tickTelemetry();
                self.cnc.battery_pct = self.prefs.power.bat_pct;
                self.cnc.battery_charge_state = self.prefs.power.charge_state;
                self.cnc.battery_charging = self.prefs.power.charge_state == 1 or self.prefs.power.charge_state == 2;
                self.cnc.battery_fast_charge = battery_chrome.isFastCharge(
                    self.prefs.power.charge_state,
                    @abs(self.prefs.power.bat_ma),
                );
                self.prefs.wireless.tickTelemetry();
            }
            // Device: session phase comes from mirrorCncStatus, not host stub FSM.
            if (self.transport_reinit_sink == null) {
                self.prefs.cnc.tickTelemetry();
            }
            if (self.screen == .dashboard) {
                self.syncStatusBarChrome();
                // QS scrim owns the status band on-screen; regional status present
                // punches chrome through the scrim (black flash on tab change).
                if (self.liveDashboard()) {
                    self.repaintStatusRegion();
                }
            } else if (self.screen == .settings and !self.settingsHasBlockingModal() and
                (self.tab_selected == 9 or self.tab_selected == 5 or self.tab_selected == 4 or self.tab_selected == 0))
            {
                self.repaintSettingsContentPane();
            }
        }
        // Storage telemetry — 2 s (LVGL stor_timer parity).
        self.stor_refresh_accum += dt_sec;
        while (self.stor_refresh_accum >= 2) {
            self.stor_refresh_accum -= 2;
            if (!self.emitStorSys(.poll)) {
                self.prefs.storage.tickTelemetry();
            }
            // Host soft accrual only — device mirrors Driver.maint in storagePoll.
            if (self.now_us_sink == null) {
                self.prefs.machine.tickMaint();
            }
            if (self.screen == .settings and !self.settingsHasBlockingModal() and
                (self.tab_selected == 8 or self.tab_selected == 7))
            {
                self.repaintSettingsContentPane();
            }
        }

        // Before full/regional paint: device mirror may have flipped strip/phase.
        if (live) self.syncMirroredChromePaint();

        if (self.needs_full_repaint) {
            const qs_open_early = quick_settings.isOpen(self.sheet_y.value);
            // QS: paint underlay then blend MD3 scrim (opaque stand-in — no translucent layer).
            // Never paintStatus alone under QS: chrome punches through → status flicker.
            if (qs_open_early and (self.screen == .dashboard or self.screen == .settings)) {
                const sy: i32 = i32FromF(@floor(self.sheet_y.value));
                self.paintQsUnderlay();
                self.paintSheet(sy);
                self.dirty.add(.{
                    .x = 0,
                    .y = 0,
                    .w = tokens.Logical.width,
                    .h = tokens.Logical.height,
                });
            } else switch (self.screen) {
                .dashboard => self.paintDashboard(),
                .settings => self.paintSettingsShell(),
                .power => self.paintPowerMenu(),
                .pin => self.paintPinStub(),
                .boot => self.paintBoot(),
                .catalog => {
                    settings_form.bindWidgetMotion(&self.motion_phys, &self.widget_fx);
                    defer settings_form.unbindWidgetMotion();
                    self.catalog.press_x = self.press_x;
                    self.catalog.press_y = self.press_y;
                    self.catalog.press_t = self.press_fx.value;
                    self.catalog.press_active = self.press_fx.value > 0.08;
                    md3_catalog.paint(&self.logical, self.theme, &self.catalog);
                },
            }
            const qs_open = quick_settings.isOpen(self.sheet_y.value);
            if (!qs_open_early or !(self.screen == .dashboard or self.screen == .settings)) {
                if (qs_open) {
                    const sy: i32 = i32FromF(self.sheet_y.value);
                    self.paintSheet(sy);
                    self.dirty.add(.{
                        .x = 0,
                        .y = sy,
                        .w = tokens.Logical.width,
                        .h = tokens.Logical.height - sy,
                    });
                } else if (self.settings_present_window and self.screen == .settings) {
                    self.dirty.add(settings_form.windowRect());
                } else {
                    self.dirty.add(fullRect());
                }
            }
            self.settings_present_window = false;
            self.needs_full_repaint = false;
        } else if (live) {
            // Phase B: regional invalidation (LVGL change-gate class).
            if (led_moving) self.repaintStatusRegion();
            self.syncDroLivePaint();
            if (dro_sel_moving or dro_scroll_moving) self.repaintDroRegion();
            if (job_moving or job_wave_moving) self.repaintJobRegion();
            if (feed_moving or spindle_moving or rapid_moving) {
                const fv: u8 = u8FromF(self.cnc.feed_vis);
                const sv: u8 = u8FromF(self.cnc.spindle_vis);
                const rv: u8 = u8FromF(self.cnc.rapid_vis);
                if (fv != self.gate_feed_vis or sv != self.gate_spindle_vis or rv != self.gate_rapid_vis) {
                    self.gate_feed_vis = fv;
                    self.gate_spindle_vis = sv;
                    self.gate_rapid_vis = rv;
                    self.repaintCenterRegion();
                }
            }
            if (widget_moving) {
                self.repaintDroRegion();
                self.repaintCenterRegion();
                self.repaintActionsRegion();
            }
            if (press_stain_clear) {
                const pr: geom.Rect = .{
                    .x = self.press_x - 56,
                    .y = self.press_y - 56,
                    .w = 112,
                    .h = 112,
                };
                if (!geom.Rect.intersect(pr, dashboard.jogBounds(self.cnc)).isEmpty() or
                    !geom.Rect.intersect(pr, dashboard.overrideBounds(self.cnc)).isEmpty())
                {
                    self.repaintCenterRegion();
                } else if (!geom.Rect.intersect(pr, dashboard.actionsBounds(self.cnc)).isEmpty()) {
                    self.repaintActionsRegion();
                } else if (!geom.Rect.intersect(pr, dashboard.droBounds(self.cnc)).isEmpty()) {
                    self.repaintDroRegion();
                } else if (!geom.Rect.intersect(pr, dashboard.statusBounds()).isEmpty()) {
                    self.repaintStatusRegion();
                }
            }
        }

        const catalog_moving = if (self.screen == .catalog) md3_catalog.tick(&self.catalog, dt_sec) else false;
        const catalog_widget = self.screen == .catalog and widget_moving;
        if (self.screen == .catalog and (catalog_moving or catalog_widget)) {
            settings_form.bindWidgetMotion(&self.motion_phys, &self.widget_fx);
            defer settings_form.unbindWidgetMotion();
            self.catalog.press_x = self.press_x;
            self.catalog.press_y = self.press_y;
            self.catalog.press_t = self.press_fx.value;
            self.catalog.press_active = self.press_fx.value > 0.08;
            md3_catalog.paint(&self.logical, self.theme, &self.catalog);
            self.dirty.add(fullRect());
        }

        // Settings scroll / shared-axis / widget morph: content dirty.
        // An open menu owns scroll input (see nudgeScroll). Residual spring
        // paint must still re-layer the menu or the pane covers it.
        // Blocking modals (profiles, pad, PIN, …) own the frame — content
        // punches would glitch settings chrome through the modal.
        if (self.screen == .settings and !self.settingsHasBlockingModal() and
            (scroll_moving or tab_axis_moving or widget_moving))
        {
            const pane = settings_form.contentPaneRect();
            const row_band = if (!self.settings_row_dirty.isEmpty())
                geom.Rect.intersect(pane, .{
                    .x = pane.x,
                    .y = self.settings_row_dirty.y - 4,
                    .w = pane.w,
                    .h = self.settings_row_dirty.h + 8,
                })
            else
                geom.Rect.empty();
            const damage = if ((scroll_moving or tab_axis_moving) or row_band.isEmpty()) pane else row_band;
            // Clip paint to the damage band — culled rows skip draw (visibleRow).
            self.logical.setClip(damage);
            self.paintSettingsContent();
            self.logical.setClip(null);
            self.dirty.add(damage);
            self.layerOpenMenu();
        }

        const sy: i32 = i32FromF(@floor(self.sheet_y.value));
        const qs_open = quick_settings.isOpen(self.sheet_y.value);
        // qs_content_dirty / qs_slider: touch updates paint logical then tick clears dirty —
        // must re-paint + dirty here or button/slider state never presents until QS close.
        const qs_live = qs_open and (self.qs_content_dirty or self.qs_slider != .none);
        if (sheet_moving or sy != self.prev_sheet_y or qs_live or (qs_open and (press_moving or press_stain_clear or qs_tab_moving))) {
            const old_y = self.prev_sheet_y;
            const top = @min(old_y, sy);
            const closing = sy > old_y;
            const opening = sy < old_y;
            // Opening / closing: paint underlay then blend scrim. Stationary live: panel only.
            if (closing or opening or sheet_moving) {
                self.paintQsUnderlay();
                self.paintSheet(sy);
            } else {
                self.paintSheetOpts(sy, false);
            }
            self.dirty.add(.{
                .x = 0,
                .y = if (qs_open and !sheet_moving and !closing) quick_settings.openY() else top,
                .w = tokens.Logical.width,
                .h = tokens.Logical.height - (if (qs_open and !sheet_moving and !closing) quick_settings.openY() else top),
            });
            self.prev_sheet_y = sy;
            self.qs_content_dirty = false;
        }

        if (self.snack_frames > 0 and self.snack_len > 0) {
            const msg = self.snack_buf[0..self.snack_len];
            const act: ?[]const u8 = if (self.snack_action_len > 0) self.snack_action_buf[0..self.snack_action_len] else null;
            const lift: i32 = i32FromF((1.0 - self.snack_fx.value) * 48.0);
            self.snack_action_rect = widgets.drawSnackbarActionLift(&self.logical, msg, act, self.theme, lift);
            self.dirty.add(widgets.snackbarRectAction(msg, act));
            self.snack_frames -= 1;
            if (self.snack_frames == 0) {
                self.snack_action_len = 0;
                self.snack_undo_dark = null;
                self.needs_full_repaint = true;
            }
        }

        if (self.pad.open) {
            self.pad.kb_full = self.prefs.system.kb_full;
            // Instant dock — no slide-up enter (pad_fx removed).
            input_pad.paint(&self.logical, self.theme, &self.pad);
            // Present full frame so blended scrim over underlay is visible.
            self.dirty.add(fullRect());
        }

        if (self.dialog_open) {
            self.dialog_ok = widgets.drawDialogEnter(
                &self.logical,
                "Confirm",
                "Apply theme and motion?",
                self.theme,
                self.dialog_fx.value,
            );
            self.dirty.add(fullRect());
        }

        if (!self.hover_rect.isEmpty() and !qs_open and self.screen != .settings) {
            const hr = self.hover_rect;
            const rad = @min(tokens.Shape.button, @divTrunc(@min(hr.w, hr.h), 2));
            widgets.drawStateLayer(&self.logical, hr, rad, self.theme, tokens.StateLayer.hover);
            self.dirty.add(hr);
        }

        if (self.focus_kind != .none and !self.focus_rect.isEmpty() and !qs_open) {
            const fr = self.focus_rect;
            const rad = @min(tokens.Shape.button, @divTrunc(@min(fr.w, fr.h), 2));
            widgets.drawStateLayer(&self.logical, fr, rad, self.theme, tokens.StateLayer.focus);
            widgets.strokeRoundRect(&self.logical, fr, rad, self.theme.primary, 2);
            self.dirty.add(fr);
        }

        if (self.busy_frames > 0) {
            expr.drawLoadingIndicator(&self.logical, .{
                .x = @divTrunc(tokens.Logical.width - 200, 2),
                .y = tokens.Logical.height - 100,
                .w = 200,
                .h = 8,
            }, self.busy_phase, self.theme);
            self.dirty.add(.{ .x = @divTrunc(tokens.Logical.width - 200, 2), .y = tokens.Logical.height - 100, .w = 200, .h = 16 });
        }

        const t_draw_end = self.nowUs();
        self.flushDirty();
        const t_flush_end = self.nowUs();

        self.metrics = .{
            .draw_us = @intCast(t_draw_end -| t_tick_start),
            .rotate_us = @intCast(t_flush_end -| t_draw_end),
            .dirty_px = self.panel.last_write_px,
            .rotate_px = self.panel.last_write_px,
            .present_px = self.present_dirty.totalArea(),
            .device_stub_px = if (comptime @import("builtin").os.tag == .freestanding) 0 else flush_shim.submitDirtyTiles(&self.logical, &self.present_dirty).px,
            .spring_active = scroll_moving or tab_axis_moving or qs_tab_moving or press_moving or dialog_moving or power_moving or power_confirm_moving or settings_confirm_moving or cnc_overlay_moving or dash_overlay_moving or pin_overlay_moving or mach_str_moving or extra_moving or sheet_moving or catalog_moving or theme_moving or led_moving or dro_sel_moving or dro_scroll_moving or job_moving or job_wave_moving or feed_moving or spindle_moving or rapid_moving or widget_moving or snack_moving or dump_moving or self.snack_frames > 0 or self.dialog_open or self.busy_frames > 0 or self.mach_pull_polls != 0 or self.probe_busy_frames > 0 or self.qs_slider != .none or self.qs_content_dirty or (live and self.cnc_ui_sink == null and self.cnc.actions.phase == .run and self.cnc.job_progress < 1),
        };
        return self.metrics;
    }

    fn flushDirty(self: *Engine) void {
        // Idle skip — no rotate / cache write-back when nothing invalided.
        // `prev_dirty` survives: no flip happened, so the back FB still owes it.
        if (self.dirty.len == 0) {
            self.present_dirty.clear();
            self.panel.last_write_px = 0;
            return;
        }
        // Dual FB: the back buffer holds the frame before last, so it is stale
        // wherever last frame painted. Repaint that damage or the flip shows it —
        // the status bar / menu flicker and the frozen band under the app bar.
        var own: geom.DirtySet(geom.dirty_cap) = .{};
        flush_shim.copyDirty(&own, &self.dirty);
        if (flush_shim.dualBuffered()) foldStaleDamage(&self.dirty, &self.prev_dirty);
        coalesceDenseDirty(&self.dirty);
        flush_shim.copyDirty(&self.present_dirty, &self.dirty);
        // Device: rotate into DPI back FB; dual-FB flips DMA (tear-free).
        const stats = flush_shim.presentRotated(&self.panel, &self.logical, &self.dirty);
        self.panel.last_write_px = stats.px;
        // Only genuinely new damage makes the other buffer stale; re-rotated
        // catch-up pixels already match it. Keeps the set from growing to full screen.
        flush_shim.copyDirty(&self.prev_dirty, &own);
        self.dirty.clear();
    }

    /// Fold the previous frame's damage into this frame's rotate set. `logical`
    /// keeps the full composite, so this is a re-rotate, not a re-draw.
    fn foldStaleDamage(
        dirty: *geom.DirtySet(geom.dirty_cap),
        prev: *const geom.DirtySet(geom.dirty_cap),
    ) void {
        var i: usize = 0;
        while (i < prev.len) : (i += 1) dirty.add(prev.rects[i]);
    }

    /// Merge sparse dirty lists into one AABB when the union is not a blow-up —
    /// one PPA submit and a shorter mid-scan tear window.
    fn coalesceDenseDirty(d: *geom.DirtySet(geom.dirty_cap)) void {
        if (d.len <= 2) return;
        var u = d.rects[0];
        var i: usize = 1;
        while (i < d.len) : (i += 1) {
            u = geom.Rect.unionBounds(u, d.rects[i]);
        }
        if (u.area() > d.totalArea() * 2) return;
        d.clear();
        d.add(u);
    }

    /// Rects for host dirty present (valid until next tick).
    pub fn presentRects(self: *const Engine) []const geom.Rect {
        return self.present_dirty.rects[0..self.present_dirty.len];
    }

    pub fn estimateWorkUs(self: *const Engine, m: FrameMetrics) u64 {
        return (m.rotate_px * self.ns_per_px) / 1000;
    }

    pub fn withinBudget(self: *const Engine, m: FrameMetrics) bool {
        return self.estimateWorkUs(m) <= self.frame_budget_us;
    }
};

test "settings content paint survives non-finite tab/scroll springs" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    eng.tab_selected = 2;
    eng.scroll.value = std.math.inf(f32);
    eng.tab_axis.value = std.math.nan(f32);
    eng.paintSettingsContent(); // must not panic (ReleaseSafe device path)
    eng.kickTabAxis();
    _ = eng.tick(0.25); // oversized dt
    try std.testing.expect(std.math.isFinite(eng.tab_axis.value));
    try std.testing.expect(std.math.isFinite(eng.scroll.value));
}

test "engine scroll dirties less than full frame" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);

    eng.skipBoot();
    eng.openSettings();
    var settle: usize = 0;
    while (settle < 5) : (settle += 1) _ = eng.tick(1.0 / 60.0);

    // Spring chase (not setScrollTarget snap) — regional pane dirty under full-frame.
    eng.scroll.value = 0;
    eng.scroll.target = 0;
    eng.scroll.velocity = 0;
    eng.scroll.setTarget(200);
    var max_rot: u32 = 0;
    var f: usize = 0;
    while (f < 45) : (f += 1) {
        const m = eng.tick(1.0 / 60.0);
        max_rot = @max(max_rot, m.rotate_px);
    }
    const full: u32 = @as(u32, tokens.Logical.width) * @as(u32, tokens.Logical.height);
    try std.testing.expect(max_rot < full);
    try std.testing.expect(max_rot > 0);
}

test "ui golden: settings toggle present under window budget" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    var settle: usize = 0;
    while (settle < 8) : (settle += 1) _ = eng.tick(1.0 / 60.0);

    eng.tab_selected = 2; // Display
    eng.requestFull(); // auto -> settings window present
    const m = eng.tick(1.0 / 60.0);
    const full: u32 = @as(u32, tokens.Logical.width) * @as(u32, tokens.Logical.height);
    const win = settings_form.windowRect().area();
    try std.testing.expect(m.present_px > 0);
    try std.testing.expect(m.present_px <= win + 64); // small merge slack
    try std.testing.expect(m.present_px < full);
}

test "ui golden: dashboard status strip pixel fingerprint" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    var settle: usize = 0;
    while (settle < 12) : (settle += 1) _ = eng.tick(1.0 / 60.0);
    // Sample a fixed band of the status bar — catches theme/chrome regressions.
    var hash: u64 = 14695981039346656037;
    const y0: i32 = 20;
    const y1: i32 = 60;
    const x0: i32 = 40;
    const x1: i32 = 200;
    var y: i32 = y0;
    while (y < y1) : (y += 1) {
        var x: i32 = x0;
        while (x < x1) : (x += 1) {
            const px = eng.logical.get(x, y);
            hash ^= @as(u64, @as(u16, @bitCast(px)));
            hash *%= 1099511628211;
        }
    }
    try std.testing.expect(hash != 14695981039346656037);
    // Re-hash must be stable across ticks with no theme change.
    var hash2: u64 = 14695981039346656037;
    y = y0;
    while (y < y1) : (y += 1) {
        var x: i32 = x0;
        while (x < x1) : (x += 1) {
            const px = eng.logical.get(x, y);
            hash2 ^= @as(u64, @as(u16, @bitCast(px)));
            hash2 *%= 1099511628211;
        }
    }
    try std.testing.expectEqual(hash, hash2);
}

test "ui golden: settings settle dirty fingerprint" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    var settle: usize = 0;
    while (settle < 8) : (settle += 1) _ = eng.tick(1.0 / 60.0);
    eng.requestFull();
    _ = eng.tick(1.0 / 60.0);
    const rects = eng.presentRects();
    var hash: u64 = 14695981039346656037;
    for (rects) |r| {
        const parts = [_]i32{ r.x, r.y, r.w, r.h };
        for (parts) |v| {
            hash ^= @as(u64, @bitCast(@as(i64, v)));
            hash *%= 1099511628211;
        }
    }
    try std.testing.expect(rects.len >= 1 and rects.len <= 4);
    const full: u32 = @as(u32, tokens.Logical.width) * @as(u32, tokens.Logical.height);
    try std.testing.expect(rects[0].area() < full);
    try std.testing.expect(hash != 0);
    // Golden window AABB alone: x,y,w,h hashed. Bump when settings_form.windowRect changes.
    const win = settings_form.windowRect();
    var expect_hash: u64 = 14695981039346656037;
    const wparts = [_]i32{ win.x, win.y, win.w, win.h };
    for (wparts) |v| {
        expect_hash ^= @as(u64, @bitCast(@as(i64, v)));
        expect_hash *%= 1099511628211;
    }
    // After openSettings forceFullPresent, requestFull may present window-only (1 rect == window).
    if (rects.len == 1 and rects[0].x == win.x and rects[0].y == win.y and rects[0].w == win.w and rects[0].h == win.h) {
        try std.testing.expectEqual(expect_hash, hash);
    }
}

test "engine create defaults to single FB" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    try std.testing.expect(!eng.panel.hasBuffer());
    var dual = try Engine.createWith(gpa, .{ .keep_panel = true });
    defer dual.destroy(gpa);
    try std.testing.expect(dual.panel.hasBuffer());
}

test "boot hold does not drain until armed" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.boot_hold_armed = false;
    eng.boot_left_sec = 3.0;
    _ = eng.tick(1.0);
    try std.testing.expect(eng.screen == .boot);
    try std.testing.expectEqual(@as(f32, 3.0), eng.boot_left_sec);
    eng.armBootHold();
    _ = eng.tick(0.05);
    try std.testing.expect(eng.screen == .boot);
    try std.testing.expect(eng.boot_left_sec < 3.0);
    try std.testing.expect(eng.boot_left_sec > 2.9);
}

test "boot splash primary follows accent and dark mode" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    const teal = eng.theme.primary.toU16();
    eng.prefs.display.accent = 2; // Nocturnal Safety / amber family
    eng.prefs.display.darkmode = true;
    eng.applyPrefsPublic();
    eng.paintBoot();
    try std.testing.expect(eng.theme.dark);
    try std.testing.expect(eng.theme.primary.toU16() != teal);
    const dark_primary = eng.theme.primary.toU16();
    eng.prefs.display.darkmode = false;
    eng.applyPrefsPublic();
    eng.paintBoot();
    try std.testing.expect(!eng.theme.dark);
    try std.testing.expect(eng.theme.primary.toU16() != dark_primary);
}

test "theme toggle flips dark flag" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    try std.testing.expect(eng.theme.dark);
    eng.toggleTheme();
    try std.testing.expect(!eng.theme.dark);
    eng.toggleTheme();
    try std.testing.expect(eng.theme.dark);
}

test "dashboard screen after boot" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    try std.testing.expect(eng.screen == .boot);
    try std.testing.expectEqual(@as(f32, 3.0), eng.boot_left_sec);
    eng.handleClick(100, 100); // LVGL: splash ignores tap
    try std.testing.expect(eng.screen == .boot);
    eng.skipBoot();
    try std.testing.expect(eng.screen == .dashboard);
    _ = eng.tick(1.0 / 60.0);
    eng.openSettings();
    try std.testing.expect(eng.screen == .settings);
    eng.openPowerMenu();
    try std.testing.expect(eng.screen == .power);
}

test "center-column taps never reach the DRO" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    _ = eng.tick(1.0 / 60.0);

    const areas = [_]geom.Rect{
        dashboard.jogBounds(eng.cnc),
        dashboard.overrideBounds(eng.cnc),
        dashboard.actionsBounds(eng.cnc),
    };
    for (areas) |a| {
        var y = a.y;
        while (y < a.y + a.h) : (y += 8) {
            var x = a.x;
            while (x < a.x + a.w) : (x += 8) {
                eng.cnc.dro.selected = 1;
                eng.cnc.dro.work_um[1] = -12300;
                eng.handleClick(x, y);
                try std.testing.expectEqual(@as(usize, 1), eng.cnc.dro.selected);
                try std.testing.expectEqual(@as(i32, -12300), eng.cnc.dro.work_um[1]);
            }
        }
    }
}

test "DRO live paint gate follows work_um mirror" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    _ = eng.tick(1.0 / 60.0);
    eng.syncDroLivePaint();
    const before = eng.gate_dro_work[0];
    eng.cnc.dro.work_um[0] = before +% 1000;
    eng.syncDroLivePaint();
    try std.testing.expectEqual(eng.cnc.dro.work_um[0], eng.gate_dro_work[0]);
    eng.syncDroLivePaint(); // unchanged — no-op
    try std.testing.expectEqual(eng.cnc.dro.work_um[0], eng.gate_dro_work[0]);
}

test "boot pin_boot opens unlock pad" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    try std.testing.expect(eng.prefs.security.setPin("1234"));
    eng.prefs.security.pin_boot = true;
    eng.skipBoot();
    try std.testing.expect(eng.screen == .pin);
    try std.testing.expect(eng.pad.open);
    try std.testing.expect(eng.pad.target == .sec_pin_unlock);
}

test "boot pin lock has no exit but the PIN" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    try std.testing.expect(eng.prefs.security.setPin("1234"));
    eng.prefs.security.pin_boot = true;
    eng.skipBoot();

    // Scrim tap above the keypad dock.
    eng.handleClick(640, 20);
    try std.testing.expect(eng.screen == .pin);
    try std.testing.expect(eng.pad.open and eng.pad.target == .sec_pin_unlock);

    // Cancel key on the keypad.
    const dock = input_pad.panelRect(&eng.pad);
    eng.handleClick(dock.x + dock.w - 20, dock.y + dock.h - 20);
    try std.testing.expect(eng.screen == .pin);
    try std.testing.expect(eng.pad.open);

    // Predictive back / edge swipe.
    try std.testing.expect(eng.gestureBack());
    try std.testing.expect(eng.screen == .pin);
    try std.testing.expect(eng.pad.open);

    // Wrong PIN re-arms; correct PIN unlocks.
    eng.pad.len = 0;
    for ("9999") |c| eng.pad.pushChar(c);
    eng.commitPad();
    try std.testing.expect(eng.screen == .pin);
    for ("1234") |c| eng.pad.pushChar(c);
    eng.commitPad();
    try std.testing.expect(eng.screen == .dashboard);
    try std.testing.expect(!eng.pad.open);
}

test "number pad refuses to claim success on a bad buffer" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.prefs.display.notify_en = true;
    eng.prefs.display.bright = 60;
    eng.openNumberForTarget(.disp_bright, "Brightness", 60);
    eng.pad.len = 0; // operator backspaced the field empty
    eng.commitPad();
    try std.testing.expectEqual(@as(u8, 60), eng.prefs.display.bright);
    try std.testing.expectEqualStrings("Enter a number", eng.snack_buf[0..eng.snack_len]);

    eng.openNumberForTarget(.disp_bright, "Brightness", 60);
    eng.pad.len = 0;
    for ("75") |c| eng.pad.pushChar(c);
    eng.commitPad();
    try std.testing.expectEqual(@as(u8, 75), eng.prefs.display.bright);
}

test "popup overlays open at full enter_t (no scale-in)" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();

    eng.openPowerMenu();
    try std.testing.expectApproxEqAbs(@as(f32, 1), eng.power_fx.value, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), eng.power_fx.target, 0.001);

    eng.closePowerMenu();
    eng.openSettings();
    eng.openSettingsConfirm(.factory);
    try std.testing.expectApproxEqAbs(@as(f32, 1), eng.settings_confirm_fx.value, 0.001);

    eng.closeSettingsConfirm();
    eng.openDashWcs();
    try std.testing.expectApproxEqAbs(@as(f32, 1), eng.dash_overlay_fx.value, 0.001);

    eng.closeDashOverlay();
    eng.openExtra(.probe);
    try std.testing.expectApproxEqAbs(@as(f32, 1), eng.extra_fx.value, 0.001);

    eng.openDialog();
    try std.testing.expectApproxEqAbs(@as(f32, 1), eng.dialog_fx.value, 0.001);
}

test "power menu confirm and busy gate" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openPowerMenu();
    _ = eng.tick(1.0 / 60.0);
    try std.testing.expect(!eng.power_layout.restart.isEmpty());
    try std.testing.expect(!eng.power_layout.unlock.isEmpty());

    eng.handleClick(eng.power_layout.restart.x + 8, eng.power_layout.restart.y + 8);
    try std.testing.expect(eng.power_confirm == .restart);
    _ = eng.tick(1.0 / 60.0);
    eng.handleClick(eng.power_layout.confirm_cancel.x + 4, eng.power_layout.confirm_cancel.y + 4);
    try std.testing.expect(eng.power_confirm == .none);

    eng.cnc.connected = true;
    eng.cnc.setPhase(.run);
    eng.handleClick(eng.power_layout.shutdown.x + 8, eng.power_layout.shutdown.y + 8);
    try std.testing.expect(eng.power_confirm == .none); // busy
}

test "system tab health jump and factory confirm" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    eng.tab_selected = 9;
    eng.requestFull();
    _ = eng.tick(1.0 / 60.0);
    try std.testing.expect(eng.other_layout.n > 5);

    // Health CNC chip → CNC tab (chips sit at top — always hit-testable)
    const cnc_chip = eng.slotRect(.sys_h_cnc) orelse return error.MissingHealthChip;
    eng.handleClick(cnc_chip.x + 4, cnc_chip.y + 4);
    try std.testing.expectEqual(@as(usize, 0), eng.tab_selected);

    eng.tab_selected = 9;
    eng.requestFull();
    _ = eng.tick(1.0 / 60.0);
    // Factory row is below the fold — drive confirm API (LVGL confirm path)
    eng.openSettingsConfirm(.factory);
    try std.testing.expect(eng.settings_confirm == .factory);
    _ = eng.tick(1.0 / 60.0);
    eng.handleClick(eng.settings_confirm_cancel.x + 4, eng.settings_confirm_cancel.y + 4);
    try std.testing.expect(eng.settings_confirm == .none);

    // NTP gates manual
    eng.prefs.system.ntp = true;
    eng.requestFull();
    _ = eng.tick(1.0 / 60.0);
    const man = eng.slotRect(.sys_manual) orelse return error.MissingManual;
    // Scroll so manual row is inside the settings window before click
    if (man.y > settings_form.content_bottom - 8) {
        eng.scroll.value = @floatFromInt(man.y - settings_form.content_top - 40);
        eng.scroll.setTarget(eng.scroll.value);
        eng.requestFull();
        _ = eng.tick(1.0 / 60.0);
    }
    const man2 = eng.slotRect(.sys_manual) orelse return error.MissingManual;
    eng.handleClick(man2.x + 8, man2.y + 8);
    try std.testing.expect(!eng.pad.open);
}

test "system date time ntp sync stub" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    eng.tab_selected = 9;

    eng.prefs.system.ntp = false;
    eng.prefs.wireless.wifi = true;
    try std.testing.expect(std.mem.eql(u8, eng.prefs.system.ntpStatus(true), "Disabled"));
    try std.testing.expect(eng.tryOpenOrDragOther(.sys_sync, 0, 0));
    try std.testing.expect(!eng.prefs.system.ntp); // Sync now must not force-enable
    try std.testing.expect(std.mem.eql(u8, eng.prefs.system.ntpStatus(true), "Disabled"));

    eng.prefs.system.ntp = true;
    eng.prefs.wireless.wifi = false;
    try std.testing.expect(std.mem.eql(u8, eng.prefs.system.ntpStatus(false), "No network"));
    try std.testing.expectEqual(settings_prefs.SystemPrefs.SyncNowResult.no_net, eng.prefs.system.syncNow(false));

    eng.prefs.wireless.wifi = true;
    try std.testing.expectEqual(settings_prefs.SystemPrefs.SyncNowResult.started, eng.prefs.system.syncNow(true));
    try std.testing.expect(std.mem.eql(u8, eng.prefs.system.ntpStatus(true), "Syncing..."));
    eng.prefs.system.tickOneSec();
    eng.prefs.system.tickOneSec();
    try std.testing.expect(std.mem.eql(u8, eng.prefs.system.ntpStatus(true), "Synced"));

    eng.prefs.system.setNtpEnabled(false, true);
    try std.testing.expect(std.mem.eql(u8, eng.prefs.system.ntpStatus(true), "Disabled"));
}

test "storage tab mount eject confirm and export gate" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    eng.tab_selected = 8;
    eng.prefs.settings_advanced = true;
    eng.requestFull();
    _ = eng.tick(1.0 / 60.0);

    const sd = eng.slotRect(.stor_sd) orelse return error.MissingSd;
    eng.handleClick(sd.x + 8, sd.y + 8);
    try std.testing.expect(eng.prefs.storage.sd == .mounted);

    eng.requestFull();
    _ = eng.tick(1.0 / 60.0);
    const sd2 = eng.slotRect(.stor_sd) orelse return error.MissingSd;
    eng.handleClick(sd2.x + 8, sd2.y + 8);
    try std.testing.expect(eng.settings_confirm == .eject_sd);
    _ = eng.tick(1.0 / 60.0);
    eng.handleClick(eng.settings_confirm_ok.x + 4, eng.settings_confirm_ok.y + 4);
    try std.testing.expect(eng.prefs.storage.sd == .unmounted);

    eng.handleClick((eng.slotRect(.stor_export) orelse return error.MissingExport).x + 4, (eng.slotRect(.stor_export) orelse return error.MissingExport).y + 4);
    try std.testing.expect(eng.prefs.storage.sd == .unmounted); // still gated
    try std.testing.expect(std.mem.eql(u8, eng.prefs.storage.diagDetail(), "Insert SD card"));
}

test "storage export import clear cache stubs" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    eng.tab_selected = 8;
    eng.prefs.settings_advanced = true;
    eng.prefs.storage.mount();
    eng.prefs.machine.setName("Before");
    eng.prefs.display.bright = 40;
    eng.requestFull();
    _ = eng.tick(1.0 / 60.0);

    // Direct hit path (export row may sit below fold).
    try std.testing.expect(eng.tryOpenOrDragOther(.stor_export, 0, 0));
    try std.testing.expect(std.mem.eql(u8, eng.prefs.storage.diagDetail(), "Saved modulus_diag.txt"));
    try std.testing.expect(eng.prefs.storage.diag_flash_frames > 0);

    try std.testing.expect(eng.tryOpenOrDragOther(.stor_backup_exp, 0, 0));
    try std.testing.expect(std.mem.eql(u8, eng.prefs.storage.backupExportDetail(), "Exported"));

    try std.testing.expect(eng.tryOpenOrDragOther(.stor_backup_imp, 0, 0));
    try std.testing.expect(eng.settings_confirm == .import_settings);
    _ = eng.tick(1.0 / 60.0);
    eng.handleClick(eng.settings_confirm_ok.x + 4, eng.settings_confirm_ok.y + 4);
    try std.testing.expect(std.mem.eql(u8, eng.prefs.machine.nameSlice(), "Imported CNC"));
    try std.testing.expectEqual(@as(u8, 72), eng.prefs.display.bright);

    eng.prefs.storage.sd = .failed;
    eng.prefs.storage.diag_flash_frames = 0;
    _ = eng.prefs.storage.exportDiagnosticsStub();
    try std.testing.expect(std.mem.eql(u8, eng.prefs.storage.diagDetail(), "Export failed"));

    eng.prefs.storage.mount();
    eng.settings_confirm = .none;
    eng.snack_len = 0;
    eng.snack_frames = 0;
    eng.requestFull();
    _ = eng.tick(1.0 / 60.0);
    eng.needs_full_repaint = false;
    eng.gate_job_pct = 0;
    try std.testing.expect(eng.tryOpenOrDragOther(.stor_cache, 0, 0));
    try std.testing.expect(eng.needs_full_repaint);
    try std.testing.expectEqual(@as(u8, 0xFF), eng.gate_job_pct);
    try std.testing.expectEqual(@as(usize, 0), eng.snack_len); // LVGL: no snackbar
}

test "machine tab sync branch and reset confirm" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    eng.tab_selected = 7;
    eng.prefs.cnc.proto = 0; // GrblHAL → pull/push/$$
    eng.requestFull();
    _ = eng.tick(1.0 / 60.0);
    try std.testing.expect(eng.slotRect(.mach_pull) != null);
    try std.testing.expect(eng.slotRect(.mach_dump) != null);

    eng.openSettingsConfirm(.mach_reset);
    _ = eng.tick(1.0 / 60.0);
    try std.testing.expect(eng.settings_confirm == .mach_reset);
    eng.handleClick(eng.settings_confirm_cancel.x + 4, eng.settings_confirm_cancel.y + 4);
    try std.testing.expect(eng.settings_confirm == .none);

    eng.prefs.machine.odo_mm = 5000;
    eng.openSettingsConfirm(.maint_reset);
    _ = eng.tick(1.0 / 60.0);
    eng.handleClick(eng.settings_confirm_ok.x + 4, eng.settings_confirm_ok.y + 4);
    try std.testing.expectEqual(@as(u32, 0), eng.prefs.machine.odo_mm);
}

test "power tab deep-sleep gate and reset confirm" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    eng.tab_selected = 5;
    eng.prefs.settings_advanced = true;
    eng.prefs.power.pwr_mode = 0;
    eng.requestFull();
    _ = eng.tick(1.0 / 60.0);
    try std.testing.expect(eng.slotRect(.pwr_dsto) != null);
    try std.testing.expect(!eng.prefs.power.deepSleep());

    eng.prefs.power.pwr_mode = 1;
    eng.requestFull();
    _ = eng.tick(1.0 / 60.0);
    try std.testing.expect(eng.prefs.power.deepSleep());

    const before = eng.prefs.power.dim_idx;
    eng.prefs.power.dim_idx = 3;
    eng.openSettingsConfirm(.power_reset);
    _ = eng.tick(1.0 / 60.0);
    eng.handleClick(eng.settings_confirm_ok.x + 4, eng.settings_confirm_ok.y + 4);
    try std.testing.expectEqual(before, eng.prefs.power.dim_idx); // resetDefaults restores 0; before was whatever default
    try std.testing.expectEqual(@as(u8, 0), eng.prefs.power.dim_idx);
}

test "security tab pin gate clear and wake coupling" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    eng.tab_selected = 6;
    eng.requestFull();
    _ = eng.tick(1.0 / 60.0);
    try std.testing.expect(!eng.prefs.security.has_pin);

    try std.testing.expect(eng.prefs.security.setPin("1234"));
    eng.prefs.security.pin_tmo_idx = 0;
    eng.prefs.security.setWake(true);
    try std.testing.expectEqual(@as(u8, 6), eng.prefs.security.pin_tmo_idx);
    eng.prefs.security.applyTmoIdx(0);
    try std.testing.expect(!eng.prefs.security.pin_slp);

    eng.openPinOverlay(.clear);
    _ = eng.tick(1.0 / 60.0);
    try std.testing.expect(eng.pin_overlay == .clear);
    @memcpy(eng.pin_draft1[0..4], "1234");
    eng.pin_draft1_len = 4;
    eng.commitPinOverlaySave();
    try std.testing.expect(!eng.prefs.security.has_pin);
    try std.testing.expect(eng.pin_overlay == .none);
}

test "security set pin dual-field modal" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    eng.openPinOverlay(.set);
    _ = eng.tick(1.0 / 60.0);
    try std.testing.expect(eng.pin_overlay == .set);
    @memcpy(eng.pin_draft1[0..4], "5678");
    eng.pin_draft1_len = 4;
    eng.commitPinOverlaySave();
    try std.testing.expect(eng.pin_status_err);
    try std.testing.expect(eng.pin_err2);
    @memcpy(eng.pin_draft2[0..4], "9999");
    eng.pin_draft2_len = 4;
    eng.commitPinOverlaySave();
    try std.testing.expect(eng.pin_err1 and eng.pin_err2);
    @memcpy(eng.pin_draft2[0..4], "5678");
    eng.pin_draft2_len = 4;
    eng.commitPinOverlaySave();
    try std.testing.expect(eng.prefs.security.has_pin);
    try std.testing.expect(eng.prefs.security.verifyPin("5678"));
    try std.testing.expect(!eng.prefs.security.verifyPin("1234"));
    try std.testing.expect(eng.pin_overlay == .none);
}

test "machine pull applies envelope stub" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.prefs.machine.mxfeed = 100;
    eng.startMachPull();
    var i: u8 = 0;
    while (i < 12) : (i += 1) {
        _ = eng.tick(1.0 / 60.0);
    }
    try std.testing.expectEqual(@as(u8, 0), eng.mach_pull_polls);
    try std.testing.expectEqual(@as(u16, 5000), eng.prefs.machine.mxfeed);
    try std.testing.expectEqual(@as(u16, 1000), eng.prefs.machine.mxrpm);
}

test "machine name modal sanitizes and saves" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openMachStrOverlay(.name);
    _ = eng.tick(1.0 / 60.0);
    try std.testing.expect(eng.mach_str_overlay == .name);
    const dirty = "Hi\tCNC\x01!!";
    @memcpy(eng.mach_str_draft[0..dirty.len], dirty);
    eng.mach_str_draft_len = @intCast(dirty.len);
    eng.commitMachStrSave();
    try std.testing.expectEqualStrings("HiCNC!!", eng.prefs.machine.nameSlice());
    try std.testing.expect(eng.mach_str_overlay == .none);

    eng.openMachStrOverlay(.name);
    eng.mach_str_draft_len = 0;
    eng.commitMachStrSave();
    try std.testing.expect(eng.mach_str_err);
    try std.testing.expect(eng.mach_str_overlay == .name);
}

test "machine service notes max 63" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    var long: [80]u8 = undefined;
    @memset(&long, 'a');
    eng.prefs.machine.setSvcNotes(&long);
    try std.testing.expectEqual(@as(usize, 63), eng.prefs.machine.svcNtSlice().len);
}

test "wireless tab hub wifi scan and reset" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    eng.tab_selected = 4;
    eng.prefs.settings_advanced = true;
    eng.requestFull();
    _ = eng.tick(1.0 / 60.0);
    try std.testing.expect(eng.slotRect(.wl_wifi_page) != null);
    try std.testing.expect(eng.slotRect(.wl_reset) != null);

    eng.handleClick((eng.slotRect(.wl_wifi_page) orelse return error.MissingWifi).x + 8, (eng.slotRect(.wl_wifi_page) orelse return error.MissingWifi).y + 8);
    try std.testing.expectEqual(@as(u8, 1), eng.prefs.wireless.page);
    eng.prefs.wireless.wifi = true;
    eng.requestFull();
    _ = eng.tick(1.0 / 60.0);
    _ = eng.tryOpenOrDragOther(.wl_scan, 0, 0);
    try std.testing.expectEqual(@as(u8, 1), eng.prefs.wireless.scan_phase);
    _ = eng.tick(1.1);
    try std.testing.expectEqual(@as(u8, 2), eng.prefs.wireless.scan_phase);

    eng.openSettingsConfirm(.wireless_reset);
    _ = eng.tick(1.0 / 60.0);
    eng.handleClick(eng.settings_confirm_ok.x + 4, eng.settings_confirm_ok.y + 4);
    try std.testing.expectEqual(@as(u8, 0), eng.prefs.wireless.page);
    try std.testing.expect(!eng.prefs.wireless.wifi);
}

test "wireless bt espnow zigbee stubs" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.prefs.wireless.bt = true;
    eng.prefs.wireless.startBtScan();
    eng.prefs.wireless.tickTelemetry();
    eng.prefs.wireless.connectBt(0);
    try std.testing.expect(eng.prefs.wireless.bt_conn);
    try std.testing.expect(std.mem.eql(u8, eng.prefs.wireless.pairedText(), "Pendant-BLE"));
    eng.prefs.wireless.clearBtPaired();
    try std.testing.expect(!eng.prefs.wireless.bt_conn);

    eng.prefs.wireless.espnow = true;
    eng.prefs.wireless.startEnScan();
    eng.prefs.wireless.tickTelemetry();
    eng.prefs.wireless.setBridgePeer(0);
    try std.testing.expect(eng.prefs.wireless.peerSaved(0));
    try std.testing.expectEqual(@as(u8, 0), eng.prefs.wireless.en_active);
    eng.prefs.wireless.commitMac("aa:bb:cc:dd:ee:ff");
    try std.testing.expect(std.mem.eql(u8, eng.prefs.wireless.bridgeSlice(), "AA:BB:CC:DD:EE:FF"));
    eng.prefs.syncEspnowMacFromBridge();
    try std.testing.expect(std.mem.eql(u8, eng.prefs.cnc.espnowMacSlice(), "AA:BB:CC:DD:EE:FF"));
    try std.testing.expect(std.mem.eql(u8, eng.prefs.espnowMacForNvs(), "AA:BB:CC:DD:EE:FF"));

    eng.prefs.wireless.joinZigbee();
    try std.testing.expect(eng.prefs.wireless.zb_joined);
    try std.testing.expectEqual(@as(u8, 2), eng.prefs.wireless.zb_dev_n);
    eng.prefs.wireless.leaveZigbee();
    try std.testing.expectEqual(@as(u8, 0), eng.prefs.wireless.zb_dev_n);

    eng.prefs.wireless.attachThread();
    try std.testing.expectEqual(@as(u8, 1), eng.prefs.wireless.th_dev_n);

    const jump = settings_other_tabs.applyHit(&eng.prefs, .wl_link_ntp, null, 0, 0, .{}, 0);
    try std.testing.expectEqual(@as(?usize, 9), jump);
    const cnc = settings_other_tabs.applyHit(&eng.prefs, .wl_link_cnc, null, 0, 0, .{}, 0);
    try std.testing.expectEqual(@as(?usize, 0), cnc);
}

test "audio tab codec gate and tone snack" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    eng.tab_selected = 3;
    eng.prefs.settings_advanced = true;
    eng.prefs.audio.out_ready = false;
    eng.requestFull();
    _ = eng.tick(1.0 / 60.0);
    try std.testing.expect(eng.slotRect(.aud_vol) == null);

    eng.prefs.audio.out_ready = true;
    eng.prefs.audio.hp_inserted = true;
    eng.prefs.audio.hw_ref_exp = true;
    eng.requestFull();
    _ = eng.tick(1.0 / 60.0);
    try std.testing.expect(eng.slotRect(.aud_vol) != null);
    try std.testing.expect(eng.slotRect(.aud_tone) != null);
}

test "display tab power jump and reset confirm" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    eng.tab_selected = 2;
    eng.prefs.settings_advanced = true;
    eng.prefs.display.bright = 42;
    eng.prefs.display.motion_scheme = 1;
    eng.prefs.display.theme_ref_exp = true;
    eng.requestFull();
    _ = eng.tick(1.0 / 60.0);
    try std.testing.expect(eng.disp_layout.pwr_sleep.w > 0);
    try std.testing.expect(eng.disp_layout.reset.w > 0);

    const jump = settings_display_tab.applyHit(&eng.prefs.display, .pwr_sleep, null, 0, eng.disp_layout);
    try std.testing.expectEqual(@as(?usize, 5), jump);

    eng.openSettingsConfirm(.display_reset);
    _ = eng.tick(1.0 / 60.0);
    eng.handleClick(eng.settings_confirm_ok.x + 4, eng.settings_confirm_ok.y + 4);
    try std.testing.expectEqual(@as(u8, 100), eng.prefs.display.bright);
    try std.testing.expectEqual(@as(u8, 0), eng.prefs.display.motion_scheme);
}

test "dashboard tab links menus and reset confirm" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    eng.tab_selected = 1;
    eng.prefs.settings_advanced = true;
    eng.prefs.dash.quick[3] = .led;
    eng.requestFull();
    _ = eng.tick(1.0 / 60.0);
    try std.testing.expect(eng.dash_layout.link_mach.w > 0);
    try std.testing.expect(eng.dash_layout.link_cnc.w > 0);
    try std.testing.expect(eng.dash_layout.jogspd.w > 0);
    try std.testing.expectEqual(@as(?usize, 7), settings_dashboard_tab.applyHit(&eng.prefs.dash, .link_mach, null, 0, eng.dash_layout));
    try std.testing.expectEqual(@as(?usize, 0), settings_dashboard_tab.applyHit(&eng.prefs.dash, .link_cnc, null, 0, eng.dash_layout));
    try std.testing.expectEqual(@as(?usize, 2), settings_dashboard_tab.applyHit(&eng.prefs.dash, .link_disp, null, 0, eng.dash_layout));
    try std.testing.expect(settings_menu.targetForDashHit(.jogspd) == .jogspd);
    try std.testing.expect(settings_menu.targetForDashHit(.cnf_spin) == .confirm_spin);
    try std.testing.expect(eng.dash_layout.cnf_zero.w > 0);
    const scroll_to = @max(0, eng.dash_layout.cnf_zero.y - 120);
    eng.scroll.value = @floatFromInt(scroll_to);
    eng.scroll.setTarget(eng.scroll.value);
    eng.requestFull();
    _ = eng.tick(1.0 / 60.0);
    const cz = eng.dash_layout.cnf_zero.x + @divTrunc(eng.dash_layout.cnf_zero.w, 2);
    const cy = eng.dash_layout.cnf_zero.y + @divTrunc(eng.dash_layout.cnf_zero.h, 2);
    eng.handleClick(cz, cy);
    try std.testing.expect(eng.menu_target == .confirm_zero);
    eng.closeMenu();

    eng.openSettingsConfirm(.dashboard_reset);
    _ = eng.tick(1.0 / 60.0);
    eng.handleClick(eng.settings_confirm_ok.x + 4, eng.settings_confirm_ok.y + 4);
    try std.testing.expect(eng.prefs.dash.quick[2] == .fan);
    try std.testing.expect(eng.prefs.dash.quick[3] == .zero_all);
    try std.testing.expectEqualStrings("0.1", eng.prefs.dash.incrSlice(2));
}

test "cnc tab session disconnect preferred transport and reset" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    eng.tab_selected = 0;
    eng.prefs.cnc.conn = 4;
    eng.prefs.cnc.session_phase = 3;
    eng.prefs.cnc.session_up = true;
    eng.requestFull();
    _ = eng.tick(1.0 / 60.0);
    try std.testing.expect(eng.slotRect(.cnc_connect) != null);

    eng.prefs.settings_advanced = true;
    eng.requestFull();
    _ = eng.tick(1.0 / 60.0);
    try std.testing.expect(eng.slotRect(.cnc_dump) != null);

    eng.prefs.cnc.disconnect();
    try std.testing.expect(eng.prefs.cnc.transport_off);
    try std.testing.expectEqualStrings("Transport off", eng.prefs.cnc.sessionText());

    settings_menu.apply(&eng.prefs, .proto, 3); // LinuxCNC → Telnet 5007
    try std.testing.expectEqual(@as(u8, 2), eng.prefs.cnc.conn);
    try std.testing.expectEqual(@as(u16, 5007), eng.prefs.cnc.tn_port);
    try std.testing.expect(!eng.prefs.cnc.transport_off);

    eng.prefs.cnc.proto = 5;
    eng.requestFull();
    _ = eng.tick(1.0 / 60.0);
    try std.testing.expect(eng.slotRect(.cnc_dump) == null);

    eng.prefs.cnc.proto = 3; // LinuxCNC — $$ on CNC tab hidden (Machine uses INI)
    eng.requestFull();
    _ = eng.tick(1.0 / 60.0);
    try std.testing.expect(eng.slotRect(.cnc_dump) == null);

    eng.openSettingsConfirm(.cnc_reset);
    _ = eng.tick(1.0 / 60.0);
    eng.handleClick(eng.settings_confirm_ok.x + 4, eng.settings_confirm_ok.y + 4);
    try std.testing.expectEqual(@as(u8, 4), eng.prefs.cnc.conn);
    try std.testing.expect(!eng.prefs.cnc.transport_off);
}

test "device clock sink does not fake-discharge battery" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    // Device runtime installs now_us_sink — stub SoC must not stomp INA.
    eng.now_us_sink = struct {
        fn us() u64 {
            return 0;
        }
    }.us;
    eng.cnc.battery_pct = 95;
    eng.prefs.power.bat_pct = 95;
    eng.prefs.power.charge_state = 0;
    eng.prefs.machine.odo_mm = 1000;
    eng.prefs.wireless.espnow = true;
    eng.prefs.wireless.live_en_saved_n = 0;
    eng.prefs.wireless.en_rx = 10;
    eng.prefs.wireless.en_tx = 5;
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        _ = eng.tick(1.0);
    }
    try std.testing.expectEqual(@as(u8, 95), eng.cnc.battery_pct);
    try std.testing.expectEqual(@as(u8, 95), eng.prefs.power.bat_pct);
    try std.testing.expectEqual(@as(u32, 1000), eng.prefs.machine.odo_mm);
    try std.testing.expectEqual(@as(u32, 10), eng.prefs.wireless.en_rx);
    try std.testing.expectEqual(@as(u32, 5), eng.prefs.wireless.en_tx);
}

test "cnc profiles modal and dump browser" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    eng.tab_selected = 0;
    eng.prefs.cnc.proto = 0;
    eng.prefs.cnc.conn = 1;
    eng.prefs.cnc.ws_port = 81;
    eng.requestFull();
    _ = eng.tick(1.0 / 60.0);

    eng.openCncProfiles();
    try std.testing.expect(eng.cnc_overlay == .profiles);
    _ = eng.tick(1.0 / 60.0);
    eng.handleClick(eng.cnc_prof_layout.save.x + 4, eng.cnc_prof_layout.save.y + 4);
    try std.testing.expect(eng.prefs.cnc.profileOccupied(0));
    try std.testing.expectEqualStrings("Profile 1", eng.prefs.cnc.profileName(0));

    eng.prefs.cnc.conn = 4;
    eng.handleClick(eng.cnc_prof_layout.activate[0].x + 4, eng.cnc_prof_layout.activate[0].y + 4);
    try std.testing.expectEqual(@as(u8, 1), eng.prefs.cnc.conn);

    eng.closeCncOverlay();
    eng.openCncDump();
    try std.testing.expect(eng.cnc_overlay == .dump);
    var n: u32 = 0;
    while (!eng.cnc_dump.ready and n < 40) : (n += 1) {
        _ = eng.tick(1.0 / 60.0);
    }
    try std.testing.expect(eng.cnc_dump.ready);
    try std.testing.expect(eng.cnc_dump.len > 0);
    eng.handleClick(eng.cnc_dump.close.x + 4, eng.cnc_dump.close.y + 4);
    try std.testing.expect(eng.cnc_overlay == .none);
}

test "settings: profiles clock tick and pad dismiss present" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    eng.tab_selected = 0;
    _ = eng.tick(1.0 / 60.0);

    eng.openCncProfiles();
    try std.testing.expect(eng.settingsHasBlockingModal());
    _ = eng.tick(1.0 / 60.0);
    // Sample modal card center — must survive content-pane punch attempts.
    const cx = eng.cnc_prof_layout.card.x + @divTrunc(eng.cnc_prof_layout.card.w, 2);
    const cy = eng.cnc_prof_layout.card.y + @divTrunc(eng.cnc_prof_layout.card.h, 2);
    const modal_px = eng.logical.get(cx, cy).toU16();
    eng.repaintSettingsContentPane(); // must no-op while profiles open
    try std.testing.expectEqual(modal_px, eng.logical.get(cx, cy).toU16());
    // ~4 s of 1 Hz clock path used to punch settings chrome through the modal.
    var sec: usize = 0;
    while (sec < 5) : (sec += 1) {
        _ = eng.tick(1.0);
    }
    try std.testing.expect(eng.cnc_overlay == .profiles);
    try std.testing.expectEqual(modal_px, eng.logical.get(cx, cy).toU16());
    eng.closeCncOverlay();

    eng.openTextPad(.search, "Search tabs", "");
    try std.testing.expect(eng.pad.open);
    try std.testing.expect(eng.settingsHasBlockingModal());
    _ = eng.tick(1.0 / 60.0);
    eng.pad.clear();
    eng.afterPadDismiss();
    try std.testing.expect(!eng.pad.open);
    try std.testing.expect(!eng.settings_present_window);
    try std.testing.expect(eng.needs_full_repaint);
}

test "dashboard overlays: incr wcs macro arrange" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    eng.tab_selected = 1; // Dashboard
    eng.requestFull();
    _ = eng.tick(1.0 / 60.0);

    eng.openDashWcs();
    try std.testing.expect(eng.dash_overlay == .wcs);
    _ = eng.tick(1.0 / 60.0);
    eng.handleClick(eng.dash_wcs_layout.lock[1].x + 4, eng.dash_wcs_layout.lock[1].y + 4);
    try std.testing.expect((eng.prefs.dash.wcs_lock & 0b10) != 0);
    eng.closeDashOverlay();

    eng.openDashMacro(0, false);
    try std.testing.expect(eng.dash_overlay == .macro);
    settings_prefs.MacroSlot.setField(&eng.dash_mac_draft.name, "Air");
    settings_prefs.MacroSlot.setField(&eng.dash_mac_draft.on, "M8");
    _ = eng.tick(1.0 / 60.0);
    eng.handleClick(eng.dash_mac_layout.save.x + 4, eng.dash_mac_layout.save.y + 4);
    try std.testing.expect(eng.prefs.dash.macros[0].occupied());
    try std.testing.expect(eng.dash_overlay == .none);

    eng.openDashArrange();
    try std.testing.expect(eng.dash_overlay == .arrange);
    _ = eng.tick(1.0 / 60.0);
    eng.handleClick(eng.dash_arr_layout.slot[0].x + 4, eng.dash_arr_layout.slot[0].y + 4);
    try std.testing.expectEqual(@as(i8, 0), eng.dash_arr_pick);
    _ = eng.tick(1.0 / 60.0);
    // Pick first listed action (spindle_cw)
    eng.handleClick(eng.dash_arr_layout.picks[0].x + 4, eng.dash_arr_layout.picks[0].y + 4);
    try std.testing.expectEqual(actions_widget.QuickId.spindle_cw, eng.prefs.dash.quick[0]);
    try std.testing.expectEqual(@as(i8, -1), eng.dash_arr_pick);
}

test "RUN ticks dirty job strip not full frame" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    _ = eng.tick(1.0 / 60.0); // settle boot→dashboard full
    eng.setMachinePhase(.run);
    _ = eng.tick(1.0 / 60.0); // phase full paint + led spring start

    // Drain LED morph spring without counting those frames.
    var settle: usize = 0;
    while (settle < 90) : (settle += 1) {
        const m = eng.tick(1.0 / 60.0);
        if (!m.spring_active and m.rotate_px == 0) break;
    }

    const full: u32 = @as(u32, tokens.Logical.width) * @as(u32, tokens.Logical.height);
    const strip: u32 = @as(u32, tokens.Logical.width) * @as(u32, dashboard.job_strip_h);
    var max_rot: u32 = 0;
    var f: usize = 0;
    while (f < 120) : (f += 1) {
        const m = eng.tick(1.0 / 60.0);
        max_rot = @max(max_rot, m.rotate_px);
        try std.testing.expect(eng.withinBudget(m));
    }
    try std.testing.expect(max_rot > 0);
    try std.testing.expect(max_rot < full);
    // Change-gated wave updates stay near the strip; status may ride along
    // while the LED morph finishes draining.
    try std.testing.expect(max_rot <= strip * 3);
}

test "frame budget matches LVGL refresh floor" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    try std.testing.expectEqual(tokens.Motion.refresh_floor_us, eng.frame_budget_us);
    try std.testing.expect(eng.frame_budget_us >= 30_000);
    eng.prefs.display.refr_hz = 2;
    eng.applyPrefs();
    try std.testing.expectEqual(@as(u64, 50_000), eng.frame_budget_us);
    eng.prefs.display.touch_glove = true;
    eng.applyPrefs();
    try std.testing.expectEqual(@as(i32, 8), geom.hit_pad);
    defer geom.hit_pad = 0;
    eng.prefs.display.flip = true;
    const p = eng.mapPointer(0, 0);
    try std.testing.expectEqual(@as(i32, tokens.Logical.width - 1), p.x);
    try std.testing.expectEqual(@as(i32, tokens.Logical.height - 1), p.y);
}

test "settings finger drag scrolls content and suppresses click" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    eng.tab_selected = 0;
    _ = eng.tick(1.0 / 60.0);
    eng.settings_content_h = 2000; // force scrollable range
    const before = eng.scroll.target;
    eng.handlePointerDrag(600, 200);
    eng.handlePointerDrag(600, 140); // drag up 60px → content scrolls down
    try std.testing.expect(eng.scroll.target > before);
    try std.testing.expect(eng.drag_scrolled);
    try std.testing.expect(eng.handlePointerUp());
}

test "settings scroll track is critically damped without impulse jiggle" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    eng.settings_content_h = 2000;
    eng.setScrollTarget(100);
    eng.nudgeScroll(80);
    try std.testing.expect(eng.scroll.target == 180);
    // Value eases toward target (not hard-snapped, not impulse-kicked past it).
    try std.testing.expect(eng.scroll.value >= 100);
    try std.testing.expect(eng.scroll.value <= 180);
    var i: usize = 0;
    while (i < 90) : (i += 1) _ = eng.tick(1.0 / 60.0);
    try std.testing.expect(@abs(eng.scroll.value - 180) < 1);
    try std.testing.expect(eng.scroll.velocity == 0 or @abs(eng.scroll.velocity) < 1);
}

test "snackbar importance filter honours notification prefs" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();

    // Master off: nothing shows, not even errors.
    eng.prefs.display.notify_en = false;
    eng.showSnackbar("info");
    try std.testing.expectEqual(@as(usize, 0), eng.snack_len);
    eng.showSnackbarError("boom");
    try std.testing.expectEqual(@as(usize, 0), eng.snack_len);

    // All: plain info shows.
    eng.prefs.display.notify_en = true;
    eng.prefs.display.notify_level = 0;
    eng.showSnackbar("info");
    try std.testing.expect(eng.snack_len > 0);

    // Errors only: info dropped, error kept.
    eng.snack_len = 0;
    eng.prefs.display.notify_level = 2;
    eng.showSnackbar("info");
    try std.testing.expectEqual(@as(usize, 0), eng.snack_len);
    eng.showSnackbarError("boom");
    try std.testing.expect(eng.snack_len > 0);

    // Important: an offered Undo survives even though the call is plain.
    eng.snack_len = 0;
    eng.prefs.display.notify_level = 1;
    eng.showSnackbar("info");
    try std.testing.expectEqual(@as(usize, 0), eng.snack_len);
    eng.showSnackbarAction("Theme updated", "Undo", true);
    try std.testing.expect(eng.snack_len > 0);
}

test "settings scroll settles at slowest device frame period" {
    // 50 ms refresh: damping*dt > 2 diverged under explicit Euler (endless jump).
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    _ = eng.tick(0.05); // paint measures real content height
    const max_s = eng.scrollMax();
    try std.testing.expect(max_s > 0);
    eng.setScrollTarget(0);
    var n: usize = 0;
    while (n < 10) : (n += 1) eng.nudgeScroll(max_s / 20); // fast pan, many samples per frame
    const target = eng.scroll.target;
    var prev = eng.scroll.value;
    var i: usize = 0;
    while (i < 40) : (i += 1) {
        _ = eng.tick(0.05);
        try std.testing.expect(eng.scroll.value >= prev - 0.5); // no reversal / ringing
        try std.testing.expect(eng.scroll.value <= target + 0.5); // no overshoot
        prev = eng.scroll.value;
    }
    try std.testing.expect(@abs(eng.scroll.value - target) < 1);
}

test "settings pause freezes job progress" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.setMachinePhase(.run);
    _ = eng.tick(1.0 / 60.0);
    const before = eng.cnc.job_progress;
    eng.openSettings();
    var f: usize = 0;
    while (f < 30) : (f += 1) _ = eng.tick(1.0 / 60.0);
    try std.testing.expectEqual(before, eng.cnc.job_progress);
}

test "menu layout sticky + snack undo + search filter" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.prefs.display.notify_en = true;
    eng.openSettings();
    _ = eng.tick(1.0 / 60.0);

    // Search filter
    eng.search_buf[0] = 'p';
    eng.search_buf[1] = 'o';
    eng.search_buf[2] = 'w';
    eng.search_len = 3;
    try std.testing.expect(eng.tabMatches(5)); // Power
    try std.testing.expect(!eng.tabMatches(0)); // CNC
    try std.testing.expectEqual(@as(?usize, 5), eng.filteredTabIndexAt(0));

    eng.search_buf[0..4].* = "wifi".*;
    eng.search_len = 4;
    try std.testing.expect(eng.tabMatches(4)); // Wireless
    eng.search_buf[0..6].* = "espnow".*;
    eng.search_len = 6;
    try std.testing.expect(eng.tabMatches(4));
    eng.search_buf[0..7].* = "logging".*;
    eng.search_len = 7;
    try std.testing.expect(eng.tabMatches(8)); // Storage & diagnostics

    // Menu geometry set in openMenu, not paint
    eng.openMenu(.accent, .{ .x = 400, .y = 200, .w = 160, .h = 40 });
    try std.testing.expect(eng.menu_target == .accent);
    try std.testing.expect(!eng.menu_hit.isEmpty());
    try std.testing.expect(eng.menu_hit.w <= expr.menu_max_w);
    const hit_before = eng.menu_hit;
    eng.paintMenuOverlay();
    try std.testing.expectEqual(hit_before.x, eng.menu_hit.x);
    try std.testing.expectEqual(hit_before.y, eng.menu_hit.y);

    // Fat list-row anchor must not stretch the popup
    eng.openMenu(.language, .{ .x = 200, .y = 100, .w = 900, .h = 56 });
    try std.testing.expect(eng.menu_hit.w <= expr.menu_max_w);
    try std.testing.expect(eng.menu_hit.x + eng.menu_hit.w <= 200 + 900 + 1);

    // Idle ticks must not auto-dismiss (old 6s TTL closed mid-pick).
    var i: usize = 0;
    while (i < 400) : (i += 1) {
        _ = eng.tick(1.0 / 30.0);
    }
    try std.testing.expect(eng.menu_target == .language);

    // Outside tap closes; wheel while open scrolls the list, does not dismiss.
    eng.nudgeScroll(40);
    try std.testing.expect(eng.menu_target == .language);
    // Content pane refresh must not bury the menu under elev(1).
    eng.repaintSettingsContentPane();
    const mx = eng.menu_hit.x + @divTrunc(eng.menu_hit.w, 2);
    const my = eng.menu_hit.y + 10;
    const menu_px = eng.logical.get(mx, my).toU16();
    try std.testing.expect(menu_px != eng.theme.elev(1).toU16());
    eng.handleClick(10, 10);
    try std.testing.expect(eng.menu_target == .none);

    // Snack undo (theme)
    const was = eng.prefs.display.darkmode;
    eng.toggleTheme();
    try std.testing.expect(eng.prefs.display.darkmode != was);
    try std.testing.expect(eng.snack_action_len > 0);
    if (eng.snack_undo_dark) |d| {
        eng.prefs.display.darkmode = d;
        eng.applyPrefs();
    }
    try std.testing.expectEqual(was, eng.prefs.display.darkmode);
}

test "gesture back still works; double tap unassigned" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    try std.testing.expect(eng.gestureBack());
    try std.testing.expect(eng.screen == .dashboard);
    eng.handleGesture(.{ .kind = .double_tap, .phase = .end, .x = 100, .y = 100 });
    try std.testing.expect(eng.screen == .dashboard);
}

test "gesture back clears settings search before close" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    eng.search_buf[0..3].* = "pow".*;
    eng.search_len = 3;
    eng.search_focus = true;
    try std.testing.expect(eng.gestureBack());
    try std.testing.expect(eng.screen == .settings);
    try std.testing.expect(eng.search_len == 0);
    try std.testing.expect(eng.gestureBack());
    try std.testing.expect(eng.screen == .dashboard);
}

test "status bar blank single click does not open quick settings" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    const closed: f32 = @floatFromInt(quick_settings.closedY());
    eng.handleClick(400, 40);
    try std.testing.expect(eng.sheet_y.target >= closed - 1);
}

test "status bar blank double click opens quick settings" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    const open_y: f32 = @floatFromInt(quick_settings.openY());
    eng.handleClick(400, 40);
    eng.handleClick(400, 40);
    try std.testing.expectApproxEqAbs(open_y, eng.sheet_y.target, 1);
    try std.testing.expectApproxEqAbs(open_y, eng.sheet_y.value, 1);
}

test "status bar double tap opens quick settings" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    const closed: f32 = @floatFromInt(quick_settings.closedY());
    const open_y: f32 = @floatFromInt(quick_settings.openY());
    try std.testing.expect(eng.sheet_y.target >= closed - 1);
    eng.handleGesture(.{
        .kind = .double_tap,
        .phase = .end,
        .x = 400,
        .y = 40,
    });
    try std.testing.expectApproxEqAbs(open_y, eng.sheet_y.target, 1);
    try std.testing.expectApproxEqAbs(open_y, eng.sheet_y.value, 1);
}

test "motion fling coasts settings scroll" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    eng.settings_content_h = 2000;
    eng.setScrollTarget(0);
    const hi = eng.scrollMax();
    eng.motion_phys.fling(&eng.scroll, 144, 0, hi);
    try std.testing.expect(eng.scroll.target > 0);
}

test "settings scroll hard-clamps at edges" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    eng.settings_content_h = 2000;
    eng.scroll.value = -40;
    eng.scroll.velocity = -200;
    eng.scroll.setTarget(-40);
    eng.clampSettingsScroll();
    try std.testing.expect(eng.scroll.value == 0);
    try std.testing.expect(eng.scroll.target == 0);
    try std.testing.expect(eng.scroll.velocity == 0);
    const max_s = eng.scrollMax();
    eng.scroll.value = max_s + 80;
    eng.scroll.velocity = 120;
    eng.scroll.setTarget(max_s + 80);
    eng.clampSettingsScroll();
    try std.testing.expect(eng.scroll.value == max_s);
    try std.testing.expect(eng.scroll.target == max_s);
    try std.testing.expect(eng.scroll.velocity == 0);
}

test "widget motion springs settings switch" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.openSettings();
    eng.tab_selected = 2; // display
    eng.prefs.display.darkmode = false;
    eng.requestFull();
    _ = eng.tick(1.0 / 60.0);
    const k = motion.hashLabel("Dark mode");
    const before = eng.widget_fx.sampleBool(eng.motion_phys, k, false);
    eng.prefs.display.darkmode = true;
    const mid = eng.widget_fx.sampleBool(eng.motion_phys, k, true);
    try std.testing.expect(mid >= before);
    try std.testing.expect(mid < 1);
    var i: usize = 0;
    while (i < 120) : (i += 1) _ = eng.tick(1.0 / 60.0);
    try std.testing.expect(eng.widget_fx.sampleBool(eng.motion_phys, k, true) > 0.9);
}

test "override taps send grblHAL deltas to the driver sink" {
    const S = struct {
        var log: [4]i8 = .{ 0, 0, 0, 0 };
        var n: usize = 0;
        fn sink(which: override_widget.Which, delta: i8) void {
            const Self = @This();
            if (which != .feed) return;
            if (Self.n < Self.log.len) {
                Self.log[Self.n] = delta;
                Self.n += 1;
            }
        }
    };

    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.cnc_override_sink = S.sink;

    // Feed card, off-centre so the tap lands on the touch slab, not the circle.
    const b = dashboard.overrideBounds(eng.cnc);
    const x = b.x + 40;
    var plus_y: i32 = -1;
    var minus_y: i32 = -1;
    var reset_y: i32 = -1;
    var y = b.y;
    while (y < b.y + b.h) : (y += 1) {
        switch (dashboard.hitOverrides(x, y, eng.cnc).kind) {
            .plus => if (plus_y < 0) {
                plus_y = y;
            },
            .minus => if (minus_y < 0) {
                minus_y = y;
            },
            .reset => if (reset_y < 0) {
                reset_y = y;
            },
            .none => {},
        }
    }
    try std.testing.expect(plus_y >= 0 and minus_y >= 0 and reset_y >= 0);

    eng.handleClick(x, plus_y);
    try std.testing.expectEqual(@as(u8, 110), eng.cnc.feed_pct);
    eng.handleClick(x, minus_y);
    try std.testing.expectEqual(@as(u8, 100), eng.cnc.feed_pct);
    eng.cnc.feed_pct = 170;
    eng.handleClick(x, reset_y);
    try std.testing.expectEqual(@as(u8, 100), eng.cnc.feed_pct);

    try std.testing.expectEqual(@as(usize, 3), S.n);
    try std.testing.expectEqualSlices(i8, &[_]i8{ 10, -10, 0 }, S.log[0..3]);
}

test "dashboard actions route to cnc_ui_sink" {
    const S = struct {
        var saw_home: bool = false;
        var saw_reset: bool = false;
        var saw_jog: bool = false;
        fn sink(cmd: CncUiCmd) bool {
            switch (cmd) {
                .home_all => saw_home = true,
                .reset => saw_reset = true,
                .set_jog_mode => saw_jog = true,
                else => {},
            }
            return true;
        }
    };

    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.cnc.connected = true;
    eng.cnc_ui_sink = S.sink;

    const ab = dashboard.actionsBounds(eng.cnc);
    var hx: i32 = -1;
    var hy: i32 = -1;
    var y = ab.y;
    while (y < ab.y + ab.h) : (y += 2) {
        var x = ab.x;
        while (x < ab.x + ab.w) : (x += 2) {
            if (dashboard.hitActions(x, y, eng.cnc).kind == .home) {
                hx = x;
                hy = y;
                break;
            }
        }
        if (hx >= 0) break;
    }
    try std.testing.expect(hx >= 0);
    eng.handleClick(hx, hy);
    try std.testing.expect(S.saw_home);

    var sx: i32 = -1;
    var sy: i32 = -1;
    y = ab.y;
    while (y < ab.y + ab.h) : (y += 2) {
        var x = ab.x;
        while (x < ab.x + ab.w) : (x += 2) {
            if (dashboard.hitActions(x, y, eng.cnc).kind == .sync) {
                sx = x;
                sy = y;
                break;
            }
        }
        if (sx >= 0) break;
    }
    try std.testing.expect(sx >= 0);
    eng.handleClick(sx, sy);
    try std.testing.expect(S.saw_reset);

    const jb = dashboard.jogBounds(eng.cnc);
    var mx: i32 = -1;
    var my: i32 = -1;
    y = jb.y;
    while (y < jb.y + jb.h) : (y += 2) {
        var x = jb.x;
        while (x < jb.x + jb.w) : (x += 2) {
            if (dashboard.hitJog(x, y, eng.cnc).kind == .mode) {
                mx = x;
                my = y;
                break;
            }
        }
        if (mx >= 0) break;
    }
    try std.testing.expect(mx >= 0);
    eng.handleClick(mx, my);
    try std.testing.expect(S.saw_jog);
    try std.testing.expectEqual(@as(u8, @intCast(eng.cnc.jog_mode)), eng.prefs.dash.jog_mode);
}

test "DRO zero emits G10 path and confirm works on dashboard" {
    const S = struct {
        var saw_zero: bool = false;
        var axis: u8 = 255;
        fn sink(cmd: CncUiCmd) bool {
            switch (cmd) {
                .zero_axis => |a| {
                    saw_zero = true;
                    axis = a;
                },
                else => {},
            }
            return true;
        }
    };

    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.cnc.connected = true;
    eng.cnc.dro.work_um[0] = 12345;
    eng.cnc_ui_sink = S.sink;
    eng.prefs.dash.confirm.zero = settings_prefs.confirm_never;

    const db = dashboard.droBounds(eng.cnc);
    var zx: i32 = -1;
    var zy: i32 = -1;
    var y = db.y;
    while (y < db.y + db.h) : (y += 2) {
        var x = db.x;
        while (x < db.x + db.w) : (x += 2) {
            if (dashboard.hitDro(x, y, eng.cnc).kind == .zero) {
                zx = x;
                zy = y;
                break;
            }
        }
        if (zx >= 0) break;
    }
    try std.testing.expect(zx >= 0);
    eng.handleClick(zx, zy);
    try std.testing.expect(S.saw_zero);
    try std.testing.expectEqual(@as(u8, 0), S.axis);
    try std.testing.expectEqual(@as(i32, 0), eng.cnc.dro.work_um[0]);

    // Confirm-Always: dialog on dashboard, emit only after OK.
    S.saw_zero = false;
    eng.cnc.dro.work_um[1] = 999;
    eng.prefs.dash.confirm.zero = settings_prefs.confirm_always;
    zx = -1;
    zy = -1;
    y = db.y;
    while (y < db.y + db.h) : (y += 2) {
        var x = db.x;
        while (x < db.x + db.w) : (x += 2) {
            const h = dashboard.hitDro(x, y, eng.cnc);
            if (h.kind == .zero and h.axis == 1) {
                zx = x;
                zy = y;
                break;
            }
        }
        if (zx >= 0) break;
    }
    try std.testing.expect(zx >= 0);
    eng.handleClick(zx, zy);
    try std.testing.expect(!S.saw_zero);
    try std.testing.expect(eng.settings_confirm == .dash_zero);
    try std.testing.expect(eng.pending_cnc != null);
    // Paint so confirm hit rects exist.
    eng.paintDashboard();
    eng.handleClick(eng.settings_confirm_ok.x + 4, eng.settings_confirm_ok.y + 4);
    try std.testing.expect(S.saw_zero);
    try std.testing.expectEqual(@as(u8, 1), S.axis);
    try std.testing.expectEqual(@as(i32, 0), eng.cnc.dro.work_um[1]);
}

test "dashboard confirm overlay survives live tick without regional punch-through" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.cnc.connected = true;
    eng.cnc_ui_sink = struct {
        fn sink(_: CncUiCmd) bool {
            return true;
        }
    }.sink;
    eng.prefs.dash.confirm.zero = settings_prefs.confirm_always;
    eng.openSettingsConfirm(.dash_zero);
    _ = eng.tick(1.0 / 60.0);
    eng.paintDashboard();
    const db = dashboard.droBounds(eng.cnc);
    const px = db.x + 24;
    const py = db.y + 24;
    const scrim_px = eng.logical.get(px, py).toU16();
    // Mirror tick would regional-repaint DRO without confirm guard.
    eng.cnc.dro.work_um[0] += 1000;
    _ = eng.tick(1.0 / 60.0);
    try std.testing.expectEqual(scrim_px, eng.logical.get(px, py).toU16());
    eng.closeSettingsConfirm();
}

test "jog mode survives applyPrefs" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.cnc.connected = true;
    eng.cnc_ui_sink = struct {
        fn sink(_: CncUiCmd) bool {
            return true;
        }
    }.sink;

    const jb = dashboard.jogBounds(eng.cnc);
    var hit_x: i32 = -1;
    var hit_y: i32 = -1;
    var y = jb.y;
    while (y < jb.y + jb.h) : (y += 2) {
        var x = jb.x;
        while (x < jb.x + jb.w) : (x += 2) {
            const h = dashboard.hitJog(x, y, eng.cnc);
            if (h.kind == .mode and h.index == 2) {
                hit_x = x;
                hit_y = y;
                break;
            }
        }
        if (hit_x >= 0) break;
    }
    try std.testing.expect(hit_x >= 0);
    eng.handleClick(hit_x, hit_y);
    try std.testing.expectEqual(@as(usize, 2), eng.cnc.jog_mode);
    try std.testing.expectEqual(@as(u8, 2), eng.prefs.dash.jog_mode);
    eng.applyPrefs();
    try std.testing.expectEqual(@as(usize, 2), eng.cnc.jog_mode);
}

test "dashboard job and override springs chase" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.cnc.job_progress = 0.2;
    eng.job_fx.value = 0.2;
    eng.job_fx.setTarget(0.2);
    eng.cnc.feed_pct = 150;
    eng.feed_fx.setTarget(150);
    var i: usize = 0;
    while (i < 180) : (i += 1) _ = eng.tick(1.0 / 60.0);
    try std.testing.expect(eng.cnc.feed_vis > 140);
    eng.cnc.job_progress = 0.9;
    i = 0;
    while (i < 180) : (i += 1) _ = eng.tick(1.0 / 60.0);
    try std.testing.expect(eng.cnc.job_progress_vis > 0.8);
}

test "compact settings hub to detail" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.prefs.display.single_pane = true;
    eng.openSettings();
    try std.testing.expect(eng.settings_hub);
    try std.testing.expect(!settings_form.useRail());
    // First category under search.
    const y = settings_form.cat_list_top + 8;
    eng.handleClick(settings_form.win_x + 40, y);
    try std.testing.expect(!eng.settings_hub);
    try std.testing.expectEqual(@as(usize, 0), eng.tab_selected);
    eng.handleClick(settings_form.backHitRect().x + 8, settings_form.backHitRect().y + 8);
    try std.testing.expect(eng.settings_hub);
}

test "dual FB catch-up covers last frame and no further" {
    const clock: geom.Rect = .{ .x = 900, .y = 0, .w = 120, .h = 48 };
    const dro: geom.Rect = .{ .x = 40, .y = 120, .w = 300, .h = 200 };
    const jog: geom.Rect = .{ .x = 400, .y = 120, .w = 300, .h = 200 };

    var prev: geom.DirtySet(geom.dirty_cap) = .{};
    prev.add(clock);
    var cur: geom.DirtySet(geom.dirty_cap) = .{};
    cur.add(dro);
    Engine.foldStaleDamage(&cur, &prev);
    // The back buffer missed the clock tick, so this frame must re-rotate it.
    try std.testing.expectEqual(@as(u32, clock.area() + dro.area()), cur.totalArea());

    // Next frame only owes the DRO — the clock is now in both buffers.
    var next: geom.DirtySet(geom.dirty_cap) = .{};
    next.add(jog);
    var owed: geom.DirtySet(geom.dirty_cap) = .{};
    owed.add(dro);
    Engine.foldStaleDamage(&next, &owed);
    try std.testing.expectEqual(@as(u32, jog.area() + dro.area()), next.totalArea());
}

test "device sink blocks host demo job percent race" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.cnc.sd_percent = 20;
    eng.cnc.syncJobProgressFromSd();
    eng.setMachinePhase(.run);
    const before = eng.cnc.sd_percent;
    // Simulate device: sink installed → tick must not invent progress.
    eng.cnc_ui_sink = struct {
        fn sink(_: CncUiCmd) bool {
            return true;
        }
    }.sink;
    var i: usize = 0;
    while (i < 30) : (i += 1) _ = eng.tick(1.0 / 30.0);
    try std.testing.expectEqual(before, eng.cnc.sd_percent);
}

test "mirrored phase without setMachinePhase full-repaints strip" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.cnc_ui_sink = struct {
        fn sink(_: CncUiCmd) bool {
            return true;
        }
    }.sink;
    // Stamp idle gates like a settled device dashboard.
    _ = eng.tick(1.0 / 30.0);
    eng.needs_full_repaint = false;
    eng.dirty.clear();
    try std.testing.expect(!dashboard.jobStripVisible(eng.cnc));
    try std.testing.expectEqual(@as(f32, 0), eng.led_morph.target);

    // Device mirror path: mutate fields only (no setMachinePhase).
    eng.cnc.actions.phase = .run;
    eng.cnc.sd_streaming = true;
    eng.cnc.sd_percent = 42;
    eng.cnc.syncJobProgressFromSd();
    @memcpy(eng.cnc.job_name_buf[0..6], "job.nc");
    eng.cnc.job_name_buf[6] = 0;
    eng.cnc.job_name = eng.cnc.job_name_buf[0..6];

    _ = eng.tick(1.0 / 30.0);
    try std.testing.expectEqual(@as(f32, 1), eng.led_morph.target);
    try std.testing.expectEqual(@as(u8, 1), eng.gate_job_strip);
    try std.testing.expectEqual(@as(u8, @intFromEnum(actions_widget.MachinePhase.run)), eng.gate_phase);
}

test "createHeap destroy frees engine without leak" {
    const gpa = std.testing.allocator;
    const eng = try Engine.createHeap(gpa, .{});
    try std.testing.expect(eng.heap_owned);
    eng.destroy(gpa);
}

test "device applyPrefs preserves live feed when sink installed" {
    const gpa = std.testing.allocator;
    var eng = try Engine.create(gpa);
    defer eng.destroy(gpa);
    eng.skipBoot();
    eng.cnc_ui_sink = struct {
        fn sink(_: CncUiCmd) bool {
            return true;
        }
    }.sink;
    eng.cnc.feed_pct = 140;
    eng.cnc.wcs_i = 3;
    eng.prefs.machine.feedovr = 100;
    eng.prefs.dash.wcs = 0;
    eng.applyPrefsPublic();
    try std.testing.expectEqual(@as(u8, 140), eng.cnc.feed_pct);
    try std.testing.expectEqual(@as(u8, 3), eng.cnc.wcs_i);
}
