#pragma once
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

void halt_gpio_init(void);
void halt_gpio_set(bool assert);
bool halt_gpio_is_asserted(void);

#ifdef __cplusplus
}
#endif
