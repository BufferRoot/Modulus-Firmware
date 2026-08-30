#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/** Idle-high pull-ups on C6 UART0 (GPIO16/17) when debug cable removed. */
void modulus_c6_board_uart_pullups(void);

#ifdef __cplusplus
}
#endif
