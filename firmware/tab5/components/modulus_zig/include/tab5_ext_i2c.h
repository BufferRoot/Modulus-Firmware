#pragma once

#include <stdbool.h>
#include <driver/i2c_master.h>
#include <esp_err.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Port A Grove — I2C1 @ GPIO53/54 (M5Tab5-UserDemo BSP_EXT_I2C_NUM). */
esp_err_t tab5_ext_i2c_init(void);
esp_err_t tab5_ext_i2c_deinit(void);
/** Delete + recreate bus (caller must rm all i2c devices first). */
esp_err_t tab5_ext_i2c_reinit(void);
/** BSP deinit/init (caller must rm all i2c devices first). */
esp_err_t tab5_ext_i2c_recover_bus(void);
i2c_master_bus_handle_t tab5_ext_i2c_get_handle(void);
/** Temp device probe with clock-stretch tolerance (not i2c_master_probe). */
esp_err_t tab5_ext_i2c_probe_addr(uint8_t addr, int timeout_ms);
/** Sample wire levels only before first bus init (never deinit active bus). */
bool tab5_ext_i2c_sample_wire_levels(int *sda_out, int *scl_out);
void tab5_ext_i2c_log_line_levels(const char *why);
/** Serialize Port A probe/scan vs ExtEncoder device handle. */
bool tab5_ext_i2c_lock(uint32_t timeout_ms);
void tab5_ext_i2c_unlock(void);

#ifdef __cplusplus
}
#endif
