#!/usr/bin/env python3
"""Emit src/modulus/ui_engine/hct.zig — Cam16/HCT/TonalPalette (MCU DEFAULT VC).

Requires: pip install materialyoucolor
Regenerate: python scripts/gen_hct_zig.py
"""
from __future__ import annotations

from pathlib import Path

from materialyoucolor.hct.hct_solver import HctSolver

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "src" / "modulus" / "ui_engine" / "hct.zig"

# ViewingConditions.DEFAULT (materialyoucolor)
VC = {
    "n": 0.18418651851244416,
    "aw": 29.980997194447333,
    "nbb": 1.0169191804458755,
    "ncb": 1.0169191804458755,
    "c": 0.69,
    "nc": 1.0,
    "rgb_d0": 1.02117770275752,
    "rgb_d1": 0.9863077294280124,
    "rgb_d2": 0.9339605082802299,
    "fl": 0.3884814537800353,
    "f_l_root": 0.7894826179304937,
    "z": 1.909169568483652,
}


def zig_f64_array(name: str, values: list[float], per: int = 4) -> str:
    lines = [f"const {name} = [_]f64{{"]
    for i in range(0, len(values), per):
        chunk = values[i : i + per]
        lines.append("    " + ", ".join(f"{v:.16g}" for v in chunk) + ",")
    lines.append("};")
    return "\n".join(lines)


