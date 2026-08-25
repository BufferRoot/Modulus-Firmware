//! Generated HCT / Cam16 / TonalPalette (Material Color Utilities, DEFAULT VC).
//! Apache-2.0 Material Foundation algorithms. Regenerate: python scripts/gen_hct_zig.py
//! Do not hand-edit.

const std = @import("std");

const vc_n: f64 = 0.1841865185124442;
const vc_aw: f64 = 29.98099719444733;
const vc_nbb: f64 = 1.016919180445875;
const vc_ncb: f64 = 1.016919180445875;
const vc_c: f64 = 0.6899999999999999;
const vc_nc: f64 = 1;
const vc_rgb_d = [_]f64{ 1.02117770275752, 0.9863077294280124, 0.9339605082802299 };
const vc_fl: f64 = 0.3884814537800353;
const vc_f_l_root: f64 = 0.7894826179304937;
const vc_z: f64 = 1.909169568483652;

const critical_planes = [_]f64{
    0.01517634917744188, 0.04552904753232562, 0.07588174588720938, 0.1062344442420931,
    0.1365871425969769, 0.1669398409518606, 0.1972925393067443, 0.2276452376616281,
    0.2579979360165119, 0.2883506343713956, 0.3188300904430532, 0.350925934958123,
    0.3848314933096426, 0.4205748030104947, 0.458183274052838, 0.4976837250274023,
    0.5391024159806381, 0.5824650784040898, 0.6277969426914107, 0.6751227633498623,
    0.7244668422128921, 0.775853049866786, 0.829304845476233, 0.8848452951698498,
    0.942497089126609, 1.002282557486904, 1.064223685197358, 1.12834212588583,
    1.194659214852213, 1.263195981251186, 1.333973159534903, 1.407011200216447,
    1.482330280008642, 1.559950311387327, 1.639890951623368, 1.72217161132341,
    1.806811462515638, 1.893829446313407, 1.983244280186685, 2.075074464868551,
    2.169338290921623, 2.266053844987206, 2.36523901573795, 2.466911499553201,
    2.571088805934576, 2.677788262677979, 2.787027020816926, 2.898822059350997,
    3.013190189772091, 3.130148060400286, 3.249712160540223, 3.371898824468109,
    3.496724235258795, 3.624204428461639, 3.754355295633311, 3.887192587735158,
    4.022731918402185, 4.160988767090289, 4.301978482107941, 4.445716283538092,
    4.592217266055746, 4.741496401646282, 4.893568542229298, 5.048448422192488,
    5.20615066083972, 5.366689764757337, 5.530080130102387, 5.696336044816294,
    5.865471690767354, 6.037501145825082, 6.212438385869475, 6.390297286737924,
    6.571091626112461, 6.754835085349804, 6.941541251256611, 7.131223617812143,
    7.323895587840543, 7.519570474634667, 7.718261503533435, 7.919981813454504,
    8.124744458384042, 8.332562408825165, 8.543448553206703, 8.757415699253682,
    8.974476575321063, 9.194643831691977, 9.417930041841839, 9.644347703669503,
    9.873909240696694, 10.10662700323678, 10.34251326953402, 10.58158024687427,
    10.8238400726681, 11.06930481550736, 11.31798647619601, 11.56989698875601,
    11.82504822140934, 12.08345197753661, 12.34511999661325, 12.61006395512394,
    12.87829546745594, 13.14982608677205, 13.42466730586372, 13.70283055798511,
    13.98432721766851, 14.26916860152183, 14.55736596900856, 14.84893052321087,
    15.14387341157627, 15.44220572664832, 15.74393850678189, 16.04908273684337,
    16.35764934889634, 16.66964922287304, 16.98509318723205, 17.30399201960269,
    17.62635644741625, 17.95219714852476, 18.28152475180733, 18.61434983776456,
    18.95068293910138, 19.29053454129846, 19.63391508317269, 19.98083495742689,
    20.33130451118907, 20.6853340465415, 21.04293382103998, 21.40411404822326,
    21.76888489811322, 22.13725649770588, 22.50923893145328, 22.88484224173692,
    23.26407642933246, 23.6469514538663, 24.03347723426402, 24.42366364919083,
    24.81752053748456, 25.21505769858089, 25.61628489293138, 26.02121184241434,
    26.42984823073866, 26.84220370384083, 27.25828787027535, 27.67811030159852,
    28.10168053274597, 28.52900806240389, 28.96010235337422, 29.39497283293396,
    29.83362889318845, 30.27607989141933, 30.72233515042663, 31.17240395886551,
    31.62629557157785, 32.08401920991837, 32.54558406207592, 33.01099928338967,
    33.4802739966603, 33.95341729245683, 34.43043822941826, 34.91134583455108,
    35.39614910352207, 35.88485700094671, 36.37747846067349, 36.87402238606382,
    37.37449765026789, 37.87891309649659, 38.38727753828926, 38.89959975977785,
    39.41588851594697, 39.93615253289054, 40.46040050806455, 40.98864111053629,
    41.52088298123019, 42.05713473317016, 42.5974049517184, 43.14170219481122,
    43.6900349931913, 44.24241185063697, 44.79884124418832, 45.35933162437017,
    45.92389141541209, 46.49252901546552, 47.06525279681792, 47.64207110610409,
    48.22299226451468, 48.80802456800205, 49.3971762874833, 49.9904556690408,
    50.58787093411998, 51.18943027972472, 51.79514187861014, 52.40501387947288,
    53.0190544071392, 53.63727156275036, 54.25967342394598, 54.88626804504493,
    55.51706345722393, 56.15206766869424, 56.79128866487574, 57.43473440856916,
    58.08241284012621, 58.73433187761736, 59.39049941699807, 60.05092333227251,
    60.71561147565559, 61.38457167773311, 62.05781174761989, 62.7353394731159,
    63.41716262086091, 64.10328893648692, 64.79372614476921, 65.48848194977529,
    66.18756403501224, 66.89098006357258, 67.59873767827808, 68.31084450182222,
    69.02730813691093, 69.74813616640164, 70.47333615344107, 71.20291564160104,
    71.93688215501312, 72.67524319850172, 73.41800625771542, 74.16517879925733,
    74.91676827081361, 75.67278210128072, 76.43322770089146, 77.19811246133931,
    77.96744375590167, 78.74122893956174, 79.51947534912904, 80.30219030335869,
    81.08938110306934, 81.88105503125999, 82.67721935322541, 83.4778813166706,
    84.28304815182372, 85.09272707154808, 85.90692527145302, 86.72564993000343,
    87.54890820862819, 88.3767072518277, 89.2090541872801, 90.04595612594655,
    90.88742016217518, 91.73345337380438, 92.58406282226491, 93.43925555268066,
    94.29903859396902, 95.16341895893969, 96.03240364439274, 96.90599963121591,
    97.78421388448044, 98.6670533535366, 99.55452497210776,
};

