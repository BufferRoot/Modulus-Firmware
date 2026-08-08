//! Host mocks for C6 boot + wireless unit tests.

var mock_hal_ready: bool = true;
var mock_ble_status: u8 = 0;
var mock_espnow_status: u8 = 0;
var mock_thread_status: u8 = 0;
var mock_zigbee_status: u8 = 0;

pub fn halReady() bool {
    return mock_hal_ready;
}

pub fn bleReady() bool {
    return mock_ble_status == 1;
}

pub fn bleStatusCode() u8 {
    return mock_ble_status;
}

pub fn setMockBleStatus(code: u8) void {
    mock_ble_status = code;
}

pub fn espNowReady() bool {
    return mock_espnow_status == 1;
}

pub fn espNowStatusCode() u8 {
    return mock_espnow_status;
}

pub fn espNowPoll() void {}

pub fn setMockEspNowStatus(code: u8) void {
    mock_espnow_status = code;
}

pub fn threadReady() bool {
    return mock_thread_status == 1;
}

pub fn threadStatusCode() u8 {
    return mock_thread_status;
}

pub fn threadPoll() void {}

pub fn setMockThreadStatus(code: u8) void {
    mock_thread_status = code;
}

pub fn zigbeeReady() bool {
    return mock_zigbee_status == 1;
}

pub fn zigbeeStatusCode() u8 {
    return mock_zigbee_status;
}

pub fn zigbeePoll() void {}

pub fn setMockZigbeeStatus(code: u8) void {
    mock_zigbee_status = code;
}

pub fn delayMs(ms: u32) void {
    _ = ms;
}

pub fn logInfo(comptime msg: []const u8) void {
    _ = msg;
}

pub fn logInfoZ(msg: [*:0]const u8) void {
    _ = msg;
}

pub fn logHeartbeat(tick: u32) void {
    _ = tick;
}
