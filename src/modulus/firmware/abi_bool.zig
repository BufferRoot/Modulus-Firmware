//! C `bool` FFI — prefer `c_int` 0/1 for Zig↔C exports (Zig #35373 on rv32).

comptime {
    // Remaining C `bool` in shim headers still assume 1-byte layout.
    if (@sizeOf(bool) != 1) @compileError("Modulus C ABI requires @sizeOf(bool) == 1");
    if (@alignOf(bool) != 1) @compileError("Modulus C ABI requires @alignOf(bool) == 1");
}

/// ABI epoch 22+: status exports use `c_int` 0/1 (`boot_ok`, spawn flags, dump, OTA).
pub const prefer_c_int_for_new_exports = true;

pub inline fn asCInt(v: bool) c_int {
    return if (v) 1 else 0;
}

test "abi: bool size for C FFI" {
    try @import("std").testing.expect(@sizeOf(bool) == 1);
}

test "abi: asCInt" {
    try @import("std").testing.expectEqual(@as(c_int, 1), asCInt(true));
    try @import("std").testing.expectEqual(@as(c_int, 0), asCInt(false));
}