const scaled_discount_from_linrgb = [_][3]f64{
    .{ 0.001200833568784504, 0.002389694492170889, 0.0002795742885861124 },
    .{ 0.0005891086651375999, 0.0029785502573438758, 0.0003270666104008398 },
    .{ 0.00010146692491640572, 0.0005364214359186694, 0.0032979401770712076 },
};
const linrgb_from_scaled_discount = [_][3]f64{
    .{ 1373.2198709594231, -1100.4251190754821, -7.278681089101213 },
    .{ -271.815969077903, 559.6580465940733, -32.46047482791194 },
    .{ 1.9622899599665666, -57.173814538844006, 308.7233197812385 },
};
const y_from_linrgb = [_]f64{ 0.2126, 0.7152, 0.0722 };
pub const Hct = struct {
    hue: f64,
    chroma: f64,
    tone: f64,
    argb: u32,

    pub fn fromInt(argb: u32) Hct {
        const cam = camFromArgb(argb);
        return .{
            .hue = cam.hue,
            .chroma = cam.chroma,
            .tone = lstarFromArgb(argb),
            .argb = argb,
        };
    }

    pub fn from(hue: f64, chroma: f64, tone: f64) Hct {
        return fromInt(solveToInt(hue, chroma, tone));
    }

    pub fn toRgb24(self: Hct) u24 {
        return @truncate(self.argb & 0xffffff);
    }
};

