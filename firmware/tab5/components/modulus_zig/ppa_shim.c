/* P4 PPA scale-rotate-mirror rotate for the Zig UI scanout.
 *
 * The Zig engine paints a 1280x720 landscape framebuffer and the panel is
 * 720x1280 portrait, so every dirty rect needs a transpose. Doing that on the
 * CPU costs a PSRAM cache line per pixel (~700 ms/frame untiled, ~45 ms tiled);
 * the PPA does it as a DMA operation. esp_lvgl_port had this via
 * CONFIG_LVGL_PORT_ENABLE_PPA and the Zig scanout path lost it.
 */

#include "display_shim.h"

#include "driver/ppa.h"
#include "esp_cache.h"
#include "esp_err.h"
#include "esp_log.h"

static const char *TAG = "ppa_shim";

static ppa_client_handle_t s_srm;
static bool s_failed;

bool modulus_ppa_init(void)
{
    if (s_srm) {
        return true;
    }
    if (s_failed) {
        return false;
    }
    ppa_client_config_t cfg = {
        .oper_type = PPA_OPERATION_SRM,
        .max_pending_trans_num = 1,
        /* Enum has no 0 member — a zero-init field is an invalid burst length. */
        .data_burst_length = PPA_DATA_BURST_LENGTH_128,
    };
    esp_err_t err = ppa_register_client(&cfg, &s_srm);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "ppa_register_client failed: %s", esp_err_to_name(err));
        s_srm = NULL;
        s_failed = true;
        return false;
    }
    ESP_LOGI(TAG, "PPA SRM ready");
    return true;
}

bool modulus_ppa_available(void)
{
    return s_srm != NULL;
}

/* PPA reads the source through DMA, so CPU writes must be flushed first. Sync
 * whole source rows: a block is only contiguous in memory row-by-row. */
static bool sync_src_rows(const void *src, uint32_t src_w, uint32_t by, uint32_t bh)
{
    void *row0 = (void *)((uintptr_t)src + (size_t)by * src_w * 2u);
    const size_t span = (size_t)bh * src_w * 2u;
    /* UNALIGNED lets the driver widen to cache lines itself. Writing back a few
     * neighbouring bytes is harmless — they are our own framebuffer. */
    esp_err_t err = esp_cache_msync(row0, span,
                                    ESP_CACHE_MSYNC_FLAG_DIR_C2M | ESP_CACHE_MSYNC_FLAG_UNALIGNED);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "msync failed: %s", esp_err_to_name(err));
        return false;
    }
    return true;
}

bool modulus_ppa_rotate_block(const void *src, void *dst, uint32_t dst_bytes,
                              uint32_t src_w, uint32_t src_h,
                              uint32_t dst_w, uint32_t dst_h,
                              uint32_t bx, uint32_t by, uint32_t bw, uint32_t bh,
                              bool flipped)
{
    if (!s_srm || !src || !dst || bw == 0 || bh == 0) {
        return false;
    }
    if (bx + bw > src_w || by + bh > src_h) {
        return false;
    }

    /* 90 CCW maps logical (lx,ly) -> panel (ly, src_w-1-lx); 270 is the 180
     * mirror of that. Block dimensions swap, so the output origin is derived
     * from the far corner on the swapped axis. */
    uint32_t out_x, out_y;
    ppa_srm_rotation_angle_t angle;
    if (flipped) {
        angle = PPA_SRM_ROTATION_ANGLE_270;
        out_x = dst_w - by - bh;
        out_y = bx;
    } else {
        angle = PPA_SRM_ROTATION_ANGLE_90;
        out_x = by;
        out_y = dst_h - bx - bw;
    }
    if (out_x + bh > dst_w || out_y + bw > dst_h) {
        return false;
    }

    if (!sync_src_rows(src, src_w, by, bh)) {
        return false;
    }

    ppa_srm_oper_config_t oper = {
        .in = {
            .buffer = src,
            .pic_w = src_w,
            .pic_h = src_h,
            .block_w = bw,
            .block_h = bh,
            .block_offset_x = bx,
            .block_offset_y = by,
            .srm_cm = PPA_SRM_COLOR_MODE_RGB565,
        },
        .out = {
            .buffer = dst,
            .buffer_size = dst_bytes,
            .pic_w = dst_w,
            .pic_h = dst_h,
            .block_offset_x = out_x,
            .block_offset_y = out_y,
            .srm_cm = PPA_SRM_COLOR_MODE_RGB565,
        },
        .rotation_angle = angle,
        .scale_x = 1.0f,
        .scale_y = 1.0f,
        .rgb_swap = false,
        .byte_swap = false,
        .mode = PPA_TRANS_MODE_BLOCKING,
    };

    esp_err_t err = ppa_do_scale_rotate_mirror(s_srm, &oper);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "SRM %ux%u@%u,%u failed: %s", (unsigned)bw, (unsigned)bh,
                 (unsigned)bx, (unsigned)by, esp_err_to_name(err));
        return false;
    }
    return true;
}

/* Zig imports these as c_int 0/1 — keeps bool ABI for any C callers. */
int modulus_ppa_init_zi(void)
{
    return modulus_ppa_init() ? 1 : 0;
}

int modulus_ppa_rotate_block_zi(const void *src, void *dst, uint32_t dst_bytes,
                                uint32_t src_w, uint32_t src_h,
                                uint32_t dst_w, uint32_t dst_h,
                                uint32_t bx, uint32_t by, uint32_t bw, uint32_t bh,
                                int flipped)
{
    return modulus_ppa_rotate_block(src, dst, dst_bytes, src_w, src_h, dst_w, dst_h,
                                    bx, by, bw, bh, flipped != 0)
               ? 1
               : 0;
}
