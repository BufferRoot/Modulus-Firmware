#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Lazy Port A bus init; safe to call from Core 1 poll loop. */
void modulus_ext_encoder_hw_init(void);

void modulus_ext_encoder_hw_deinit(void);

/**
 * Probe / read ExtEncoder @ 0x59. Updates *connected and *count on success.
 * Returns false when disconnected or I2C read failed (clears connected).
 */
bool modulus_ext_encoder_hw_maintain(bool *connected, int32_t *count, uint8_t *fw_version);

/** Serial trace @ ESP_LOGV — enable Settings → Log level = Verbose. */
void modulus_ext_encoder_trace_wheel(int32_t count, int32_t delta, bool mpg_active, char axis,
                                     uint8_t machine_state, int32_t jog_steps, float jog_mm,
                                     uint8_t block_code);

/** Periodic disconnected/connected status @ ESP_LOGV (~10 s). */
void modulus_ext_encoder_trace_status(bool connected, uint8_t fw_version);

/** Reset Port A detect backoff when EXT5V rail changes (Power settings). */
void modulus_ext_encoder_notify_ext5v(bool enabled);

/** Immediate re-probe (Storage → Scan Port A, EXT5V on). */
void modulus_ext_encoder_force_detect(void);

/** Release Port A device handle during I2C bus scan (Storage diagnostics). */
void modulus_ext_encoder_scan_begin(void);
void modulus_ext_encoder_scan_end(void);

#ifdef __cplusplus
}
#endif
