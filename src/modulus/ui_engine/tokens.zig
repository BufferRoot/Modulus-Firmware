//! MD3 + Expressive design tokens (Zig 0.16, host-first; mirrors ui_internal.h).
//! Color roles follow md.sys; elevation is tonal (no shadows).

const color = @import("color.zig");

/// MD3 + Expressive corner scale (dp). Full morph library = 35 shapes on device later.
/// ponytail: host paints circle / round-rect / pill / diamond only.
pub const Shape = struct {
    pub const none: i32 = 0;
    pub const extra_small: i32 = 4;
    pub const xs: i32 = 4;
    pub const small: i32 = 8;
    pub const sm: i32 = 8;
    pub const medium: i32 = 12;
    pub const md: i32 = 12;
    pub const large: i32 = 16;
    pub const lg: i32 = 16;
    pub const large_increased: i32 = 20;
    pub const lg_inc: i32 = 20;
    pub const extra_large: i32 = 28;
    pub const xl: i32 = 28;
    pub const extra_large_increased: i32 = 32;
    pub const xxl: i32 = 32;
    pub const extra_extra_large: i32 = 48;
    pub const xxxl: i32 = 48;
    pub const full: i32 = 9999;
    pub const card: i32 = md;
    pub const dialog: i32 = xl;
    pub const menu: i32 = sm;
    pub const sheet: i32 = xxxl;
    pub const button: i32 = full;
    pub const chip: i32 = full;
    pub const fab: i32 = 16;
    pub const fab_large: i32 = 28;
    pub const toolbar: i32 = full;

    /// Decorative crop kinds (host subset of M3 shape library → 10 paints).
    pub const Kind = enum { rounded, circle, pill, square, diamond, arch, soft_burst, cookie, clam, slanted };

    pub fn radiusFor(kind: Kind, size: i32) i32 {
        return switch (kind) {
            .rounded, .cookie => md,
            .circle, .pill, .soft_burst => full,
            .square, .slanted => none,
            .diamond, .arch, .clam => @divTrunc(size, 2),
        };
    }
};

/// MD3 window size classes (dp). Tab5 landscape 1280 → expanded.
pub const WindowSizeClass = enum {
    compact,
    medium,
    expanded,
    large,
    extra_large,

    pub fn fromWidth(w: i32) WindowSizeClass {
        if (w < 600) return .compact;
        if (w < 840) return .medium;
        if (w < 1200) return .expanded;
        if (w < 1600) return .large;
        return .extra_large;
    }

    /// Tab5 Modulus host / device logical canvas.
    pub fn tab5() WindowSizeClass {
        return fromWidth(@as(i32, Logical.width));
    }

    pub fn contentMaxWidth(self: WindowSizeClass) i32 {
        return switch (self) {
            .compact => 600,
            .medium => 840,
            .expanded => 1040,
            .large => 1040,
            .extra_large => 1040,
        };
    }

    pub fn margin(self: WindowSizeClass) i32 {
        return switch (self) {
            .compact => Space.sm,
            .medium => Space.md,
            .expanded, .large, .extra_large => Space.lg,
        };
    }

    pub fn useNavRail(self: WindowSizeClass) bool {
        return @intFromEnum(self) >= @intFromEnum(WindowSizeClass.medium);
    }
};

/// MD3 state-layer alphas over on-surface / on-primary (Compose parity).
pub const StateLayer = struct {
    pub const hover: u8 = 20; // ~8%
    pub const focus: u8 = 26; // ~10%
    pub const press: u8 = 31; // ~12%
    pub const drag: u8 = 41; // ~16%
};

/// MD3 8dp spacing grid.
pub const Space = struct {
    pub const xs: i32 = 4;
    pub const sm: i32 = 8;
    pub const md: i32 = 16;
    pub const lg: i32 = 24;
    pub const xl: i32 = 32;
};

