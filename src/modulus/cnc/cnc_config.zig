//! CNC configuration enums — mirrors `cnc_config.h`.

pub const k_default_cnc_conn: u8 = @intFromEnum(Connection.rs485);
pub const k_default_cnc_proto: u8 = @intFromEnum(Protocol.grblhal);

pub const Protocol = enum(u8) {
    grblhal = 0,
    classic_grbl,
    fluid_nc,
    linux_cnc,
    mach3_mach4,
    masso,
    _count,
};

pub const Connection = enum(u8) {
    esp_now = 0,
    websocket,
    telnet,
    serial_usb,
    rs485,
    ble_hid,
    i2c,
    usb_hid,
    usb_gamepad,
    can_bus,
    _count,
};

pub const ConnStatus = enum(u8) {
    disconnected = 0,
    connecting,
    connected,
};

pub const AxesPreset = enum(u8) {
    xy = 0,
    xyz,
    xyza,
    xyzab,
    xyzabc,
    _count,
};

pub const JogMode = enum(u8) {
    step = 0,
    continuous,
    _count,
};

pub const MachineLimits = struct {
    max_feed_rate: u16 = 5000,
    max_spindle: u16 = 24000,
    default_jog: u16 = 1000,
    enable_sp_ccw: bool = true,
};

/// Pendant-side soft limits (machine coords 0..max after homing).
/// Linear axes in mm; rotary A/B/C in degrees.
pub const SoftLimits = struct {
    enabled: bool = false,
    max_x: f32 = 300,
    max_y: f32 = 300,
    max_z: f32 = 100,
    max_a: f32 = 360,
    max_b: f32 = 360,
    max_c: f32 = 360,
};

/// Human-readable label for a CNC transport connection.
///
/// ```zig
/// const std = @import("std");
/// const cnc_config = @import("cnc_config.zig");
///
/// try std.testing.expectEqualStrings("RS-485", cnc_config.connectionStr(.rs485));
/// ```
pub fn connectionStr(c: Connection) []const u8 {
    return switch (c) {
        .esp_now => "ESP-NOW",
        .websocket => "WebSocket",
        .telnet => "Telnet",
        .serial_usb => "Serial USB",
        .rs485 => "RS-485",
        .ble_hid => "BLE HID",
        .i2c => "I2C",
        .usb_hid => "USB HID",
        .usb_gamepad => "USB Gamepad",
        .can_bus => "CAN Bus",
        else => "?",
    };
}

pub fn protocolStr(p: Protocol) []const u8 {
    return switch (p) {
        .grblhal => "GrblHAL",
        .classic_grbl => "Grbl",
        .fluid_nc => "FluidNC",
        .linux_cnc => "LinuxCNC",
        .mach3_mach4 => "Mach3/Mach4",
        .masso => "Masso",
        else => "?",
    };
}

/// Pendant implements grblHAL, stock Grbl 1.1, FluidNC, LinuxCNC linuxcncrsh,
/// Mach3/Mach4 MMBP, and Masso Link UDP (status/keepalive; DRO XYZ not in RE'd Link packets).
pub fn protocolImplemented(p: Protocol) bool {
    return switch (p) {
        .grblhal, .classic_grbl, .fluid_nc, .linux_cnc, .mach3_mach4, .masso => true,
        else => false,
    };
}

pub fn usesGrblEngine(p: Protocol) bool {
    return switch (p) {
        .grblhal, .classic_grbl, .fluid_nc => true,
        else => false,
    };
}

/// grbl `$$` settings browser / envelope pull — Grbl-family + LinuxCNC INI.
pub fn supportsSettingsDump(p: Protocol) bool {
    return usesGrblEngine(p) or p == .linux_cnc;
}

/// Human paste of `$nn=` or `KEY=val` lines into pendant NVS (Mach3/Masso).
pub fn supportsEnvelopePaste(p: Protocol) bool {
    return switch (p) {
        .mach3_mach4, .masso => true,
        else => false,
    };
}

/// FluidNC and stock Grbl 1.1 speak the classic dialect: literal `?` status
/// polls, `$H`/`$H<axis>` text homing, no grblHAL 0x80-range realtime bytes.
pub fn usesClassicRealtime(p: Protocol) bool {
    return switch (p) {
        .classic_grbl, .fluid_nc => true,
        else => false,
    };
}

/// Preferred transport for a protocol (UI hint; user may override).
pub fn preferredConnection(p: Protocol) Connection {
    return switch (p) {
        .linux_cnc, .mach3_mach4 => .telnet,
        .fluid_nc => .websocket,
        // Masso Link UDP — transport layer opens UDP when proto=masso (see dispatcher).
        .masso => .websocket,
        else => .rs485,
    };
}