pub const TonalPalette = struct {
    hue: f64,
    chroma: f64,

    pub fn fromHueAndChroma(hue: f64, chroma: f64) TonalPalette {
        return .{ .hue = sanitizeDegrees(hue), .chroma = chroma };
    }

    pub fn fromArgb(argb: u32) TonalPalette {
        const h = Hct.fromInt(argb);
        return fromHueAndChroma(h.hue, h.chroma);
    }

    /// ARGB with alpha 0xFF. Tone is L* 0..100.
    pub fn tone(self: TonalPalette, t: f64) u32 {
        return solveToInt(self.hue, self.chroma, t);
    }

    pub fn toneRgb24(self: TonalPalette, t: f64) u24 {
        return @truncate(self.tone(t) & 0xffffff);
    }
};

const Cam = struct { hue: f64, chroma: f64, j: f64 };

fn signum(x: f64) f64 {
    if (x < 0) return -1;
    if (x > 0) return 1;
    return 0;
}

fn sanitizeDegrees(d: f64) f64 {
    var x = @mod(d, 360.0);
    if (x < 0) x += 360.0;
    return x;
}

fn sanitizeRadians(angle: f64) f64 {
    return @mod(angle + std.math.pi * 8.0, std.math.pi * 2.0);
}

fn clampInt(lo: i32, hi: i32, x: i32) i32 {
    return @max(lo, @min(hi, x));
}

fn linearized(comp: i32) f64 {
    const normalized = @as(f64, @floatFromInt(comp)) / 255.0;
    if (normalized <= 0.040449936) return normalized / 12.92 * 100.0;
    return std.math.pow(f64, (normalized + 0.055) / 1.055, 2.4) * 100.0;
}

fn delinearized(comp: f64) i32 {
    const normalized = comp / 100.0;
    const d = if (normalized <= 0.0031308)
        normalized * 12.92
    else
        1.055 * std.math.pow(f64, normalized, 1.0 / 2.4) - 0.055;
    return clampInt(0, 255, @intFromFloat(@round(d * 255.0)));
}

fn argbFromRgb(r: i32, g: i32, b: i32) u32 {
    return 0xff000000 |
        (@as(u32, @intCast(r)) << 16) |
        (@as(u32, @intCast(g)) << 8) |
        @as(u32, @intCast(b));
}

fn argbFromLinrgb(lin: [3]f64) u32 {
    return argbFromRgb(delinearized(lin[0]), delinearized(lin[1]), delinearized(lin[2]));
}

fn labF(t: f64) f64 {
    const e = 216.0 / 24389.0;
    const kappa = 24389.0 / 27.0;
    if (t > e) return std.math.cbrt(t);
    return (kappa * t + 16.0) / 116.0;
}

fn labInvf(ft: f64) f64 {
    const e = 216.0 / 24389.0;
    const kappa = 24389.0 / 27.0;
    const ft3 = ft * ft * ft;
    if (ft3 > e) return ft3;
    return (116.0 * ft - 16.0) / kappa;
}

fn yFromLstar(lstar: f64) f64 {
    return 100.0 * labInvf((lstar + 16.0) / 116.0);
}

fn argbFromLstar(lstar: f64) u32 {
    const y = yFromLstar(lstar);
    const c = delinearized(y);
    return argbFromRgb(c, c, c);
}

fn lstarFromArgb(argb: u32) f64 {
    const r = linearized(@intCast((argb >> 16) & 0xff));
    const g = linearized(@intCast((argb >> 8) & 0xff));
    const b = linearized(@intCast(argb & 0xff));
    const y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    return 116.0 * labF(y / 100.0) - 16.0;
}

fn matrixMul(row: [3]f64, mat: [3][3]f64) [3]f64 {
    return .{
        mat[0][0] * row[0] + mat[0][1] * row[1] + mat[0][2] * row[2],
        mat[1][0] * row[0] + mat[1][1] * row[1] + mat[1][2] * row[2],
        mat[2][0] * row[0] + mat[2][1] * row[1] + mat[2][2] * row[2],
    };
}

fn camFromArgb(argb: u32) Cam {
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
    return .{ .hue = hue, .chroma = chroma, .j = j };
}

fn trueDelinearized(rgb_component: f64) f64 {
    const normalized = rgb_component / 100.0;
    const d = if (normalized <= 0.0031308)
        normalized * 12.92
    else
        1.055 * std.math.pow(f64, normalized, 1.0 / 2.4) - 0.055;
    return d * 255.0;
}

