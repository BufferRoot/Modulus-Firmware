#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/** NVS `en_log`: 0=off, 1=debug, 2=verbose. Persists across reboot. */
#define MODULUS_ESPNOW_LOG_OFF     0
#define MODULUS_ESPNOW_LOG_DEBUG   1
#define MODULUS_ESPNOW_LOG_VERBOSE 2

uint8_t modulus_espnow_log_level(void);
void modulus_espnow_log_set_level(uint8_t level);
bool modulus_espnow_log_active(void);

void modulus_espnow_debug_event(const char *tag, const char *fmt, ...)
    __attribute__((format(printf, 2, 3)));

/** Human-readable CNC/transport snapshot for settings UI (static buffer). */
const char *modulus_espnow_debug_snapshot(void);

/** Last recorded transition (static buffer). */
const char *modulus_espnow_debug_last_event(void);

/** Apply esp_log_level_set for wl_espnow / espnow_tx tags. */
void modulus_espnow_debug_apply_log_tags(void);
