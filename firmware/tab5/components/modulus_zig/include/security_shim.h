#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void modulus_security_init(void);
bool modulus_security_has_pin(void);
bool modulus_security_lock_on_boot(void);
bool modulus_security_lock_on_sleep(void);
uint16_t modulus_security_lock_timeout(void);
bool modulus_security_is_locked(void);
void modulus_security_lock(void);
void modulus_security_unlock(void);
bool modulus_security_verify_pin(const char *pin);
bool modulus_security_set_pin(const char *pin);
bool modulus_security_clear_pin(const char *current_pin);
void modulus_security_on_sleep_wake(int64_t sleep_start_us);
bool modulus_security_idle_lock_enabled(void);
uint16_t modulus_security_idle_lock_timeout(void);
void modulus_security_idle_lock_tick(uint32_t inactive_ms);

#ifdef __cplusplus
}
#endif
