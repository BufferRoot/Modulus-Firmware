import re
from pathlib import Path

src = Path("firmware/tab5/components/modulus_zig/assets/icons/generated/icon_assets_24.c")
text = src.read_text(encoding="utf-8", errors="replace")
want = ["power", "gear", "play", "pause", "spindle", "coolant", "fan", "house", "wifi", "lightning"]
maps = {}
for m in re.finditer(
    r"const LV_ATTRIBUTE_MEM_ALIGN uint8_t mod_icon_(\w+)_24_map\[\] = \{([^}]+)\}",
    text,
    re.S,
):
    short, body = m.group(1), m.group(2)
    if short not in want:
        continue
    vals = [int(x, 16) for x in re.findall(r"0x([0-9a-fA-F]+)", body)]
    assert len(vals) == 576, (short, len(vals))
    maps[short] = vals

lines = [
    "//! A8 Phosphor 24px icons (from firmware icon_assets_24) — host blit with alpha.",
    'const color = @import("color.zig");',
    'const fb = @import("fb.zig");',
    "",
    "pub const size: i32 = 24;",
    "",
    "pub const Id = enum { power, gear, play, pause, spindle, coolant, fan, house, wifi, lightning };",
    "",
]
for name in want:
    vals = maps[name]
    lines.append(f"const {name}_map: [576]u8 = .{{")
    for i in range(0, 576, 24):
        row = ", ".join(f"0x{v:02X}" for v in vals[i : i + 24])
        lines.append(f"    {row},")
    lines.append("};")
    lines.append("")

lines += [
    "fn mapFor(id: Id) *const [576]u8 {",
    "    return switch (id) {",
]
for name in want:
    lines.append(f"        .{name} => &{name}_map,")
lines += [
    "    };",
    "}",
    "",
    "/// Blend A8 glyph onto logical FB (24×24).",
    "pub fn draw(logical: *fb.LogicalFb, x: i32, y: i32, id: Id, fg: color.Rgb565) void {",
    "    const data = mapFor(id);",
    "    var row: i32 = 0;",
    "    while (row < 24) : (row += 1) {",
    "        var col: i32 = 0;",
    "        while (col < 24) : (col += 1) {",
    "            const a = data[@as(usize, @intCast(row)) * 24 + @as(usize, @intCast(col))];",
    "            if (a == 0) continue;",
    "            const px = x + col;",
    "            const py = y + row;",
    "            if (px < 0 or py < 0 or px >= logical.w or py >= logical.h) continue;",
    "            const i = @as(usize, @intCast(py)) * @as(usize, logical.w) + @as(usize, @intCast(px));",
    "            if (a >= 240) {",
    "                logical.pixels[i] = fg;",
    "            } else {",
    "                logical.pixels[i] = color.blendRgb565(logical.pixels[i], fg, a);",
    "            }",
    "        }",
    "    }",
    "}",
    "",
    'test "a8 icon has opaque pixels" {',
    '    const std = @import("std");',
    "    const gpa = std.testing.allocator;",
    "    var logical = try fb.LogicalFb.alloc(gpa);",
    "    defer logical.deinit(gpa);",
    "    const fg = color.Rgb565.fromHex(0xFFFFFF);",
    "    draw(&logical, 0, 0, .house, fg);",
    "    var found = false;",
    "    var yy: i32 = 0;",
    "    while (yy < 24) : (yy += 1) {",
    "        var xx: i32 = 0;",
    "        while (xx < 24) : (xx += 1) {",
    "            if (logical.get(xx, yy).toU16() != 0) found = true;",
    "        }",
    "    }",
    "    try std.testing.expect(found);",
    "}",
    "",
]
out = Path("src/modulus/ui_engine/icons_a8.zig")
out.write_text("\n".join(lines), encoding="utf-8")
print("wrote", out, out.stat().st_size)
