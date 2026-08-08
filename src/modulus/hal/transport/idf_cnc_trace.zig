//! grblHAL TX trace — bridge to `cnc_trace_shim.c`.

const c = @import("modulus_shims");

pub fn traceTx(data: []const u8) void {
    c.modulus_cnc_trace_tx(data.ptr, data.len);
}
