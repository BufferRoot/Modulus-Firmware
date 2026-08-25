//! Comptime ABI proofs — Zig `CncStatus` must match C `modulus_cnc_status_t`.
//! Host: stub ↔ translated `ui_shim.h`. Device: Zig facade ↔ translate-C bundle.

const std = @import("std");
const build_options = @import("build_options");
const device_ui = @import("../ui/device_ui.zig");

fn layoutMatches(comptime C: type, comptime Z: type) void {
    if (@sizeOf(bool) != 1) {
        @compileError("C bool ABI assumes @sizeOf(bool) == 1");
    }
    if (@alignOf(bool) != 1) {
        @compileError("C bool ABI assumes @alignOf(bool) == 1");
    }

    if (@sizeOf(C) != @sizeOf(Z)) {
        @compileError("CncStatus size mismatch vs modulus_cnc_status_t");
    }
    if (@alignOf(C) != @alignOf(Z)) {
        @compileError("CncStatus alignment mismatch vs modulus_cnc_status_t");
    }

    for (@typeInfo(Z).@"struct".fields) |zf| {
        if (!@hasField(C, zf.name)) {
            @compileError("missing C field: " ++ zf.name);
        }
        const zt = @FieldType(Z, zf.name);
        const ct = @FieldType(C, zf.name);
        if (@offsetOf(Z, zf.name) != @offsetOf(C, zf.name)) {
            @compileError("offset mismatch: " ++ zf.name);
        }
        if (@sizeOf(zt) != @sizeOf(ct)) {
            @compileError("field size mismatch: " ++ zf.name);
        }
        if (@alignOf(zt) != @alignOf(ct)) {
            @compileError("field align mismatch: " ++ zf.name);
        }
        // `char[]` may be `c_char` from translate-C vs `u8` in the stub — size/align already match.
        if (zt != ct and !((zt == [32]u8 and ct == [32]c_char) or (zt == [32]c_char and ct == [32]u8))) {
            @compileError("field type mismatch: " ++ zf.name);
        }
    }
}

comptime {
    const Z = device_ui.CncStatus;
    if (build_options.device_nvs) {
        layoutMatches(@import("modulus_shims").modulus_cnc_status_t, Z);
    } else {
        // Real header layout — not the host stub (which aliases Z).
        layoutMatches(@import("ui_shim_hdr").modulus_cnc_status_t, Z);
        layoutMatches(@import("ui_shim_hdr").modulus_cnc_status_t, @import("modulus_shims").modulus_cnc_status_t);
    }
}

test "abi: CncStatus layout matches modulus_cnc_status_t" {
    const Z = device_ui.CncStatus;
    const C = if (build_options.device_nvs)
        @import("modulus_shims").modulus_cnc_status_t
    else
        @import("ui_shim_hdr").modulus_cnc_status_t;
    try std.testing.expectEqual(@sizeOf(C), @sizeOf(Z));
    try std.testing.expectEqual(@alignOf(C), @alignOf(Z));
    inline for (@typeInfo(Z).@"struct".fields) |zf| {
        try std.testing.expectEqual(@offsetOf(C, zf.name), @offsetOf(Z, zf.name));
    }
}
