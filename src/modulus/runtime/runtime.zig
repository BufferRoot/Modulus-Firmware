//! Host/device runtime — owns HAL + CNC instances and boot wiring.

const std = @import("std");
const build_options = @import("build_options");
const boot_mod = @import("../core/boot.zig");
const modulus = @import("../core/modulus.zig");
const event_bus = @import("../core/event_bus.zig");
const settings_store = @import("../core/settings_store.zig");
const driver_mod = @import("../cnc/driver.zig");
const cnc_config = @import("../cnc/cnc_config.zig");
const display_mod = @import("../hal/platform/display.zig");
const audio_mod = @import("../hal/platform/audio.zig");
const battery_mod = @import("../hal/platform/battery.zig");
const power_mod = @import("../hal/platform/power.zig");
const i2c_coex_mod = @import("../hal/platform/i2c_coex.zig");
const ext_encoder_mod = @import("../hal/platform/ext_encoder.zig");
const dispatcher_mod = @import("../hal/transport/dispatcher.zig");
const wireless_mod = @import("../hal/wireless/wireless.zig");
const touch_mod = @import("../hal/platform/touch.zig");
const security_mod = @import("../hal/platform/security.zig");
const imu_mod = @import("../hal/platform/imu.zig");
const i18n_mod = @import("../hal/platform/i18n.zig");
const rtc_mod = @import("../hal/platform/rtc.zig");
const storage_mod = @import("../hal/platform/storage.zig");
const dsp_mod = @import("../hal/platform/dsp.zig");
const settings_dump_mod = @import("../cnc/settings_dump.zig");
const host_io_mod = @import("../core/host_io.zig");
const host_diag_mod = @import("../core/host_diagnostics.zig");
const ota_mod = @import("../firmware/ota.zig");
const hooks = @import("hooks.zig");
const leak_guard = @import("../testing/leak_guard.zig");

