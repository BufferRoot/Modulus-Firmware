#pragma once
#include "bridge_config.h"
#include <nvs.h>
#include <nvs_flash.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    nvs_handle_t h;
    bool         ok;
} bridge_nvs_t;

static inline bridge_nvs_t bridge_nvs_open(nvs_open_mode mode)
{
    bridge_nvs_t ctx = {};
    ctx.ok = (nvs_open(NVS_NAMESPACE, mode, &ctx.h) == ESP_OK);
    return ctx;
}

static inline void bridge_nvs_close(bridge_nvs_t* ctx)
{
    if (ctx && ctx->ok) {
        nvs_close(ctx->h);
        ctx->ok = false;
    }
}

#ifdef __cplusplus
}
#endif
