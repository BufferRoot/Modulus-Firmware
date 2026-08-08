//! Validates build-time NVS key manifest matches `settings_keys.all_keys`.

const std = @import("std");
const settings_keys = @import("settings_keys.zig");
const generated = @import("nvs_key_manifest");

test "core: generated nvs manifest matches all_keys" {
    try std.testing.expectEqual(settings_keys.all_keys.len, generated.count);
    try std.testing.expectEqual(generated.count, generated.keys.len);
    inline for (settings_keys.all_keys, 0..) |key, i| {
        try std.testing.expectEqualStrings(key, generated.keys[i]);
    }
}
