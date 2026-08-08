#pragma once

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    MODULUS_I2C_SCAN_ALL = 0,
    MODULUS_I2C_SCAN_MBUS,
    MODULUS_I2C_SCAN_PORT_A,
    MODULUS_I2C_SCAN_EXP1,
    MODULUS_I2C_SCAN_EXP2,
} modulus_i2c_scan_target_t;

/** Known Tab5 I2C device name for address (ASCII, never NULL). */
const char *modulus_i2c_device_name(uint8_t addr);

/** Format probe result: "0x32 RX8130, 0x41 INA226" or "no devices". */
void modulus_i2c_format_addr_list(const uint8_t *addrs, uint8_t count, char *buf, size_t len);

void modulus_i2c_scan_init(void);

/** Non-blocking scan on worker task. Returns false if already busy. */
bool modulus_i2c_scan_start(modulus_i2c_scan_target_t target);

bool modulus_i2c_scan_busy(void);
bool modulus_i2c_scan_done(void);

const char *modulus_i2c_scan_status_text(void);
const char *modulus_i2c_scan_port_a_text(void);
const char *modulus_i2c_scan_mbus_text(void);
const char *modulus_i2c_scan_exp1_text(void);
const char *modulus_i2c_scan_exp2_text(void);

#ifdef __cplusplus
}
#endif
