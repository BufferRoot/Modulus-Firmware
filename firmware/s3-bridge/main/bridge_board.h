#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    const char *id;
    const char *vendor;
    const char *name;
    int uart_tx;
    int uart_rx;
    int led_tx;
    int led_rx;
    int led_on; /* 1 = active high */
    int halt;
} bridge_board_t;

void bridge_board_init(void);
const bridge_board_t *bridge_board_get(void);
int bridge_board_set(const char *id); /* 0 ok, -1 unknown */
void bridge_board_print_list(void);

#ifdef __cplusplus
}
#endif
