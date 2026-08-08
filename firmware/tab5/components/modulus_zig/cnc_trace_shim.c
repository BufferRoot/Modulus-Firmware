/*
 * grblHAL TX trace — jog lines and realtime bytes at ESP_LOGV.
 */
#include "cnc_trace_shim.h"

#include <esp_log.h>
#include <string.h>

static const char *TAG = "grblhal";

void modulus_cnc_trace_tx(const uint8_t *data, size_t len)
{
    if (!data || len == 0) {
        return;
    }
    if (len == 1) {
        ESP_LOGV(TAG, "tx rt 0x%02X", data[0]);
        return;
    }
    size_t n = len;
    if (n > 0 && data[n - 1] == '\n') {
        n--;
    }
    if (n >= 3 && data[0] == '$' && memcmp(data, "$J=", 3) == 0) {
        ESP_LOGV(TAG, "tx jog %.*s", (int)n, data);
        return;
    }
    if (n <= 48) {
        ESP_LOGV(TAG, "tx %.*s", (int)n, data);
    }
}
