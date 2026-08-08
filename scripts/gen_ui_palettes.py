#!/usr/bin/env python3
"""Generate MD3 tonal palette tables for Modulus Tab5 UI (9 accents x light/dark).

Enforces WCAG AA (≥4.5:1) for chroma roles and accent-tinted surface inks
(on_surface / outline family) against each scheme's background.
"""

from __future__ import annotations

import colorsys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "firmware/tab5/components/modulus_zig/include/ui_palette_schemes.h"

# name, dark_bg, dark_seed, light_bg, light_seed
ACCENTS = [
    ("Industrial Teal", 0x101417, 0x4DD0E1, 0xF0F2F5, 0x00838F),
    ("Cyber-Industrial", 0x1A1C1E, 0x00D4FF, 0xF0F2F5, 0x007BFF),
    ("Nocturnal Safety", 0x121212, 0xFFB300, 0xFFFFFF, 0xE65100),
    ("Deep Sea", 0x0B1117, 0x48BB78, 0xEBF8FF, 0x2F855A),
    ("Steel & Ruby", 0x212121, 0xFF4D4D, 0xF8F9FA, 0xC62828),
    ("Electric Orchid", 0x141414, 0x9D7BFF, 0xF3F0FF, 0x6B46C1),
    ("Tactical Sage", 0x1C1F1A, 0xC5E1A5, 0xF1F8E9, 0x558B2F),
    ("Nordic White", 0x0D1117, 0x58A6FF, 0xFFFFFF, 0x0969DA),
    ("Monochrome Pro", 0x121212, 0xFFFFFF, 0xFFFFFF, 0x000000),
]

ROLES = (
    "primary",
    "on_primary",
    "primary_container",
    "on_primary_container",
    "secondary",
    "on_secondary",
    "secondary_container",
    "on_secondary_container",
    "tertiary",
    "on_tertiary",
    "tertiary_container",
    "on_tertiary_container",
    "on_surface",
    "on_surface_variant",
    "outline",
    "outline_variant",
    "icon_chrome",
    "surface_container_lowest",
    "surface_container_low",
    "surface_container",
    "surface_container_high",
    "surface_container_highest",
)

AA = 4.5
AA_OUTLINE = 3.0  # WCAG UI-component / large text floor


def hex_rgb(h: int) -> tuple[int, int, int]:
    h &= 0xFFFFFF
    return (h >> 16) & 255, (h >> 8) & 255, h & 255


def rgb_hex(r: int, g: int, b: int) -> int:
    return ((r & 255) << 16) | ((g & 255) << 8) | (b & 255)


def _lin(c: float) -> float:
    c /= 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rel_l(h: int) -> float:
    r, g, b = hex_rgb(h)
    return 0.2126 * _lin(r) + 0.7152 * _lin(g) + 0.0722 * _lin(b)


