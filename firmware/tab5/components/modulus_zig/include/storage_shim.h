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
/** FAT32 format + recreate /sdcard/modulus layout. Erases all card data. */
bool modulus_storage_format_sd(void);
void modulus_storage_get_sd_info(modulus_sd_info_t *out);
void modulus_storage_get_mem_info(modulus_mem_info_t *out);
bool modulus_storage_export_diagnostics(const char *path);
/** Export NVS settings JSON to path. include_secrets=false skips passwords/PIN. */
bool modulus_storage_export_settings(const char *path, bool include_secrets);
/** Import settings JSON from path. Returns false on I/O or parse failure. */
bool modulus_storage_import_settings(const char *path, bool include_secrets);
void modulus_storage_clear_ui_cache(void);
/** True when ≥1 USB device enumerated (VBUS on + host stack). */
bool modulus_storage_is_usb_host_enabled(void);

/** True only once an MSC volume is actually mounted at /usb.
 *  modulus_storage_is_usb_host_enabled() counts ANY enumerated USB device
 *  (keyboard, hub, …) — gate the file manager on this instead. */
bool modulus_storage_usb_volume_mounted(void);
/** Human status: "VBUS off" / "No device" / "Device linked" / fail. */
const char *modulus_storage_usb_host_status_text(void);

/** USB MSC G-code catalog at /usb (empty until MSC mount lands). */
size_t modulus_usb_volume_refresh(void);
bool modulus_usb_volume_name(size_t index, char *buf, size_t cap);
bool modulus_usb_volume_delete(size_t index);
bool modulus_usb_volume_rename(size_t index, const char *new_name);
bool modulus_usb_volume_eject(void);

/** Max characters kept per G-code line in the View pane; longer lines are
 *  truncated rather than wrapped. */
#define MODULUS_USB_VIEW_LINE_MAX 96

/** Read up to `max_lines` NUL-terminated lines starting at `first_line`.
 *  Offsets into `buf` are written to `line_offsets`. Returns lines written.
 *  Line-oriented on purpose — G-code files are far too large to slurp. */
size_t modulus_usb_volume_read_lines(size_t index,
                                     size_t first_line,
                                     char *buf,
                                     size_t buf_cap,
                                     uint16_t *line_offsets,
                                     size_t max_lines);

/** Total lines in the file — drives the viewer scrollbar and "N of M". */
size_t modulus_usb_volume_line_count(size_t index);

/** Organized SD layout under /sdcard/modulus/{logs,backups,...}. */
typedef enum {
    MODULUS_SD_VOL_LOGS = 0,
    MODULUS_SD_VOL_BACKUPS,
    MODULUS_SD_VOL_MACROS,
    MODULUS_SD_VOL_SCRIPTS,
    MODULUS_SD_VOL_REPORTS,
    MODULUS_SD_VOL_CACHE,
} modulus_sd_vol_folder_t;

#define MODULUS_SD_VOL_FOLDER_COUNT 6

bool modulus_sd_volume_ensure_layout(void);
const char *modulus_sd_volume_folder_rel(modulus_sd_vol_folder_t folder);
size_t modulus_sd_volume_refresh(modulus_sd_vol_folder_t folder);
bool modulus_sd_volume_name(size_t index, char *buf, size_t cap);
bool modulus_sd_volume_delete(modulus_sd_vol_folder_t folder, size_t index);
bool modulus_sd_volume_backup_path(char *out, size_t cap);
bool modulus_sd_volume_log_path(char *out, size_t cap);
bool modulus_sd_volume_entry_path(modulus_sd_vol_folder_t folder, size_t index, char *out, size_t cap);

#ifdef __cplusplus
}
#endif
