/*
 * NVS bridge for Modulus Zig settings_store (ESP-IDF flash backend).
 * Linked by modulus_zig IDF component; Zig calls via extern decls in idf_nvs.zig.
 */
#include "nvs_shim.h"

#include <esp_err.h>
#include <esp_log.h>
#include <nvs.h>
#include <nvs_flash.h>
#include <string.h>

static const char *TAG = "nvs_shim";
static const char *NVS_NAMESPACE = "modulus";
static nvs_handle_t s_nvs = 0;
static int s_batch_depth = 0;

static int nvs_commit_if_needed(void)
{
    if (s_batch_depth == 0 && s_nvs) {
        return (int)nvs_commit(s_nvs);
    }
    return (int)ESP_OK;
}

void modulus_nvs_begin_batch(void)
{
    s_batch_depth++;
}

void modulus_nvs_end_batch(void)
{
    if (s_batch_depth > 0) {
        s_batch_depth--;
    }
    if (s_batch_depth == 0 && s_nvs) {
        esp_err_t err = nvs_commit(s_nvs);
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "end_batch commit failed: %s", esp_err_to_name(err));
        }
    }
}

int modulus_nvs_init(void)
{
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    if (err != ESP_OK) {
        return (int)err;
    }

    err = nvs_open(NVS_NAMESPACE, NVS_READWRITE, &s_nvs);
    return (int)err;
}

bool modulus_nvs_has_u8(const char *key)
{
    if (!s_nvs || !key) {
        return false;
    }
    uint8_t val = 0;
    return nvs_get_u8(s_nvs, key, &val) == ESP_OK;
}

uint8_t modulus_nvs_get_u8(const char *key, uint8_t def)
{
    if (!s_nvs || !key) {
        return def;
    }
    uint8_t val = def;
    nvs_get_u8(s_nvs, key, &val);
    return val;
}

int modulus_nvs_set_u8(const char *key, uint8_t val)
{
    if (!s_nvs || !key) {
        return (int)ESP_ERR_INVALID_STATE;
    }
    esp_err_t err = nvs_set_u8(s_nvs, key, val);
    if (err != ESP_OK) {
        return (int)err;
    }
    return nvs_commit_if_needed();
}

uint16_t modulus_nvs_get_u16(const char *key, uint16_t def)
{
    if (!s_nvs || !key) {
        return def;
    }
    uint16_t val = def;
    nvs_get_u16(s_nvs, key, &val);
    return val;
}

int modulus_nvs_set_u16(const char *key, uint16_t val)
{
    if (!s_nvs || !key) {
        return (int)ESP_ERR_INVALID_STATE;
    }
    esp_err_t err = nvs_set_u16(s_nvs, key, val);
    if (err != ESP_OK) {
        return (int)err;
    }
    return nvs_commit_if_needed();
}

bool modulus_nvs_get_str(const char *key, char *buf, size_t buf_len)
{
    if (!s_nvs || !key || !buf || buf_len == 0) {
        if (buf && buf_len > 0) {
            buf[0] = '\0';
        }
        return false;
    }
    size_t len = buf_len;
    esp_err_t err = nvs_get_str(s_nvs, key, buf, &len);
    if (err != ESP_OK) {
        buf[0] = '\0';
        return false;
    }
    return true;
}

int modulus_nvs_set_str(const char *key, const char *val)
{
    if (!s_nvs || !key) {
        return (int)ESP_ERR_INVALID_STATE;
    }
    esp_err_t err = nvs_set_str(s_nvs, key, val ? val : "");
    if (err != ESP_OK) {
        return (int)err;
    }
    return nvs_commit_if_needed();
}

int modulus_nvs_erase_all(void)
{
    if (!s_nvs) {
        ESP_LOGE(TAG, "erase_all: NVS not open");
        return (int)ESP_ERR_INVALID_STATE;
    }
    esp_err_t err = nvs_erase_all(s_nvs);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "erase_all failed: %s", esp_err_to_name(err));
        return (int)err;
    }
    err = nvs_commit(s_nvs);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "erase_all commit failed: %s", esp_err_to_name(err));
        return (int)err;
    }
    return 0;
}

int modulus_factory_reset(void)
{
    ESP_LOGW(TAG, "=== FACTORY RESET ===");
    return modulus_nvs_erase_all();
}