/// Expressive button container heights (Compose XS–XL stand-in).
pub const ButtonSize = enum {
    xs,
    s,
    m,
    l,
    xl,

    pub fn height(self: ButtonSize) i32 {
        return switch (self) {
            .xs => 32,
            .s => 40,
            .m => 48,
            .l => 56,
            .xl => 64,
        };
    }

    pub fn padX(self: ButtonSize) i32 {
        return switch (self) {
            .xs => Space.sm,
            .s => 12,
            .m => Space.md,
            .l => 20,
            .xl => Space.lg,
        };
    }
};

/// Compose MotionScheme stand-in — picks spatial/effects spring pairs.
pub const MotionScheme = enum {
    standard,
    expressive,

    pub fn spatialStiffness(self: MotionScheme) f32 {
        return switch (self) {
            .standard => Motion.spring_stiffness,
            .expressive => Motion.spatial_stiffness,
        };
    }
    pub fn spatialDamping(self: MotionScheme) f32 {
        return switch (self) {
            .standard => Motion.spring_damping,
            .expressive => Motion.spatial_damping,
        };
    }
    pub fn effectsStiffness(self: MotionScheme) f32 {
        return switch (self) {
            .standard => 260.0,
            .expressive => Motion.effects_stiffness,
        };
    }
    pub fn effectsDamping(self: MotionScheme) f32 {
        return switch (self) {
            .standard => 32.0,
            .expressive => Motion.effects_damping,
        };
    }
};

/// MD3 Expressive motion — spatial springs (position) + effects springs (color/opacity).
/// Spec: https://m3.material.io/styles/motion/overview/how-it-works
pub const Motion = struct {
    pub const enter_ms: u32 = 400;
    pub const exit_ms: u32 = 200;
    pub const util_ms: u32 = 300;
    pub const settings_ms: u32 = 120;
    pub const morph_ms: u32 = 180;
    pub const sheet_slide_px: i32 = 320;
    /// LVGL QS bottom panel height (host silhouette).
    pub const qs_panel_h: i32 = 460;
    pub const snackbar_ms: u32 = 2500;
    /// Shared-axis enter offset (settings tab change).
    pub const shared_axis_px: f32 = 28;
    /// Soft overscroll (px) before spring snaps back.
    pub const overscroll_px: f32 = 64;
    pub const spring_stiffness: f32 = 300.0;
    pub const spring_damping: f32 = 28.0;
    pub const spring_stiffness_expressive: f32 = 380.0;
    pub const spring_damping_expressive: f32 = 22.0;
    /// Spatial — object translation / size (snappier).
    pub const spatial_stiffness: f32 = 380.0;
    pub const spatial_damping: f32 = 22.0;
    /// Effects — color / opacity (softer).
    pub const effects_stiffness: f32 = 220.0;
    pub const effects_damping: f32 = 30.0;
    /// Scroll settle — tighter than default so idle dirty goes to 0 fast.
    pub const scroll_epsilon: f32 = 0.25;
    /// Finger-tracked scroll chase (ζ=1) — ~75 ms settle, ≈2 frames of lag at 33 ms.
    pub const scroll_track_stiffness: f32 = 1500;
    /// Tab5 LVGL refresh floor (ms) — IDLE0 WDT history; never budget below this.
    pub const refresh_floor_ms: u32 = 33;
    pub const refresh_floor_us: u64 = refresh_floor_ms * 1000;
};

