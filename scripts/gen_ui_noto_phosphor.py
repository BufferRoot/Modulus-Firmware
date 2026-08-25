#!/usr/bin/env python3
"""Bake Noto Sans + Phosphor into Zig A8 atlases for ui_engine host demo.

Sources (override with env):
  NOTO_DIR   — folder with NotoSans-*.ttf (default: assets/ui/fonts)
  PHOSPHOR   — phosphor-icons root with PNGs/{light,fill}/
"""
from __future__ import annotations

import os
import struct
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "src" / "modulus" / "ui_engine"
NOTO_DIR = Path(os.environ.get("NOTO_DIR", ROOT / "assets" / "ui" / "fonts"))
PHOSPHOR = Path(
    os.environ.get(
        "PHOSPHOR",
        Path.home() / "Desktop" / "phosphor-icons (1)",
    )
)

# ASCII printable
FIRST, LAST = 32, 126
NCHARS = LAST - FIRST + 1

# UI faces: (name, ttf, px, cell_w, cell_h)
# Weight siblings at same px so emph roles use real Medium/Bold (no double-stroke).
# cell_w sized for widest ASCII advance (W/@) — too-narrow cells capped advances unevenly.
# DRO/display faces: Montserrat (LVGL family). display_l=44 Medium→dro40;
# display_m work digits: Regular 32 (not Bold 36 — Bold overflowed unit lane).
# ui28 stays Noto 28 for headlines.
FACES = [
    ("ui14", "NotoSans-Regular.ttf", 14, 14, 18),
    ("ui14m", "NotoSans-Medium.ttf", 14, 14, 18),
    ("ui16", "NotoSans-Medium.ttf", 16, 16, 22),
    ("ui16b", "NotoSans-Bold.ttf", 16, 16, 22),
    ("ui22", "Montserrat-Bold.ttf", 22, 28, 28),
    ("ui28", "NotoSans-Bold.ttf", 28, 30, 36),
    ("ui36", "Montserrat-Regular.ttf", 32, 36, 40),
    ("dro40", "Montserrat-Medium.ttf", 44, 52, 56),
]

# Phosphor PNGs → Id (24px bake). Prefer fill for actions, light for chrome.
ICONS = [
    ("power", "light", "power-light.png"),
    ("gear", "light", "gear-six-light.png"),
    ("play", "fill", "play-fill.png"),
    ("pause", "fill", "pause-fill.png"),
    ("spindle", "fill", "arrows-clockwise-fill.png"),
    ("coolant", "fill", "drop-fill.png"),
    ("fan", "fill", "fan-fill.png"),
    ("house", "fill", "house-fill.png"),
    ("house_light", "light", "house-light.png"),
    ("wifi", "light", "wifi-high-light.png"),
    ("lightning", "fill", "lightning-fill.png"),
    ("zero", "fill", "number-circle-zero-fill.png"),
    ("gamepad", "light", "joystick-light.png"),
    ("broadcast", "light", "broadcast-light.png"),
    # Status-bar vertical pack (level + charge + fault). `battery` = Power tab.
    ("battery", "light", "battery-vertical-high-light.png"),
    ("battery_full", "light", "battery-vertical-full-light.png"),
    ("battery_high", "light", "battery-vertical-high-light.png"),
    ("battery_medium", "light", "battery-vertical-medium-light.png"),
    ("battery_low", "light", "battery-vertical-low-light.png"),
    ("battery_empty", "light", "battery-vertical-empty-light.png"),
    ("battery_charging", "light", "battery-charging-vertical-light.png"),
    ("battery_warning", "light", "battery-warning-vertical-light.png"),
    ("battery_plus", "light", "battery-plus-vertical-light.png"),
    ("usb", "light", "usb-light.png"),
    ("bluetooth", "light", "bluetooth-light.png"),
    ("arrow_up", "fill", "arrow-up-fill.png"),
    ("arrow_down", "fill", "arrow-down-fill.png"),
    ("stop", "fill", "stop-fill.png"),
    ("mist", "fill", "cloud-fill.png"),
    ("led", "fill", "lightbulb-fill.png"),
    ("scroll", "fill", "scroll-fill.png"),
    ("search", "light", "magnifying-glass-light.png"),
    ("check", "bold", "check-bold.png"),
    ("caret_right", "light", "caret-right-light.png"),
    ("cpu", "light", "cpu-light.png"),
    ("paint_roller", "light", "paint-roller-light.png"),
    ("speaker_hifi", "light", "speaker-hifi-light.png"),
    ("lock_key", "light", "lock-key-light.png"),
    ("hard_drives", "light", "hard-drives-light.png"),
    ("clipboard_text", "light", "clipboard-text-light.png"),
    ("cards_three", "fill", "cards-three-fill.png"),
    ("rss_simple", "light", "rss-simple-light.png"),
    ("airplane", "light", "airplane-light.png"),
    ("speaker_slash", "light", "speaker-slash-light.png"),
    ("speedometer", "light", "speedometer-light.png"),
    # Zigbee device purpose tiles (QS)
    ("warning_diamond", "light", "warning-diamond-light.png"),
    ("person_simple_run", "light", "person-simple-run-light.png"),
    ("thermometer_simple", "light", "thermometer-simple-light.png"),
    ("lightbulb_filament", "light", "lightbulb-filament-light.png"),
    ("plugs", "light", "plugs-light.png"),
    ("security_camera", "light", "security-camera-light.png"),
    ("lightning_a", "light", "lightning-a-light.png"),
    ("hand_withdraw", "light", "hand-withdraw-light.png"),
]
ICON_SIZE = 24


