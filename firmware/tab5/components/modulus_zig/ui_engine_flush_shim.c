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
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#if !CONFIG_MODULUS_ZIG_UI_ENGINE
#include <esp_lvgl_port.h>
#include <lvgl.h>
#endif

static const char *TAG = "ui_engine_flush";
static uint32_t s_last_px;
static esp_lcd_panel_handle_t s_panel;
static uint16_t *s_fb[3];
static uint8_t s_num_fbs;
static uint8_t s_back; /* index Zig paints into */
static uint16_t *s_scanout;
/* Given by the DPI refresh-done ISR once the DMA link switch has landed. */
static SemaphoreHandle_t s_flip_done;
static bool s_flip_cb_ok;

static bool IRAM_ATTR on_refresh_done(esp_lcd_panel_handle_t panel,
                                      esp_lcd_dpi_panel_event_data_t *edata,
                                      void *user_ctx)
{
    (void)panel;
    (void)edata;
    (void)user_ctx;
    BaseType_t hp = pdFALSE;
    if (s_flip_done) {
        xSemaphoreGiveFromISR(s_flip_done, &hp);
    }
    return hp == pdTRUE;
}

/* Take over the DPI refresh-done callback so flip can wait for vsync.
 *
 * Call ONLY after lvgl_port_remove_disp() — display_shim does this in
 * modulus_display_zig_takeover(). esp_lcd_dpi_panel_register_event_callbacks
 * *replaces* the callback set, and esp_lvgl_port's callback is what completes
 * an LVGL flush. Two earlier attempts failed for exactly that reason:
 *   1. Register while the LVGL display still existed -> a flush in flight at
 *      takeover never completed, and lv_refr.c wait_for_flushing() (a bare
 *      `while(disp->flushing);`) spun taskLVGL at prio 5 on Core 0, starving
 *      IDLE0. Task WDT every 5 s, "CPU 0: taskLVGL".
 *   2. Complete it with lv_display_flush_ready() from our ISR -> WDT gone,
 *      but that dispatches LVGL events and is not ISR-safe; zig_ui hung.
 * With the display removed there is no flush to orphan, so neither applies. */
void modulus_ui_engine_flush_enable_vsync(void)
{
    if (s_flip_cb_ok || !s_panel || s_num_fbs < 2) {
        return;
    }
    if (!s_flip_done) {
        s_flip_done = xSemaphoreCreateBinary();
    }
    esp_lcd_dpi_panel_event_callbacks_t cbs = {
        .on_refresh_done = on_refresh_done,
    };
    const esp_err_t cb = esp_lcd_dpi_panel_register_event_callbacks(s_panel, &cbs, NULL);
    s_flip_cb_ok = (cb == ESP_OK && s_flip_done != NULL);
    if (!s_flip_cb_ok) {
        ESP_LOGW(TAG, "flip vsync wait off (%s) — tear possible", esp_err_to_name(cb));
    } else {
        ESP_LOGI(TAG, "flip vsync wait: on");
    }
}

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
    /* draw_bitmap only QUEUES the DMA link switch; the panel keeps scanning
     * the old buffer until the next frame boundary. Releasing that buffer to
     * Zig as the new back before then lets the next paint tear the frame still
     * on screen. Wait for refresh-done. */
    if (s_flip_cb_ok) {
        (void)xSemaphoreTake(s_flip_done, pdMS_TO_TICKS(50));
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

#if !CONFIG_MODULUS_ZIG_UI_ENGINE
/* LVGL-only: under ZIG_UI display_shim binds the panel directly from
 * bsp_display_new_with_handles(), so this private-struct read is gone. */
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
#endif /* !CONFIG_MODULUS_ZIG_UI_ENGINE */

/** True when panel + at least one DPI FB are ready for Zig paint. */
bool modulus_ui_engine_flush_ready(void)
{
    return s_panel != NULL && s_scanout != NULL;
}

uint32_t modulus_ui_engine_flush_last_px(void)
{
    return s_last_px;
}
