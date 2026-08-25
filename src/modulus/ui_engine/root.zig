//! Host-first Modulus UI engine (no LVGL, no firmware).
//! Prove MD3 tokens + dirty paint + rotate-on-write + springs before Tab5 port.

const builtin = @import("builtin");

pub const color = @import("color.zig");
pub const geom = @import("geom.zig");
pub const tokens = @import("tokens.zig");
pub const spring = @import("spring.zig");
pub const fb = @import("fb.zig");
pub const font = @import("font.zig");
pub const font_noto = @import("font_noto.zig");
pub const widgets = @import("widgets.zig");
pub const dashboard = @import("dashboard.zig");
pub const dro_widget = @import("dro_widget.zig");
pub const jog_widget = @import("jog_widget.zig");
pub const override_widget = @import("override_widget.zig");
pub const actions_widget = @import("actions_widget.zig");
pub const job_progress_widget = @import("job_progress_widget.zig");
pub const settings_prefs = @import("settings_prefs.zig");
pub const settings_form = @import("settings_form.zig");
pub const settings_dashboard_tab = @import("settings_dashboard_tab.zig");
pub const settings_display_tab = @import("settings_display_tab.zig");
pub const settings_other_tabs = @import("settings_other_tabs.zig");
pub const settings_cnc_modals = @import("settings_cnc_modals.zig");
pub const settings_dashboard_modals = @import("settings_dashboard_modals.zig");
pub const settings_extra_modals = @import("settings_extra_modals.zig");
pub const settings_pin_modal = @import("settings_pin_modal.zig");
pub const settings_mach_string_modal = @import("settings_mach_string_modal.zig");
pub const settings_menu = @import("settings_menu.zig");
pub const widgets_expressive = @import("widgets_expressive.zig");
pub const hct = @import("hct.zig");
pub const palette = @import("palette.zig");
pub const md3_catalog = @import("md3_catalog.zig");
pub const icons_phosphor = @import("icons_phosphor.zig");
pub const battery_chrome = @import("battery_chrome.zig");
pub const flush_shim = @import("flush_shim.zig");
pub const input_pad = @import("input_pad.zig");
pub const gestures = @import("gestures.zig");
pub const motion = @import("motion.zig");
pub const engine = @import("engine.zig");
pub const quick_settings = @import("quick_settings.zig");
pub const zb_purpose = @import("zb_purpose.zig");
pub const ui_lint = @import("ui_lint.zig");
pub const host_win32 = if (builtin.os.tag == .windows) @import("host_win32.zig") else struct {
    pub const Input = struct {
        quit: bool = false,
        wheel_y: i32 = 0,
        click_x: i32 = -1,
        click_y: i32 = -1,
        drag_active: bool = false,
        drag_x: i32 = -1,
        drag_y: i32 = -1,
        pointer_up: bool = false,
        key_space: bool = false,
        key_theme: bool = false,
        key_dialog: bool = false,
        key_pin: bool = false,
        key_catalog: bool = false,
        key_tab: bool = false,
        key_shift_tab: bool = false,
        key_enter: bool = false,
        chars: [8]u8 = .{0} ** 8,
        chars_len: usize = 0,
        key_backspace: bool = false,
        hover_x: i32 = -1,
        hover_y: i32 = -1,
    };
    pub fn sleepMs(_: u32) void {}
    pub const View = struct {
        pub fn open(_: []const u8) !View {
            return error.WindowUnsupported;
        }
        pub fn close(_: *View) void {}
        pub fn poll(_: *View, _: *Input) void {}
        pub fn present(_: *View, _: []const color.Rgb565) void {}
        pub fn presentDirty(_: *View, _: []const color.Rgb565, _: []const geom.Rect, _: bool) u32 {
            return 0;
        }
    };
};

test {
    _ = color;
    _ = geom;
    _ = tokens;
    _ = spring;
    _ = fb;
    _ = font;
    _ = font_noto;
    _ = widgets;
    _ = dashboard;
    _ = dro_widget;
    _ = jog_widget;
    _ = override_widget;
    _ = actions_widget;
    _ = job_progress_widget;
    _ = settings_prefs;
    _ = settings_form;
    _ = settings_dashboard_tab;
    _ = settings_display_tab;
    _ = settings_other_tabs;
    _ = settings_cnc_modals;
    _ = settings_dashboard_modals;
    _ = settings_pin_modal;
    _ = settings_mach_string_modal;
    _ = settings_menu;
    _ = widgets_expressive;
    _ = hct;
    _ = palette;
    _ = md3_catalog;
    _ = icons_phosphor;
    _ = battery_chrome;
    _ = flush_shim;
    _ = input_pad;
    _ = gestures;
    _ = motion;
    _ = engine;
    _ = quick_settings;
    _ = zb_purpose;
    _ = ui_lint;
    _ = host_win32;
}