def zig_bytes(data: bytes, per_line: int = 24) -> str:
    lines = []
    for i in range(0, len(data), per_line):
        chunk = data[i : i + per_line]
        lines.append("    " + ", ".join(f"0x{b:02X}" for b in chunk) + ",")
    return "\n".join(lines)


def render_face(name: str, ttf: Path, px: int, cell_w: int, cell_h: int) -> tuple[bytes, list[int]]:
    font = ImageFont.truetype(str(ttf), px)
    atlas = bytearray(NCHARS * cell_w * cell_h)
    advances: list[int] = []
    for i, code in enumerate(range(FIRST, LAST + 1)):
        ch = chr(code)
        img = Image.new("L", (cell_w, cell_h), 0)
        draw = ImageDraw.Draw(img)
        bbox = font.getbbox(ch)
        # Left-align to pen at x=0 (clip rare negative bearings). Never center —
        # centering + ink-width advance made gaps depend on neighboring glyph padding.
        th = bbox[3] - bbox[1]
        y = max(0, (cell_h - th) // 2 - bbox[1])
        draw.text((0, y), ch, font=font, fill=255)
        raw = img.tobytes()
        off = i * cell_w * cell_h
        atlas[off : off + len(raw)] = raw
        adv = max(1, int(round(font.getlength(ch))))
        if ch == " ":
            adv = max(adv, max(4, px // 3))
        if adv > cell_w:
            raise SystemExit(
                f"{name} glyph {ch!r} advance {adv} > cell_w {cell_w} — widen FACES cell"
            )
        advances.append(adv)
    return bytes(atlas), advances


def write_font_zig(faces: dict) -> None:
    path = OUT / "font_noto.zig"
    parts = [
        "//! Generated Noto Sans A8 glyph cells — do not hand-edit.",
        "//! Regenerate: python scripts/gen_ui_noto_phosphor.py",
        "",
        "pub const first_code: u8 = 32;",
        "pub const last_code: u8 = 126;",
        f"pub const nchars: usize = {NCHARS};",
        "",
        f"pub const Face = enum {{ {', '.join(faces.keys())} }};",
        "",
    ]
    for name, (cw, ch, atlas, adv) in faces.items():
        n = len(atlas)
        parts.append(f"pub const {name}_cell_w: u8 = {cw};")
        parts.append(f"pub const {name}_cell_h: u8 = {ch};")
        parts.append(f"pub const {name}_atlas: [{n}]u8 = .{{")
        parts.append(zig_bytes(atlas))
        parts.append("};")
        parts.append(f"pub const {name}_advance: [{NCHARS}]u8 = .{{")
        parts.append("    " + ", ".join(str(a) for a in adv) + ",")
        parts.append("};")
        parts.append("")

    parts += [
        "pub fn cellSize(face: Face) struct { w: u8, h: u8 } {",
        "    return switch (face) {",
    ]
    for name in faces:
        parts.append(f"        .{name} => .{{ .w = {name}_cell_w, .h = {name}_cell_h }},")
    parts += [
        "    };",
        "}",
        "",
        "pub fn atlasPtr(face: Face) []const u8 {",
        "    return switch (face) {",
    ]
    for name in faces:
        parts.append(f"        .{name} => &{name}_atlas,")
    parts += [
        "    };",
        "}",
        "",
        "pub fn advanceOf(face: Face, ch: u8) u8 {",
        "    if (ch < first_code or ch > last_code) return cellSize(face).w;",
        "    const i = ch - first_code;",
        "    return switch (face) {",
    ]
    for name in faces:
        parts.append(f"        .{name} => {name}_advance[i],")
    parts += [
        "    };",
        "}",
        "",
    ]
    path.write_text("\n".join(parts), encoding="utf-8")
    print("wrote", path, path.stat().st_size)


def png_to_a8(path: Path, size: int) -> bytes:
    im = Image.open(path).convert("RGBA")
    im = im.resize((size, size), Image.Resampling.LANCZOS)
    out = bytearray(size * size)
    px = im.load()
    for y in range(size):
        for x in range(size):
            r, g, b, a = px[x, y]
            # Prefer alpha; fall back to luminance for opaque black icons
            if a < 8:
                v = 0
            else:
                lum = (r + g + b) // 3
                v = min(255, (a * max(lum, 255 - lum // 4)) // 255)
                if v < 16 and a > 128:
                    v = a  # thin stroke icons
            out[y * size + x] = v
    return bytes(out)


def write_icons_zig(icons: list[tuple[str, bytes]]) -> None:
    path = OUT / "icons_phosphor.zig"
    n = ICON_SIZE * ICON_SIZE
    parts = [
        "//! Generated Phosphor A8 24px icons — do not hand-edit.",
        "//! Regenerate: python scripts/gen_ui_noto_phosphor.py",
        "",
        "const color = @import(\"color.zig\");",
        "const fb = @import(\"fb.zig\");",
        "",
        f"pub const size: i32 = {ICON_SIZE};",
        "",
        "pub const Id = enum { " + ", ".join(n for n, _ in icons) + " };",
        "",
    ]
    for name, data in icons:
        parts.append(f"const {name}_map: [{n}]u8 = .{{")
        parts.append(zig_bytes(data, ICON_SIZE))
        parts.append("};")
        parts.append("")

    parts.append("fn mapFor(id: Id) *const [%d]u8 {" % n)
    parts.append("    return switch (id) {")
    for name, _ in icons:
        parts.append(f"        .{name} => &{name}_map,")
    parts += [
        "    };",
        "}",
        "",
        "pub fn draw(logical: *fb.LogicalFb, x: i32, y: i32, id: Id, fg: color.Rgb565) void {",
        "    const data = mapFor(id);",
        "    var row: i32 = 0;",
        "    while (row < size) : (row += 1) {",
        "        var col: i32 = 0;",
        "        while (col < size) : (col += 1) {",
        "            const a = data[@as(usize, @intCast(row)) * @as(usize, size) + @as(usize, @intCast(col))];",
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
        "/// Center ink bbox on (cx, cy) — Phosphor pads unevenly in the cell.",
        "pub fn drawCentered(logical: *fb.LogicalFb, cx: i32, cy: i32, id: Id, fg: color.Rgb565) void {",
        "    drawCenteredScaled(logical, cx, cy, id, fg, size);",
        "}",
        "",
        "/// Nearest-neighbor scale of atlas; ink bbox centered on (cx, cy).",
        "pub fn drawCenteredScaled(logical: *fb.LogicalFb, cx: i32, cy: i32, id: Id, fg: color.Rgb565, out_size: i32) void {",
        "    if (out_size <= 0) return;",
        "    if (out_size == size) {",
        "        const data = mapFor(id);",
        "        var min_c: i32 = size;",
        "        var min_r: i32 = size;",
        "        var max_c: i32 = -1;",
        "        var max_r: i32 = -1;",
        "        var row: i32 = 0;",
        "        while (row < size) : (row += 1) {",
        "            var col: i32 = 0;",
        "            while (col < size) : (col += 1) {",
        "                const a = data[@as(usize, @intCast(row)) * @as(usize, size) + @as(usize, @intCast(col))];",
        "                if (a < 32) continue;",
        "                if (col < min_c) min_c = col;",
        "                if (row < min_r) min_r = row;",
        "                if (col > max_c) max_c = col;",
        "                if (row > max_r) max_r = row;",
        "            }",
        "        }",
        "        if (max_c < 0) {",
        "            draw(logical, cx - @divTrunc(size, 2), cy - @divTrunc(size, 2), id, fg);",
        "            return;",
        "        }",
        "        const cw = max_c - min_c + 1;",
        "        const ch = max_r - min_r + 1;",
        "        draw(logical, cx - min_c - @divTrunc(cw, 2), cy - min_r - @divTrunc(ch, 2), id, fg);",
        "        return;",
        "    }",
        "",
        "    const data = mapFor(id);",
        "    var min_c: i32 = size;",
        "    var min_r: i32 = size;",
        "    var max_c: i32 = -1;",
        "    var max_r: i32 = -1;",
        "    var row: i32 = 0;",
        "    while (row < size) : (row += 1) {",
        "        var col: i32 = 0;",
        "        while (col < size) : (col += 1) {",
        "            const a = data[@as(usize, @intCast(row)) * @as(usize, size) + @as(usize, @intCast(col))];",
        "            if (a < 32) continue;",
        "            if (col < min_c) min_c = col;",
        "            if (row < min_r) min_r = row;",
        "            if (col > max_c) max_c = col;",
        "            if (row > max_r) max_r = row;",
        "        }",
        "    }",
        "    const ink_w = if (max_c >= 0) max_c - min_c + 1 else size;",
        "    const ink_h = if (max_c >= 0) max_r - min_r + 1 else size;",
        "    const scaled_w = @divTrunc(ink_w * out_size, size);",
        "    const scaled_h = @divTrunc(ink_h * out_size, size);",
        "    const dest_x0 = cx - @divTrunc(scaled_w, 2);",
        "    const dest_y0 = cy - @divTrunc(scaled_h, 2);",
        "    var dy: i32 = 0;",
        "    while (dy < scaled_h) : (dy += 1) {",
        "        var dx: i32 = 0;",
        "        while (dx < scaled_w) : (dx += 1) {",
        "            const sx = min_c + @divTrunc(dx * size, out_size);",
        "            const sy = min_r + @divTrunc(dy * size, out_size);",
        "            if (sx < 0 or sy < 0 or sx >= size or sy >= size) continue;",
        "            const a = data[@as(usize, @intCast(sy)) * @as(usize, size) + @as(usize, @intCast(sx))];",
        "            if (a == 0) continue;",
        "            const px = dest_x0 + dx;",
        "            const py = dest_y0 + dy;",
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
        'test "phosphor icon draws" {',
        '    const std = @import("std");',
        "    const gpa = std.testing.allocator;",
        "    var logical = try fb.LogicalFb.alloc(gpa);",
        "    defer logical.deinit(gpa);",
        "    draw(&logical, 0, 0, .house, color.Rgb565.fromHex(0xFFFFFF));",
        "    var found = false;",
        "    var yy: i32 = 0;",
        "    while (yy < size) : (yy += 1) {",
        "        var xx: i32 = 0;",
        "        while (xx < size) : (xx += 1) {",
        "            if (logical.get(xx, yy).toU16() != 0) found = true;",
        "        }",
        "    }",
        "    try std.testing.expect(found);",
        "}",
        "",
    ]
    path.write_text("\n".join(parts), encoding="utf-8")
    print("wrote", path, path.stat().st_size)


def main() -> None:
    icons_only = "--icons-only" in sys.argv
    if not icons_only:
        faces = {}
        for name, ttf_name, px, cw, ch in FACES:
            ttf = NOTO_DIR / ttf_name
            if not ttf.exists():
                raise SystemExit(f"missing font: {ttf}")
            atlas, adv = render_face(name, ttf, px, cw, ch)
            faces[name] = (cw, ch, atlas, adv)
            print(f"face {name}: {len(atlas)} bytes")
        write_font_zig(faces)

    icons = []
    for name, style, file in ICONS:
        p = PHOSPHOR / "PNGs" / style / file
        if not p.exists():
            raise SystemExit(f"missing icon: {p}")
        icons.append((name, png_to_a8(p, ICON_SIZE)))
        print(f"icon {name}: {p.name}")
    write_icons_zig(icons)


if __name__ == "__main__":
    main()
