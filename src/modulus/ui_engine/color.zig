//! RGB565 pixel helpers (Tab5 LV_COLOR_DEPTH_16).

const std = @import("std");

pub const Rgb565 = packed struct(u16) {
    b: u5,
    g: u6,
    r: u5,

    pub fn fromRgb888(r: u8, g: u8, b: u8) Rgb565 {
        return .{
            .r = @truncate(r >> 3),
            .g = @truncate(g >> 2),
            .b = @truncate(b >> 3),
        };
    }

    pub fn fromHex(hex: u24) Rgb565 {
        return fromRgb888(
            @truncate(hex >> 16),
            @truncate(hex >> 8),
            @truncate(hex),
        );
    }

    pub fn toU16(self: Rgb565) u16 {
        return @bitCast(self);
    }

    pub fn fromU16(v: u16) Rgb565 {
        return @bitCast(v);
    }

    /// Expand to 8-bit channel (MSB replicate).
    pub fn toRgb888(self: Rgb565) struct { r: u8, g: u8, b: u8 } {
        return .{
            .r = (@as(u8, self.r) << 3) | (@as(u8, self.r) >> 2),
            .g = (@as(u8, self.g) << 2) | (@as(u8, self.g) >> 4),
            .b = (@as(u8, self.b) << 3) | (@as(u8, self.b) >> 2),
        };
    }

    pub fn toHex(self: Rgb565) u24 {
        const c = self.toRgb888();
        return (@as(u24, c.r) << 16) | (@as(u24, c.g) << 8) | c.b;
    }
};

/// Relative luminance 0..1 (sRGB, WCAG).
pub fn relativeLuminance(hex: u24) f32 {
    const r = lin(@as(f32, @floatFromInt((hex >> 16) & 0xff)));
    const g = lin(@as(f32, @floatFromInt((hex >> 8) & 0xff)));
    const b = lin(@as(f32, @floatFromInt(hex & 0xff)));
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

fn lin(c8: f32) f32 {
    const c = c8 / 255.0;
    return if (c <= 0.04045) c / 12.92 else std.math.pow(f32, (c + 0.055) / 1.055, 2.4);
}

/// WCAG contrast ratio (≥4.5 text, ≥3.0 UI).
pub fn contrastRatio(a: u24, b: u24) f32 {
    const la = relativeLuminance(a);
    const lb = relativeLuminance(b);
    const hi = @max(la, lb);
    const lo = @min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
}

/// Alpha blend `fg` over `bg` with 8-bit coverage (Phosphor A8).
pub fn blendRgb565(bg: Rgb565, fg: Rgb565, alpha: u8) Rgb565 {
    if (alpha == 0) {
        @branchHint(.unlikely);
        return bg;
    }
    if (alpha >= 255) {
        @branchHint(.likely);
        return fg;
    }
    const a: u16 = alpha;
    const ia: u16 = 255 - a;
    const br: u16 = bg.r;
    const bg_: u16 = bg.g;
    const bb: u16 = bg.b;
    const fr: u16 = fg.r;
    const fg_: u16 = fg.g;
    const fb: u16 = fg.b;
    return .{
        .r = @intCast((fr * a + br * ia) / 255),
        .g = @intCast((fg_ * a + bg_ * ia) / 255),
        .b = @intCast((fb * a + bb * ia) / 255),
    };
}

test "hex roundtrip bits" {
    const c = Rgb565.fromHex(0x34D399);
    const back = Rgb565.fromU16(c.toU16());
    try std.testing.expectEqual(c.r, back.r);
    try std.testing.expectEqual(c.g, back.g);
    try std.testing.expectEqual(c.b, back.b);
}

test "contrast black white" {
    try std.testing.expect(contrastRatio(0x000000, 0xFFFFFF) > 20.0);
}
