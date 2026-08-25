//! MD3 seed → theme via real HCT / Cam16 tonal palettes (SchemeTonalSpot tones).

const std = @import("std");
const color = @import("color.zig");
const hct = @import("hct.zig");
const tokens = @import("tokens.zig");

/// SchemeTonalSpot chromas (materialyoucolor DynamicScheme default spec).
const primary_chroma: f64 = 36.0;
const secondary_chroma: f64 = 16.0;
const tertiary_chroma: f64 = 24.0;
const neutral_chroma: f64 = 6.0;
const neutral_variant_chroma: f64 = 8.0;
const tertiary_hue_rotate: f64 = 60.0;

pub fn applySeedToTheme(theme: *tokens.Theme, seed: u24, dark: bool) void {
    const src = hct.Hct.fromInt(0xff000000 | @as(u32, seed));
    const primary_p = hct.TonalPalette.fromHueAndChroma(src.hue, primary_chroma);
    const secondary_p = hct.TonalPalette.fromHueAndChroma(src.hue, secondary_chroma);
    const tertiary_p = hct.TonalPalette.fromHueAndChroma(src.hue + tertiary_hue_rotate, tertiary_chroma);
    const neutral_p = hct.TonalPalette.fromHueAndChroma(src.hue, neutral_chroma);
    const nv_p = hct.TonalPalette.fromHueAndChroma(src.hue, neutral_variant_chroma);

    const R = color.Rgb565.fromHex;
    theme.dark = dark;

    if (dark) {
        theme.primary = R(primary_p.toneRgb24(80));
        theme.on_primary = R(primary_p.toneRgb24(20));
        theme.primary_container = R(primary_p.toneRgb24(30));
        theme.on_primary_container = R(primary_p.toneRgb24(90));
        theme.secondary = R(secondary_p.toneRgb24(80));
        theme.on_secondary = R(secondary_p.toneRgb24(20));
        theme.secondary_container = R(secondary_p.toneRgb24(30));
        theme.on_secondary_container = R(secondary_p.toneRgb24(90));
        theme.tertiary = R(tertiary_p.toneRgb24(80));
        theme.on_tertiary = R(tertiary_p.toneRgb24(20));
        theme.tertiary_container = R(tertiary_p.toneRgb24(30));
        theme.on_tertiary_container = R(tertiary_p.toneRgb24(90));

        theme.surface = R(neutral_p.toneRgb24(6));
        theme.surface_dim = R(neutral_p.toneRgb24(6));
        theme.surface_bright = R(neutral_p.toneRgb24(24));
        theme.surface_container_lowest = R(neutral_p.toneRgb24(4));
        theme.surface_container_low = R(neutral_p.toneRgb24(10));
        theme.surface_container = R(neutral_p.toneRgb24(12));
        theme.surface_container_high = R(neutral_p.toneRgb24(17));
        theme.surface_container_highest = R(neutral_p.toneRgb24(22));

        theme.on_surface = R(neutral_p.toneRgb24(90));
        theme.on_surface_variant = R(nv_p.toneRgb24(80));
        theme.outline = R(nv_p.toneRgb24(60));
        theme.outline_variant = R(nv_p.toneRgb24(30));

        theme.inverse_surface = R(neutral_p.toneRgb24(90));
        theme.inverse_on_surface = R(neutral_p.toneRgb24(20));
        theme.inverse_primary = R(primary_p.toneRgb24(40));
    } else {
        theme.primary = R(primary_p.toneRgb24(40));
        theme.on_primary = R(primary_p.toneRgb24(100));
        theme.primary_container = R(primary_p.toneRgb24(90));
        theme.on_primary_container = R(primary_p.toneRgb24(10));
        theme.secondary = R(secondary_p.toneRgb24(40));
        theme.on_secondary = R(secondary_p.toneRgb24(100));
        theme.secondary_container = R(secondary_p.toneRgb24(90));
        theme.on_secondary_container = R(secondary_p.toneRgb24(10));
        theme.tertiary = R(tertiary_p.toneRgb24(40));
        theme.on_tertiary = R(tertiary_p.toneRgb24(100));
        theme.tertiary_container = R(tertiary_p.toneRgb24(90));
        theme.on_tertiary_container = R(tertiary_p.toneRgb24(10));

        theme.surface = R(neutral_p.toneRgb24(98));
        theme.surface_dim = R(neutral_p.toneRgb24(87));
        theme.surface_bright = R(neutral_p.toneRgb24(98));
        theme.surface_container_lowest = R(neutral_p.toneRgb24(100));
        theme.surface_container_low = R(neutral_p.toneRgb24(96));
        theme.surface_container = R(neutral_p.toneRgb24(94));
        theme.surface_container_high = R(neutral_p.toneRgb24(92));
        theme.surface_container_highest = R(neutral_p.toneRgb24(90));

        theme.on_surface = R(neutral_p.toneRgb24(10));
        theme.on_surface_variant = R(nv_p.toneRgb24(30));
        theme.outline = R(nv_p.toneRgb24(50));
        theme.outline_variant = R(nv_p.toneRgb24(80));

        theme.inverse_surface = R(neutral_p.toneRgb24(20));
        theme.inverse_on_surface = R(neutral_p.toneRgb24(95));
        theme.inverse_primary = R(primary_p.toneRgb24(80));
    }

    theme.syncScrim();
    theme.primary_fixed = R(primary_p.toneRgb24(90));
    theme.on_primary_fixed = R(primary_p.toneRgb24(10));
    theme.primary_fixed_dim = R(primary_p.toneRgb24(80));
    theme.secondary_fixed = R(secondary_p.toneRgb24(90));
    theme.on_secondary_fixed = R(secondary_p.toneRgb24(10));
    theme.tertiary_fixed = R(tertiary_p.toneRgb24(90));
    theme.on_tertiary_fixed = R(tertiary_p.toneRgb24(10));
    theme.ensureContrast();
    theme.bindCncAliases();
}

test "palette seed builds AA primary" {
    var t = tokens.Theme.industrialTealDark();
    applySeedToTheme(&t, 0x4FD6E0, true);
    try std.testing.expect(t.contrastOk());
    applySeedToTheme(&t, 0xFF6B6B, true);
    try std.testing.expect(t.contrastOk());
    applySeedToTheme(&t, 0x00BCD4, false);
    try std.testing.expect(t.contrastOk());
}

test "palette seed uses HCT primary tone" {
    var t = tokens.Theme.industrialTealDark();
    applySeedToTheme(&t, 0x00BCD4, true);
    const p = hct.TonalPalette.fromHueAndChroma(hct.Hct.fromInt(0xff00BCD4).hue, primary_chroma);
    try std.testing.expectEqual(color.Rgb565.fromHex(p.toneRgb24(80)), t.primary);
}
