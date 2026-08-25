/*
 * Zig UI-engine → MIPI panel present.
 *
 * Dual DPI FB (CONFIG_BSP_LCD_DPI_BUFFER_NUMS=2): rotate into the back buffer,
 * then esp_lcd_panel_draw_bitmap(panel, …, back) flips DMA to that buffer
 * (driver treats a registered FB address as a swap, not a copy). Single-FB
 * fallback: rotate into the live scanout + cache write-back of dirty rows.
 */
#include "ui_engine_flush.h"

#include <string.h>

#include <sdkconfig.h>
#include <esp_cache.h>
#include <esp_lcd_mipi_dsi.h>
#include <esp_lcd_panel_ops.h>
#include <esp_log.h>
#include <esp_lvgl_port.h>
#include <lvgl.h>

static const char *TAG = "ui_engine_flush";
static uint32_t s_last_px;
static esp_lcd_panel_handle_t s_panel;
static uint16_t *s_fb[3];
static uint8_t s_num_fbs;
static uint8_t s_back; /* index Zig paints into */
static uint16_t *s_scanout;

enum {
    k_panel_w = 720,
    k_panel_h = 1280,
    k_fb_px = k_panel_w * k_panel_h,
};

static void bind_scanout(void)
{
    void *fb0 = NULL;
    void *fb1 = NULL;
    void *fb2 = NULL;

    /* Prefer dual FB when the BSP allocated them. */
    if (esp_lcd_dpi_panel_get_frame_buffer(s_panel, 2, &fb0, &fb1) == ESP_OK && fb0 && fb1) {
        s_fb[0] = fb0;
        s_fb[1] = fb1;
        s_num_fbs = 2;
        s_back = 1; /* scan fb0 while we paint fb1 */
        /* Seed back from the currently scanned buffer so the first flip is clean. */
        memcpy(s_fb[1], s_fb[0], (size_t)k_fb_px * sizeof(uint16_t));
        (void)esp_cache_msync(s_fb[1], (size_t)k_fb_px * sizeof(uint16_t),
                              ESP_CACHE_MSYNC_FLAG_DIR_C2M | ESP_CACHE_MSYNC_FLAG_UNALIGNED);
        s_scanout = s_fb[s_back];
        ESP_LOGI(TAG, "dual DPI FB %p / %p (back=%u) — tear-free flip", fb0, fb1, (unsigned)s_back);
        return;
    }

    if (esp_lcd_dpi_panel_get_frame_buffer(s_panel, 3, &fb0, &fb1, &fb2) == ESP_OK && fb0 && fb1 && fb2) {
        s_fb[0] = fb0;
        s_fb[1] = fb1;
        s_fb[2] = fb2;
        s_num_fbs = 3;
        s_back = 1;
        memcpy(s_fb[1], s_fb[0], (size_t)k_fb_px * sizeof(uint16_t));
        (void)esp_cache_msync(s_fb[1], (size_t)k_fb_px * sizeof(uint16_t),
                              ESP_CACHE_MSYNC_FLAG_DIR_C2M | ESP_CACHE_MSYNC_FLAG_UNALIGNED);
        s_scanout = s_fb[s_back];
        ESP_LOGI(TAG, "triple DPI FB — using back=%u", (unsigned)s_back);
        return;
    }

    fb0 = NULL;
    const esp_err_t err = esp_lcd_dpi_panel_get_frame_buffer(s_panel, 1, &fb0);
    if (err != ESP_OK || !fb0) {
        ESP_LOGE(TAG, "no DPI frame buffer (%s) — Zig scanout unavailable",
                 esp_err_to_name(err));
        s_num_fbs = 0;
        s_scanout = NULL;
        return;
    }
    s_fb[0] = fb0;
    s_num_fbs = 1;
    s_back = 0;
    s_scanout = s_fb[0];
    ESP_LOGW(TAG, "single DPI FB %p — compose-in-place (enable CONFIG_BSP_LCD_DPI_BUFFER_NUMS=2)", fb0);
}

void modulus_ui_engine_flush_bind_panel(esp_lcd_panel_handle_t panel)
{
    s_panel = panel;
    ESP_LOGI(TAG, "panel bind %p", (void *)panel);
    bind_scanout();
}

uint16_t *modulus_ui_engine_flush_scanout(void)
{
    return s_scanout;
}

uint32_t modulus_ui_engine_flush_scanout_px(void)
{
    return s_scanout ? (uint32_t)k_fb_px : 0u;
}

