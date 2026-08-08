//! CNC driver shared types — enums/config only (struct lives in `driver.zig`).

const settings_store = @import("../core/settings_store.zig");
const event_bus = @import("../core/event_bus.zig");
const engine_mod = @import("protocol_engine.zig");

pub const Engine = engine_mod.Engine;
pub const SendFn = engine_mod.SendFn;

pub const HomingBlockReason = enum(u8) {
    none = 0,
    disconnected,
    alarm,
    busy,
};

pub const Config = struct {
    store: ?*settings_store.Store = null,
    bus: ?*event_bus.EventBus = null,
};
