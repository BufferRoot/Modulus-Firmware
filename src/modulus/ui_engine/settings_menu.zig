//! Settings dropdown menu — open/select instead of tap-cycle.
//! ponytail: static option tables; engine paints overlay.

const std = @import("std");
const prefs_mod = @import("settings_prefs.zig");

pub const Target = enum {
    none,
    accent,
    proto,
    conn,
    wcs,
    confirm_cycle,
    confirm_spin,
    confirm_zero,
    confirm_home,
    confirm_mac,
    jogspd,
    dim,
    language,
    timezone,
    mach_type,
    mnt_odo,
    mnt_sph,
    mnt_run,
    mnt_warn,
    pwr_scr,
    pwr_dsto,
    pwr_wtmin,
    pwr_bat_type,
    pwr_warn,
    sec_tmo,
    sec_idle_tmo,
    en_chan,
    en_rate,
    ser_baud,
    r4_baud,
    can_brate,
};

const confirm_labels = [_][]const u8{ "Never", "Always", "When running" };
const can_brate_labels = [_][]const u8{ "125K", "250K", "500K", "1M" };

pub fn labels(target: Target) []const []const u8 {
    return switch (target) {
        .none => &.{},
        .accent => &prefs_mod.DisplayPrefs.accent_names,
        .proto => &prefs_mod.proto_names,
        .conn => &prefs_mod.transport_names,
        .wcs => &.{ "G54", "G55", "G56", "G57", "G58", "G59" },
        .confirm_cycle, .confirm_spin, .confirm_zero, .confirm_home, .confirm_mac => &confirm_labels,
        .jogspd => &prefs_mod.DashboardPrefs.jogspd_labels,
        .dim => &prefs_mod.PowerPrefs.dim_labels,
        .language => &.{ "English", "Spanish", "German", "French", "Chinese" },
        .timezone => &prefs_mod.SystemPrefs.tz_labels,
        .mach_type => &prefs_mod.mach_type_names,
        .mnt_odo => &prefs_mod.MachinePrefs.mnt_odo_labels,
        .mnt_sph, .mnt_run => &prefs_mod.MachinePrefs.mnt_hours_labels,
        .mnt_warn => &prefs_mod.MachinePrefs.mnt_warn_labels,
        .pwr_scr => &prefs_mod.PowerPrefs.scr_labels,
        .pwr_dsto => &prefs_mod.PowerPrefs.dsto_labels,
        .pwr_wtmin => &prefs_mod.PowerPrefs.wtmin_labels,
        .pwr_bat_type => &prefs_mod.PowerPrefs.bat_type_labels,
        .pwr_warn => &prefs_mod.PowerPrefs.warn_labels,
        .sec_tmo => &prefs_mod.SecurityPrefs.tmo_labels,
        .sec_idle_tmo => &prefs_mod.SecurityPrefs.idle_tmo_labels,
        .en_chan => &prefs_mod.WirelessPrefs.chan_labels,
        .en_rate => &prefs_mod.WirelessPrefs.rate_labels,
        .ser_baud, .r4_baud => &prefs_mod.baud_labels,
        .can_brate => &can_brate_labels,
    };
}

pub fn selectedIndex(prefs: *const prefs_mod.Prefs, target: Target) usize {
    return switch (target) {
        .none => 0,
        .accent => prefs.display.accent,
        .proto => prefs.cnc.proto,
        .conn => prefs.cnc.conn,
        .wcs => prefs.dash.wcs,
        .confirm_cycle => prefs.dash.confirm.cycle,
        .confirm_spin => prefs.dash.confirm.spin,
        .confirm_zero => prefs.dash.confirm.zero,
        .confirm_home => prefs.dash.confirm.home,
        .confirm_mac => prefs.dash.confirm.mac,
        .jogspd => prefs.dash.jogspd_idx,
        .dim => prefs.power.dim_idx,
        .language => prefs.system.lang,
        .timezone => prefs.system.tz_idx,
        .mach_type => prefs.machine.mach_type,
        .mnt_odo => prefs.machine.mnt_odo_idx,
        .mnt_sph => prefs.machine.mnt_sph_idx,
        .mnt_run => prefs.machine.mnt_run_idx,
        .mnt_warn => prefs.machine.mnt_warn_idx,
        .pwr_scr => prefs.power.scr_idx,
        .pwr_dsto => prefs.power.dsto_idx,
        .pwr_wtmin => prefs.power.wtmin_idx,
        .pwr_bat_type => prefs.power.bat_type,
        .pwr_warn => prefs.power.bat_warn_idx,
        .sec_tmo => prefs.security.pin_tmo_idx,
        .sec_idle_tmo => prefs.security.pin_idle_tmo_idx,
        .en_chan => if (prefs.wireless.en_chan == 0) 0 else prefs.wireless.en_chan - 1,
        .en_rate => prefs.wireless.en_rate,
        .ser_baud => prefs.cnc.ser_baud_idx,
        .r4_baud => prefs.cnc.r4_baud_idx,
        .can_brate => prefs.cnc.can_brate,
    };
}

