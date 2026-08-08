//! grblHAL parser fuzz — corpus runs under `zig build test`; use `zig build test -- --fuzz` on Unix.

const std = @import("std");
const corpus_mod = @import("parser_fuzz_corpus.zig");
const parser_mod = @import("parser.zig");

const Parser = parser_mod.Parser;
const line_buf_max = parser_mod.line_buf_max;

test "cnc: parser fuzz status and bracket lines" {
    return std.testing.fuzz({}, fuzzParserLine, .{
        .corpus = &corpus_mod.lines,
    });
}

fn fuzzParserLine(_: void, smith: *std.testing.Smith) !void {
    @disableInstrumentation();
    var p = Parser.init();
    var buf: [line_buf_max]u8 = undefined;
    const len = smith.sliceWeightedBytes(buf[0..], &.{
        .rangeAtMost(u8, 0x20, 0x7e, 4),
        .rangeAtMost(u8, 0x00, 0xff, 1),
    });
    _ = p.parseLine(buf[0..len]);
}
