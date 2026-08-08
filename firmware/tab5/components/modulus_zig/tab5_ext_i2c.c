/*
 * Tab5 Port A Grove I2C — I2C1 @ G53/G54 (M5Tab5-UserDemo BSP_EXT_I2C_NUM).
 * Independent from internal M-Bus I2C0 — do not use modulus_i2c_coex here.
 * Never gpio_config SDA/SCL while the I2C driver owns them (P4 gpio conflict).
 */
#include "tab5_ext_i2c.h"
#include "tab5_hw.h"
#include "transport_shim.h"

#include <driver/i2c_master.h>
#include <esp_log.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include <freertos/task.h>

static const char *TAG = "tab5_ext_i2c";

#define TAB5_EXT_I2C_HZ       100000
#define TAB5_EXT_SCL_WAIT_US  50000

static i2c_master_bus_handle_t s_ext_bus = NULL;
static bool s_ext_initialized = false;
static SemaphoreHandle_t s_port_a_mux = NULL;

static void ensure_port_a_mux(void)
{
    if (s_port_a_mux == NULL) {
        s_port_a_mux = xSemaphoreCreateMutex();
    }
}

static void release_port_a_alt_peripherals(void)
{
    modulus_i2c_transport_stop();
    modulus_canbus_stop();
}

esp_err_t tab5_ext_i2c_init(void)
{
    ensure_port_a_mux();
    release_port_a_alt_peripherals();

    if (s_ext_initialized && s_ext_bus != NULL) {
        return ESP_OK;
    }

    /* trans_queue_depth MUST stay 0 — >0 enables experimental async mode. */
    const i2c_master_bus_config_t cfg = {
        .i2c_port = TAB5_EXT_I2C_PORT,
        .sda_io_num = TAB5_EXT_I2C_SDA_GPIO,
        .scl_io_num = TAB5_EXT_I2C_SCL_GPIO,
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .glitch_ignore_cnt = 7,
        .flags.enable_internal_pullup = true,
    };
    const esp_err_t err = i2c_new_master_bus(&cfg, &s_ext_bus);
    if (err != ESP_OK || s_ext_bus == NULL) {
        ESP_LOGE(TAG, "Port A I2C init failed port=%d SDA=%d SCL=%d: %s",
                 TAB5_EXT_I2C_PORT, (int)TAB5_EXT_I2C_SDA_GPIO, (int)TAB5_EXT_I2C_SCL_GPIO,
                 esp_err_to_name(err));
        return (err != ESP_OK) ? err : ESP_ERR_INVALID_STATE;
    }

    s_ext_initialized = true;
    ESP_LOGI(TAG, "Port A I2C ready port=%d SDA=%d SCL=%d @ %d kHz",
             TAB5_EXT_I2C_PORT, (int)TAB5_EXT_I2C_SDA_GPIO, (int)TAB5_EXT_I2C_SCL_GPIO,
             TAB5_EXT_I2C_HZ / 1000);
    return ESP_OK;
}

esp_err_t tab5_ext_i2c_deinit(void)
{
    if (!s_ext_initialized || s_ext_bus == NULL) {
        return ESP_OK;
    }
    const esp_err_t err = i2c_del_master_bus(s_ext_bus);
    if (err != ESP_OK) {
        /* Delete fails if a device is still attached to the bus (e.g. the 0x59
         * ExtEncoder). Keep the existing handle and state intact so the next
         * tab5_ext_i2c_init() reuses this still-valid bus instead of trying to
         * acquire a fresh one on the same port — that path returns
         * ESP_ERR_INVALID_STATE ("already acquired") and bricks Port A until a
         * reboot. Callers must remove_device() before reinit; this is the guard. */
        ESP_LOGW(TAG, "Port A bus delete failed (%s) — keeping existing handle (device attached?)",
                 esp_err_to_name(err));
        return err;
    }
    s_ext_bus = NULL;
    s_ext_initialized = false;
    vTaskDelay(pdMS_TO_TICKS(100));
    return err;
}

i2c_master_bus_handle_t tab5_ext_i2c_get_handle(void)
{
    if (tab5_ext_i2c_init() != ESP_OK) {
        return NULL;
    }
    return s_ext_bus;
}

esp_err_t tab5_ext_i2c_probe_addr(uint8_t addr, int timeout_ms)
{
    i2c_master_bus_handle_t bus = tab5_ext_i2c_get_handle();
    if (!bus) {
        return ESP_ERR_INVALID_STATE;
    }
    /* Address-only ACK probe — identical to the proven hal_ext_encoder.cpp
     * detection. The previous add_device + write-reg + STOP + read sequence was
     * non-standard (the ExtEncoder STM32 expects a repeated-start register read)
     * and forced an scl_wait_us clock-stretch window that isn't needed here.
     * Actual register reads use i2c_master_transmit_receive in ext_encoder_shim. */
    return i2c_master_probe(bus, addr, timeout_ms);
}

esp_err_t tab5_ext_i2c_reinit(void)
{
    ensure_port_a_mux();
    if (s_port_a_mux && xSemaphoreTake(s_port_a_mux, pdMS_TO_TICKS(5000)) != pdTRUE) {
        return ESP_ERR_TIMEOUT;
    }

    ESP_LOGW(TAG, "Port A I2C bus reinit (driver deinit only — no GPIO bitbang)");
    release_port_a_alt_peripherals();
    (void)tab5_ext_i2c_deinit();
    const esp_err_t err = tab5_ext_i2c_init();

    if (s_port_a_mux) {
        xSemaphoreGive(s_port_a_mux);
    }
    return err;
}

esp_err_t tab5_ext_i2c_recover_bus(void)
{
    /* Soft FSM/bus clear — mirrors the proven hal_ext_encoder.cpp recovery
     * (single i2c_master_bus_reset). Deliberately does NOT delete+recreate the
     * master bus: repeated i2c_del_master_bus / i2c_new_master_bus on the
     * ESP32-P4 corrupts the I2C peripheral and yields the
     * "clear bus failed / reset hardware failed" cascade seen in the logs. */
    i2c_master_bus_handle_t bus = tab5_ext_i2c_get_handle();
    if (!bus) {
        return ESP_ERR_INVALID_STATE;
    }
    const esp_err_t err = i2c_master_bus_reset(bus);
    vTaskDelay(pdMS_TO_TICKS(100));
    return err;
}

bool tab5_ext_i2c_sample_wire_levels(int *sda_out, int *scl_out)
{
    if (sda_out) {
        *sda_out = -1;
    }
    if (scl_out) {
        *scl_out = -1;
    }
    return s_ext_initialized;
}

void tab5_ext_i2c_log_line_levels(const char *why)
{
    ESP_LOGW(TAG, "Port A I2C failed (%s) — EXT5V on? Grove on front Port A (not M5-Bus)?",
             why ? why : "?");
}

bool tab5_ext_i2c_lock(uint32_t timeout_ms)
{
    ensure_port_a_mux();
    if (!s_port_a_mux) {
        return true;
    }
    return xSemaphoreTake(s_port_a_mux, pdMS_TO_TICKS(timeout_ms)) == pdTRUE;
}

void tab5_ext_i2c_unlock(void)
{
    if (s_port_a_mux) {
        xSemaphoreGive(s_port_a_mux);
    }
}