pub const Runtime = struct {
    allocator: std.mem.Allocator,
    /// Host: `init.io` from Juicy Main. Device freestanding: always `null`.
    io: ?std.Io = null,
    store: settings_store.Store,
    bus: event_bus.EventBus,
    display: display_mod.Display = .{},
    audio: audio_mod.Audio = .{},
    battery: battery_mod.Battery = .{},
    power: power_mod.Power = .{},
    coex: i2c_coex_mod.I2cCoex = .{},
    drv: driver_mod.Driver = undefined,
    transport: dispatcher_mod.Dispatcher = undefined,
    wireless: wireless_mod.Wireless = .{},
    encoder: ext_encoder_mod.ExtEncoder = undefined,
    touch: touch_mod.Touch = .{},
    security: security_mod.Security = .{},
    imu: imu_mod.Imu = .{},
    i18n: i18n_mod.I18n = .{},
    rtc: rtc_mod.Rtc = .{},
    storage: storage_mod.Storage = .{},
    dsp: dsp_mod.Dsp = .{},
    tick_ms: u32 = 0,
    last_battery_ms: u32 = 0,
    system_task_armed: bool = false,
    transport_ready: bool = false,
    wireless_ready: bool = false,
    encoder_ready: bool = false,

    pub fn init(allocator: std.mem.Allocator, io: ?std.Io) Runtime {
        return .{
            .allocator = allocator,
            .io = io,
            .store = settings_store.Store.init(allocator),
            .bus = event_bus.EventBus.init(),
        };
    }

    pub fn deinit(self: *Runtime) void {
        if (self.transport_ready) self.transport.deinit();
        if (self.encoder_ready) self.encoder.deinit();
        if (self.wireless_ready) self.wireless.deinit();
        self.bus.deinit();
        self.store.deinit();
    }

    pub fn syncPowerHooks(self: *Runtime) void {
        self.power.hooks = hooks.makePowerHooks();
    }

    pub fn boot(self: *Runtime) !void {
        hooks.bind(self);
        var ctx = boot_mod.BootContext{
            .allocator = self.allocator,
            .store = &self.store,
            .bus = &self.bus,
            .hal = hooks.makeHalHooks(),
            .settings_hooks = hooks.makeSettingsOpenHooks(),
            .spawn_system_task = spawnSystemTask,
        };
        try modulus.start(&ctx);
        if (!build_options.device_nvs) {
            self.bus.dispatchAll();
        }
    }

    pub fn systemTick(self: *Runtime, tick_ms: u32) void {
        self.tick_ms = tick_ms;
        self.dsp.process();
        self.drv.poll(tick_ms);
        if (self.transport_ready) {
            const poll_transport = if (build_options.device_nvs) blk: {
                const gate = @import("../firmware/transport_reinit_task.zig");
                break :blk !gate.active.load(.acquire);
            } else true;
            if (poll_transport) self.transport.poll();
        }
        if (self.encoder_ready) self.encoder.poll(tick_ms);
        if (build_options.device_nvs and tick_ms -% self.last_battery_ms >= 2000) {
            // Interval gate — `(tick_ms % 2000) < 10` could skip a whole window
            // (tick jitter) or double-fire within one.
            self.last_battery_ms = tick_ms;
            self.battery.poll();
        }
    }

    pub fn markTransportReady(self: *Runtime) void {
        self.transport_ready = true;
    }

    pub fn markWirelessReady(self: *Runtime) void {
        self.wireless_ready = true;
    }

    pub fn markWirelessNotReady(self: *Runtime) void {
        self.wireless_ready = false;
    }

    pub fn markEncoderReady(self: *Runtime) void {
        self.encoder_ready = true;
    }

    /// Host file I/O — forwards `Runtime.io` into `core/host_io.zig` helpers.
    pub fn hostIo(self: *Runtime) host_io_mod.Error!std.Io {
        return host_io_mod.require(self.io);
    }

    pub fn writeHostTextFile(self: *Runtime, path: []const u8, data: []const u8) host_io_mod.Error!void {
        if (comptime build_options.device_nvs) return error.IoUnavailable;
        const io = try self.hostIo();
        return host_io_mod.writeTextFile(io, path, data);
    }

    pub fn exportSettingsDump(self: *Runtime, path: []const u8, dump: *const settings_dump_mod.SettingsDump) host_io_mod.Error!void {
        if (comptime build_options.device_nvs) return error.IoUnavailable;
        return exportSettingsDumpCold(self, path, dump);
    }

    fn exportSettingsDumpCold(self: *Runtime, path: []const u8, dump: *const settings_dump_mod.SettingsDump) host_io_mod.Error!void {
        @branchHint(.cold);
        return dump.writeHostExport(self.io, path);
    }

    pub fn diagnosticSnapshot(self: *const Runtime) host_diag_mod.Snapshot {
        return .{
            .transport_ready = self.transport_ready,
            .transport_conn = if (self.transport_ready) self.transport.activeConnection() else 0,
            .wireless_ready = self.wireless_ready,
            .system_task_armed = self.system_task_armed,
            .sd_mounted = self.storage.isMounted(),
        };
    }

    pub fn exportHostDiagnostics(self: *Runtime, path: []const u8) host_io_mod.Error!void {
        if (comptime build_options.device_nvs) return error.IoUnavailable;
        return exportHostDiagnosticsCold(self, path);
    }

    fn exportHostDiagnosticsCold(self: *Runtime, path: []const u8) host_io_mod.Error!void {
        @branchHint(.cold);
        const io = try self.hostIo();
        return host_diag_mod.writeFile(io, path, self.diagnosticSnapshot());
    }

    pub fn exportHostDiagnosticsFault(self: *Runtime, path: []const u8, err: anyerror) host_io_mod.Error!void {
        if (comptime build_options.device_nvs) return error.IoUnavailable;
        return exportHostDiagnosticsFaultCold(self, path, err);
    }

    fn exportHostDiagnosticsFaultCold(self: *Runtime, path: []const u8, err: anyerror) host_io_mod.Error!void {
        @branchHint(.cold);
        const io = try self.hostIo();
        return host_diag_mod.writeFaultFile(io, path, self.diagnosticSnapshot(), err);
    }

    pub fn exportOtaStagingManifest(self: *Runtime, path: []const u8) host_io_mod.Error!void {
        if (comptime build_options.device_nvs) return error.IoUnavailable;
        return exportOtaStagingManifestCold(self, path);
    }

    fn exportOtaStagingManifestCold(self: *Runtime, path: []const u8) host_io_mod.Error!void {
        @branchHint(.cold);
        const io = try self.hostIo();
        return ota_mod.writeStagingManifest(io, self.allocator, path);
    }
};

