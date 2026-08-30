#pragma once

#include <stdbool.h>

bool modulus_ble_host_ensure(void);
bool modulus_ble_host_ready(void);
/** True after HCI/SDIO failure (reset streak or ensure fail). */
bool modulus_ble_host_failed(void);
/** After sync timeout or controller fail — allows next ensure() to re-probe. */
void modulus_ble_host_reset(void);
