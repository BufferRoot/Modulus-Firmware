//! INA226 battery shim — `battery_shim.c`.

const battery_mod = @import("battery.zig");
const c = @import("modulus_shims");

pub const CStatus = c.modulus_battery_status_t;

pub fn hwInit() void {
    c.modulus_battery_init();
}

pub fn syncStatus(dst: *battery_mod.Status) void {
    var raw: CStatus = undefined;
    if (!c.modulus_battery_get_status(&raw)) return;
    dst.voltage = raw.voltage;
    dst.current = raw.current;
    dst.power = raw.power;
    dst.percent = raw.percent;
    dst.charge_state = @enumFromInt(raw.charge_state);
    dst.cpu_temp = raw.cpu_temp;
    dst.rate_mA = raw.rate_mA;
    dst.time_to_empty = raw.time_to_empty;
    dst.time_to_full = raw.time_to_full;
}
