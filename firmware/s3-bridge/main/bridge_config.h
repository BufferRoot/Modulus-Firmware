/*
 * ESP32-S3 ESP-NOW ↔ UART Bridge  (grblHAL full-duplex serial interface)
 * ─────────────────────────────────────────────────────────────────────────
 * Pin maps live in bridge_board.cpp. USB shell `board` lists profiles;
 * `board <id>` saves pinout (ESP32-S3 image only).
 *
 *   Tab5 (ESP-NOW) ──► S3 TX ──► grblHAL RX
 *   grblHAL TX ──► S3 RX ──► Tab5
 *
 * Cross TX↔RX. 3.3 V. Custom pins: txgpio / rxgpio after board select.
 */
#pragma once

#include <driver/uart.h>

#define ESPNOW_DEFAULT_CHANNEL   1
#define ESPNOW_MAX_PAYLOAD       1470
#define ESPNOW_QUEUE_DEPTH       24      /* Tab5 → UART (keep commands) */
#define ESPNOW_OUTBOUND_DEPTH    16      /* UART → Tab5 (drop oldest if full) */
#define ESPNOW_TX_LOCK_MS        200
#define ESPNOW_TX_WAIT_MS        200

#define UART_PORT_NUM            UART_NUM_1
#define UART_DEFAULT_BAUD        921600
#define UART_RTS_GPIO            (-1)
#define UART_CTS_GPIO            (-1)
#define UART_RX_BUF_SIZE         (16384)
#define UART_TX_BUF_SIZE         (4096)
#define UART_RX_BATCH_MS         2       /* first-byte + inter-byte idle coalesce */
#define UART_RX_BATCH_MAX        1470
#define UART_TX_WAIT_MS          100
#define UART_EVT_QUEUE_LEN       20

#define LED_PULSE_US             80000

#define NVS_NAMESPACE            "s3uart"
#define NVS_KEY_CHANNEL          "espnow_ch"
#define NVS_KEY_TAB5_MAC         "tab5_mac"
#define NVS_KEY_BAUD             "uart_baud"
#define NVS_KEY_TX_GPIO          "uart_tx"
#define NVS_KEY_RX_GPIO          "uart_rx"
#define NVS_KEY_BATCH_MS         "batch_ms"
#define NVS_KEY_LED_EN           "led_en"
#define NVS_KEY_BOARD            "board"
#define NVS_KEY_BOARD_MAX        24
