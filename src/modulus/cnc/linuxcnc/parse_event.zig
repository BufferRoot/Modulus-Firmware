//! LinuxCNC linuxcncrsh parser event types.

pub const ParseEvent = enum(u8) {
    none = 0,
    hello_ack,
    hello_nak,
    enable_on,
    enable_off,
    estop_on,
    estop_off,
    program_status,
    abs_act_pos,
    rel_act_pos,
    feed_override,
    spindle_override,
    spindle,
    joint_homed,
    ini,
    mode_manual,
    machine_on,
    machine_off,
    set_ack,
    err,
};
