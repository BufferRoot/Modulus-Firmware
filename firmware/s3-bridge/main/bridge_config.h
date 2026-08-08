/*
 * ESP32-S3-MINI-1  ESP-NOW ↔ UART Bridge  (grblHAL full-duplex serial interface)
 * ─────────────────────────────────────────────────────────────────────────
 * Module: ESP32-S3-MINI-1 on I2C_ESP32_Module / handwheel board (schematic A1).
 * Replaces prior ESP32-S3-WROOM-1 dev kit (UART GPIO17/18, WS2812 GPIO48).
 *
 * Signal flow:
 *   Tab5 (ESP-NOW) ──► ESP32-S3 TX ──► grblHAL UART RX   (commands)
 *   grblHAL UART TX ──► ESP32-S3 RX ──► Tab5 (ESP-NOW)   (status / DRO)
 *
 * Wiring (UART1 — all GPIOs remappable via NVS shell):
 *
 *  Flexi-HAL exposes USART6 on the pendant/remote header:
 *    PC6 = USART6_TX  (STM32 transmits status/responses)
 *    PC7 = USART6_RX  (STM32 receives G-code commands)
 *
 *  Handwheel-interface board: the pads silk-screened SDA_host / SCL_host
 *  (I2C_ESP32_Module schematic) are repurposed here as the grblHAL UART.
 *
 *  ┌─────────────────────┬──────────────────────────────────────────────┐
 *  │  ESP32-S3 GPIO      │  Flexi-HAL pin (STM32F446 USART6)           │
 *  ├─────────────────────┼──────────────────────────────────────────────┤
 *  │  GPIO8  (TX, SDA)   │  PC7  — USART6_RX  (S3 sends commands → HAL) │
 *  │  GPIO9  (RX, SCL)   │  PC6  — USART6_TX  (HAL sends status  → S3)  │
 *  │  GND                │  GND                                         │
 *  └─────────────────────┴──────────────────────────────────────────────┘
 *
 *  ⚠  Cross-connect TX→RX and RX→TX (standard UART — never TX→TX).
 *  3.3V logic — both ESP32-S3 and STM32F446 are 3V3 tolerant.
 *  No level shifter required for direct connection.
 *
 *  ⚠  If the S3 has been flashed before, NVS may still hold a saved baud
 *     rate (e.g. 921600 from an older build).  Type 'baud 115200' in the
 *     shell to force-save it, then 'status' to confirm.
 *
 *  Optional hardware flow control (RTS/CTS):
 *    UART_RTS_GPIO / UART_CTS_GPIO — set to -1 to disable (default).
 *
 * Baud rate:
 *   Default 115200 — configurable via shell ('baud' command).
 *   Supported: 115200 / 230400 / 460800 / 921600
 *   Teensy 4.1 grblHAL firmware defaults to 115200; raise with 'baud' command if needed.
 *
 * Shell commands (UART0 / USB-CDC 115200):
 *   channel <1-13>   - ESP-NOW Wi-Fi channel (live apply)
 *   stats reset      – clear traffic / fail counters
 *   baud <rate>      – UART baud rate (115200 / 230400 / 460800 / 921600)
 *   txgpio <n>       – UART TX GPIO
 *   rxgpio <n>       – UART RX GPIO
 *   batchms <1-20>  – UART→ESP-NOW batch wait (ms)
 *   led on|off      – activity LED pulses
 *   status           – print current config and counters
 *   help             – list commands
 */
#pragma once

// ── ESP-NOW ───────────────────────────────────────────────────────────────────
#define ESPNOW_DEFAULT_CHANNEL   1       // must match Tab5 Settings -> Protocols
#define ESPNOW_MAX_PAYLOAD       1470    // ESP-NOW v2 ceiling (IDF 6)
#define ESPNOW_QUEUE_DEPTH       24      // inbound depth (trade size vs RAM vs 250x64)

// ── UART (grblHAL serial connection) ─────────────────────────────────────────
#define UART_PORT_NUM            UART_NUM_1      // UART0 is reserved for debug shell
#define UART_DEFAULT_BAUD        115200          // Teensy 4.1 grblHAL default
#define UART_TX_GPIO             8               // SDA_host pad — ESP32-S3 → grblHAL RX
#define UART_RX_GPIO             9               // SCL_host pad — grblHAL TX → ESP32-S3
#define UART_RTS_GPIO            (-1)            // -1 = disabled (no H/W flow ctrl)
#define UART_CTS_GPIO            (-1)            // -1 = disabled
#define UART_RX_BUF_SIZE         (8192)          // 8K — absorbs grblHAL status bursts without drop
#define UART_TX_BUF_SIZE         (4096)          // 4K — enough depth for multi-command queuing
#define UART_RX_BATCH_MS         2               // default ms wait for first byte (shell: batchms)
#define UART_RX_BATCH_MAX        1470            // max bytes per ESP-NOW send (v2 ceiling)

// ── Activity LEDs (discrete, GPIO-driven, active-high through series R) ───────────
//   Handwheel board carries two single-colour LEDs (I2C_ESP32_Module schematic):
//     LED_R / D3 (GPIO45) — pulses on data SENT      (S3 → grblHAL)
//     LED_G / D2 (GPIO46) — pulses on data RECEIVED  (grblHAL → S3)
//   NOTE: these are plain GPIO LEDs (gpio_set_level drive in uart_bridge.cpp),
//   NOT the WS2812 used on the old GPIO48 board. activity_led_pulse_tx/rx()
//   pulse them independently for the send and receive directions.
#define LED_TX_GPIO              45              // Red   — TX / send-data activity
#define LED_RX_GPIO              46              // Green — RX / receive-data activity
#define LED_PULSE_US             80000           // 80 ms ON duration (microseconds)

// ── grblHAL hardware E-stop (I2C_ESP32_Module schematic) ─────────────────────
#define HALT_HOST_GPIO           37              // HALT_host — active LOW (pull-up on host)

// ── NVS keys ──────────────────────────────────────────────────────────────────
#define NVS_NAMESPACE            "s3uart"
#define NVS_KEY_CHANNEL          "espnow_ch"
#define NVS_KEY_TAB5_MAC         "tab5_mac"
#define NVS_KEY_BAUD             "uart_baud"
#define NVS_KEY_TX_GPIO          "uart_tx"
#define NVS_KEY_RX_GPIO          "uart_rx"
#define NVS_KEY_BATCH_MS         "batch_ms"
#define NVS_KEY_LED_EN           "led_en"
