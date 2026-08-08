//! Writes `nvs_key_manifest.zig` to the path passed as argv[1] (build `addOutputFileArg`).

const std = @import("std");
const settings_keys = @import("settings_keys");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) return error.MissingArg;
    const out_path = args[1];

    var out = std.ArrayList(u8).empty;
    defer out.deinit(arena);
    var writer = std.Io.Writer.Allocating.fromArrayList(arena, &out);

    try std.Io.Writer.writeAll(&writer.writer, "//! Generated NVS key manifest — do not edit\n");
    try std.Io.Writer.writeAll(&writer.writer, "pub const keys = [_][]const u8{\n");
    inline for (settings_keys.all_keys) |key| {
        try std.Io.Writer.print(&writer.writer, "    \"{s}\",\n", .{key});
    }
    try std.Io.Writer.writeAll(&writer.writer, "};\n");
    try std.Io.Writer.print(&writer.writer, "pub const count = {d};\n", .{settings_keys.all_keys.len});

    out = writer.toArrayList();
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = out_path,
        .data = out.items,
    });
}
