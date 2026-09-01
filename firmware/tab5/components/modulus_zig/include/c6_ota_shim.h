#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define MODULUS_C6_OTA_MAX_FILES 8
#define MODULUS_C6_OTA_NAME_LEN 96
#define MODULUS_C6_OTA_STATUS_LEN 160

typedef enum {
    MODULUS_C6_OTA_IDLE = 0,
    MODULUS_C6_OTA_READY,
    MODULUS_C6_OTA_ARMED,
    MODULUS_C6_OTA_FLASHING,
    MODULUS_C6_OTA_SUCCESS,
    MODULUS_C6_OTA_ERROR,
} modulus_c6_ota_phase_t;

typedef struct {
    modulus_c6_ota_phase_t phase;
    uint8_t file_count;
    uint8_t selected;
    uint8_t progress;
    bool c6_connected;
    char c6_version[24];
    char files[MODULUS_C6_OTA_MAX_FILES][MODULUS_C6_OTA_NAME_LEN];
    char status[MODULUS_C6_OTA_STATUS_LEN];
} modulus_c6_ota_snapshot_t;

void modulus_c6_ota_refresh(void);
void modulus_c6_ota_select(uint8_t index);
void modulus_c6_ota_arm_selected(void);
void modulus_c6_ota_start(void);
void modulus_c6_ota_restart(void);
void modulus_c6_ota_get_snapshot(modulus_c6_ota_snapshot_t *out);

#ifdef __cplusplus
}
#endif