fn chromaticAdaptation(component: f64) f64 {
    const af = std.math.pow(f64, @abs(component), 0.42);
    return signum(component) * 400.0 * af / (af + 27.13);
}

fn inverseChromaticAdaptation(adapted: f64) f64 {
    const adapted_abs = @abs(adapted);
    const base = @max(0.0, 27.13 * adapted_abs / (400.0 - adapted_abs));
    return signum(adapted) * std.math.pow(f64, base, 1.0 / 0.42);
}

fn hueOf(linrgb: [3]f64) f64 {
    const scaled = matrixMul(linrgb, scaled_discount_from_linrgb);
    const r_a = chromaticAdaptation(scaled[0]);
    const g_a = chromaticAdaptation(scaled[1]);
    const b_a = chromaticAdaptation(scaled[2]);
    const a = (11.0 * r_a + -12.0 * g_a + b_a) / 11.0;
    const b = (r_a + g_a - 2.0 * b_a) / 9.0;
    return std.math.atan2(b, a);
}

fn areInCyclicOrder(a: f64, b: f64, c: f64) bool {
    return sanitizeRadians(b - a) < sanitizeRadians(c - a);
}

fn intercept(source: f64, mid: f64, target: f64) f64 {
    return (mid - source) / (target - source);
}

fn lerpPoint(source: [3]f64, t: f64, target: [3]f64) [3]f64 {
    return .{
        source[0] + (target[0] - source[0]) * t,
        source[1] + (target[1] - source[1]) * t,
        source[2] + (target[2] - source[2]) * t,
    };
}

fn setCoordinate(source: [3]f64, coordinate: f64, target: [3]f64, axis: usize) [3]f64 {
    const t = intercept(source[axis], coordinate, target[axis]);
    return lerpPoint(source, t, target);
}

fn isBounded(x: f64) bool {
    return x >= 0.0 and x <= 100.0;
}

fn nthVertex(y: f64, n: i32) [3]f64 {
    const kr = y_from_linrgb[0];
    const kg = y_from_linrgb[1];
    const kb = y_from_linrgb[2];
    const coord_a: f64 = if (@mod(n, 4) <= 1) 0.0 else 100.0;
    const coord_b: f64 = if (@mod(n, 2) == 0) 0.0 else 100.0;
    if (n < 4) {
        const g = coord_a;
        const b = coord_b;
        const r = (y - g * kg - b * kb) / kr;
        if (isBounded(r)) return .{ r, g, b };
        return .{ -1, -1, -1 };
    } else if (n < 8) {
        const b = coord_a;
        const r = coord_b;
        const g = (y - r * kr - b * kb) / kg;
        if (isBounded(g)) return .{ r, g, b };
        return .{ -1, -1, -1 };
    } else {
        const r = coord_a;
        const g = coord_b;
        const b = (y - r * kr - g * kg) / kb;
        if (isBounded(b)) return .{ r, g, b };
        return .{ -1, -1, -1 };
    }
}

fn bisectToSegment(y: f64, target_hue: f64) struct { left: [3]f64, right: [3]f64 } {
    var left = [_]f64{ -1, -1, -1 };
    var right = left;
    var left_hue: f64 = 0;
    var right_hue: f64 = 0;
    var initialized = false;
    var uncut = true;
    var n: i32 = 0;
    while (n < 12) : (n += 1) {
        const mid = nthVertex(y, n);
        if (mid[0] < 0) continue;
        const mid_hue = hueOf(mid);
        if (!initialized) {
            left = mid;
            right = mid;
            left_hue = mid_hue;
            right_hue = mid_hue;
            initialized = true;
            continue;
        }
        if (uncut or areInCyclicOrder(left_hue, mid_hue, right_hue)) {
            uncut = false;
            if (areInCyclicOrder(left_hue, target_hue, mid_hue)) {
                right = mid;
                right_hue = mid_hue;
            } else {
                left = mid;
                left_hue = mid_hue;
            }
        }
    }
    return .{ .left = left, .right = right };
}

