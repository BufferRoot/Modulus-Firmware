//! ASCII case-insensitive substring match (Montserrat / UI search).

/// Lowercase alnum only — folds `-`, spaces, `&`, etc. for tab search.
pub fn foldAscii(out: []u8, src: []const u8) []const u8 {
    var n: usize = 0;
    for (src) |c| {
        const lc: u8 = if (c >= 'A' and c <= 'Z') c + 32 else c;
        if ((lc >= 'a' and lc <= 'z') or (lc >= '0' and lc <= '9')) {
            if (n >= out.len) break;
            out[n] = lc;
            n += 1;
        }
    }
    return out[0..n];
}

pub fn containsIgnoreCase(hay: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > hay.len) return false;
    var i: usize = 0;
    while (i + needle.len <= hay.len) : (i += 1) {
        var ok = true;
        for (needle, 0..) |nc, j| {
            const hc = hay[i + j];
            const a = if (nc >= 'A' and nc <= 'Z') nc + 32 else nc;
            const b = if (hc >= 'A' and hc <= 'Z') hc + 32 else hc;
            if (a != b) {
                ok = false;
                break;
            }
        }
        if (ok) return true;
    }
    return false;
}

/// Title/keyword match: raw case-insensitive, then folded alnum substring.
pub fn matchesFolded(hay: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (containsIgnoreCase(hay, needle)) return true;
    var hf: [64]u8 = undefined;
    var nf: [32]u8 = undefined;
    const h = foldAscii(&hf, hay);
    const n = foldAscii(&nf, needle);
    if (n.len == 0) return true;
    return containsIgnoreCase(h, n);
}

test "containsIgnoreCase" {
    const std = @import("std");
    try std.testing.expect(containsIgnoreCase("Brightness", "bright"));
    try std.testing.expect(containsIgnoreCase("Wi-Fi", "wifi") == false);
    try std.testing.expect(containsIgnoreCase("Theme", ""));
}

test "matchesFolded" {
    const std = @import("std");
    try std.testing.expect(matchesFolded("Wi-Fi", "wifi"));
    try std.testing.expect(matchesFolded("esp-now", "espnow"));
    try std.testing.expect(matchesFolded("Storage & diagnostics", "diagnostic"));
    try std.testing.expect(matchesFolded("logging", "log"));
    try std.testing.expect(!matchesFolded("CNC", "power"));
}
