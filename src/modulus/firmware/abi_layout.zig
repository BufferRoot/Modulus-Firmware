//! Comptime ABI proofs — `modulus_cnc_status_t` must match Zig `CncStatus` field layout.

const device_ui = @import("../ui/device_ui.zig");

comptime {
    const C = @import("modulus_shims").modulus_cnc_status_t;
    const Z = device_ui.CncStatus;

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
        if (zt != ct) {
            @compileError("field type mismatch: " ++ zf.name);
        }
    }
}

test "abi: CncStatus layout matches modulus_cnc_status_t" {
    _ = @import("std").testing;
}
