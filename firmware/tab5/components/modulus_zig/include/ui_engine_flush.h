#pragma once

/**
 * Zig UI-engine → Tab5 panel present ABI.
 *
 * Dual DPI FB (CONFIG_BSP_LCD_DPI_BUFFER_NUMS≥2): rotate into the back buffer,
 * then `modulus_ui_engine_flush_flip` switches DMA via draw_bitmap(FB addr).
 * Single FB: rotate into the live scanout + cache write-back of dirty rows.
 *
 * Coordinates are portrait panel space (720×1280). Core 0 only.
 */

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <esp_err.h>
#include <esp_lcd_types.h>

#ifdef __cplusplus
extern "C" {
#endif

struct _lv_display_t;
typedef struct _lv_display_t lv_display_t;

void modulus_ui_engine_flush_bind_panel(esp_lcd_panel_handle_t panel);
esp_lcd_panel_handle_t modulus_ui_engine_flush_panel(void);
void modulus_ui_engine_flush_try_bind_from_lvgl(lv_display_t *disp);

/** True when panel handle + DPI scanout FB are bound. */
bool modulus_ui_engine_flush_ready(void);

/** Current back buffer Zig paints into (updates after flip). */
uint16_t *modulus_ui_engine_flush_scanout(void);
uint32_t modulus_ui_engine_flush_scanout_px(void);

/** True when ≥2 DPI FBs are bound (tear-free flip path). */
bool modulus_ui_engine_flush_dual(void);

/** Cache write-back of dirty rows on the current back buffer. */
esp_err_t modulus_ui_engine_flush_rows(uint16_t y0, uint16_t y1);

/** Dual-FB: make the current back the scanned buffer; advance back pointer. */
esp_err_t modulus_ui_engine_flush_flip(void);

/** Take over the DPI refresh-done callback so flip waits for vsync.
 *  Call ONLY after lvgl_port_remove_disp() — it replaces esp_lvgl_port's
 *  callbacks, and an orphaned LVGL flush spins taskLVGL into a task WDT. */
void modulus_ui_engine_flush_enable_vsync(void);

uint32_t modulus_ui_engine_flush_last_px(void);

#ifdef __cplusplus
}
#endif
