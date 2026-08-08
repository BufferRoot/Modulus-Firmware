/*

 * Tab5 expansion buses — M-Bus (internal I2C), HY2.0-4P Port A, rear M5-Bus map.

 */

#include "mbus_shim.h"

#include "i2c_coex_shim.h"

#include "i2c_scan_shim.h"

#include "tab5_ext_i2c.h"

#include "tab5_hw.h"

#include "tab5_pi4ioe.h"

#include "ext_encoder_shim.h"

#include "nvs_shim.h"
#include "transport_shim.h"



#include <bsp/m5stack_tab5.h>

#include <sdkconfig.h>

#include <driver/i2c_master.h>

#include <esp_log.h>

#include <freertos/FreeRTOS.h>

#include <freertos/task.h>

#include <string.h>



static const char *TAG = "modulus_mbus";



#define PORT_A_PROBE_MS          100

#define PORT_A_EXTENC_PROBE_MS   250

#define PORT_A_EXT5V_SETTLE_MS   500

#define PORT_A_STM32_BOOT_MS     300



static const char *k_labels[MODULUS_MBUS_COUNT] = {

    "Int I2C0 M-Bus",

    "Port A Grove I2C1",

    "M5-Bus (Int I2C0)",

    "PI4IOE1 EXP1",

    "PI4IOE2 EXP2",

};



/* C++ hal_hardware.cpp targeted Port A list — no 0x08-0x77 sweep (ghost + coex starvation). */

static const uint8_t k_port_a_targeted[] = {

    TAB5_I2C_ADDR_EXT_ENCODER,

    0x45, 0x38, 0x39, 0x08, 0x30, 0x55, 0x58, 0x70, 0x50, 0x51,

};



static bool is_internal_mbus_addr(uint8_t addr)

{

    switch (addr) {

    case TAB5_I2C_ADDR_ES8388:

    case TAB5_I2C_ADDR_ES7210:

    case TAB5_I2C_ADDR_GT911:

    case TAB5_I2C_ADDR_ST7123:

    case TAB5_I2C_ADDR_BMI270:

    case TAB5_I2C_ADDR_RX8130:

    case TAB5_I2C_ADDR_INA226:

    case TAB5_I2C_ADDR_PI4IOE1:

    case TAB5_I2C_ADDR_PI4IOE2:

        return true;

    default:

        return false;

    }

}



static bool probe_addr_locked(i2c_master_bus_handle_t bus, uint8_t addr, int timeout_ms)

{

    if (!bus) {

        return false;

    }

    if (!modulus_i2c_coex_lock(3000)) {

        return false;

    }

    const bool ok = i2c_master_probe(bus, addr, timeout_ms) == ESP_OK;

    modulus_i2c_coex_unlock();

    if (ok) {

        vTaskDelay(pdMS_TO_TICKS(1));

    }

    return ok;

}



static bool s_port_a_power_ready = false;
static bool s_port_a_ext5v_last = false;

static void port_a_power_prepare(void)

{

    if (!tab5_pi4ioe_ensure_init()) {

        ESP_LOGW(TAG, "PI4IOE missing — Port A EXT5V not asserted");

        return;

    }

    /* Respect the EXT5V power toggle. set_ext_5v_en() re-asserts P2 as a driven
     * (non-Hi-Z) push-pull output on every call, so it survives the stock BSP's
     * expander reset (which left P2 high-impedance — the real 0.6 V cause). */
    const bool ext5v = modulus_nvs_get_u8("ext5v", 1) != 0;

    tab5_pi4ioe_set_ext_5v_en(ext5v);

    if (!ext5v) {

        s_port_a_power_ready = false;

        s_port_a_ext5v_last = false;

        ESP_LOGW(TAG, "Port A EXT5V off (toggle) — Grove units unpowered");

        return;

    }

    if (s_port_a_power_ready && s_port_a_ext5v_last) {

        return;

    }

    s_port_a_ext5v_last = true;

    vTaskDelay(pdMS_TO_TICKS(PORT_A_EXT5V_SETTLE_MS));

    vTaskDelay(pdMS_TO_TICKS(PORT_A_STM32_BOOT_MS));

    s_port_a_power_ready = true;

    /* No bus reinit here. EXT5V is up before the bus is first created, so the

     * bus is healthy. Bus recovery is the encoder read-fail path's job — it

     * calls remove_device() BEFORE reinit. A reinit while the 0x59 device is

     * still attached fails ("devices still attached") and leaks the port,

     * yielding the permanent "already acquired" wedge seen during Scan. */

}



bool modulus_mbus_port_a_ensure(void)

{

    port_a_power_prepare();

    /* EXT5V off (NVS ext5v=0) -> the Grove unit is unpowered and clamps SDA

     * low. Creating/using the I2C bus on held-low lines wedges the controller

     * ("clear bus failed / reset hardware failed"). Do NOT touch the bus until

     * the rail is up; turn EXT5V on in Power settings to use Port A units. */

    if (!s_port_a_power_ready) {

        return false;

    }

    modulus_i2c_transport_stop();

    modulus_canbus_stop();

    return tab5_ext_i2c_init() == ESP_OK && tab5_ext_i2c_get_handle() != NULL;

}

void modulus_mbus_port_a_power_invalidate(void)

{

    s_port_a_power_ready = false;

    s_port_a_ext5v_last = false;

}