/// Bitmap proxy for MD3 typescale + full Expressive emphasized set (15).
/// Host: emph ≈ larger face / tighter tracking (no variable font axes).
pub const TypeRole = enum {
    display_l,
    display_m,
    display_s,
    headline_l,
    headline_m,
    headline_s,
    title_l,
    title_m,
    title_s,
    body_l,
    body_m,
    body_s,
    label_l,
    label_m,
    label_s,
    emph_display_l,
    emph_display_m,
    emph_display_s,
    emph_headline_l,
    emph_headline_m,
    emph_headline_s,
    emph_title_l,
    emph_title_m,
    emph_title_s,
    emph_body_l,
    emph_body_m,
    emph_body_s,
    emph_label_l,
    emph_label_m,
    emph_label_s,

    pub fn bitmapScale(self: TypeRole) u8 {
        return switch (self) {
            .display_l, .emph_display_l => 4,
            .display_m, .emph_display_m, .headline_l, .emph_headline_l => 3,
            .display_s, .emph_display_s, .headline_m, .emph_headline_m, .headline_s, .emph_headline_s => 3,
            .title_l, .emph_title_l => 2,
            .title_m, .emph_title_m, .title_s, .emph_title_s, .body_l, .emph_body_l, .body_m, .emph_body_m, .label_l, .emph_label_l => 2,
            .body_s, .emph_body_s, .label_m, .emph_label_m, .label_s, .emph_label_s => 1,
        };
    }

    pub fn emphasized(self: TypeRole) bool {
        return @intFromEnum(self) >= @intFromEnum(TypeRole.emph_display_l);
    }

    /// Approximate letter-spacing stand-in (px). Emph = slightly tighter (−1).
    pub fn trackingPx(self: TypeRole) i32 {
        if (self.emphasized()) return -1;
        return switch (self) {
            .display_l, .display_m, .display_s => 0,
            .headline_l, .headline_m, .headline_s => 0,
            .label_l, .label_m, .label_s => 0,
            else => 0,
        };
    }

    /// Emph uses baked Medium/Bold faces — no double-stroke proxy.
    pub fn boldPass(self: TypeRole) bool {
        _ = self;
        return false;
    }

    pub fn lineHeight(self: TypeRole) i32 {
        const s: i32 = self.bitmapScale();
        const base: i32 = 8 * s;
        return switch (self) {
            .display_l, .emph_display_l, .display_m, .emph_display_m => base + 12,
            .display_s, .emph_display_s => base + 8,
            .headline_l, .emph_headline_l, .headline_m, .emph_headline_m, .headline_s, .emph_headline_s => base + 6,
            .title_l, .emph_title_l, .title_m, .emph_title_m, .title_s, .emph_title_s => base + 4,
            .body_l, .emph_body_l, .body_m, .emph_body_m, .body_s, .emph_body_s => base + 4,
            .label_l, .emph_label_l, .label_m, .emph_label_m, .label_s, .emph_label_s => base + 2,
        };
    }
};

pub const Logical = struct {
    pub const width: u16 = 1280;
    pub const height: u16 = 720;
    pub const panel_w: u16 = 720;
    pub const panel_h: u16 = 1280;
    pub const touch_min: i32 = 48;

    /// Centered min touch target around a point.
    pub fn touchHit(cx: i32, cy: i32) @import("geom.zig").Rect {
        const s = touch_min;
        return .{ .x = cx - @divTrunc(s, 2), .y = cy - @divTrunc(s, 2), .w = s, .h = s };
    }
};

