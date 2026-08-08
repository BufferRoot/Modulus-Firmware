//! MMBP parser event types.

pub const ParseEvent = enum(u8) {
    none = 0,
    hello_ack,
    hello_nak,
    status,
    pos,
    ovr,
    ok,
    err,
};