i2c_master_bus_handle_t modulus_mbus_port_a_bus(void)

{

    return tab5_ext_i2c_get_handle();

}



void modulus_mbus_init(void)

{

    ESP_LOGI(TAG, "Bus map: internal I2C%d SCL32/SDA31, Port A I2C%d G53/G54, rear=internal",

             CONFIG_BSP_I2C_NUM, TAB5_EXT_I2C_PORT);

}



const char *modulus_mbus_label(modulus_mbus_id_t bus)

{

    if (bus >= MODULUS_MBUS_COUNT) {

        return "?";

    }

    return k_labels[bus];

}



static bool scan_bus_internal(i2c_master_bus_handle_t bus, modulus_mbus_scan_t *out)

{

    if (!bus || !out) {

        return false;

    }

    out->addr_count = 0;



    const esp_log_level_t prev_lvl = esp_log_level_get("i2c.master");

    esp_log_level_set("i2c.master", ESP_LOG_NONE);



    for (uint8_t addr = 0x08; addr < 0x78; ++addr) {

        if (!probe_addr_locked(bus, addr, 25)) {

            continue;

        }

        if (out->addr_count < sizeof(out->addrs)) {

            out->addrs[out->addr_count++] = addr;

        }

    }



    esp_log_level_set("i2c.master", prev_lvl);

    out->ready = true;

    return true;

}



static bool scan_bus_port_a(i2c_master_bus_handle_t bus, modulus_mbus_scan_t *out)

{

    if (!bus || !out) {

        return false;

    }

    out->addr_count = 0;

    if (!tab5_ext_i2c_lock(5000)) {
        return false;
    }

    const esp_log_level_t prev_lvl = esp_log_level_get("i2c.master");

    esp_log_level_set("i2c.master", ESP_LOG_NONE);



    for (size_t i = 0; i < sizeof(k_port_a_targeted) / sizeof(k_port_a_targeted[0]); ++i) {

        const uint8_t addr = k_port_a_targeted[i];

        const int tmo = (addr == TAB5_I2C_ADDR_EXT_ENCODER) ? PORT_A_EXTENC_PROBE_MS

                                                            : PORT_A_PROBE_MS;

        if (tab5_ext_i2c_probe_addr(addr, tmo) != ESP_OK) {

            continue;

        }

        if (is_internal_mbus_addr(addr)) {

            ESP_LOGW(TAG, "Port A: 0x%02X is internal M-Bus only — ignore (floating bus?)",

                     addr);

            tab5_ext_i2c_log_line_levels("ghost internal addr on Port A");

            continue;

        }

        if (out->addr_count < sizeof(out->addrs)) {

            out->addrs[out->addr_count++] = addr;

        }

        if (addr == TAB5_I2C_ADDR_EXT_ENCODER) {

            ESP_LOGI(TAG, "Port A: ExtEncoder 0x%02X ACK", addr);

        }

    }



    esp_log_level_set("i2c.master", prev_lvl);

    out->ready = true;



    if (out->addr_count == 0) {
        tab5_ext_i2c_log_line_levels("Port A scan empty");
    }

    tab5_ext_i2c_unlock();
    return true;
}



bool modulus_mbus_scan(modulus_mbus_id_t bus, modulus_mbus_scan_t *out)

{

    if (!out || bus >= MODULUS_MBUS_COUNT) {

        return false;

    }

    memset(out, 0, sizeof(*out));

    out->id = bus;

    out->label = modulus_mbus_label(bus);



    switch (bus) {

    case MODULUS_MBUS_INTERNAL: {

        i2c_master_bus_handle_t mbus = bsp_i2c_get_handle();

        if (!mbus) {

            ESP_LOGW(TAG, "M-Bus handle missing");

            return false;

        }

        return scan_bus_internal(mbus, out);

    }

    case MODULUS_MBUS_PORT_A:

        if (!modulus_mbus_port_a_ensure()) {

            return false;

        }

        {

            i2c_master_bus_handle_t pa = tab5_ext_i2c_get_handle();

            modulus_ext_encoder_scan_begin();

            const bool ok = scan_bus_port_a(pa, out);

            modulus_ext_encoder_scan_end();

            if (out->addr_count == 0) {

                ESP_LOGW(TAG, "Port A scan: no devices (EXT5V on? Grove cable on front Port A?)");

            } else {

                char list[128];

                modulus_i2c_format_addr_list(out->addrs, out->addr_count, list, sizeof(list));

                ESP_LOGI(TAG, "Port A scan: %u device(s): %s", (unsigned)out->addr_count, list);

            }

            return ok;

        }

    case MODULUS_MBUS_REAR:

        return modulus_mbus_scan(MODULUS_MBUS_INTERNAL, out);

    case MODULUS_MBUS_EXP1:

    case MODULUS_MBUS_EXP2: {

        i2c_master_bus_handle_t mbus = bsp_i2c_get_handle();

        if (!mbus) {

            ESP_LOGW(TAG, "M-Bus handle missing");

            return false;

        }

        const uint8_t addr = (bus == MODULUS_MBUS_EXP1) ? TAB5_I2C_ADDR_PI4IOE1

                                                          : TAB5_I2C_ADDR_PI4IOE2;

        if (probe_addr_locked(mbus, addr, 25)) {

            out->addrs[out->addr_count++] = addr;

        }

        out->ready = true;

        return true;

    }

    default:

        return false;

    }

}


