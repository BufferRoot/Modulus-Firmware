//! C6 wireless policy — stacks backed by IDF/C via bridge (Phase 9+).
//! ESP-NOW peer registry is a Zig-side stub until P4 RPC exposes peers.

const std = @import("std");
const bridge = @import("../bridge_c6.zig");

pub const max_espnow_peers = 8;

pub const EspNowPeer = struct {
    mac: [6]u8 = .{0xff} ** 6,
    channel: u8 = 0,
    registered: bool = false,
};

/// P4 policy / hosted RPC will fill this; C6 broadcast peer stays in `modulus_c6_espnow.c`.
const empty_espnow_peer = EspNowPeer{};
var espnow_peer_registry: [max_espnow_peers]EspNowPeer = [_]EspNowPeer{empty_espnow_peer} ** max_espnow_peers;

pub fn espnowPeerCount() usize {
    var n: usize = 0;
    for (espnow_peer_registry) |p| {
        if (p.registered) n += 1;
    }
    return n;
}

/// Register a peer MAC for future policy (no-op on C6 until RPC).
pub fn espnowRegisterPeer(mac: *const [6]u8, channel: u8) bool {
    for (&espnow_peer_registry) |*slot| {
        if (!slot.registered) {
            slot.mac = mac.*;
            slot.channel = channel;
            slot.registered = true;
            return true;
        }
    }
    return false;
}

pub fn espnowClearPeers() void {
    espnow_peer_registry = [_]EspNowPeer{empty_espnow_peer} ** max_espnow_peers;
}

pub const StackStatus = enum(u8) {
    disabled = 0,
    planned = 1,
    partial = 2,
    ready = 3,
    fault = 4,
};

pub const StackId = enum(u8) {
    ble = 0,
    esp_now = 1,
    thread = 2,
    zigbee = 3,
};

pub const StackState = struct {
    id: StackId,
    status: StackStatus,
    detail: [32]u8,
};

const default_detail: [32]u8 = .{0} ** 32;

fn setDetail(buf: *[32]u8, comptime msg: []const u8) void {
    @memset(buf, 0);
    const n = @min(msg.len, buf.len - 1);
    @memcpy(buf[0..n], msg[0..n]);
}

var stacks: [4]StackState = .{
    .{ .id = .ble, .status = .planned, .detail = default_detail },
    .{ .id = .esp_now, .status = .planned, .detail = default_detail },
    .{ .id = .thread, .status = .planned, .detail = default_detail },
    .{ .id = .zigbee, .status = .planned, .detail = default_detail },
};

pub fn stackStatus(id: StackId) StackStatus {
    return stacks[@intFromEnum(id)].status;
}

pub fn stackState(id: StackId) StackState {
    return stacks[@intFromEnum(id)];
}

fn applyBleStatus(code: u8) void {
    const slot = &stacks[@intFromEnum(StackId.ble)];
    switch (code) {
        1 => {
            slot.status = .ready;
            setDetail(&slot.detail, "HCI MODULUS_TAB5");
        },
        2 => {
            slot.status = .fault;
            setDetail(&slot.detail, "HCI controller error");
        },
        else => {
            if (slot.status == .ready or slot.status == .fault) return;
            slot.status = .partial;
            setDetail(&slot.detail, "HCI pending");
        },
    }
}

fn applyEspNowStatus(code: u8) void {
    const slot = &stacks[@intFromEnum(StackId.esp_now)];
    switch (code) {
        1 => {
            slot.status = .ready;
            setDetail(&slot.detail, "peer-ready ch coex");
        },
        2 => {
            slot.status = .fault;
            setDetail(&slot.detail, "init or wifi down");
        },
        else => {
            if (slot.status == .ready or slot.status == .fault) return;
            slot.status = .partial;
            setDetail(&slot.detail, "Wi-Fi pending");
        },
    }
}

fn initBle() void {
    applyBleStatus(bridge.bleStatusCode());
    if (stackStatus(.ble) == .ready) {
        bridge.logInfo("c6 wireless: BLE ready");
    } else if (stackStatus(.ble) == .fault) {
        bridge.logInfo("c6 wireless: BLE fault");
    } else {
        bridge.logInfo("c6 wireless: BLE starting");
    }
}

fn initEspNow() void {
    applyEspNowStatus(bridge.espNowStatusCode());
    if (stackStatus(.esp_now) == .ready) {
        bridge.logInfo("c6 wireless: ESP-NOW ready");
    } else if (stackStatus(.esp_now) == .fault) {
        bridge.logInfo("c6 wireless: ESP-NOW fault");
    } else if (stackStatus(.esp_now) == .partial) {
        bridge.logInfo("c6 wireless: ESP-NOW Wi-Fi pending");
    } else {
        bridge.logInfo("c6 wireless: ESP-NOW starting");
    }
}

fn applyThreadStatus(code: u8) void {
    const slot = &stacks[@intFromEnum(StackId.thread)];
    switch (code) {
        1 => {
            slot.status = .ready;
            setDetail(&slot.detail, "detached Modulus");
        },
        2 => {
            slot.status = .fault;
            setDetail(&slot.detail, "ot init or coex");
        },
        else => {
            if (slot.status == .ready or slot.status == .fault) return;
            slot.status = .partial;
            setDetail(&slot.detail, "Wi-Fi pending");
        },
    }
}

fn initThread() void {
    applyThreadStatus(bridge.threadStatusCode());
    if (stackStatus(.thread) == .ready) {
        bridge.logInfo("c6 wireless: Thread ready");
    } else if (stackStatus(.thread) == .fault) {
        bridge.logInfo("c6 wireless: Thread fault");
    } else if (stackStatus(.thread) == .partial) {
        bridge.logInfo("c6 wireless: Thread Wi-Fi pending");
    } else {
        bridge.logInfo("c6 wireless: Thread starting");
    }
}