fn spawnSystemTask() void {
    const ok = hooks.invokeSpawnHandler();
    if (hooks.rtPtr()) |rt| rt.system_task_armed = ok;
}

test "runtime: boot wires rs485 transport" {
    const io = std.testing.io;
    try leak_guard.withNoLeaks(struct {
        fn body(allocator: std.mem.Allocator) !void {
            var rt = Runtime.init(allocator, io);
            defer rt.deinit();
            try rt.boot();
            try std.testing.expect(rt.system_task_armed);
            try std.testing.expectEqual(
                @as(u8, @intFromEnum(cnc_config.Connection.rs485)),
                rt.transport.activeConnection(),
            );
        }
    }.body);
}

test "runtime: system tick polls driver" {
    const io = std.testing.io;
    try leak_guard.withNoLeaks(struct {
        fn body(allocator: std.mem.Allocator) !void {
            var rt = Runtime.init(allocator, io);
            defer rt.deinit();
            try rt.boot();
            rt.systemTick(0);
        }
    }.body);
}

test "runtime: export host diagnostics via io" {
    if (comptime build_options.device_nvs) return error.SkipZigTest;
    const io = std.testing.io;
    try leak_guard.withNoLeaks(struct {
        fn body(allocator: std.mem.Allocator) !void {
            var rt = Runtime.init(allocator, io);
            defer rt.deinit();
            try rt.boot();

            const path = ".zig-cache/modulus_runtime_host_diag.txt";
            try rt.exportHostDiagnostics(path);
            defer std.Io.Dir.cwd().deleteFile(io, path) catch {};

            const data = try host_io_mod.readTextFileAlloc(io, allocator, path);
            defer allocator.free(data);
            try std.testing.expect(std.mem.indexOf(u8, data, "transport_conn=rs485") != null);
        }
    }.body);
}

test "runtime: export ota staging manifest via io" {
    if (comptime build_options.device_nvs) return error.SkipZigTest;
    const io = std.testing.io;
    try leak_guard.withNoLeaks(struct {
        fn body(allocator: std.mem.Allocator) !void {
            var rt = Runtime.init(allocator, io);
            defer rt.deinit();

            const path = ".zig-cache/modulus_runtime_ota_staging.json";
            try rt.exportOtaStagingManifest(path);
            defer std.Io.Dir.cwd().deleteFile(io, path) catch {};

            const data = try host_io_mod.readTextFileAlloc(io, allocator, path);
            defer allocator.free(data);
            try std.testing.expect(std.mem.indexOf(u8, data, "\"status\":\"not_implemented\"") != null);
        }
    }.body);
}

test "runtime: export settings dump via io" {
    if (comptime build_options.device_nvs) return error.SkipZigTest;
    const io = std.testing.io;
    try leak_guard.withNoLeaks(struct {
        fn body(allocator: std.mem.Allocator) !void {
            var rt = Runtime.init(allocator, io);
            defer rt.deinit();

            var dump: settings_dump_mod.SettingsDump = .{};
            dump.begin();
            try std.testing.expect(dump.appendLine("$110=5000"));
            dump.onOk();

            const path = ".zig-cache/modulus_runtime_settings_dump.txt";
            try rt.exportSettingsDump(path, &dump);
            defer std.Io.Dir.cwd().deleteFile(io, path) catch {};

            const data = try host_io_mod.readTextFileAlloc(io, allocator, path);
            defer allocator.free(data);
            try std.testing.expectEqualStrings("$110=5000\n", data);
        }
    }.body);
}
