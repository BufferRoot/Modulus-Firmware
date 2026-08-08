#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Initialise UART driver with config loaded from NVS */
void     uart_bridge_init();

/* Re-initialise UART after a baud/GPIO change (from shell) */
void     uart_bridge_reinit(uint32_t baud, int tx_gpio, int rx_gpio);

/* (Re-)send 0x8B to activate MPG mode on grblHAL Flexi-HAL */
void     uart_bridge_mpg_activate();

/* Queue bytes for UART TX → grblHAL (ESP-NOW worker or shell) */
void     uart_bridge_send(const uint8_t* data, size_t len);

/* Runtime tunables (persisted in NVS) */
uint32_t uart_bridge_batch_ms();
void     uart_bridge_set_batch_ms(uint32_t ms);
bool     uart_bridge_led_enabled();
void     uart_bridge_set_led_enabled(bool on);

/* Accessors for the status shell */
uint32_t uart_bridge_baud();
int      uart_bridge_tx_gpio();
int      uart_bridge_rx_gpio();
uint32_t uart_bridge_bytes_tx();    // bytes sent to grblHAL
uint32_t uart_bridge_bytes_rx();    // bytes received from grblHAL → Tab5
uint32_t uart_bridge_uart_tx_fails();
size_t   uart_bridge_rx_buffered(); // bytes waiting in UART RX driver

bool     uart_bridge_self_check();
void     uart_bridge_reset_stats();

#ifdef __cplusplus
}
#endif
