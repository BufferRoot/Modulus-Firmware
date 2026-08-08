//! System event IDs — mirrors `main/core/system_events.h` in C++ reference.

pub const EventId = u16;

// ── Core System (0x00xx) ──
pub const EVT_SYSTEM_BOOT_COMPLETE: EventId = 0x0001;
pub const EVT_SYSTEM_SHUTDOWN: EventId = 0x0002;
pub const EVT_SYSTEM_DEEP_SLEEP: EventId = 0x0003;
pub const EVT_SYSTEM_WAKE: EventId = 0x0004;

// ── Display (0x01xx) ──
pub const EVT_DISPLAY_READY: EventId = 0x0100;
pub const EVT_DISPLAY_SLEEP: EventId = 0x0101;
pub const EVT_DISPLAY_WAKE: EventId = 0x0102;

// ── Touch / Input (0x02xx) ──
pub const EVT_TOUCH_PRESSED: EventId = 0x0200;
pub const EVT_TOUCH_RELEASED: EventId = 0x0201;

// ── Screen Navigation (0x03xx) ──
pub const EVT_SCREEN_BOOT_DONE: EventId = 0x0300;
pub const EVT_SCREEN_CHANGE: EventId = 0x0301;

// ── CNC Protocol (0x10xx) ──
pub const EVT_CNC_STATUS_UPDATE: EventId = 0x1000;
pub const EVT_CNC_ALARM: EventId = 0x1001;
pub const EVT_CNC_POSITION_UPDATE: EventId = 0x1002;
pub const EVT_CNC_FEED_OVERRIDE: EventId = 0x1003;
pub const EVT_CNC_CONNECTED: EventId = 0x1004;
pub const EVT_CNC_DISCONNECTED: EventId = 0x1005;
pub const EVT_CNC_ERROR: EventId = 0x1006;
pub const EVT_CNC_MESSAGE: EventId = 0x1007;
pub const EVT_CNC_PARSER_STATE: EventId = 0x1008;
pub const EVT_CNC_HOMING_CHANGED: EventId = 0x1009;
pub const EVT_CNC_TOOL_CHANGE: EventId = 0x100A;
pub const EVT_CNC_MPG_STATE: EventId = 0x100B;
pub const EVT_CNC_SESSION_STATE: EventId = 0x100C;
/// Maintenance due/warn — payload: 1 byte meter id (0=travel, 1=spindle, 2=run).
pub const EVT_CNC_MAINT_WARN: EventId = 0x100D;

// ── DSP / Signal Processing (0x11xx) ──
pub const EVT_DSP_FFT_READY: EventId = 0x1100;
pub const EVT_DSP_PEAK_CHANGED: EventId = 0x1101;
pub const EVT_DSP_OVERLOAD: EventId = 0x1102;

// ── AMP Inter-Core (0x12xx) ──
pub const EVT_AMP_SUBCORE_READY: EventId = 0x1200;
pub const EVT_AMP_SUBCORE_FAULT: EventId = 0x1201;

// ── Battery / Power (0x04xx) ──
pub const EVT_BATTERY_LOW: EventId = 0x0400;
pub const EVT_BATTERY_CRITICAL: EventId = 0x0401;

// ── Communication (0x20xx) ──
pub const EVT_WIFI_CONNECTED: EventId = 0x2000;
pub const EVT_WIFI_DISCONNECTED: EventId = 0x2001;
pub const EVT_BT_CONNECTED: EventId = 0x2010;
pub const EVT_BT_DISCONNECTED: EventId = 0x2011;
pub const EVT_RS485_DATA_RECEIVED: EventId = 0x2020;
pub const EVT_USB_DEVICE_ATTACHED: EventId = 0x2030;
pub const EVT_USB_DEVICE_DETACHED: EventId = 0x2031;
