#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void modulus_bridge_c6_set_hal_ready(bool ready);
bool modulus_bridge_c6_hal_ready(void);
void modulus_bridge_c6_delay_ms(uint32_t ms);
void modulus_bridge_c6_log_info(const char *msg);
void modulus_bridge_c6_log_heartbeat(uint32_t tick);

#ifdef __cplusplus
}
#endif
