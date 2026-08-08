//! C6 firmware bridge — FreeRTOS delay + ESP_LOG via modulus_bridge_c6.c (no std).

extern fn modulus_bridge_c6_hal_ready() bool;
extern fn modulus_c6_ble_ready() bool;
extern fn modulus_c6_ble_status() u8;
extern fn modulus_c6_espnow_ready() bool;
extern fn modulus_c6_espnow_status() u8;
extern fn modulus_c6_espnow_poll() void;
extern fn modulus_c6_thread_ready() bool;
extern fn modulus_c6_thread_status() u8;
extern fn modulus_c6_thread_poll() void;
extern fn modulus_c6_zigbee_ready() bool;
extern fn modulus_c6_zigbee_status() u8;
extern fn modulus_c6_zigbee_poll() void;
extern fn modulus_bridge_c6_delay_ms(ms: u32) void;
extern fn modulus_bridge_c6_log_info(msg: [*:0]const u8) void;
extern fn modulus_bridge_c6_log_heartbeat(tick: u32) void;

pub fn halReady() bool {
    return modulus_bridge_c6_hal_ready();
}

pub fn bleReady() bool {
    return modulus_c6_ble_ready();
}

pub fn bleStatusCode() u8 {
    return modulus_c6_ble_status();
}

pub fn espNowReady() bool {
    return modulus_c6_espnow_ready();
}

pub fn espNowStatusCode() u8 {
    return modulus_c6_espnow_status();
}

pub fn espNowPoll() void {
    modulus_c6_espnow_poll();
}

pub fn threadReady() bool {
    return modulus_c6_thread_ready();
}

pub fn threadStatusCode() u8 {
    return modulus_c6_thread_status();
}

pub fn threadPoll() void {
    modulus_c6_thread_poll();
}

pub fn zigbeeReady() bool {
    return modulus_c6_zigbee_ready();
}

pub fn zigbeeStatusCode() u8 {
    return modulus_c6_zigbee_status();
}

pub fn zigbeePoll() void {
    modulus_c6_zigbee_poll();
}

pub fn setMockBleStatus(_: u8) void {}

pub fn setMockEspNowStatus(_: u8) void {}

pub fn setMockThreadStatus(_: u8) void {}

pub fn setMockZigbeeStatus(_: u8) void {}

pub fn delayMs(ms: u32) void {
    modulus_bridge_c6_delay_ms(ms);
}

pub fn logInfo(comptime msg: []const u8) void {
    const terminated = msg ++ "\x00";
    modulus_bridge_c6_log_info(terminated.ptr);
}

pub fn logInfoZ(msg: [*:0]const u8) void {
    modulus_bridge_c6_log_info(msg);
}

pub fn logHeartbeat(tick: u32) void {
    modulus_bridge_c6_log_heartbeat(tick);
}
