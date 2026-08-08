#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int modulus_nvs_init(void);
bool modulus_nvs_has_u8(const char *key);
uint8_t modulus_nvs_get_u8(const char *key, uint8_t def);
/** Returns esp_err_t as int (0 = OK). */
int modulus_nvs_set_u8(const char *key, uint8_t val);
uint16_t modulus_nvs_get_u16(const char *key, uint16_t def);
int modulus_nvs_set_u16(const char *key, uint16_t val);
bool modulus_nvs_get_str(const char *key, char *buf, size_t buf_len);
int modulus_nvs_set_str(const char *key, const char *val);
/** Defer flash commit across many set_* calls (Core 1 maintenance flush). */
void modulus_nvs_begin_batch(void);
void modulus_nvs_end_batch(void);
int modulus_nvs_erase_all(void);
int modulus_factory_reset(void);

#ifdef __cplusplus
}
#endif