bool modulus_ui_engine_flush_dual(void)
{
    return s_num_fbs >= 2;
}

esp_err_t modulus_ui_engine_flush_rows(uint16_t y0, uint16_t y1)
{
    if (!s_scanout) {
        return ESP_ERR_INVALID_STATE;
    }
    if (y1 > k_panel_h || y0 >= y1) {
        return ESP_ERR_INVALID_ARG;
    }
    /* Dual-FB path: cache sync only — flip happens in flush_flip(). */
    const size_t row_bytes = (size_t)k_panel_w * sizeof(uint16_t);
    s_last_px = (uint32_t)(y1 - y0) * (uint32_t)k_panel_w;
    return esp_cache_msync(
        s_scanout + (size_t)y0 * k_panel_w,
        (size_t)(y1 - y0) * row_bytes,
        ESP_CACHE_MSYNC_FLAG_DIR_C2M | ESP_CACHE_MSYNC_FLAG_UNALIGNED);
}

esp_err_t modulus_ui_engine_flush_flip(void)
{
    if (!s_panel || s_num_fbs < 2 || !s_fb[s_back]) {
        return ESP_ERR_INVALID_STATE;
    }
    /* Passing a registered FB address switches DMA to that buffer (no copy). */
    const esp_err_t err = esp_lcd_panel_draw_bitmap(
        s_panel, 0, 0, k_panel_w, k_panel_h, s_fb[s_back]);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "FB flip failed: %s", esp_err_to_name(err));
        return err;
    }
    s_back = (uint8_t)((s_back + 1u) % s_num_fbs);
    s_scanout = s_fb[s_back];
    s_last_px = (uint32_t)k_fb_px;
    return ESP_OK;
}

esp_lcd_panel_handle_t modulus_ui_engine_flush_panel(void)
{
    return s_panel;
}

/* Prefix of esp_lvgl_port's private lvgl_port_display_ctx_t (src/lvgl9). */
typedef struct {
    int disp_type;
    esp_lcd_panel_io_handle_t io_handle;
    esp_lcd_panel_handle_t panel_handle;
    esp_lcd_panel_handle_t control_handle;
    lvgl_port_rotation_cfg_t rotation;
    void *draw_buffs[3];
    uint8_t *oled_buffer;
    lv_display_t *disp_drv;
} lvgl_port_disp_ctx_prefix_t;

void modulus_ui_engine_flush_try_bind_from_lvgl(lv_display_t *disp)
{
    if (!disp || s_panel) {
        return;
    }
    const lvgl_port_disp_ctx_prefix_t *ctx = lv_display_get_driver_data(disp);
    if (!ctx) {
        ESP_LOGW(TAG, "LVGL driver_data null — panel unbound");
        return;
    }
    /* Must match esp_lvgl_port src/lvgl9/esp_lvgl_port_disp.c layout. */
    if (ctx->disp_drv != disp) {
        ESP_LOGE(TAG, "lvgl_port ctx layout mismatch (disp_drv=%p want %p) — panel unbound",
                 (void *)ctx->disp_drv, (void *)disp);
        return;
    }
    if (!ctx->panel_handle) {
        ESP_LOGW(TAG, "LVGL panel slot empty — panel unbound");
        return;
    }
    s_panel = ctx->panel_handle;
    ESP_LOGI(TAG, "panel bind from lvgl_port ctx → %p (io %p)",
             (void *)ctx->panel_handle, (void *)ctx->io_handle);
    bind_scanout();
    if (!s_scanout) {
        ESP_LOGE(TAG, "panel bound but no DPI frame buffer — Zig scanout dead");
        s_panel = NULL;
        return;
    }
#if CONFIG_BSP_LCD_DPI_BUFFER_NUMS >= 2
    if (s_num_fbs < 2) {
        ESP_LOGE(TAG, "expected ≥2 DPI FBs (CONFIG_BSP_LCD_DPI_BUFFER_NUMS=%d) got %u — tear-free flip unavailable",
                 CONFIG_BSP_LCD_DPI_BUFFER_NUMS, (unsigned)s_num_fbs);
        /* Keep single-FB scanout — still better than blank; callers may refuse boot. */
    }
#endif
}

/** True when panel + at least one DPI FB are ready for Zig paint. */
bool modulus_ui_engine_flush_ready(void)
{
    return s_panel != NULL && s_scanout != NULL;
}

uint32_t modulus_ui_engine_flush_last_px(void)
{
    return s_last_px;
}