pub fn apply(prefs: *prefs_mod.Prefs, target: Target, index: usize) void {
    const labs = labels(target);
    if (labs.len == 0) return;
    const i: u8 = @intCast(@min(index, labs.len - 1));
    switch (target) {
        .none => {},
        .accent => prefs.display.accent = i,
        .proto => {
            prefs.cnc.proto = i;
            prefs.cnc.applyPreferredTransport();
            prefs.cnc.session_phase = 1;
            prefs.cnc.session_up = false;
            prefs.cnc.connect_hold_frames = 90;
        },
        .conn => {
            prefs.cnc.conn = i;
            prefs.cnc.transport_off = false;
            prefs.cnc.session_phase = 1;
            prefs.cnc.session_up = false;
            prefs.cnc.connect_hold_frames = 90;
        },
        .wcs => prefs.dash.wcs = i,
        .confirm_cycle => prefs.dash.confirm.cycle = i,
        .confirm_spin => prefs.dash.confirm.spin = i,
        .confirm_zero => prefs.dash.confirm.zero = i,
        .confirm_home => prefs.dash.confirm.home = i,
        .confirm_mac => prefs.dash.confirm.mac = i,
        .jogspd => {
            prefs.dash.jogspd_idx = i;
            prefs.machine.jogspd = prefs_mod.DashboardPrefs.jogspdMmAt(i);
        },
        .dim => prefs.power.dim_idx = i,
        .language => prefs.system.lang = i,
        .timezone => prefs.system.tz_idx = i,
        .mach_type => prefs.machine.mach_type = i,
        .mnt_odo => prefs.machine.mnt_odo_idx = i,
        .mnt_sph => prefs.machine.mnt_sph_idx = i,
        .mnt_run => prefs.machine.mnt_run_idx = i,
        .mnt_warn => prefs.machine.mnt_warn_idx = i,
        .pwr_scr => prefs.power.scr_idx = i,
        .pwr_dsto => prefs.power.dsto_idx = i,
        .pwr_wtmin => prefs.power.wtmin_idx = i,
        .pwr_bat_type => prefs.power.bat_type = i,
        .pwr_warn => prefs.power.bat_warn_idx = i,
        .sec_tmo => prefs.security.applyTmoIdx(i),
        .sec_idle_tmo => prefs.security.applyIdleTmoIdx(i),
        .en_chan => prefs.wireless.en_chan = i + 1,
        .en_rate => prefs.wireless.en_rate = i,
        .ser_baud => prefs.cnc.ser_baud_idx = i,
        .r4_baud => prefs.cnc.r4_baud_idx = i,
        .can_brate => prefs.cnc.can_brate = i,
    }
}

pub fn targetForDisplayHit(hit: @import("settings_display_tab.zig").Hit) Target {
    return if (hit == .accent) .accent else .none;
}

pub fn targetForOtherHit(hit: @import("settings_other_tabs.zig").Hit) Target {
    return switch (hit) {
        .cnc_proto => .proto,
        .cnc_conn => .conn,
        .pwr_dim => .dim,
        .pwr_scr => .pwr_scr,
        .pwr_dsto => .pwr_dsto,
        .pwr_wtmin => .pwr_wtmin,
        .pwr_bat_type => .pwr_bat_type,
        .pwr_warn => .pwr_warn,
        .sys_lang => .none, // English-only chrome until i18n ships
        .sys_tz => .timezone,
        .mach_type => .mach_type,
        .mach_mnt_odo => .mnt_odo,
        .mach_mnt_sph => .mnt_sph,
        .mach_mnt_run => .mnt_run,
        .mach_mnt_warn => .mnt_warn,
        .sec_tmo => .sec_tmo,
        .wl_en_chan => .en_chan,
        .wl_en_rate => .en_rate,
        else => .none,
    };
}

pub fn targetForDashHit(hit: @import("settings_dashboard_tab.zig").Hit) Target {
    return switch (hit) {
        .wcs => .wcs,
        .jogspd => .jogspd,
        .cnf_cycle => .confirm_cycle,
        .cnf_spin => .confirm_spin,
        .cnf_zero => .confirm_zero,
        .cnf_home => .confirm_home,
        .cnf_mac => .confirm_mac,
        else => .none,
    };
}

test "menu apply accent and dim" {
    var prefs: prefs_mod.Prefs = .{};
    apply(&prefs, .accent, 3);
    try std.testing.expectEqual(@as(u8, 3), prefs.display.accent);
    apply(&prefs, .dim, 2);
    try std.testing.expectEqual(@as(u8, 2), prefs.power.dim_idx);
    try std.testing.expect(labels(.accent).len >= 9);
    try std.testing.expectEqual(@as(usize, 3), selectedIndex(&prefs, .accent));
    apply(&prefs, .jogspd, 3);
    try std.testing.expectEqual(@as(u8, 3), prefs.dash.jogspd_idx);
    apply(&prefs, .confirm_zero, 1);
    try std.testing.expectEqual(@as(u8, 1), prefs.dash.confirm.zero);
}
