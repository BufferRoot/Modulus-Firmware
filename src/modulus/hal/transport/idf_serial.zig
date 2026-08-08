//! ESP-IDF UART backend — bridge to `firmware/tab5/components/modulus_zig/serial_shim.c`.

const c = @import("modulus_shims");
const driver = @import("../../cnc/driver.zig");

fn serialRxThunk(data: [*c]const u8, len: usize) callconv(.c) void {
    c.modulus_zig_serial_rx(@constCast(data), len);
}

pub fn registerRxHandler() void {
    c.modulus_serial_set_rx_handler(serialRxThunk);
}

pub const Io = struct {
    pub fn reset(_: *Io) void {
        c.modulus_serial_close();
    }

    pub fn open(_: *Io, port: u8, baud: u32, data_bits: u8, parity: u8, stop_bits: u8) bool {
        return c.modulus_serial_open(port, baud, data_bits, parity, stop_bits);
    }

    pub fn send(_: *Io, data: []const u8) bool {
        if (!c.modulus_serial_is_open()) return false;
        const n = c.modulus_serial_write(data.ptr, data.len);
        return n == @as(c_int, @intCast(data.len));
    }

    pub fn pollRx(_: *Io, _: *driver.Driver) void {}

    pub fn injectRx(_: *Io, _: []const u8) bool {
        return false;
    }

    pub fn drainTx(_: *Io) []const u8 {
        return &[_]u8{};
    }
};
