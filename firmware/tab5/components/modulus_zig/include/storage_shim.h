#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    MODULUS_SD_NOT_PRESENT = 0,
    MODULUS_SD_MOUNTED,
    MODULUS_SD_ERROR,
} modulus_sd_state_t;

typedef struct {
    modulus_sd_state_t state;
    uint64_t total_bytes;
    uint64_t free_bytes;
    uint8_t bus_width;
} modulus_sd_info_t;

typedef struct {
    size_t internal_free;
    size_t internal_total;
    size_t internal_min_free;
    size_t psram_free;
    size_t psram_total;
    size_t lvgl_free;       /* PSRAM largest free block (CLIB malloc path) */
    uint8_t lvgl_used_pct;  /* PSRAM used percent (shared C heap, not LVGL TLSF) */
} modulus_mem_info_t;

void modulus_storage_init(void);
bool modulus_storage_mount(void);
void modulus_storage_unmount(void);
bool modulus_storage_is_mounted(void);
void modulus_storage_get_sd_info(modulus_sd_info_t *out);
void modulus_storage_get_mem_info(modulus_mem_info_t *out);
bool modulus_storage_export_diagnostics(const char *path);
/** Export NVS settings JSON to path. include_secrets=false skips passwords/PIN. */
bool modulus_storage_export_settings(const char *path, bool include_secrets);
/** Import settings JSON from path. Returns false on I/O or parse failure. */
bool modulus_storage_import_settings(const char *path, bool include_secrets);
void modulus_storage_clear_ui_cache(void);
bool modulus_storage_is_usb_host_enabled(void);
/** Human status for Settings — host-data detect is BSP-pending. */
const char *modulus_storage_usb_host_status_text(void);

#ifdef __cplusplus
}
#endif
