//! grblHAL real-time single-byte commands.

pub const STATUS_QUERY_ALT: u8 = 0x80;
pub const CYCLE_START_ALT: u8 = 0x81;
pub const FEED_HOLD_ALT: u8 = 0x82;
pub const JOG_CANCEL: u8 = 0x85;
pub const FULL_STATUS_REQ: u8 = 0x87;
pub const SINGLE_STEP_TOGGLE: u8 = 0x89;
pub const FAN0_TOGGLE: u8 = 0x8A;
pub const MPG_MODE_TOGGLE: u8 = 0x8B;
pub const SOFT_RESET: u8 = 0x18;
pub const STOP: u8 = 0x19;
pub const PARSER_STATE_REQ: u8 = 0x83;
pub const FEED_OVR_RESET: u8 = 0x90;
pub const FEED_OVR_INC_10: u8 = 0x91;
pub const FEED_OVR_DEC_10: u8 = 0x92;
pub const FEED_OVR_INC_1: u8 = 0x93;
pub const FEED_OVR_DEC_1: u8 = 0x94;
pub const RAPID_OVR_RESET: u8 = 0x95;
pub const RAPID_OVR_50: u8 = 0x96;
pub const RAPID_OVR_25: u8 = 0x97;
pub const SPINDLE_OVR_RESET: u8 = 0x99;
pub const SPINDLE_OVR_INC_10: u8 = 0x9A;
pub const SPINDLE_OVR_DEC_10: u8 = 0x9B;
pub const SPINDLE_OVR_INC_1: u8 = 0x9C;
pub const SPINDLE_OVR_DEC_1: u8 = 0x9D;
pub const SPINDLE_STOP_TOG: u8 = 0x9E;
pub const COOLANT_FLOOD_TOG: u8 = 0xA0;
pub const COOLANT_MIST_TOG: u8 = 0xA1;
pub const TOOL_CHANGE_ACK: u8 = 0xA3;

pub const accessory = struct {
    pub const SPINDLE_CW: u8 = 1 << 0; // S — M3
    pub const SPINDLE_CCW: u8 = 1 << 1; // C — M4
    pub const COOLANT_MIST: u8 = 1 << 2; // M — M7
    pub const COOLANT_FLOOD: u8 = 1 << 3; // F — M8
    pub const TOOL_CHANGE: u8 = 1 << 4; // T — M6 pending

    pub fn fromChar(c: u8) u8 {
        return switch (c) {
            'S' => SPINDLE_CW,
            'C' => SPINDLE_CCW,
            'M' => COOLANT_MIST,
            'F' => COOLANT_FLOOD,
            'T' => TOOL_CHANGE,
            else => 0,
        };
    }
};

/// Pin-state flags from the `|Pn:` status report element (grblhal_defs.h `pin`).
pub const pin = struct {
    pub const PROBE: u32 = 1 << 0; // P
    pub const PROBE_DISC: u32 = 1 << 1; // O
    pub const LIMIT_X: u32 = 1 << 2; // X
    pub const LIMIT_Y: u32 = 1 << 3; // Y
    pub const LIMIT_Z: u32 = 1 << 4; // Z
    pub const LIMIT_A: u32 = 1 << 5; // A
    pub const LIMIT_B: u32 = 1 << 6; // B
    pub const LIMIT_C: u32 = 1 << 7; // C
    pub const LIMIT_U: u32 = 1 << 8; // U
    pub const LIMIT_V: u32 = 1 << 9; // V
    pub const LIMIT_W: u32 = 1 << 10; // W
    pub const DOOR: u32 = 1 << 11; // D
    pub const RESET_SW: u32 = 1 << 12; // R
    pub const FEED_HOLD: u32 = 1 << 13; // H
    pub const CYCLE_START: u32 = 1 << 14; // S
    pub const ESTOP: u32 = 1 << 15; // E
    pub const BLOCK_DEL: u32 = 1 << 16; // L
    pub const OPT_STOP: u32 = 1 << 17; // T
    pub const MOTOR_WARN: u32 = 1 << 18; // M
    pub const MOTOR_FAULT: u32 = 1 << 19; // F
    pub const SINGLE_STEP: u32 = 1 << 20; // Q

    pub fn fromChar(c: u8) u32 {
        return switch (c) {
            'P' => PROBE,
            'O' => PROBE_DISC,
            'X' => LIMIT_X,
            'Y' => LIMIT_Y,
            'Z' => LIMIT_Z,
            'A' => LIMIT_A,
            'B' => LIMIT_B,
            'C' => LIMIT_C,
            'U' => LIMIT_U,
            'V' => LIMIT_V,
            'W' => LIMIT_W,
            'D' => DOOR,
            'R' => RESET_SW,
            'H' => FEED_HOLD,
            'S' => CYCLE_START,
            'E' => ESTOP,
            'L' => BLOCK_DEL,
            'T' => OPT_STOP,
            'M' => MOTOR_WARN,
            'F' => MOTOR_FAULT,
            'Q' => SINGLE_STEP,
            else => 0,
        };
    }
};
