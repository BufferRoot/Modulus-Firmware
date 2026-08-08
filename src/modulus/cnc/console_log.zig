//! Console line log — lock-light ring shared between the CNC engine task
//! (producer: RX lines + TX echo) and the LVGL/UI task (consumer via ABI pop).
//!
//! Deliberately tiny: fixed lines, drop-oldest on overflow, status reports
//! ('<...>') and '?' polls filtered at the producer so the ring holds only
//! human-meaningful traffic (ok / error / [MSG:..] / alarms / sent G-code).
//!
//! Concurrency: single producer (CNC task), single consumer (UI task).
//! head/tail are monotonic u32 with acquire/release atomics; on overflow the
//! producer advances tail (drop-oldest). The worst race is the consumer
//! reading a line the producer is about to overwrite — cosmetic for a log,
//! and bounded to one garbled line in the UI, never memory-unsafe.

const std = @import("std");

pub const LINE_CAP = 96;
const N = 32; // power of two

const Dir = enum(u8) { rx = 0, tx = 1 };

var lines: [N][LINE_CAP]u8 = undefined;
var lens: [N]u8 = [_]u8{0} ** N;
var dirs: [N]u8 = [_]u8{0} ** N;
var head: u32 = 0; // next write slot (producer)
var tail: u32 = 0; // next read slot (consumer)

fn shouldSkipRx(line: []const u8) bool {
    if (line.len == 0) return true;
    return line[0] == '<'; // realtime status spam (5-10 Hz)
}

fn shouldSkipTx(data: []const u8) bool {
    if (data.len == 0) return true;
    if (data.len == 1) {
        // Realtime single bytes: show reset/hold/start, hide '?' poll flood.
        return data[0] == '?';
    }
    return false;
}

fn pushRaw(dir: Dir, data: []const u8) void {
    var trimmed = data;
    while (trimmed.len > 0 and (trimmed[trimmed.len - 1] == '\n' or
        trimmed[trimmed.len - 1] == '\r')) trimmed = trimmed[0 .. trimmed.len - 1];
    if (trimmed.len == 0) return;

    const h = @atomicLoad(u32, &head, .acquire);
    const t = @atomicLoad(u32, &tail, .acquire);
    if (h -% t >= N) {
        @atomicStore(u32, &tail, t +% 1, .release); // drop oldest
    }
    const slot = h % N;
    const n: u8 = @intCast(@min(trimmed.len, LINE_CAP));
    @memcpy(lines[slot][0..n], trimmed[0..n]);
    lens[slot] = n;
    dirs[slot] = @intFromEnum(dir);
    @atomicStore(u32, &head, h +% 1, .release);
}

/// Engine RX tap (call with the parsed-line slice, pre-parse).
pub fn pushRx(line: []const u8) void {
    if (shouldSkipRx(line)) return;
    pushRaw(.rx, line);
}

/// Engine TX tap (call with outbound bytes).
pub fn pushTx(data: []const u8) void {
    if (shouldSkipTx(data)) return;
    if (data.len == 1) {
        // Render realtime bytes readably.
        const label: []const u8 = switch (data[0]) {
            0x18 => "^X (soft reset)",
            '!' => "! (feed hold)",
            '~' => "~ (cycle start)",
            else => return,
        };
        pushRaw(.tx, label);
        return;
    }
    pushRaw(.tx, data);
}

/// UI pop: copies one line into out, sets dir (0=rx, 1=tx).
/// Returns line length, or -1 when the ring is empty.
pub fn pop(dir_out: *u8, out: []u8) i32 {
    const t = @atomicLoad(u32, &tail, .acquire);
    const h = @atomicLoad(u32, &head, .acquire);
    if (t == h) return -1;
    const slot = t % N;
    const n = @min(@as(usize, lens[slot]), out.len);
    @memcpy(out[0..n], lines[slot][0..n]);
    dir_out.* = dirs[slot];
    @atomicStore(u32, &tail, t +% 1, .release);
    return @intCast(n);
}