def contrast(a: int, b: int) -> float:
    la, lb = rel_l(a), rel_l(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def on_color(fill: int) -> int:
    return 0x000000 if contrast(0x000000, fill) >= contrast(0xFFFFFF, fill) else 0xFFFFFF


def mix(a: int, b: int, t: float) -> int:
    ar, ag, ab = hex_rgb(a)
    br, bg, bb = hex_rgb(b)
    return rgb_hex(
        int(ar + (br - ar) * t),
        int(ag + (bg - ag) * t),
        int(ab + (bb - ab) * t),
    )


def hsl_hex(h: int) -> tuple[float, float, float]:
    r, g, b = hex_rgb(h)
    return colorsys.rgb_to_hls(r / 255.0, g / 255.0, b / 255.0)


def from_hsl(h: float, l: float, s: float) -> int:
    r, g, b = colorsys.hls_to_rgb(h % 1.0, max(0.0, min(1.0, l)), max(0.0, min(1.0, s)))
    return rgb_hex(int(r * 255), int(g * 255), int(b * 255))


def ensure_aa(fill: int, prefer_darken: bool) -> tuple[int, int]:
    h, l, s = hsl_hex(fill)
    best_fill, best_on, best_c = fill, on_color(fill), contrast(on_color(fill), fill)
    if best_c >= AA:
        return best_fill, best_on
    for step in range(1, 48):
        delta = 0.02 * step
        for sign in ((-1, 1) if prefer_darken else (1, -1)):
            nl = max(0.05, min(0.95, l + sign * delta))
            cand = from_hsl(h, nl, s)
            ink = on_color(cand)
            c = contrast(ink, cand)
            if c > best_c:
                best_fill, best_on, best_c = cand, ink, c
            if c >= AA:
                return cand, ink
    return best_fill, best_on


def pair_container(bg: int, seed: int, t: float) -> tuple[int, int]:
    cont = mix(bg, seed, t)
    ink = on_color(cont)
    if contrast(ink, cont) >= AA:
        return cont, ink
    for t2 in [t + d for d in (0.05, 0.1, 0.15, 0.2, -0.05, -0.1, 0.25, 0.3)]:
        t2 = max(0.08, min(0.75, t2))
        cont = mix(bg, seed, t2)
        ink = on_color(cont)
        if contrast(ink, cont) >= AA:
            return cont, ink
    cont = mix(bg, seed, t)
    return cont, on_color(cont)


def tint_ink(base: int, primary: int, bg: int, tint: float, floor: float) -> int:
    """Mix primary into base ink; reduce tint until contrast(bg) ≥ floor."""
    for t in [tint - i * 0.02 for i in range(0, 12)]:
        t = max(0.0, t)
        cand = mix(base, primary, t)
        if contrast(cand, bg) >= floor:
            return cand
    # last resort: untinted base, or nudge luminance away from bg
    if contrast(base, bg) >= floor:
        return base
    h, l, s = hsl_hex(base)
    prefer_light = rel_l(bg) < 0.5
    for step in range(1, 40):
        nl = min(0.95, l + 0.02 * step) if prefer_light else max(0.05, l - 0.02 * step)
        cand = from_hsl(h, nl, s)
        if contrast(cand, bg) >= floor:
            return cand
    return base


def surface_roles(primary: int, bg: int, dark: bool) -> dict[str, int]:
    if dark:
        on_s = tint_ink(0xDDE3E8, primary, bg, 0.14, AA)
        on_v = tint_ink(0xBFC8CF, primary, bg, 0.12, AA)
        out = tint_ink(0x8A9399, primary, bg, 0.18, AA_OUTLINE)
        chrome = tint_ink(0xE2E2E9, primary, bg, 0.10, AA)
        # MD3 tonal elevation ladder — slight primary tint, baked (not runtime lighten).
        sc_lowest = mix(bg, 0x000000, 0.06)
        sc_low = mix(bg, primary, 0.04)
        sc = mix(bg, primary, 0.08)
        sc_high = mix(bg, primary, 0.12)
        sc_highest = mix(bg, primary, 0.16)
    else:
        on_s = tint_ink(0x1A1C1E, primary, bg, 0.12, AA)
        on_v = tint_ink(0x44474E, primary, bg, 0.10, AA)
        out = tint_ink(0x74777F, primary, bg, 0.16, AA_OUTLINE)
        chrome = tint_ink(0x45464F, primary, bg, 0.10, AA)
        sc_lowest = bg
        sc_low = mix(bg, primary, 0.03)
        sc = mix(bg, primary, 0.06)
        sc_high = mix(bg, primary, 0.10)
        sc_highest = mix(bg, primary, 0.14)
    out_var = mix(out, bg, 0.55 if dark else 0.62)
    return {
        "on_surface": on_s,
        "on_surface_variant": on_v,
        "outline": out,
        "outline_variant": out_var,
        "icon_chrome": chrome,
        "surface_container_lowest": sc_lowest,
        "surface_container_low": sc_low,
        "surface_container": sc,
        "surface_container_high": sc_high,
        "surface_container_highest": sc_highest,
    }


def accent_roles(accent: int, bg: int, dark: bool) -> dict[str, int]:
    h, l, s = hsl_hex(accent)
    primary, on_primary = ensure_aa(accent, prefer_darken=not dark)

    sec_l = l if dark else min(0.42, l)
    secondary = from_hsl(h, sec_l, s * 0.55)
    secondary, on_secondary = ensure_aa(secondary, prefer_darken=not dark)

    ter_h = (h + (0.083 if dark else 0.06)) % 1.0
    tertiary = from_hsl(ter_h, min(0.72, l + (0.08 if dark else 0.0)), min(1.0, s * 0.85))
    tertiary, on_tertiary = ensure_aa(tertiary, prefer_darken=not dark)

    pc_t = 0.34 if dark else 0.22
    sc_t = 0.42 if dark else 0.28
    tc_t = 0.38 if dark else 0.26

    primary_container, on_primary_container = pair_container(bg, primary, pc_t)
    secondary_container, on_secondary_container = pair_container(bg, secondary, sc_t)
    tertiary_container, on_tertiary_container = pair_container(bg, tertiary, tc_t)

    roles = {
        "primary": primary,
        "on_primary": on_primary,
        "primary_container": primary_container,
        "on_primary_container": on_primary_container,
        "secondary": secondary,
        "on_secondary": on_secondary,
        "secondary_container": secondary_container,
        "on_secondary_container": on_secondary_container,
        "tertiary": tertiary,
        "on_tertiary": on_tertiary,
        "tertiary_container": tertiary_container,
        "on_tertiary_container": on_tertiary_container,
    }
    roles.update(surface_roles(primary, bg, dark))
    return roles


PAIR_CHECKS = (
    ("primary", "on_primary", AA),
    ("secondary", "on_secondary", AA),
    ("tertiary", "on_tertiary", AA),
    ("primary_container", "on_primary_container", AA),
    ("secondary_container", "on_secondary_container", AA),
    ("tertiary_container", "on_tertiary_container", AA),
)


def check_roles(name: str, mode: str, bg: int, roles: dict[str, int], fails: list[str]) -> None:
    for fill_k, on_k, floor in PAIR_CHECKS:
        c = contrast(roles[on_k], roles[fill_k])
        if c < floor:
            fails.append(f"{mode} {name} {fill_k}: {c:.2f}")
    for ink_k, floor in (
        ("on_surface", AA),
        ("on_surface_variant", AA),
        ("icon_chrome", AA),
        ("outline", AA_OUTLINE),
    ):
        c = contrast(roles[ink_k], bg)
        if c < floor:
            fails.append(f"{mode} {name} {ink_k}/bg: {c:.2f}")


def emit() -> None:
    lines = [
        "/* Auto-generated by scripts/gen_ui_palettes.py — do not edit. */",
        "#pragma once",
        "",
        "#include <stdint.h>",
        "",
        "typedef struct {",
    ]
    for role in ROLES:
        lines.append(f"    uint32_t {role};")
    lines.append("} ui_accent_scheme_t;")
    lines.append("")
    lines.append("#define MOD_UI_SCHEME_COUNT 9")
    lines.append("")
    lines.append("static const ui_accent_scheme_t k_ui_schemes_dark[MOD_UI_SCHEME_COUNT] = {")

    fails: list[str] = []
    for name, dark_bg, dark_ac, _light_bg, _light_ac in ACCENTS:
        roles = accent_roles(dark_ac, dark_bg, True)
        check_roles(name, "DARK", dark_bg, roles, fails)
        vals = ", ".join(f"0x{roles[r]:06X}u" for r in ROLES)
        lines.append(f"    {{ {vals} }},")

    lines.append("};")
    lines.append("")
    lines.append("static const ui_accent_scheme_t k_ui_schemes_light[MOD_UI_SCHEME_COUNT] = {")

    for name, _dark_bg, _dark_ac, light_bg, light_ac in ACCENTS:
        roles = accent_roles(light_ac, light_bg, False)
        check_roles(name, "LIGHT", light_bg, roles, fails)
        vals = ", ".join(f"0x{roles[r]:06X}u" for r in ROLES)
        lines.append(f"    {{ {vals} }},")

    lines.append("};")
    lines.append("")

    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {OUT}")
    if fails:
        print("AA failures remaining:")
        for f in fails:
            print(" ", f)
        raise SystemExit(1)
    print("All chroma + surface-ink pairs pass AA gates")


if __name__ == "__main__":
    emit()
