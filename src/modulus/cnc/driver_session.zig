//! CNC driver poll interval, connect defaults, envelope sync queue.

const std = @import("std");
const cnc_config = @import("cnc_config.zig");
const cnc_state = @import("cnc_state.zig");
const envelope = @import("envelope.zig");
const settings_keys = @import("../core/settings_keys.zig");
const driver_ops = @import("driver_ops.zig");
const gating = @import("driver_gating.zig");

pub fn syncLine(drv: anytype, idx: u8) []const u8 {
    return drv.sync_lines[idx][0..drv.sync_line_lens[idx]];
}

pub fn advanceSyncQueue(drv: anytype) void {
    if (!drv.sync_pending) return;
    if (drv.sync_line_next >= drv.sync_line_count) {
        drv.sync_pending = false;
        return;
    }
    driver_ops.sendGcodeClamped(drv, syncLine(drv, drv.sync_line_next));
    drv.sync_line_next += 1;
    if (drv.sync_line_next >= drv.sync_line_count) drv.sync_pending = false;
}

pub fn onRxProcessed(drv: anytype) void {
    if (drv.settings_dump.complete or drv.settings_dump.failed) {
        drv.engine.setSettingsDump(null);
    }
    if (drv.sync_pending and drv.engine.lastEventIsOk()) {
        advanceSyncQueue(drv);
    }
}

pub fn applyPollInterval(drv: anytype, tick_ms: u32) void {
    if (!drv.poll_interval_loaded or tick_ms -% drv.poll_interval_reload_ms >= 1000) {
        if (drv.store) |s| {
            drv.poll_interval_cached =
                std.math.clamp(s.getU16(settings_keys.cnc_poll, 100), 100, 2000);
        }
        drv.poll_interval_loaded = true;
        drv.poll_interval_reload_ms = tick_ms;
    }
    var ms = drv.poll_interval_cached;
    const st = drv.engine.status().state;
    if (st == .jog or st == .run) ms = @min(ms, 100);
    drv.engine.setPollInterval(ms);
}

fn patchSnapshotDefaults(drv: anytype, wcs: cnc_state.WCS, feed_pct: u8, spind_pct: u8) void {
    gating.lockSnapshot(drv);
    drv.snapshot.wcs = wcs;
    drv.snapshot.overrides.feed = feed_pct;
    drv.snapshot.overrides.spindle = spind_pct;
    gating.unlockSnapshot(drv);
}

pub fn applySessionDefaults(drv: anytype) void {
    if (!drv.apply_defaults_pending) return;
    if (drv.engine.session() != .ready) return;
    if (drv.store) |s| {
        const proto_idx = s.getU8(settings_keys.cnc_proto, cnc_config.k_default_cnc_proto);
        const proto: cnc_config.Protocol = if (proto_idx < @intFromEnum(cnc_config.Protocol._count))
            @enumFromInt(proto_idx)
        else
            .grblhal;
        if (!cnc_config.usesGrblEngine(proto)) return;
        var wcs_idx = s.getU8(settings_keys.cnc_wcs, 0);
        if (wcs_idx >= @intFromEnum(cnc_state.WCS._count)) wcs_idx = 0;
        const wcs: cnc_state.WCS = @enumFromInt(wcs_idx);
        driver_ops.sendGcodeClamped(drv, cnc_state.wcsStr(wcs));
        driver_ops.sendGcodeClamped(drv, if (s.getBool(settings_keys.cnc_unit, true)) "$13=0" else "$13=1");
        drv.reloadLimits();
        const st = drv.engine.status();
        const base_feed = st.feed_rate;
        const base_rpm = @as(f32, @floatFromInt(st.spindle_speed));
        var feed_pct = driver_ops.clampOverridePct(s.getU8(settings_keys.cnc_feedovr, 100));
        var spind_pct = driver_ops.clampOverridePct(s.getU8(settings_keys.cnc_spindovr, 100));
        feed_pct = envelope.clampFeedOverridePct(base_feed, feed_pct, drv.limits.max_feed_rate);
        spind_pct = envelope.clampSpindleOverridePct(base_rpm, spind_pct, drv.limits.max_spindle);
        driver_ops.applyOverridePct(&drv.engine, true, feed_pct);
        driver_ops.applyOverridePct(&drv.engine, false, spind_pct);
        patchSnapshotDefaults(drv, wcs, feed_pct, spind_pct);
    }
    drv.apply_defaults_pending = false;
}
