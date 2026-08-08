//! C6 HAL bridge — host mocks or firmware C bindings (no P4 dashboard/HAL).

const builtin = @import("builtin");
const firmware = builtin.target.os.tag == .freestanding;

const impl = if (firmware) @import("bridge_firmware_c6.zig") else @import("bridge_host_c6.zig");

pub const halReady = impl.halReady;
pub const bleReady = impl.bleReady;
pub const bleStatusCode = impl.bleStatusCode;
pub const espNowReady = impl.espNowReady;
pub const espNowStatusCode = impl.espNowStatusCode;
pub const espNowPoll = impl.espNowPoll;
pub const threadReady = impl.threadReady;
pub const threadStatusCode = impl.threadStatusCode;
pub const threadPoll = impl.threadPoll;
pub const zigbeeReady = impl.zigbeeReady;
pub const zigbeeStatusCode = impl.zigbeeStatusCode;
pub const zigbeePoll = impl.zigbeePoll;
pub const setMockBleStatus = impl.setMockBleStatus;
pub const setMockEspNowStatus = impl.setMockEspNowStatus;
pub const setMockThreadStatus = impl.setMockThreadStatus;
pub const setMockZigbeeStatus = impl.setMockZigbeeStatus;
pub const delayMs = impl.delayMs;
pub const logInfo = impl.logInfo;
pub const logInfoZ = impl.logInfoZ;
pub const logHeartbeat = impl.logHeartbeat;