pub fn pollThread() void {
    bridge.threadPoll();
    const prev = stackStatus(.thread);
    applyThreadStatus(bridge.threadStatusCode());
    if (prev != .ready and stackStatus(.thread) == .ready) {
        bridge.logInfo("c6 wireless: Thread ready (sync)");
    }
}

fn applyZigbeeStatus(code: u8) void {
    const slot = &stacks[@intFromEnum(StackId.zigbee)];
    switch (code) {
        1 => {
            slot.status = .ready;
            setDetail(&slot.detail, "ZB factory-new");
        },
        2 => {
            slot.status = .fault;
            setDetail(&slot.detail, "zb init or coex");
        },
        else => {
            if (slot.status == .ready or slot.status == .fault) return;
            slot.status = .partial;
            setDetail(&slot.detail, "802.15.4 w/ Thread");
        },
    }
}

fn initZigbee() void {
    applyZigbeeStatus(bridge.zigbeeStatusCode());
    if (stackStatus(.zigbee) == .ready) {
        bridge.logInfo("c6 wireless: Zigbee ready");
    } else if (stackStatus(.zigbee) == .fault) {
        bridge.logInfo("c6 wireless: Zigbee fault");
    } else if (stackStatus(.zigbee) == .partial) {
        bridge.logInfo("c6 wireless: Zigbee deferred (Thread)");
    } else {
        bridge.logInfo("c6 wireless: Zigbee starting");
    }
}

pub fn pollZigbee() void {
    bridge.zigbeePoll();
    const prev = stackStatus(.zigbee);
    applyZigbeeStatus(bridge.zigbeeStatusCode());
    if (prev != .ready and stackStatus(.zigbee) == .ready) {
        bridge.logInfo("c6 wireless: Zigbee ready (sync)");
    }
}

/// Refresh BLE row after NimBLE sync (call from idle).
pub fn pollBle() void {
    const prev = stackStatus(.ble);
    applyBleStatus(bridge.bleStatusCode());
    if (prev != .ready and stackStatus(.ble) == .ready) {
        bridge.logInfo("c6 wireless: BLE ready (sync)");
    }
}

pub fn pollEspNow() void {
    bridge.espNowPoll();
    const prev = stackStatus(.esp_now);
    applyEspNowStatus(bridge.espNowStatusCode());
    if (prev != .ready and stackStatus(.esp_now) == .ready) {
        bridge.logInfo("c6 wireless: ESP-NOW ready (sync)");
    }
}

pub fn initAll() void {
    initBle();
    initEspNow();
    initThread();
    initZigbee();
}

pub fn resetForTest() void {
    stacks = .{
        .{ .id = .ble, .status = .planned, .detail = default_detail },
        .{ .id = .esp_now, .status = .planned, .detail = default_detail },
        .{ .id = .thread, .status = .planned, .detail = default_detail },
        .{ .id = .zigbee, .status = .planned, .detail = default_detail },
    };
    bridge.setMockBleStatus(0);
    bridge.setMockEspNowStatus(0);
    bridge.setMockThreadStatus(0);
    bridge.setMockZigbeeStatus(0);
}

pub fn logSummary() void {
    const ble = stackStatus(.ble);
    const enow = stackStatus(.esp_now);
    if (ble == .ready and enow == .ready) {
        bridge.logInfo("c6 wireless: policy online (BLE+ESP-NOW ready)");
    } else if (ble == .ready) {
        bridge.logInfo("c6 wireless: policy online (BLE ready, ESP-NOW pending)");
    } else {
        bridge.logInfo("c6 wireless: policy online (stacks pending)");
    }
}

test "wireless scaffold defaults" {
    resetForTest();
    const ble = stackStatus(.ble);
    try std.testing.expect(ble == .planned);
}

test "initAll smoke (host)" {
    resetForTest();
    initAll();
    try std.testing.expect(stackStatus(.thread) == .partial);
}

test "thread ready when mock status 1" {
    resetForTest();
    bridge.setMockThreadStatus(1);
    defer resetForTest();
    pollThread();
    try std.testing.expect(stackStatus(.thread) == .ready);
}

test "ble ready when mock status 1" {
    resetForTest();
    bridge.setMockBleStatus(1);
    defer resetForTest();
    pollBle();
    try std.testing.expect(stackStatus(.ble) == .ready);
}

test "espnow ready when mock status 1" {
    resetForTest();
    bridge.setMockEspNowStatus(1);
    defer resetForTest();
    pollEspNow();
    try std.testing.expect(stackStatus(.esp_now) == .ready);
}

test "zigbee partial when mock status 0" {
    resetForTest();
    defer resetForTest();
    initZigbee();
    try std.testing.expect(stackStatus(.zigbee) == .partial);
}

test "espnow peer registry stub" {
    resetForTest();
    defer resetForTest();
    const mac = [_]u8{ 0x11, 0x22, 0x33, 0x44, 0x55, 0x66 };
    try std.testing.expect(espnowRegisterPeer(&mac, 1));
    try std.testing.expect(espnowPeerCount() == 1);
    espnowClearPeers();
    try std.testing.expect(espnowPeerCount() == 0);
}

test "zigbee ready when mock status 1" {
    resetForTest();
    bridge.setMockZigbeeStatus(1);
    defer resetForTest();
    pollZigbee();
    try std.testing.expect(stackStatus(.zigbee) == .ready);
}
