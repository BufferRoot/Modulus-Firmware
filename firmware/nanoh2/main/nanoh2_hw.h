#pragma once

/**
 * M5Stack NanoH2 (SKU C149) — ESP32-H2FH4S board pins.
 * Schematic: SCH_M5NanoH2_v0.0.3. Docs header "ESP32-C6FH4" is wrong; SoC is H2.
 *
 * Flash: hold BUTTON (GPIO9), then plug USB-C → download mode.
 */

#define NANOH2_GPIO_GROVE_SCL 1 /* Grove white */
#define NANOH2_GPIO_GROVE_SDA 2 /* Grove yellow */
#define NANOH2_GPIO_IR        3
#define NANOH2_GPIO_LED       4 /* blue */
#define NANOH2_GPIO_BTN       9 /* user + boot strap (active low) */
#define NANOH2_GPIO_RGB_EN   10 /* HIGH = WS2812 powered (AW35122) */
#define NANOH2_GPIO_RGB_DI   11

/* Grove port is repurposed as the UART link to the Tab5 (P4 UART2):
 *   G1 (white)  = H2 TX -> P4 GPIO7 (M5BUS pin 15, RXD2)
 *   G2 (yellow) = H2 RX <- P4 GPIO6 (M5BUS pin 16, TXD2)
 * Grove 5V from M5BUS pin 28 (SYS_EXT5VO), GND to M5BUS GND. */
#define NANOH2_UART_TX NANOH2_GPIO_GROVE_SCL /* GPIO1 */
#define NANOH2_UART_RX NANOH2_GPIO_GROVE_SDA /* GPIO2 */