pub const Theme = struct {
    surface: color.Rgb565,
    on_surface: color.Rgb565,
    on_surface_variant: color.Rgb565,
    surface_dim: color.Rgb565,
    surface_bright: color.Rgb565,
    surface_container_lowest: color.Rgb565,
    surface_container_low: color.Rgb565,
    surface_container: color.Rgb565,
    surface_container_high: color.Rgb565,
    surface_container_highest: color.Rgb565,
    primary: color.Rgb565,
    on_primary: color.Rgb565,
    primary_container: color.Rgb565,
    on_primary_container: color.Rgb565,
    secondary: color.Rgb565,
    on_secondary: color.Rgb565,
    secondary_container: color.Rgb565,
    on_secondary_container: color.Rgb565,
    tertiary: color.Rgb565,
    on_tertiary: color.Rgb565,
    tertiary_container: color.Rgb565,
    on_tertiary_container: color.Rgb565,
    outline: color.Rgb565,
    outline_variant: color.Rgb565,
    err: color.Rgb565,
    on_error: color.Rgb565,
    error_container: color.Rgb565,
    on_error_container: color.Rgb565,
    inverse_surface: color.Rgb565,
    inverse_on_surface: color.Rgb565,
    inverse_primary: color.Rgb565,
    /// Fixed roles — Expressive vibrant hierarchy (seed-independent accents).
    primary_fixed: color.Rgb565,
    on_primary_fixed: color.Rgb565,
    primary_fixed_dim: color.Rgb565,
    secondary_fixed: color.Rgb565,
    on_secondary_fixed: color.Rgb565,
    tertiary_fixed: color.Rgb565,
    on_tertiary_fixed: color.Rgb565,
    /// Opaque MD3 scrim stand-in (black @ ~32% over `surface`). Tab5 forbids
    /// translucent full-screen layers under sw_rotate — use `widgets.fillScrim`
    /// or `widgets.paintScrimOver` (blend onto painted underlay).
    scrim: color.Rgb565,
    /// CNC action fills — color-locked (shop semantics); not scheme aliases.
    cycle: color.Rgb565,
    on_cycle: color.Rgb565,
    hold: color.Rgb565,
    on_hold: color.Rgb565,
    home: color.Rgb565,
    on_home: color.Rgb565,
    stop: color.Rgb565,
    on_stop: color.Rgb565,
    feed_resume: color.Rgb565,
    on_feed_resume: color.Rgb565,
    dark: bool,

    pub fn industrialTealDark() Theme {
        const R = color.Rgb565.fromHex;
        var t: Theme = .{
            .surface = R(0x101417),
            .on_surface = R(0xE2E2E5),
            .on_surface_variant = R(0xC2C7CE),
            .surface_dim = R(0x101417),
            .surface_bright = R(0x363A3D),
            .surface_container_lowest = R(0x0B0E11),
            .surface_container_low = R(0x181C1F),
            .surface_container = R(0x1C2024),
            .surface_container_high = R(0x262A2E),
            .surface_container_highest = R(0x313539),
            .primary = R(0x4FD6E0),
            .on_primary = R(0x00363B),
            .primary_container = R(0x004F56),
            .on_primary_container = R(0x97F0F8),
            .secondary = R(0xB1CBD0),
            .on_secondary = R(0x1C3438),
            .secondary_container = R(0x334B4F),
            .on_secondary_container = R(0xCDE7EC),
            .tertiary = R(0xB8C4EA),
            .on_tertiary = R(0x22304C),
            .tertiary_container = R(0x384664),
            .on_tertiary_container = R(0xDAE2FF),
            .outline = R(0x8C9198),
            .outline_variant = R(0x41484D),
            .err = R(0xFFB4AB),
            .on_error = R(0x690005),
            .error_container = R(0x93000A),
            .on_error_container = R(0xFFDAD6),
            .inverse_surface = R(0xE2E2E5),
            .inverse_on_surface = R(0x2E3133),
            .inverse_primary = R(0x006974),
            .primary_fixed = R(0x97F0F8),
            .on_primary_fixed = R(0x00363B),
            .primary_fixed_dim = R(0x4FD6E0),
            .secondary_fixed = R(0xCDE7EC),
            .on_secondary_fixed = R(0x051F23),
            .tertiary_fixed = R(0xDAE2FF),
            .on_tertiary_fixed = R(0x0B1B36),
            .scrim = undefined,
            // Placeholders — lockCncActionColors overwrites.
            .cycle = R(0),
            .on_cycle = R(0),
            .hold = R(0),
            .on_hold = R(0),
            .home = R(0),
            .on_home = R(0),
            .stop = R(0),
            .on_stop = R(0),
            .feed_resume = R(0),
            .on_feed_resume = R(0),
            .dark = true,
        };
        t.syncScrim();
        t.lockCncActionColors();
        return t;
    }

    pub fn industrialTealLight() Theme {
        const R = color.Rgb565.fromHex;
        var t: Theme = .{
            .surface = R(0xF0F2F5),
            .on_surface = R(0x191C1E),
            .on_surface_variant = R(0x40484C),
            .surface_dim = R(0xD0D3D6),
            .surface_bright = R(0xF0F2F5),
            .surface_container_lowest = R(0xFFFFFF),
            .surface_container_low = R(0xEAECEE),
            .surface_container = R(0xE4E7E9),
            .surface_container_high = R(0xDEE3E6),
            .surface_container_highest = R(0xD8DDDF),
            .primary = R(0x006974),
            .on_primary = R(0xFFFFFF),
            .primary_container = R(0x9DF0F8),
            .on_primary_container = R(0x00363B),
            .secondary = R(0x4A6267),
            .on_secondary = R(0xFFFFFF),
            .secondary_container = R(0xCDE7EC),
            .on_secondary_container = R(0x051F23),
            .tertiary = R(0x505E7C),
            .on_tertiary = R(0xFFFFFF),
            .tertiary_container = R(0xDAE2FF),
            .on_tertiary_container = R(0x0B1B36),
            .outline = R(0x70787C),
            .outline_variant = R(0xBFC8CC),
            .err = R(0xBA1A1A),
            .on_error = R(0xFFFFFF),
            .error_container = R(0xFFDAD6),
            .on_error_container = R(0x410002),
            .inverse_surface = R(0x2E3133),
            .inverse_on_surface = R(0xEFEFF1),
            .inverse_primary = R(0x4FD6E0),
            .primary_fixed = R(0x9DF0F8),
            .on_primary_fixed = R(0x00363B),
            .primary_fixed_dim = R(0x4FD6E0),
            .secondary_fixed = R(0xCDE7EC),
            .on_secondary_fixed = R(0x051F23),
            .tertiary_fixed = R(0xDAE2FF),
            .on_tertiary_fixed = R(0x0B1B36),
            .scrim = undefined,
            .cycle = R(0),
            .on_cycle = R(0),
            .hold = R(0),
            .on_hold = R(0),
            .home = R(0),
            .on_home = R(0),
            .stop = R(0),
            .on_stop = R(0),
            .feed_resume = R(0),
            .on_feed_resume = R(0),
            .dark = false,
        };
        t.syncScrim();
        t.lockCncActionColors();
        return t;
    }

    /// Expressive vibrant dark — sharper primary/tertiary contrast for key actions.
    pub fn expressiveVibrantDark() Theme {
        var t = industrialTealDark();
        const R = color.Rgb565.fromHex;
        t.primary = R(0x00E5FF);
        t.primary_container = R(0x005F66);
        t.tertiary = R(0xFFB020);
        t.tertiary_container = R(0x5C3B00);
        t.on_tertiary_container = R(0xFFDDB0);
        t.primary_fixed = R(0xA8F5FF);
        t.primary_fixed_dim = R(0x00E5FF);
        t.secondary_fixed = R(0xE8C4FF);
        t.on_secondary_fixed = R(0x2A004D);
        // CNC fills stay locked — do not re-alias to primary/tertiary.
        return t;
    }

    /// Shop color-lock for Cycle / Hold / Stop / Home (Tab5 `apply_semantic_colors` parity + user tweaks).
    /// Seed / theme toggle must not retint these — muscle memory on the rail.
    pub fn lockCncActionColors(self: *Theme) void {
        const R = color.Rgb565.fromHex;
        if (self.dark) {
            self.cycle = R(0x22C55E); // vibrant green
            self.on_cycle = R(0x0D0D12);
            self.hold = R(0xF59E0B); // golden orange
            self.on_hold = R(0x0D0D12);
            self.home = R(0x1E3A8A); // dark blue
            self.on_home = R(0xFFFFFF);
            self.stop = R(0x991B1B); // dark red
            self.on_stop = R(0xFFFFFF);
            self.feed_resume = R(0xA3E635); // lime — distinct from cycle
            self.on_feed_resume = R(0x0D0D12);
        } else {
            self.cycle = R(0x15803D);
            self.on_cycle = R(0xFFFFFF);
            self.hold = R(0xC2410C);
            self.on_hold = R(0xFFFFFF);
            self.home = R(0x1E3A8A);
            self.on_home = R(0xFFFFFF);
            self.stop = R(0x7F1D1D);
            self.on_stop = R(0xFFFFFF);
            self.feed_resume = R(0x4D7C0F);
            self.on_feed_resume = R(0xFFFFFF);
        }
    }

    /// Deprecated name — keeps seed/palette call sites compiling; locks CNC colors.
    pub fn bindCncAliases(self: *Theme) void {
        self.lockCncActionColors();
    }

    /// MD3 dialog/sheet scrim opacity (black over content) as 8-bit coverage.
    pub const scrim_alpha: u8 = 82; // ~32%

    /// Recompute opaque scrim from current `surface` (call after seed/theme swap).
    pub fn syncScrim(self: *Theme) void {
        self.scrim = color.blendRgb565(self.surface, color.Rgb565.fromHex(0), scrim_alpha);
    }

    /// Tonal elevation ladder (MD3 levels 0–4 → surface containers).
    pub fn elev(self: Theme, level: u3) color.Rgb565 {
        return switch (level) {
            0 => self.surface,
            1 => self.surface_container_low,
            2 => self.surface_container,
            3 => self.surface_container_high,
            else => self.surface_container_highest,
        };
    }

    /// WCAG-ish gate for key pairs. Thresholds allow RGB565 quantization loss.
    pub fn contrastOk(self: Theme) bool {
        const aa: f32 = 4.0;
        const ui: f32 = 2.5;
        return color.contrastRatio(self.on_surface.toHex(), self.surface.toHex()) >= aa and
            color.contrastRatio(self.on_primary.toHex(), self.primary.toHex()) >= aa and
            color.contrastRatio(self.on_primary_container.toHex(), self.primary_container.toHex()) >= aa and
            color.contrastRatio(self.outline.toHex(), self.surface.toHex()) >= ui;
    }

    /// User contrast 0=standard 1=medium 2=high (shop lighting). Applied after seed.
    pub fn applyContrastLevel(self: *Theme, level: u8) void {
        const R = color.Rgb565.fromHex;
        switch (level) {
            0 => {},
            1 => {
                // Medium — stronger outline + secondary text (readable under glare).
                if (self.dark) {
                    self.outline = R(0xD0D5DC);
                    self.outline_variant = R(0x7A8288);
                    self.on_surface_variant = R(0xF0F2F5);
                } else {
                    self.outline = R(0x1A2226);
                    self.outline_variant = R(0x5A6268);
                    self.on_surface_variant = R(0x1A2226);
                }
            },
            else => {
                // High — near max ink / paper on surfaces.
                if (self.dark) {
                    self.on_surface = R(0xFFFFFF);
                    self.on_surface_variant = R(0xFFFFFF);
                    self.outline = R(0xFFFFFF);
                    self.outline_variant = R(0xB0B8C0);
                } else {
                    self.on_surface = R(0x000000);
                    self.on_surface_variant = R(0x000000);
                    self.outline = R(0x000000);
                    self.outline_variant = R(0x404850);
                }
            },
        }
    }

    /// Regenerate full scheme from seed (HLS tonal — see palette.zig).
    pub fn applySeed(self: *Theme, seed: u24, dark: bool) void {
        @import("palette.zig").applySeedToTheme(self, seed, dark);
        self.bindCncAliases();
    }

    /// Force key pairs to AA after seed/accent mutation (RGB565-safe).
    pub fn ensureContrast(self: *Theme) void {
        const R = color.Rgb565.fromHex;
        self.ensurePair(&self.on_surface, self.surface);
        self.ensurePair(&self.on_surface_variant, self.surface);
        self.ensurePair(&self.on_primary, self.primary);
        self.ensurePair(&self.on_primary_container, self.primary_container);
        self.ensurePair(&self.on_secondary, self.secondary);
        self.ensurePair(&self.on_secondary_container, self.secondary_container);
        self.ensurePair(&self.on_tertiary, self.tertiary);
        self.ensurePair(&self.on_tertiary_container, self.tertiary_container);
        self.ensurePair(&self.on_error, self.err);
        if (color.contrastRatio(self.outline.toHex(), self.surface.toHex()) < 2.5) {
            self.outline = if (self.dark) R(0xC0C5CC) else R(0x1A2226);
        }
        // Last: re-lock CNC shop colors (never follow primary after seed).
        self.lockCncActionColors();
    }

    fn ensurePair(self: *Theme, on: *color.Rgb565, fill: color.Rgb565) void {
        _ = self;
        const fill_h = fill.toHex();
        const cb = color.contrastRatio(0x000000, fill_h);
        const cw = color.contrastRatio(0xFFFFFF, fill_h);
        on.* = color.Rgb565.fromHex(if (cb >= cw) 0x000000 else 0xFFFFFF);
    }
};

