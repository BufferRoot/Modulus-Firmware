#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void modulus_i2c_coex_init(void);
bool modulus_i2c_coex_lock(uint32_t timeout_ms);
void modulus_i2c_coex_unlock(void);

#ifdef __cplusplus
}
#endif
