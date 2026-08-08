#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* port: 0 = RS-485 (UART1 TX20/RX21/DE34), 1 = USB serial (UART0) */
bool modulus_serial_open(uint8_t port, uint32_t baud, uint8_t data_bits, uint8_t parity,
                         uint8_t stop_bits);
void modulus_serial_close(void);
bool modulus_serial_is_open(void);
int modulus_serial_write(const uint8_t *data, size_t len);
int modulus_serial_read(uint8_t *buf, size_t max_len);

typedef void (*modulus_serial_rx_fn)(const uint8_t *data, size_t len);
void modulus_serial_set_rx_handler(modulus_serial_rx_fn handler);

#ifdef __cplusplus
}
#endif