def main() -> None:
    planes = list(HctSolver.CRITICAL_PLANES)
    body = f'''//! Generated HCT / Cam16 / TonalPalette (Material Color Utilities, DEFAULT VC).
//! Apache-2.0 Material Foundation algorithms. Regenerate: python scripts/gen_hct_zig.py
//! Do not hand-edit.

const std = @import("std");

const vc_n: f64 = {VC["n"]:.16g};
const vc_aw: f64 = {VC["aw"]:.16g};
const vc_nbb: f64 = {VC["nbb"]:.16g};
const vc_ncb: f64 = {VC["ncb"]:.16g};
const vc_c: f64 = {VC["c"]:.16g};
const vc_nc: f64 = {VC["nc"]:.16g};
const vc_rgb_d = [_]f64{{ {VC["rgb_d0"]:.16g}, {VC["rgb_d1"]:.16g}, {VC["rgb_d2"]:.16g} }};
const vc_fl: f64 = {VC["fl"]:.16g};
const vc_f_l_root: f64 = {VC["f_l_root"]:.16g};
const vc_z: f64 = {VC["z"]:.16g};

{zig_f64_array("critical_planes", planes)}

const scaled_discount_from_linrgb = [_][3]f64{{
    .{{ 0.001200833568784504, 0.002389694492170889, 0.0002795742885861124 }},
    .{{ 0.0005891086651375999, 0.0029785502573438758, 0.0003270666104008398 }},
    .{{ 0.00010146692491640572, 0.0005364214359186694, 0.0032979401770712076 }},
}};
const linrgb_from_scaled_discount = [_][3]f64{{
    .{{ 1373.2198709594231, -1100.4251190754821, -7.278681089101213 }},
    .{{ -271.815969077903, 559.6580465940733, -32.46047482791194 }},
    .{{ 1.9622899599665666, -57.173814538844006, 308.7233197812385 }},
}};
const y_from_linrgb = [_]f64{{ 0.2126, 0.7152, 0.0722 }};
const xyz_to_srgb = [_][3]f64{{
    .{{ 3.2413774792388685, -1.5373329694897852, -0.49861121901076274 }},
    .{{ -0.9692436362808797, 1.8759675015077204, 0.04155505703236188 }},
    .{{ 0.05563007969699361, -0.20397695888897652, 1.0569715142428786 }},
}};

pub const Hct = struct {{
    hue: f64,
    chroma: f64,
    tone: f64,
    argb: u32,

    pub fn fromInt(argb: u32) Hct {{
        const cam = camFromArgb(argb);
        return .{{
            .hue = cam.hue,
            .chroma = cam.chroma,
            .tone = lstarFromArgb(argb),
            .argb = argb,
        }};
    }}

    pub fn from(hue: f64, chroma: f64, tone: f64) Hct {{
        return fromInt(solveToInt(hue, chroma, tone));
    }}

    pub fn toRgb24(self: Hct) u24 {{
        return @truncate(self.argb & 0xffffff);
    }}
}};

pub const TonalPalette = struct {{
    hue: f64,
    chroma: f64,

    pub fn fromHueAndChroma(hue: f64, chroma: f64) TonalPalette {{
        return .{{ .hue = sanitizeDegrees(hue), .chroma = chroma }};
    }}

    pub fn fromArgb(argb: u32) TonalPalette {{
        const h = Hct.fromInt(argb);
        return fromHueAndChroma(h.hue, h.chroma);
    }}

    /// ARGB with alpha 0xFF. Tone is L* 0..100.
    pub fn tone(self: TonalPalette, t: f64) u32 {{
        return solveToInt(self.hue, self.chroma, t);
    }}

    pub fn toneRgb24(self: TonalPalette, t: f64) u24 {{
        return @truncate(self.tone(t) & 0xffffff);
    }}
}};

const Cam = struct {{ hue: f64, chroma: f64, j: f64 }};

fn signum(x: f64) f64 {{
    if (x < 0) return -1;
    if (x > 0) return 1;
    return 0;
}}

fn sanitizeDegrees(d: f64) f64 {{
    var x = @mod(d, 360.0);
    if (x < 0) x += 360.0;
    return x;
}}

fn sanitizeRadians(angle: f64) f64 {{
    return @mod(angle + std.math.pi * 8.0, std.math.pi * 2.0);
}}

fn clampInt(lo: i32, hi: i32, x: i32) i32 {{
    return @max(lo, @min(hi, x));
}}

fn linearized(comp: i32) f64 {{
    const normalized = @as(f64, @floatFromInt(comp)) / 255.0;
    if (normalized <= 0.040449936) return normalized / 12.92 * 100.0;
    return std.math.pow(f64, (normalized + 0.055) / 1.055, 2.4) * 100.0;
}}

fn delinearized(comp: f64) i32 {{
    const normalized = comp / 100.0;
    const d = if (normalized <= 0.0031308)
        normalized * 12.92
    else
        1.055 * std.math.pow(f64, normalized, 1.0 / 2.4) - 0.055;
    return clampInt(0, 255, @intFromFloat(@round(d * 255.0)));
}}

fn argbFromRgb(r: i32, g: i32, b: i32) u32 {{
    return 0xff000000 |
        (@as(u32, @intCast(r)) << 16) |
        (@as(u32, @intCast(g)) << 8) |
        @as(u32, @intCast(b));
}}

fn argbFromLinrgb(lin: [3]f64) u32 {{
    return argbFromRgb(delinearized(lin[0]), delinearized(lin[1]), delinearized(lin[2]));
}}

fn labF(t: f64) f64 {{
    const e = 216.0 / 24389.0;
    const kappa = 24389.0 / 27.0;
    if (t > e) return std.math.cbrt(t);
    return (kappa * t + 16.0) / 116.0;
}}

fn labInvf(ft: f64) f64 {{
    const e = 216.0 / 24389.0;
    const kappa = 24389.0 / 27.0;
    const ft3 = ft * ft * ft;
    if (ft3 > e) return ft3;
    return (116.0 * ft - 16.0) / kappa;
}}

fn yFromLstar(lstar: f64) f64 {{
    return 100.0 * labInvf((lstar + 16.0) / 116.0);
}}

fn argbFromLstar(lstar: f64) u32 {{
    const y = yFromLstar(lstar);
    const c = delinearized(y);
    return argbFromRgb(c, c, c);
}}

fn lstarFromArgb(argb: u32) f64 {{
    const r = linearized(@intCast((argb >> 16) & 0xff));
    const g = linearized(@intCast((argb >> 8) & 0xff));
    const b = linearized(@intCast(argb & 0xff));
    const y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    return 116.0 * labF(y / 100.0) - 16.0;
}}

fn matrixMul(row: [3]f64, mat: [3][3]f64) [3]f64 {{
    return .{{
        mat[0][0] * row[0] + mat[0][1] * row[1] + mat[0][2] * row[2],
        mat[1][0] * row[0] + mat[1][1] * row[1] + mat[1][2] * row[2],
        mat[2][0] * row[0] + mat[2][1] * row[1] + mat[2][2] * row[2],
    }};
}}

fn camFromArgb(argb: u32) Cam {{
    const red_l = linearized(@intCast((argb >> 16) & 0xff));
    const green_l = linearized(@intCast((argb >> 8) & 0xff));
    const blue_l = linearized(@intCast(argb & 0xff));
    const x = 0.41233895 * red_l + 0.35762064 * green_l + 0.18051042 * blue_l;
    const y = 0.2126 * red_l + 0.7152 * green_l + 0.0722 * blue_l;
    const z = 0.01932141 * red_l + 0.11916382 * green_l + 0.95034478 * blue_l;

    const r_c = 0.401288 * x + 0.650173 * y - 0.051461 * z;
    const g_c = -0.250268 * x + 1.204414 * y + 0.045854 * z;
    const b_c = -0.002079 * x + 0.048952 * y + 0.953127 * z;

    const r_d = vc_rgb_d[0] * r_c;
    const g_d = vc_rgb_d[1] * g_c;
    const b_d = vc_rgb_d[2] * b_c;

    const r_af = std.math.pow(f64, (vc_fl * @abs(r_d)) / 100.0, 0.42);
    const g_af = std.math.pow(f64, (vc_fl * @abs(g_d)) / 100.0, 0.42);
    const b_af = std.math.pow(f64, (vc_fl * @abs(b_d)) / 100.0, 0.42);

    const r_a = (signum(r_d) * 400.0 * r_af) / (r_af + 27.13);
    const g_a = (signum(g_d) * 400.0 * g_af) / (g_af + 27.13);
    const b_a = (signum(b_d) * 400.0 * b_af) / (b_af + 27.13);

    const a = (11.0 * r_a + -12.0 * g_a + b_a) / 11.0;
    const b = (r_a + g_a - 2.0 * b_a) / 9.0;
    const u = (20.0 * r_a + 20.0 * g_a + 21.0 * b_a) / 20.0;
    const p2 = (40.0 * r_a + 20.0 * g_a + b_a) / 20.0;
    const hue = sanitizeDegrees(std.math.atan2(b, a) * 180.0 / std.math.pi);

    const ac = p2 * vc_nbb;
    const j = 100.0 * std.math.pow(f64, ac / vc_aw, vc_c * vc_z);
    const hue_prime = if (hue < 20.14) hue + 360.0 else hue;
    const e_hue = 0.25 * (std.math.cos(hue_prime * std.math.pi / 180.0 + 2.0) + 3.8);
    const p1 = (50000.0 / 13.0) * e_hue * vc_nc * vc_ncb;
    const t = (p1 * @sqrt(a * a + b * b)) / (u + 0.305);
    const alpha = std.math.pow(f64, t, 0.9) * std.math.pow(f64, 1.64 - std.math.pow(f64, 0.29, vc_n), 0.73);
    const chroma = alpha * @sqrt(j / 100.0);
    return .{{ .hue = hue, .chroma = chroma, .j = j }};
}}

fn trueDelinearized(rgb_component: f64) f64 {{
    const normalized = rgb_component / 100.0;
    const d = if (normalized <= 0.0031308)
        normalized * 12.92
    else
        1.055 * std.math.pow(f64, normalized, 1.0 / 2.4) - 0.055;
    return d * 255.0;
}}

fn chromaticAdaptation(component: f64) f64 {{
    const af = std.math.pow(f64, @abs(component), 0.42);
    return signum(component) * 400.0 * af / (af + 27.13);
}}

fn inverseChromaticAdaptation(adapted: f64) f64 {{
    const adapted_abs = @abs(adapted);
    const base = @max(0.0, 27.13 * adapted_abs / (400.0 - adapted_abs));
    return signum(adapted) * std.math.pow(f64, base, 1.0 / 0.42);
}}

fn hueOf(linrgb: [3]f64) f64 {{
    const scaled = matrixMul(linrgb, scaled_discount_from_linrgb);
    const r_a = chromaticAdaptation(scaled[0]);
    const g_a = chromaticAdaptation(scaled[1]);
    const b_a = chromaticAdaptation(scaled[2]);
    const a = (11.0 * r_a + -12.0 * g_a + b_a) / 11.0;
    const b = (r_a + g_a - 2.0 * b_a) / 9.0;
    return std.math.atan2(b, a);
}}

fn areInCyclicOrder(a: f64, b: f64, c: f64) bool {{
    return sanitizeRadians(b - a) < sanitizeRadians(c - a);
}}

fn intercept(source: f64, mid: f64, target: f64) f64 {{
    return (mid - source) / (target - source);
}}

fn lerpPoint(source: [3]f64, t: f64, target: [3]f64) [3]f64 {{
    return .{{
        source[0] + (target[0] - source[0]) * t,
        source[1] + (target[1] - source[1]) * t,
        source[2] + (target[2] - source[2]) * t,
    }};
}}

fn setCoordinate(source: [3]f64, coordinate: f64, target: [3]f64, axis: usize) [3]f64 {{
    const t = intercept(source[axis], coordinate, target[axis]);
    return lerpPoint(source, t, target);
}}

fn isBounded(x: f64) bool {{
    return x >= 0.0 and x <= 100.0;
}}

fn nthVertex(y: f64, n: i32) [3]f64 {{
    const kr = y_from_linrgb[0];
    const kg = y_from_linrgb[1];
    const kb = y_from_linrgb[2];
    const coord_a: f64 = if (@mod(n, 4) <= 1) 0.0 else 100.0;
    const coord_b: f64 = if (@mod(n, 2) == 0) 0.0 else 100.0;
    if (n < 4) {{
        const g = coord_a;
        const b = coord_b;
        const r = (y - g * kg - b * kb) / kr;
        if (isBounded(r)) return .{{ r, g, b }};
        return .{{ -1, -1, -1 }};
    }} else if (n < 8) {{
        const b = coord_a;
        const r = coord_b;
        const g = (y - r * kr - b * kb) / kg;
        if (isBounded(g)) return .{{ r, g, b }};
        return .{{ -1, -1, -1 }};
    }} else {{
        const r = coord_a;
        const g = coord_b;
        const b = (y - r * kr - g * kg) / kb;
        if (isBounded(b)) return .{{ r, g, b }};
        return .{{ -1, -1, -1 }};
    }}
}}

fn bisectToSegment(y: f64, target_hue: f64) struct {{ left: [3]f64, right: [3]f64 }} {{
    var left = [_]f64{{ -1, -1, -1 }};
    var right = left;
    var left_hue: f64 = 0;
    var right_hue: f64 = 0;
    var initialized = false;
    var uncut = true;
    var n: i32 = 0;
    while (n < 12) : (n += 1) {{
        const mid = nthVertex(y, n);
        if (mid[0] < 0) continue;
        const mid_hue = hueOf(mid);
        if (!initialized) {{
            left = mid;
            right = mid;
            left_hue = mid_hue;
            right_hue = mid_hue;
            initialized = true;
            continue;
        }}
        if (uncut or areInCyclicOrder(left_hue, mid_hue, right_hue)) {{
            uncut = false;
            if (areInCyclicOrder(left_hue, target_hue, mid_hue)) {{
                right = mid;
                right_hue = mid_hue;
            }} else {{
                left = mid;
                left_hue = mid_hue;
            }}
        }}
    }}
    return .{{ .left = left, .right = right }};
}}

fn bisectToLimit(y: f64, target_hue: f64) [3]f64 {{
    const segment = bisectToSegment(y, target_hue);
    var left = segment.left;
    var left_hue = hueOf(left);
    var right = segment.right;
    var axis: usize = 0;
    while (axis < 3) : (axis += 1) {{
        if (left[axis] == right[axis]) continue;
        var l_plane: f64 = undefined;
        var r_plane: f64 = undefined;
        if (left[axis] < right[axis]) {{
            l_plane = @floor(trueDelinearized(left[axis]) - 0.5);
            r_plane = @ceil(trueDelinearized(right[axis]) - 0.5);
        }} else {{
            l_plane = @ceil(trueDelinearized(left[axis]) - 0.5);
            r_plane = @floor(trueDelinearized(right[axis]) - 0.5);
        }}
        var i: i32 = 0;
        while (i < 8) : (i += 1) {{
            if (@abs(r_plane - l_plane) <= 1) break;
            const m_plane = @floor((l_plane + r_plane) / 2.0);
            const mid_plane_coordinate = critical_planes[@intFromFloat(m_plane)];
            const mid = setCoordinate(left, mid_plane_coordinate, right, axis);
            const mid_hue = hueOf(mid);
            if (areInCyclicOrder(left_hue, target_hue, mid_hue)) {{
                right = mid;
                r_plane = m_plane;
            }} else {{
                left = mid;
                left_hue = mid_hue;
                l_plane = m_plane;
            }}
        }}
    }}
    return .{{
        (left[0] + right[0]) / 2.0,
        (left[1] + right[1]) / 2.0,
        (left[2] + right[2]) / 2.0,
    }};
}}

fn findResultByJ(hue_radians: f64, chroma: f64, y: f64) u32 {{
    var j = @sqrt(y) * 11.0;
    const t_inner_coeff = 1.0 / std.math.pow(f64, 1.64 - std.math.pow(f64, 0.29, vc_n), 0.73);
    const e_hue = 0.25 * (std.math.cos(hue_radians + 2.0) + 3.8);
    const p1 = e_hue * (50000.0 / 13.0) * vc_nc * vc_ncb;
    const h_sin = std.math.sin(hue_radians);
    const h_cos = std.math.cos(hue_radians);
    var iteration_round: i32 = 0;
    while (iteration_round < 5) : (iteration_round += 1) {{
        const j_normalized = j / 100.0;
        const alpha = if (chroma != 0.0 and j != 0.0) chroma / @sqrt(j_normalized) else 0.0;
        const t = std.math.pow(f64, alpha * t_inner_coeff, 1.0 / 0.9);
        const ac = vc_aw * std.math.pow(f64, j_normalized, 1.0 / vc_c / vc_z);
        const p2 = ac / vc_nbb;
        const gamma = 23.0 * (p2 + 0.305) * t / (23.0 * p1 + 11.0 * t * h_cos + 108.0 * t * h_sin);
        const a = gamma * h_cos;
        const b = gamma * h_sin;
        const r_a = (460.0 * p2 + 451.0 * a + 288.0 * b) / 1403.0;
        const g_a = (460.0 * p2 - 891.0 * a - 261.0 * b) / 1403.0;
        const b_a = (460.0 * p2 - 220.0 * a - 6300.0 * b) / 1403.0;
        const linrgb = matrixMul(.{{
            inverseChromaticAdaptation(r_a),
            inverseChromaticAdaptation(g_a),
            inverseChromaticAdaptation(b_a),
        }}, linrgb_from_scaled_discount);
        if (linrgb[0] < 0 or linrgb[1] < 0 or linrgb[2] < 0) return 0;
        const fnj = y_from_linrgb[0] * linrgb[0] + y_from_linrgb[1] * linrgb[1] + y_from_linrgb[2] * linrgb[2];
        if (fnj <= 0) return 0;
        if (iteration_round == 4 or @abs(fnj - y) < 0.002) {{
            if (linrgb[0] > 100.01 or linrgb[1] > 100.01 or linrgb[2] > 100.01) return 0;
            return argbFromLinrgb(linrgb);
        }}
        j = j - (fnj - y) * j / (2.0 * fnj);
    }}
    return 0;
}}

fn solveToInt(hue_degrees: f64, chroma: f64, lstar: f64) u32 {{
    if (chroma < 0.0001 or lstar < 0.0001 or lstar > 99.9999) return argbFromLstar(lstar);
    const hue = sanitizeDegrees(hue_degrees);
    const hue_radians = hue / 180.0 * std.math.pi;
    const y = yFromLstar(lstar);
    const exact = findResultByJ(hue_radians, chroma, y);
    if (exact != 0) return exact;
    return argbFromLinrgb(bisectToLimit(y, hue_radians));
}}

test "hct roundtrip seed teal" {{
    const h = Hct.fromInt(0xff00BCD4);
    try std.testing.expect(@abs(h.hue - 212.44) < 0.5);
    try std.testing.expect(@abs(h.chroma - 49.96) < 0.5);
    const p = TonalPalette.fromHueAndChroma(h.hue, h.chroma);
    try std.testing.expectEqual(@as(u24, 0x006876), p.toneRgb24(40));
    try std.testing.expectEqual(@as(u24, 0x44D8F1), p.toneRgb24(80));
}}
'''
    # Drop unused xyz_to_srgb to keep file lean (argb_from_xyz not needed for tone path)
    body = body.replace(
        "const xyz_to_srgb = [_][3]f64{\n"
        "    .{ 3.2413774792388685, -1.5373329694897852, -0.49861121901076274 },\n"
        "    .{ -0.9692436362808797, 1.8759675015077204, 0.04155505703236188 },\n"
        "    .{ 0.05563007969699361, -0.20397695888897652, 1.0569715142428786 },\n"
        "};\n\n",
        "",
    )
    OUT.write_text(body, encoding="utf-8")
    print("wrote", OUT, OUT.stat().st_size)


if __name__ == "__main__":
    main()
