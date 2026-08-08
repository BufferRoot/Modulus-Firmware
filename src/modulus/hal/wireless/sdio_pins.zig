//! Tab5 ESP32-C6 SDIO2 pin map — frozen for ESP-Hosted transport.

pub const clk_gpio: u8 = 12;
pub const cmd_gpio: u8 = 13;
pub const d0_gpio: u8 = 11;
pub const d1_gpio: u8 = 10;
pub const d2_gpio: u8 = 9;
pub const d3_gpio: u8 = 8;
pub const rst_gpio: u8 = 15;

pub const esp_espnow_if: u8 = 8;
pub const esp_zigbee_if: u8 = 9;
pub const esp_thread_if: u8 = 10;

test "hal: sdio pin constants" {
    const std = @import("std");
    try std.testing.expectEqual(@as(u8, 12), clk_gpio);
    try std.testing.expectEqual(@as(u8, 15), rst_gpio);
    try std.testing.expectEqual(@as(u8, 8), esp_espnow_if);
}
