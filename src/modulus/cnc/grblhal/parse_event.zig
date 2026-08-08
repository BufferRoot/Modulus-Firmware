//! grblHAL parser event types.

pub const ParseEvent = enum(u8) {
    none = 0,
    status_report,
    ok,
    err,
    alarm,
    welcome,
    message,
    parser_state_update,
    setting,
    info_response,
    setting_enum,
    setting_group_enum,
    alarm_enum,
    error_enum,
    spindle_enum,
    feedback,
    probe_result,
};
