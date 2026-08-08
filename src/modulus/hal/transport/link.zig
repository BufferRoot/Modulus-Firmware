//! Active transport send bridge — maps grblHAL SendFn to instance method.

const build_options = @import("build_options");
const idf_cnc_trace = if (build_options.device_nvs)
    @import("idf_cnc_trace.zig")
else
    struct {
        pub fn traceTx(_: []const u8) void {}
    };

var g_ctx: ?*anyopaque = null;
var g_send: ?*const fn (*anyopaque, []const u8) bool = null;

pub fn setActive(ctx: *anyopaque, send_impl: *const fn (*anyopaque, []const u8) bool) void {
    if (g_ctx != null and g_ctx != ctx) {
        g_ctx = null;
        g_send = null;
    }
    g_ctx = ctx;
    g_send = send_impl;
}

pub fn clearActive(ctx: *anyopaque) void {
    if (g_ctx == ctx) {
        g_ctx = null;
        g_send = null;
    }
}

pub fn bridgeSend(data: []const u8) bool {
    idf_cnc_trace.traceTx(data);
    if (g_ctx) |ctx| {
        if (g_send) |send| return send(ctx, data);
    }
    return false;
}

pub const sendFn = bridgeSend;

test "transport: link bridge inactive returns false" {
    try @import("std").testing.expect(!bridgeSend("?\n"));
}

test "transport: link setActive forwards to send impl" {
    var ctx: u8 = 0;
    const Ctx = struct {
        var out: []const u8 = undefined;
        fn send(c: *anyopaque, data: []const u8) bool {
            _ = c;
            out = data;
            return true;
        }
    };
    setActive(&ctx, Ctx.send);
    try @import("std").testing.expect(bridgeSend("G0\n"));
    try @import("std").testing.expectEqualStrings("G0\n", Ctx.out);
    clearActive(&ctx);
    try @import("std").testing.expect(!bridgeSend("?\n"));
}

test "transport: link clearActive ignores other ctx" {
    var ctx_a: u8 = 1;
    var ctx_b: u8 = 2;
    const noop = struct {
        fn send(_: *anyopaque, _: []const u8) bool {
            return true;
        }
    };
    setActive(&ctx_a, noop.send);
    clearActive(&ctx_b);
    try @import("std").testing.expect(bridgeSend("?\n"));
    clearActive(&ctx_a);
    try @import("std").testing.expect(!bridgeSend("?\n"));
}
