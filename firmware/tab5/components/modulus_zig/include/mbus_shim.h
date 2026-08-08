#pragma once

#include <driver/i2c_master.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    MODULUS_MBUS_INTERNAL = 0,
    MODULUS_MBUS_PORT_A,
    MODULUS_MBUS_REAR,
    MODULUS_MBUS_EXP1, /* PI4IOE1 0x43 on internal M-Bus */
    MODULUS_MBUS_EXP2, /* PI4IOE2 0x44 on internal M-Bus */
    MODULUS_MBUS_COUNT,
} modulus_mbus_id_t;

typedef struct {
    modulus_mbus_id_t id;
    const char *label;
    bool ready;
    uint8_t addr_count;
    uint8_t addrs[16];
} modulus_mbus_scan_t;

void modulus_mbus_init(void);
/** Lazy Port A bus (I2C1 / G53/G54); NULL until first scan or transport open. */
i2c_master_bus_handle_t modulus_mbus_port_a_bus(void);
bool modulus_mbus_port_a_ensure(void);
/** Re-run EXT5V settle delay after rail toggle. */
void modulus_mbus_port_a_power_invalidate(void);
bool modulus_mbus_scan(modulus_mbus_id_t bus, modulus_mbus_scan_t *out);
const char *modulus_mbus_label(modulus_mbus_id_t bus);

#ifdef __cplusplus
}
#endif