fn bisectToLimit(y: f64, target_hue: f64) [3]f64 {
    const segment = bisectToSegment(y, target_hue);
    var left = segment.left;
    var left_hue = hueOf(left);
    var right = segment.right;
    var axis: usize = 0;
    while (axis < 3) : (axis += 1) {
        if (left[axis] == right[axis]) continue;
        var l_plane: f64 = undefined;
        var r_plane: f64 = undefined;
        if (left[axis] < right[axis]) {
            l_plane = @floor(trueDelinearized(left[axis]) - 0.5);
            r_plane = @ceil(trueDelinearized(right[axis]) - 0.5);
        } else {
            l_plane = @ceil(trueDelinearized(left[axis]) - 0.5);
            r_plane = @floor(trueDelinearized(right[axis]) - 0.5);
        }
        var i: i32 = 0;
        while (i < 8) : (i += 1) {
            if (@abs(r_plane - l_plane) <= 1) break;
            const m_plane = @floor((l_plane + r_plane) / 2.0);
            const mid_plane_coordinate = critical_planes[@intFromFloat(m_plane)];
            const mid = setCoordinate(left, mid_plane_coordinate, right, axis);
            const mid_hue = hueOf(mid);
            if (areInCyclicOrder(left_hue, target_hue, mid_hue)) {
                right = mid;
                r_plane = m_plane;
            } else {
                left = mid;
                left_hue = mid_hue;
                l_plane = m_plane;
            }
        }
    }
    return .{
        (left[0] + right[0]) / 2.0,
        (left[1] + right[1]) / 2.0,
        (left[2] + right[2]) / 2.0,
    };
}

fn findResultByJ(hue_radians: f64, chroma: f64, y: f64) u32 {
    var j = @sqrt(y) * 11.0;
    const t_inner_coeff = 1.0 / std.math.pow(f64, 1.64 - std.math.pow(f64, 0.29, vc_n), 0.73);
    const e_hue = 0.25 * (std.math.cos(hue_radians + 2.0) + 3.8);
    const p1 = e_hue * (50000.0 / 13.0) * vc_nc * vc_ncb;
    const h_sin = std.math.sin(hue_radians);
    const h_cos = std.math.cos(hue_radians);
    var iteration_round: i32 = 0;
    while (iteration_round < 5) : (iteration_round += 1) {
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
        const linrgb = matrixMul(.{
            inverseChromaticAdaptation(r_a),
            inverseChromaticAdaptation(g_a),
            inverseChromaticAdaptation(b_a),
        }, linrgb_from_scaled_discount);
        if (linrgb[0] < 0 or linrgb[1] < 0 or linrgb[2] < 0) return 0;
        const fnj = y_from_linrgb[0] * linrgb[0] + y_from_linrgb[1] * linrgb[1] + y_from_linrgb[2] * linrgb[2];
        if (fnj <= 0) return 0;
        if (iteration_round == 4 or @abs(fnj - y) < 0.002) {
            if (linrgb[0] > 100.01 or linrgb[1] > 100.01 or linrgb[2] > 100.01) return 0;
            return argbFromLinrgb(linrgb);
        }
        j = j - (fnj - y) * j / (2.0 * fnj);
    }
    return 0;
}

fn solveToInt(hue_degrees: f64, chroma: f64, lstar: f64) u32 {
    if (chroma < 0.0001 or lstar < 0.0001 or lstar > 99.9999) return argbFromLstar(lstar);
    const hue = sanitizeDegrees(hue_degrees);
    const hue_radians = hue / 180.0 * std.math.pi;
    const y = yFromLstar(lstar);
    const exact = findResultByJ(hue_radians, chroma, y);
    if (exact != 0) return exact;
    return argbFromLinrgb(bisectToLimit(y, hue_radians));
}

test "hct roundtrip seed teal" {
    const h = Hct.fromInt(0xff00BCD4);
    try std.testing.expect(@abs(h.hue - 212.44) < 0.5);
    try std.testing.expect(@abs(h.chroma - 49.96) < 0.5);
    const p = TonalPalette.fromHueAndChroma(h.hue, h.chroma);
    try std.testing.expectEqual(@as(u24, 0x006876), p.toneRgb24(40));
    try std.testing.expectEqual(@as(u24, 0x44D8F1), p.toneRgb24(80));
}
