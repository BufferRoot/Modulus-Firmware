#pragma once

#include <driver/i2c_master.h>
#include <stdbool.h>
#include <time.h>

#ifdef __cplusplus
extern "C" {
#endif

bool rx8130_begin(i2c_master_bus_handle_t bus, uint8_t addr);
void rx8130_init_bat(void);
void rx8130_set_time(struct tm *time);
bool rx8130_get_time(struct tm *time);
void rx8130_clear_irq_flags(void);
void rx8130_disable_irq(void);
bool rx8130_is_ready(void);
bool rx8130_voltage_low(void);
void rx8130_set_timer_irq(uint16_t seconds);

#ifdef __cplusplus
}
#endif
