//! Zigbee QS tile icon by functional purpose (caps + name/model/devdb text).

const std = @import("std");
const icons_phosphor = @import("icons_phosphor.zig");
const settings_prefs = @import("settings_prefs.zig");
const ascii_util = @import("ascii_util.zig");

pub const Purpose = enum(u8) {
    safety,
    motion,
    climate,
    lighting,
    power,
    security,
    switches,
    remotes,
    unknown,
};

pub fn icon(p: Purpose) icons_phosphor.Id {
    return switch (p) {
        .safety => .warning_diamond,
        .motion => .person_simple_run,
        .climate => .thermometer_simple,
        .lighting => .lightbulb_filament,
        .power => .plugs,
        .security => .security_camera,
        .switches => .lightning_a,
        .remotes => .hand_withdraw,
        .unknown => .lightning,
    };
}

fn anyOf(hay: []const u8, needles: []const []const u8) bool {
    for (needles) |n| {
        if (ascii_util.containsIgnoreCase(hay, n)) return true;
    }
    return false;
}

fn hitText(name: []const u8, model: []const u8, desc: []const u8, needles: []const []const u8) bool {
    return anyOf(name, needles) or anyOf(model, needles) or anyOf(desc, needles);
}

/// Classify device purpose for QS icon. Keyword hits beat caps; caps fill gaps.
pub fn classify(caps: u8, name: []const u8, model: []const u8, desc: []const u8) Purpose {
    const Z = settings_prefs.ZbCap;

    // 1 Safety & Environment
    if (hitText(name, model, desc, &.{
        "leak", "flood", "smoke", "carbon", "monoxide", "gas detect", "gas sensor", "water leak",
    })) return .safety;

    // 2 Motion & Presence
    if (hitText(name, model, desc, &.{
        "motion", "pir", "presence", "mmwave", "occupancy", "contact", "door", "window", "magnetic",
    })) return .motion;

    // 3 Climate & Air
    if (hitText(name, model, desc, &.{
        "temperature", "humidity", "thermo", "trv", "radiator", "climate", "air quality", "voc", "pm2",
    })) return .climate;

    // 4 Lighting & Illumination
    if (hitText(name, model, desc, &.{
        "bulb", "light", "led", "dimmer", "filament", "lamp", "strip", "luminaire",
    })) return .lighting;

    // 5 Power & Energy
    if (hitText(name, model, desc, &.{
        "plug", "outlet", "socket", "energy", "meter", "relay", "power monitor",
    })) return .power;

    // 6 Security & Access
    if (hitText(name, model, desc, &.{
        "lock", "siren", "alarm", "beacon", "camera", "keypad", "security",
    })) return .security;

    // 7 Switches & Controls
    if (hitText(name, model, desc, &.{
        "wall switch", "in-wall", "in wall", "smart switch", "light switch", "module",
    })) return .switches;

    // 8 Remotes & Interfaces
    if (hitText(name, model, desc, &.{
        "remote", "button", "dial", "knob", "scene", "wireless switch", "puck", "fob",
    })) return .remotes;

    // Caps fallback (HA simple-descriptor bits).
    if ((caps & Z.thermostat) != 0) return .climate;
    if ((caps & (Z.level | Z.color)) != 0) return .lighting;
    if ((caps & (Z.power | Z.meter)) != 0) return .power;
    if ((caps & Z.sensor) != 0) return .motion;
    if ((caps & Z.cover) != 0) return .switches;
    if ((caps & Z.onoff) != 0) return .switches;
    if (ascii_util.containsIgnoreCase(name, "switch")) return .switches;
    if (ascii_util.containsIgnoreCase(name, "sensor")) return .motion;
    return .unknown;
}

pub fn classifySnap(name: []const u8, snap: settings_prefs.ZbDevSnap) Purpose {
    return classify(snap.caps, name, snap.modelSlice(), snap.descSlice());
}

test "zb purpose: door contact is motion" {
    try std.testing.expectEqual(Purpose.motion, classify(settings_prefs.ZbCap.sensor, "Door contact", "", ""));
}

test "zb purpose: bulb keyword and level cap" {
    try std.testing.expectEqual(Purpose.lighting, classify(0, "Kitchen bulb", "", ""));
    try std.testing.expectEqual(Purpose.lighting, classify(settings_prefs.ZbCap.level, "Dev 1", "", ""));
}

test "zb purpose: plug and smoke" {
    try std.testing.expectEqual(Purpose.power, classify(settings_prefs.ZbCap.onoff, "Smart plug", "", ""));
    try std.testing.expectEqual(Purpose.safety, classify(settings_prefs.ZbCap.sensor, "Smoke alarm", "", "smoke detector"));
}

test "zb purpose: icon mapping" {
    try std.testing.expectEqual(icons_phosphor.Id.plugs, icon(.power));
    try std.testing.expectEqual(icons_phosphor.Id.warning_diamond, icon(.safety));
}