const std = @import("std");

test "theme elev ladder and pairs" {
    const t = Theme.industrialTealDark();
    const light = Theme.industrialTealLight();
    try std.testing.expect(t.dark);
    try std.testing.expect(!light.dark);
    try std.testing.expect(t.elev(0).toU16() != t.elev(4).toU16());
    try std.testing.expect(t.surface.toU16() != light.surface.toU16());
    try std.testing.expect(t.inverse_surface.toU16() != t.surface.toU16());
    try std.testing.expect(TypeRole.title_m.bitmapScale() == 2);
    try std.testing.expect(TypeRole.emph_body_m.emphasized());
    try std.testing.expect(!TypeRole.body_m.emphasized());
    try std.testing.expect(t.contrastOk());
    try std.testing.expect(WindowSizeClass.tab5() == .large);
    try std.testing.expect(t.cycle.toU16() != t.primary.toU16());
    try std.testing.expect(t.hold.toU16() != t.tertiary.toU16());
    try std.testing.expect(t.home.toU16() != t.secondary.toU16());
    try std.testing.expect(color.contrastRatio(t.on_cycle.toHex(), t.cycle.toHex()) >= 2.5);
    try std.testing.expect(color.contrastRatio(t.on_hold.toHex(), t.hold.toHex()) >= 2.5);
    try std.testing.expect(color.contrastRatio(t.on_home.toHex(), t.home.toHex()) >= 2.5);
    try std.testing.expect(color.contrastRatio(t.on_stop.toHex(), t.stop.toHex()) >= 2.5);
    try std.testing.expect(color.contrastRatio(t.on_error.toHex(), t.err.toHex()) >= 2.5);
    var seeded = Theme.industrialTealDark();
    seeded.applySeed(0xFF6B6B, true);
    try std.testing.expect(seeded.primary.toU16() != Theme.industrialTealDark().primary.toU16());
    // Color lock: seed must not retint Cycle Start.
    try std.testing.expect(seeded.cycle.toU16() == Theme.industrialTealDark().cycle.toU16());
    try std.testing.expect(seeded.contrastOk());
}

test "scrim is MD3 tonal over surface" {
    const dark = Theme.industrialTealDark();
    const light = Theme.industrialTealLight();
    const expect_dark = color.blendRgb565(dark.surface, color.Rgb565.fromHex(0), Theme.scrim_alpha);
    const expect_light = color.blendRgb565(light.surface, color.Rgb565.fromHex(0), Theme.scrim_alpha);
    try std.testing.expectEqual(expect_dark.toU16(), dark.scrim.toU16());
    try std.testing.expectEqual(expect_light.toU16(), light.scrim.toU16());
    // Light must not keep the old hard-coded near-black void.
    try std.testing.expect(light.scrim.toU16() != color.Rgb565.fromHex(0x0A0C12).toU16());
}
