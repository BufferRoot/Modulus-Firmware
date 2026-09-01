/*
 * SD card mount + memory/flash diagnostics — mirrors C++ hal_storage.cpp.
 * Tab5: SDMMC 4-bit @ /sdcard via m5stack_tab5 BSP.
 */
#include "storage_shim.h"
#include "i2c_scan_shim.h"
#include "mbus_shim.h"
#include "tab5_port_map.h"
#include "modulus_zig.h"
#include "nvs_shim.h"
#include "i2c_coex_shim.h"

#include <bsp/m5stack_tab5.h>
#include <esp_heap_caps.h>
#include <esp_log.h>
#include <esp_partition.h>
#include <esp_timer.h>
#include <esp_vfs_fat.h>
#include <driver/sdmmc_host.h>
#include <sd_pwr_ctrl_by_on_chip_ldo.h>
#include <lvgl.h>
#include <usb/usb_host.h>
#include <usb/msc_host.h>
#include <usb/msc_host_vfs.h>
#include "tab5_pi4ioe.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <dirent.h>
#include <strings.h>
#include <unistd.h>
#include <sys/stat.h>

static const char *TAG = "modulus_storage";

static const char *const k_loglvl_names[] = {
    "None", "Error", "Warn", "Info", "Debug", "Verbose",
};

static bool s_sd_mounted = false;
static char s_mount_point[] = "/sdcard";
static sdmmc_card_t *s_sd_card = NULL;
static sd_pwr_ctrl_handle_t s_sd_pwr = NULL;

/* ESP-IDF 6 permits the P4 SDMMC controller to be created only once.
 * ESP-Hosted owns that controller for C6 SDIO on slot 1; the physical microSD
 * card must therefore add only slot 0. This is the same workaround used by
 * Espressif's esp_hosted host_sdcard_with_hosted example. */
static esp_err_t shared_sdmmc_host_init(void)
{
    return ESP_OK;
}

static esp_err_t shared_sdmmc_host_deinit(void)
{
    return ESP_OK;
}

static esp_err_t shared_sdcard_mount(bool format_if_mount_failed)
{
    esp_vfs_fat_sdmmc_mount_config_t mount_cfg = {
        .format_if_mount_failed = format_if_mount_failed,
        .max_files = 5,
        .allocation_unit_size = 16 * 1024,
    };
    sdmmc_host_t host = SDMMC_HOST_DEFAULT();
    host.slot = SDMMC_HOST_SLOT_0;
    host.max_freq_khz = SDMMC_FREQ_HIGHSPEED;
    host.init = shared_sdmmc_host_init;
    host.deinit = shared_sdmmc_host_deinit;

    sdmmc_slot_config_t slot = {0};
    bsp_sdcard_sdmmc_get_slot(SDMMC_HOST_SLOT_0, &slot);

    sd_pwr_ctrl_ldo_config_t ldo_cfg = {
        .ldo_chan_id = 4,
    };
    esp_err_t ret = sd_pwr_ctrl_new_on_chip_ldo(&ldo_cfg, &s_sd_pwr);
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "SD LDO acquire failed: %s", esp_err_to_name(ret));
        s_sd_pwr = NULL;
        return ret;
    }
    host.pwr_ctrl_handle = s_sd_pwr;

    ret = esp_vfs_fat_sdmmc_mount(s_mount_point, &host, &slot, &mount_cfg, &s_sd_card);
    if (ret != ESP_OK) {
        s_sd_card = NULL;
        const esp_err_t pwr_ret = sd_pwr_ctrl_del_on_chip_ldo(s_sd_pwr);
        if (pwr_ret != ESP_OK) {
            ESP_LOGW(TAG, "SD LDO cleanup failed: %s", esp_err_to_name(pwr_ret));
        }
        s_sd_pwr = NULL;
    }
    return ret;
}

static esp_err_t shared_sdcard_unmount(void)
{
    esp_err_t ret = ESP_OK;
    if (s_sd_card) {
        ret = esp_vfs_fat_sdcard_unmount(s_mount_point, s_sd_card);
        s_sd_card = NULL;
    }
    if (s_sd_pwr) {
        const esp_err_t pwr_ret = sd_pwr_ctrl_del_on_chip_ldo(s_sd_pwr);
        if (ret == ESP_OK) ret = pwr_ret;
        s_sd_pwr = NULL;
    }
    return ret;
}

/* USB Type-A host: Power tab owns VBUS (usb5v / PI4IOE E2.P3); BSP host stack
 * enumerates devices when that rail is on. Same pin as BSP_FEATURE_USB. */
static bool s_usb_started = false;
static int s_usb_dev_count = 0;
static char s_usb_status[32] = "VBUS off";
static int64_t s_usb_last_poll_us = 0;

static TaskHandle_t s_usb_lib_task;

#define USB_VOL_PATH "/usb"
#define USB_VOL_MAX 32
#define USB_VOL_NAME 28

/* --- USB mass storage --------------------------------------------------
 *
 * usb_host_install() only enumerates; it does NOT make files visible. The
 * M-Panel USB tool reads /usb via opendir(), so a G-code stick showed the tile
 * as active (s_usb_dev_count > 0 counts *any* device) but listed nothing.
 * MSC class driver + FATFS VFS is the missing layer.
 *
 * Mount/unmount is driven by the MSC connect callback, never polled: the UI
 * calls modulus_storage_is_usb_host_enabled() every frame, and doing
 * filesystem work on the paint path is how the I2C storm happened. */
static msc_host_device_handle_t s_msc_dev;
static msc_host_vfs_handle_t s_msc_vfs;
static uint8_t s_msc_pending_addr;   /* set by callback, consumed by usb_host_ensure */
static bool s_msc_pending_disconnect;
static bool s_msc_mounted;

/* Defined after s_usb_vol; clears the cached G-code list on unmount. */
static void msc_clear_catalog(void);
/* Defined below; starts the host stack and consumes MSC events. */
static void usb_host_ensure(void);

static void msc_event_cb(const msc_host_event_t *event, void *arg)
{
    (void)arg;
    if (!event) {
        return;
    }
    /* Callback runs on the MSC driver task — record intent only, do the mount
     * from usb_host_ensure() where the I2C coex lock is already handled. */
    if (event->event == MSC_DEVICE_CONNECTED) {
        s_msc_pending_addr = event->device.address;
    } else if (event->event == MSC_DEVICE_DISCONNECTED) {
        s_msc_pending_disconnect = true;
    }
}

static void msc_unmount(void)
{
    if (s_msc_vfs) {
        (void)msc_host_vfs_unregister(s_msc_vfs);
        s_msc_vfs = NULL;
    }
    if (s_msc_dev) {
        (void)msc_host_uninstall_device(s_msc_dev);
        s_msc_dev = NULL;
    }
    if (s_msc_mounted) {
        s_msc_mounted = false;
        msc_clear_catalog();   /* drop stale names so the UI cannot act on them */
        ESP_LOGI(TAG, "USB volume unmounted");
    }
}

static void msc_try_mount(uint8_t addr)
{
    if (s_msc_mounted) {
        return;
    }
    esp_err_t err = msc_host_install_device(addr, &s_msc_dev);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "msc_host_install_device: %s", esp_err_to_name(err));
        s_msc_dev = NULL;
        return;
    }
    const esp_vfs_fat_mount_config_t mount_cfg = {
        .format_if_mount_failed = false,   /* never reformat a user's stick */
        .max_files = 4,
        .allocation_unit_size = 8192,
    };
    err = msc_host_vfs_register(s_msc_dev, USB_VOL_PATH, &mount_cfg, &s_msc_vfs);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "msc_host_vfs_register(%s): %s", USB_VOL_PATH, esp_err_to_name(err));
        (void)msc_host_uninstall_device(s_msc_dev);
        s_msc_dev = NULL;
        s_msc_vfs = NULL;
        return;
    }
    s_msc_mounted = true;
    ESP_LOGI(TAG, "USB volume mounted at %s", USB_VOL_PATH);
}

/** True once an MSC volume is mounted at /usb — not merely "a device exists".
 *
 * Also pumps usb_host_ensure(): this is the per-frame call from
 * device_ui_bridge, and it is what starts the host stack and consumes MSC
 * connect/disconnect events. Without the pump nothing ever enumerates. */
bool modulus_storage_usb_volume_mounted(void)
{
    usb_host_ensure();
    return s_msc_mounted;
}


/* Mirror of the BSP's usb_lib_task — we cannot use bsp_usb_host_start(), see
 * usb_host_start_safe(). */
static void usb_lib_task(void *arg)
{
    (void)arg;
    for (;;) {
        uint32_t event_flags = 0;
        usb_host_lib_handle_events(portMAX_DELAY, &event_flags);
        if (event_flags & USB_HOST_LIB_EVENT_FLAGS_NO_CLIENTS) {
            (void)usb_host_device_free_all();
        }
    }
}

/* bsp_usb_host_start() = bsp_feature_enable(BSP_FEATURE_USB) + usb_host_install()
 * + task. We deliberately skip the feature_enable step.
 *
 * BSP_USB_EN is the same PI4IOE pin as our usb5v rail (E2.P3), which
 * tab5_pi4ioe already drives. esp_io_expander does read-modify-write against
 * its OWN cached register image, and that cache is stale because we write the
 * chip directly — so its set_dir/set_output_mode pass knocks WLAN_PWR_EN
 * (E2.P0) to High-Z. The C6 browns out and esp_hosted dies ~14 ms later:
 *
 *   I (18656) Installing USB Host
 *   E (18670) sdmmc_io: sdmmc_send_cmd returned 0x107
 *   E (18685) H_SDIO_DRV: Unrecoverable host sdio state
 *
 * Re-driving the rail afterwards does NOT help — verified on device; a
 * momentary High-Z already reset the C6. The clobber must not happen at all.
 * VBUS is already on from modulus_power_apply_rails(), so the host stack just
 * needs installing. */
static esp_err_t usb_host_start_safe(void)
{
    if (!tab5_pi4ioe_ensure_wlan_pwr_on()) {
        ESP_LOGW(TAG, "WLAN_PWR not healthy before USB host install");
    }

    const usb_host_config_t host_config = {
        .skip_phy_setup = false,
        .intr_flags = ESP_INTR_FLAG_LOWMED,
    };
    esp_err_t err = usb_host_install(&host_config);
    if (err != ESP_OK) {
        return err;
    }
    if (xTaskCreate(usb_lib_task, "usb_lib", 4096, NULL, 10, &s_usb_lib_task) != pdPASS) {
        ESP_LOGE(TAG, "usb_lib task create failed");
        (void)usb_host_uninstall();
        return ESP_ERR_NO_MEM;
    }

    /* MSC class driver. Its task must sit BELOW zig_ui (prio 5) and stay off
     * Core 1 (CNC) — an unpinned prio-10 driver task next to the UI is how
     * taskLVGL starved IDLE0. */
    const msc_host_driver_config_t msc_cfg = {
        .create_backround_task = true,
        .task_priority = 4,
        .stack_size = 4096,
        .callback = msc_event_cb,
        .callback_arg = NULL,
        .core_id = 0,
    };
    err = msc_host_install(&msc_cfg);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "msc_host_install: %s — USB drive files unavailable",
                 esp_err_to_name(err));
        /* Non-fatal: enumeration still works, the volume just stays empty. */
    }
    return ESP_OK;
}

static esp_err_t usb_host_stop_safe(void)
{
    /* Order matters: drop the volume and the MSC driver before the host stack,
     * or msc_host_uninstall_device() acts on a torn-down bus. */
    msc_unmount();
    (void)msc_host_uninstall();
    s_msc_pending_addr = 0;
    s_msc_pending_disconnect = false;

    const esp_err_t err = usb_host_uninstall();
    if (s_usb_lib_task) {
        vTaskDelete(s_usb_lib_task);
        s_usb_lib_task = NULL;
    }
    return err;
}

static void usb_host_ensure(void)
{
    /* Defer until Zig boot finishes battery_init — BSP USB enable hits PI4IOE
     * on the same M-Bus as INA226 without going through coex. */
    if (!modulus_zig_boot_ok()) {
        s_usb_dev_count = 0;
        snprintf(s_usb_status, sizeof(s_usb_status), "Booting");
        return;
    }

    const bool vbus = modulus_nvs_get_u8("usb5v", 1) != 0;
    if (!vbus) {
        if (s_usb_started) {
            if (modulus_i2c_coex_lock(5000)) {
                const esp_err_t stop = usb_host_stop_safe();
                modulus_i2c_coex_unlock();
                if (stop != ESP_OK) {
                    ESP_LOGW(TAG, "USB host stop: %s", esp_err_to_name(stop));
                }
            } else {
                ESP_LOGW(TAG, "USB host stop skipped — I2C coex busy");
                return;
            }
            s_usb_started = false;
            ESP_LOGI(TAG, "USB host stopped (VBUS off)");
        }
        s_usb_dev_count = 0;
        snprintf(s_usb_status, sizeof(s_usb_status), "VBUS off");
        return;
    }

    if (!s_usb_started) {
        if (!modulus_i2c_coex_lock(5000)) {
            s_usb_dev_count = 0;
            snprintf(s_usb_status, sizeof(s_usb_status), "I2C busy");
            return;
        }
        const esp_err_t start = usb_host_start_safe();
        modulus_i2c_coex_unlock();
        if (start == ESP_OK || start == ESP_ERR_INVALID_STATE) {
            s_usb_started = true;
            if (start == ESP_OK) {
                ESP_LOGI(TAG, "USB host started (BSP)");
            }
        } else {
            s_usb_dev_count = 0;
            snprintf(s_usb_status, sizeof(s_usb_status), "Host start fail");
            ESP_LOGW(TAG, "USB host start: %s", esp_err_to_name(start));
            return;
        }
    }

    const int64_t now = esp_timer_get_time();
    if ((now - s_usb_last_poll_us) >= 200000) {
        s_usb_last_poll_us = now;
        usb_host_lib_info_t info = {0};
        if (usb_host_lib_info(&info) == ESP_OK) {
            s_usb_dev_count = info.num_devices;
        }
    }

    /* Consume MSC events recorded by the driver-task callback. Doing the
     * mount here keeps FATFS work off the callback and off the paint path. */
    if (s_msc_pending_disconnect) {
        s_msc_pending_disconnect = false;
        msc_unmount();
    }
    if (s_msc_pending_addr != 0 && !s_msc_mounted) {
        const uint8_t addr = s_msc_pending_addr;
        s_msc_pending_addr = 0;
        msc_try_mount(addr);
    }

    if (s_msc_mounted) {
        snprintf(s_usb_status, sizeof(s_usb_status), "Drive mounted");
    } else if (s_usb_dev_count > 0) {
        snprintf(s_usb_status, sizeof(s_usb_status), "Device linked");
    } else {
        snprintf(s_usb_status, sizeof(s_usb_status), "No device");
    }
}

void modulus_storage_init(void)
{
    /* Idempotent. device_ui_bridge.storagePoll() calls this on every ~2 s
     * Storage refresh, which re-read NVS, re-ran esp_log_level_set, retried the
     * SD mount and printed three lines — forever. It is an init, so run once.
     * Use modulus_storage_mount() for an explicit remount. */
    static bool s_inited = false;
    if (s_inited) {
        return;
    }
    s_inited = true;

    /* Restore log level from NVS (matches Storage tab + C++ hal_system::init). */
    {
        uint8_t lvl = modulus_nvs_get_u8("loglvl", 2);
        if (lvl > 5) {
            lvl = 2;
        }
        esp_log_level_set("*", (esp_log_level_t)lvl);
        ESP_LOGI(TAG, "Log level restored: %u", (unsigned)lvl);
    }

    modulus_mbus_init();
    /* Best-effort mount once at boot. Live get_sd_info must NOT remount —
     * otherwise Eject is undone by the 2 s Storage refresh timer. */
    (void)modulus_storage_mount();
    ESP_LOGI(TAG, "Storage HAL init (SD mount after wireless_restore — SDIO bus free)");
}

bool modulus_storage_mount(void)
{
    if (s_sd_mounted) {
        return true;
    }

    (void)s_mount_point;
    const esp_err_t ret = shared_sdcard_mount(false);
    if (ret == ESP_OK) {
        s_sd_mounted = true;
        ESP_LOGI(TAG, "SD mounted at %s", s_mount_point);
        return true;
    }

    ESP_LOGW(TAG, "SD mount failed: %s", esp_err_to_name(ret));
    s_sd_mounted = false;
    return false;
}

void modulus_storage_unmount(void)
{
    if (!s_sd_mounted) {
        return;
    }
    const esp_err_t ret = shared_sdcard_unmount();
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "SD unmount failed: %s", esp_err_to_name(ret));
    }
    s_sd_mounted = false;
    ESP_LOGI(TAG, "SD unmounted");
}

static bool sd_remount_with_format(void)
{
    (void)shared_sdcard_unmount();
    s_sd_mounted = false;

    const esp_err_t ret = shared_sdcard_mount(true);
    if (ret == ESP_OK) {
        s_sd_mounted = true;
        ESP_LOGI(TAG, "SD mounted with format-if-needed at %s", s_mount_point);
        return true;
    }
    ESP_LOGW(TAG, "SD remount with format failed: %s", esp_err_to_name(ret));
    return false;
}

bool modulus_storage_is_mounted(void)
{
    return s_sd_mounted;
}

void modulus_storage_get_sd_info(modulus_sd_info_t *out)
{
    if (!out) {
        return;
    }
    memset(out, 0, sizeof(*out));
    out->state = MODULUS_SD_NOT_PRESENT;
    out->bus_width = 4;

    /* Never auto-mount here — Mount/Eject UI owns session lifetime. */
    if (!s_sd_mounted) {
        return;
    }

    uint64_t total_bytes = 0;
    uint64_t free_bytes = 0;
    if (esp_vfs_fat_info(s_mount_point, &total_bytes, &free_bytes) == ESP_OK) {
        out->state = MODULUS_SD_MOUNTED;
        out->total_bytes = total_bytes;
        out->free_bytes = free_bytes;
    } else {
        out->state = MODULUS_SD_ERROR;
    }
}

void modulus_storage_get_mem_info(modulus_mem_info_t *out)
{
    if (!out) {
        return;
    }
    memset(out, 0, sizeof(*out));
    out->internal_free = heap_caps_get_free_size(MALLOC_CAP_INTERNAL);
    out->internal_total = heap_caps_get_total_size(MALLOC_CAP_INTERNAL);
    out->internal_min_free = heap_caps_get_minimum_free_size(MALLOC_CAP_INTERNAL);
    out->psram_free = heap_caps_get_free_size(MALLOC_CAP_SPIRAM);
    out->psram_total = heap_caps_get_total_size(MALLOC_CAP_SPIRAM);

    /* CONFIG_LV_USE_CLIB_MALLOC: lv_mem_monitor_core is a no-op (no LVGL TLSF pool).
     * LVGL widgets/layers use malloc -> PSRAM via CONFIG_SPIRAM_USE_MALLOC. Largest
     * contiguous PSRAM block is the practical headroom for layer draw buffers. */
    out->lvgl_free = heap_caps_get_largest_free_block(MALLOC_CAP_SPIRAM);
    if (out->psram_total > 0) {
        const size_t psram_used = out->psram_total - out->psram_free;
        out->lvgl_used_pct = (uint8_t)((psram_used * 100U) / out->psram_total);
        if (out->lvgl_used_pct > 100) {
            out->lvgl_used_pct = 100;
        }
    }
}

static const char *partition_type_str(esp_partition_type_t t)
{
    return (t == ESP_PARTITION_TYPE_APP) ? "app" : "data";
}

static const char *partition_subtype_str(esp_partition_type_t type, esp_partition_subtype_t sub)
{
    if (type == ESP_PARTITION_TYPE_APP) {
        switch (sub) {
        case ESP_PARTITION_SUBTYPE_APP_FACTORY:
            return "factory";
        case ESP_PARTITION_SUBTYPE_APP_OTA_0:
            return "ota_0";
        case ESP_PARTITION_SUBTYPE_APP_OTA_1:
            return "ota_1";
        default:
            return "app";
        }
    }
    switch (sub) {
    case ESP_PARTITION_SUBTYPE_DATA_NVS:
        return "nvs";
    case ESP_PARTITION_SUBTYPE_DATA_PHY:
        return "phy";
    case ESP_PARTITION_SUBTYPE_DATA_FAT:
        return "fat";
    case ESP_PARTITION_SUBTYPE_DATA_SPIFFS:
        return "spiffs";
    default:
        return "data";
    }
}

bool modulus_storage_export_diagnostics(const char *path)
{
    if (!path || path[0] == '\0') {
        return false;
    }
    if (!s_sd_mounted && !modulus_storage_mount()) {
        ESP_LOGW(TAG, "Diagnostics export requires mounted SD");
        return false;
    }

    FILE *f = fopen(path, "w");
    if (!f) {
        ESP_LOGW(TAG, "Cannot open %s", path);
        return false;
    }

    const time_t now = time(NULL);
    struct tm tm_now = {};
    if (now > 0) {
        localtime_r(&now, &tm_now);
    }

    fprintf(f, "Modulus Diagnostics Export\n");
    fprintf(f, "OS: Modulus v%s\n", modulus_zig_version());
    fprintf(f, "ABI epoch: %lu\n", (unsigned long)modulus_zig_abi_epoch());
    fprintf(f, "Framework: ESP-IDF 6.0\n");
    if (now > 0) {
        fprintf(f, "Timestamp: %04d-%02d-%02d %02d:%02d:%02d\n", tm_now.tm_year + 1900,
                tm_now.tm_mon + 1, tm_now.tm_mday, tm_now.tm_hour, tm_now.tm_min, tm_now.tm_sec);
    }

    const uint32_t sec = (uint32_t)(esp_timer_get_time() / 1000000ULL);
    fprintf(f, "Uptime: %lu s\n", (unsigned long)sec);

    const uint8_t log_lvl = modulus_nvs_get_u8("loglvl", 2);
    const char *log_name = (log_lvl <= 5) ? k_loglvl_names[log_lvl] : "Unknown";
    fprintf(f, "Log Level: %s (%u)\n", log_name, (unsigned)log_lvl);

    modulus_mem_info_t mem = {};
    modulus_storage_get_mem_info(&mem);
    fprintf(f, "Internal SRAM: %u free / %u total (min ever %u)\n",
            (unsigned)mem.internal_free, (unsigned)mem.internal_total,
            (unsigned)mem.internal_min_free);
    fprintf(f, "PSRAM: %u free / %u total\n", (unsigned)mem.psram_free,
            (unsigned)mem.psram_total);
    fprintf(f, "UI allocator: CLIB + PSRAM (<=4 KiB internal)\n");
    fprintf(f, "PSRAM largest block: %u bytes (%u%% PSRAM used)\n",
            (unsigned)mem.lvgl_free, (unsigned)mem.lvgl_used_pct);

    modulus_sd_info_t sd = {};
    modulus_storage_get_sd_info(&sd);
    const char *sd_str = (sd.state == MODULUS_SD_MOUNTED) ? "mounted"
                         : (sd.state == MODULUS_SD_ERROR) ? "error"
                                                          : "absent";
    fprintf(f, "SD Card: %s", sd_str);
    if (sd.state == MODULUS_SD_MOUNTED) {
        fprintf(f, " - %llu bytes total, %llu free", (unsigned long long)sd.total_bytes,
                (unsigned long long)sd.free_bytes);
    }
    fprintf(f, "\n");

    typedef struct {
        const char *label;
        uint32_t size;
        const char *type_str;
        const char *subtype_str;
    } flash_part_t;

    flash_part_t parts[12];
    int count = 0;
    esp_partition_iterator_t it =
        esp_partition_find(ESP_PARTITION_TYPE_ANY, ESP_PARTITION_SUBTYPE_ANY, NULL);
    while (it && count < 12) {
        const esp_partition_t *p = esp_partition_get(it);
        if (p) {
            parts[count].label = p->label;
            parts[count].size = p->size;
            parts[count].type_str = partition_type_str(p->type);
            parts[count].subtype_str = partition_subtype_str(p->type, p->subtype);
            count++;
        }
        it = esp_partition_next(it);
    }
    if (it) {
        esp_partition_iterator_release(it);
    }

    fprintf(f, "Flash partitions (%d):\n", count);
    for (int i = 0; i < count; i++) {
        fprintf(f, "  %s: %lu bytes (%s/%s)\n", parts[i].label, (unsigned long)parts[i].size,
                parts[i].type_str, parts[i].subtype_str);
    }

    fprintf(f, "USB Type-A host: %s\n", modulus_storage_usb_host_status_text());
    fprintf(f, "USB Type-A VBUS: %s\n",
            modulus_nvs_get_u8("usb5v", 1) ? "ON (Power tab)" : "OFF");

    fprintf(f, "I2C Scanner: %s\n", modulus_i2c_scan_status_text());
    fprintf(f, "Port A Grove: %s\n", modulus_i2c_scan_port_a_text());
    fprintf(f, "M-Bus system: %s\n", modulus_i2c_scan_mbus_text());
    fprintf(f, "EXP1 PI4IOE1: %s\n", modulus_i2c_scan_exp1_text());
    fprintf(f, "EXP2 PI4IOE2: %s\n", modulus_i2c_scan_exp2_text());
    tab5_port_map_write_diag(f);

    fclose(f);
    ESP_LOGI(TAG, "Diagnostics exported to %s", path);
    return true;
}

bool modulus_storage_export_settings(const char *path, bool include_secrets)
{
    if (!path || path[0] == '\0') {
        return false;
    }
    if (!s_sd_mounted && !modulus_storage_mount()) {
        return false;
    }
    FILE *f = fopen(path, "w");
    if (!f) {
        return false;
    }
    fprintf(f, "{\n  \"modulus_settings\": 1");

    static const char *const u8_keys[] = {
        "cnc_proto", "cnc_conn", "cnc_autocon", "cnc_prof", "cnc_wcs", "cnc_unit",
        "cnc_jmode", "cnc_axes", "cnc_encdiv", "cnc_contpct", "cnc_stepacc", "cnc_mpgpol",
        "cnf_cycle", "cnf_spin", "cnf_zero", "cnf_home", "cnf_mac", "jog_coal_ms",
        "jog_pend_max", "ovr_l", "ovr_r", "wcs_lock", "bright", "darkmode", "lefty", "flip",
    };
    for (unsigned i = 0; i < sizeof(u8_keys) / sizeof(u8_keys[0]); i++) {
        fprintf(f, ",\n  \"%s\": %u", u8_keys[i], (unsigned)modulus_nvs_get_u8(u8_keys[i], 0));
    }
    static const char *const u16_keys[] = {
        "cnc_jogspd", "ws_port", "tn_port", "ser_baud", "r4_baud", "masso_tx", "masso_rx",
    };
    for (unsigned i = 0; i < sizeof(u16_keys) / sizeof(u16_keys[0]); i++) {
        fprintf(f, ",\n  \"%s\": %u", u16_keys[i], (unsigned)modulus_nvs_get_u16(u16_keys[i], 0));
    }
    static const char *const str_keys[] = {
        "ws_host", "ws_path", "tn_host", "mach_name", "cnc_incr", "cnc_macro",
        "cnc_mac0", "cnc_mac1", "cnc_mac2", "cnc_mac3", "cnc_p0", "cnc_p1", "cnc_p2", "cnc_p3",
        "wcs_n0", "wcs_n1", "wcs_n2", "wcs_n3", "wcs_n4", "wcs_n5", "masso_ip", "masso_sn",
    };
    for (unsigned i = 0; i < sizeof(str_keys) / sizeof(str_keys[0]); i++) {
        char buf[192];
        if (!modulus_nvs_get_str(str_keys[i], buf, sizeof(buf))) {
            buf[0] = '\0';
        }
        fprintf(f, ",\n  \"%s\": \"", str_keys[i]);
        for (const char *c = buf; *c; c++) {
            if (*c == '"' || *c == '\\') {
                fputc('\\', f);
            }
            fputc(*c, f);
        }
        fputc('"', f);
    }
    if (include_secrets) {
        char buf[128];
        if (modulus_nvs_get_str("wf_pass", buf, sizeof(buf))) {
            fprintf(f, ",\n  \"wf_pass\": \"%s\"", buf);
        }
        if (modulus_nvs_get_str("wf_ssid", buf, sizeof(buf))) {
            fprintf(f, ",\n  \"wf_ssid\": \"%s\"", buf);
        }
    }
    fprintf(f, "\n}\n");
    fclose(f);
    ESP_LOGI(TAG, "Settings exported to %s (secrets=%d)", path, (int)include_secrets);
    return true;
}

static bool json_get_u_number(const char *json, const char *key, unsigned *out)
{
    char pat[48];
    snprintf(pat, sizeof(pat), "\"%s\":", key);
    const char *p = strstr(json, pat);
    if (!p) {
        return false;
    }
    p += strlen(pat);
    while (*p == ' ' || *p == '\t') {
        p++;
    }
    *out = (unsigned)strtoul(p, NULL, 10);
    return true;
}

static bool json_get_string(const char *json, const char *key, char *out, size_t out_len)
{
    char pat[48];
    snprintf(pat, sizeof(pat), "\"%s\":", key);
    const char *p = strstr(json, pat);
    if (!p || out_len == 0) {
        return false;
    }
    p += strlen(pat);
    while (*p == ' ' || *p == '\t') {
        p++;
    }
    if (*p != '"') {
        return false;
    }
    p++;
    size_t i = 0;
    while (*p && *p != '"' && i + 1 < out_len) {
        if (*p == '\\' && p[1]) {
            p++;
        }
        out[i++] = *p++;
    }
    out[i] = '\0';
    return true;
}

bool modulus_storage_import_settings(const char *path, bool include_secrets)
{
    if (!path || path[0] == '\0') {
        return false;
    }
    if (!s_sd_mounted && !modulus_storage_mount()) {
        return false;
    }
    FILE *f = fopen(path, "r");
    if (!f) {
        return false;
    }
    char *json = calloc(1, 16384);
    if (!json) {
        fclose(f);
        return false;
    }
    const size_t n = fread(json, 1, 16383, f);
    fclose(f);
    json[n] = '\0';
    if (!strstr(json, "\"modulus_settings\"")) {
        free(json);
        return false;
    }

    static const char *const u8_keys[] = {
        "cnc_proto", "cnc_conn", "cnc_autocon", "cnc_prof", "cnc_wcs", "cnc_unit",
        "cnc_jmode", "cnc_axes", "cnc_encdiv", "cnc_contpct", "cnc_stepacc", "cnc_mpgpol",
        "cnf_cycle", "cnf_spin", "cnf_zero", "cnf_home", "cnf_mac", "jog_coal_ms",
        "jog_pend_max", "ovr_l", "ovr_r", "wcs_lock", "bright", "darkmode", "lefty", "flip",
    };
    for (unsigned i = 0; i < sizeof(u8_keys) / sizeof(u8_keys[0]); i++) {
        unsigned v = 0;
        if (json_get_u_number(json, u8_keys[i], &v)) {
            modulus_nvs_set_u8(u8_keys[i], (uint8_t)v);
        }
    }
    static const char *const u16_keys[] = {
        "cnc_jogspd", "ws_port", "tn_port", "ser_baud", "r4_baud", "masso_tx", "masso_rx",
    };
    for (unsigned i = 0; i < sizeof(u16_keys) / sizeof(u16_keys[0]); i++) {
        unsigned v = 0;
        if (json_get_u_number(json, u16_keys[i], &v)) {
            modulus_nvs_set_u16(u16_keys[i], (uint16_t)v);
        }
    }
    static const char *const str_keys[] = {
        "ws_host", "ws_path", "tn_host", "mach_name", "cnc_incr", "cnc_macro",
        "cnc_mac0", "cnc_mac1", "cnc_mac2", "cnc_mac3", "cnc_p0", "cnc_p1", "cnc_p2", "cnc_p3",
        "wcs_n0", "wcs_n1", "wcs_n2", "wcs_n3", "wcs_n4", "wcs_n5", "masso_ip", "masso_sn",
    };
    for (unsigned i = 0; i < sizeof(str_keys) / sizeof(str_keys[0]); i++) {
        char buf[192];
        if (json_get_string(json, str_keys[i], buf, sizeof(buf))) {
            modulus_nvs_set_str(str_keys[i], buf);
        }
    }
    if (include_secrets) {
        char buf[128];
        if (json_get_string(json, "wf_pass", buf, sizeof(buf))) {
            modulus_nvs_set_str("wf_pass", buf);
        }
        if (json_get_string(json, "wf_ssid", buf, sizeof(buf))) {
            modulus_nvs_set_str("wf_ssid", buf);
        }
    }
    free(json);
    ESP_LOGI(TAG, "Settings imported from %s", path);
    return true;
}

void modulus_storage_clear_ui_cache(void)
{
#if !CONFIG_MODULUS_ZIG_UI_ENGINE
    lv_obj_t *scr = lv_screen_active();
    if (scr) {
        lv_obj_invalidate(scr);
    }
    /* Let LVGL refr timer flush — lv_refr_now pins taskLVGL on 1280x720 sw_rotate. */
#endif
    /* Zig UI: the engine repaints from its own dirty set; nothing to invalidate. */
    ESP_LOGI(TAG, "UI cache cleared");
}

bool modulus_storage_is_usb_host_enabled(void)
{
    usb_host_ensure();
    return s_usb_dev_count > 0;
}

/** Human status for Settings — VBUS + BSP USB host enumeration. */
const char *modulus_storage_usb_host_status_text(void)
{
    usb_host_ensure();
    return s_usb_status;
}

static struct {
    char names[USB_VOL_MAX][USB_VOL_NAME];
    size_t count;
} s_usb_vol;

static void msc_clear_catalog(void)
{
    s_usb_vol.count = 0;
}

static bool usb_vol_is_gcode(const char *name)
{
    const char *dot = strrchr(name, '.');
    if (!dot) {
        return false;
    }
    const char *ext = dot + 1;
    return strcasecmp(ext, "nc") == 0 || strcasecmp(ext, "gcode") == 0 ||
           strcasecmp(ext, "ngc") == 0 || strcasecmp(ext, "tap") == 0;
}

static bool usb_vol_path(char *out, size_t cap, const char *name)
{
    int n = snprintf(out, cap, "%s/%s", USB_VOL_PATH, name);
    return n > 0 && (size_t)n < cap;
}

size_t modulus_usb_volume_refresh(void)
{
    s_usb_vol.count = 0;
    /* Gate on a MOUNTED volume, not on "a device is present" —
     * s_usb_dev_count counts any USB device (keyboard, hub, …). */
    if (!s_msc_mounted) {
        return 0;
    }
    DIR *d = opendir(USB_VOL_PATH);
    if (!d) {
        ESP_LOGW(TAG, "opendir(%s) failed though volume is mounted", USB_VOL_PATH);
        return 0;
    }
    struct dirent *ent;
    while ((ent = readdir(d)) != NULL && s_usb_vol.count < USB_VOL_MAX) {
#if defined(DT_REG)
        if (ent->d_type != DT_UNKNOWN && ent->d_type != DT_REG) {
            continue;
        }
#endif
        if (!usb_vol_is_gcode(ent->d_name)) {
            continue;
        }
        strncpy(s_usb_vol.names[s_usb_vol.count], ent->d_name, USB_VOL_NAME - 1);
        s_usb_vol.names[s_usb_vol.count][USB_VOL_NAME - 1] = '\0';
        s_usb_vol.count++;
    }
    closedir(d);
    return s_usb_vol.count;
}

bool modulus_usb_volume_name(size_t index, char *buf, size_t cap)
{
    if (!buf || cap == 0 || index >= s_usb_vol.count) {
        return false;
    }
    strncpy(buf, s_usb_vol.names[index], cap - 1);
    buf[cap - 1] = '\0';
    return true;
}

bool modulus_usb_volume_delete(size_t index)
{
    if (index >= s_usb_vol.count) {
        return false;
    }
    char path[64];
    if (!usb_vol_path(path, sizeof(path), s_usb_vol.names[index])) {
        return false;
    }
    if (unlink(path) != 0) {
        return false;
    }
    modulus_usb_volume_refresh();
    return true;
}

bool modulus_usb_volume_rename(size_t index, const char *new_name)
{
    if (!new_name || new_name[0] == '\0' || index >= s_usb_vol.count || !usb_vol_is_gcode(new_name)) {
        return false;
    }
    char old_path[64];
    char new_path[64];
    if (!usb_vol_path(old_path, sizeof(old_path), s_usb_vol.names[index])) {
        return false;
    }
    if (!usb_vol_path(new_path, sizeof(new_path), new_name)) {
        return false;
    }
    if (rename(old_path, new_path) != 0) {
        return false;
    }
    modulus_usb_volume_refresh();
    return true;
}

bool modulus_usb_volume_eject(void)
{
    if (!s_msc_mounted) {
        return false;
    }
    /* Real eject: unregister the FATFS VFS and release the device so pulling
     * the stick cannot corrupt it. No sync() on newlib/IDF — and none needed:
     * esp_vfs_fat_unregister (inside msc_host_vfs_unregister) calls f_mount(0)
     * which flushes FATFS buffers from rename/delete. */
    msc_unmount();
    ESP_LOGI(TAG, "USB volume ejected — safe to remove");
    return true;
}

/* Read a window of lines from a G-code file for the View pane.
 *
 * Line-oriented, not byte-oriented: the viewer scrolls by line, and G-code
 * files run to megabytes — we must never read the whole thing into RAM. Seeks
 * from the start each call (files are small enough that this beats holding an
 * open FILE* across UI frames, which would pin a FATFS file handle while the
 * operator is idle in the viewer).
 *
 * Returns the number of lines written; each is NUL-terminated in `buf` and its
 * offset stored in `line_offsets`. Long lines are truncated, not wrapped. */
size_t modulus_usb_volume_read_lines(size_t index,
                                     size_t first_line,
                                     char *buf,
                                     size_t buf_cap,
                                     uint16_t *line_offsets,
                                     size_t max_lines)
{
    if (!s_msc_mounted || index >= s_usb_vol.count || !buf || !line_offsets ||
        buf_cap == 0 || max_lines == 0) {
        return 0;
    }
    char path[64];
    if (!usb_vol_path(path, sizeof(path), s_usb_vol.names[index])) {
        return 0;
    }
    FILE *f = fopen(path, "r");
    if (!f) {
        ESP_LOGW(TAG, "view: fopen(%s) failed", path);
        return 0;
    }

    char line[MODULUS_USB_VIEW_LINE_MAX];
    size_t skipped = 0;
    while (skipped < first_line && fgets(line, sizeof(line), f)) {
        skipped++;
    }

    size_t out_n = 0;
    size_t used = 0;
    while (out_n < max_lines && fgets(line, sizeof(line), f)) {
        size_t len = strlen(line);
        while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r')) {
            line[--len] = '\0';
        }
        if (used + len + 1 > buf_cap) {
            break;   /* buffer full — caller pages again */
        }
        line_offsets[out_n] = (uint16_t)used;
        memcpy(buf + used, line, len);
        buf[used + len] = '\0';
        used += len + 1;
        out_n++;
    }
    fclose(f);
    return out_n;
}

/** Total line count — for the viewer's scrollbar and "line N of M". */
size_t modulus_usb_volume_line_count(size_t index)
{
    if (!s_msc_mounted || index >= s_usb_vol.count) {
        return 0;
    }
    char path[64];
    if (!usb_vol_path(path, sizeof(path), s_usb_vol.names[index])) {
        return 0;
    }
    FILE *f = fopen(path, "r");
    if (!f) {
        return 0;
    }
    size_t n = 0;
    int c;
    int last = '\n';
    while ((c = fgetc(f)) != EOF) {
        if (c == '\n') n++;
        last = c;
    }
    if (last != '\n') n++;   /* final line without trailing newline */
    fclose(f);
    return n;
}

#define SD_VOL_ROOT "/sdcard/modulus"
#define SD_VOL_MAX 32
#define SD_VOL_NAME 36

static const char *const k_sd_folders[MODULUS_SD_VOL_FOLDER_COUNT] = {
    "logs", "backups", "macros", "scripts", "reports", "cache",
};

static struct {
    char names[SD_VOL_MAX][SD_VOL_NAME];
    size_t count;
} s_sd_vol;

static bool sd_vol_mkdir_one(const char *path)
{
    struct stat st;
    if (stat(path, &st) == 0) {
        return S_ISDIR(st.st_mode);
    }
    if (mkdir(path, 0755) == 0) {
        return true;
    }
    return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

static bool sd_vol_mkdir_p(const char *path)
{
    char tmp[96];
    const size_t n = strnlen(path, sizeof(tmp) - 1);
    if (n == 0 || n >= sizeof(tmp)) {
        return false;
    }
    memcpy(tmp, path, n + 1);
    for (size_t i = 1; i < n; i++) {
        if (tmp[i] != '/') {
            continue;
        }
        tmp[i] = '\0';
        if (!sd_vol_mkdir_one(tmp)) {
            return false;
        }
        tmp[i] = '/';
    }
    return sd_vol_mkdir_one(tmp);
}

bool modulus_sd_volume_ensure_layout(void)
{
    if (!s_sd_mounted && !modulus_storage_mount()) {
        return false;
    }
    if (!sd_vol_mkdir_p(SD_VOL_ROOT)) {
        return false;
    }
    char path[96];
    for (size_t i = 0; i < MODULUS_SD_VOL_FOLDER_COUNT; i++) {
        snprintf(path, sizeof(path), "%s/%s", SD_VOL_ROOT, k_sd_folders[i]);
        if (!sd_vol_mkdir_p(path)) {
            return false;
        }
    }
    return true;
}

const char *modulus_sd_volume_folder_rel(modulus_sd_vol_folder_t folder)
{
    if ((size_t)folder >= MODULUS_SD_VOL_FOLDER_COUNT) {
        return "";
    }
    return k_sd_folders[folder];
}

static bool sd_vol_full_path(char *out, size_t cap, modulus_sd_vol_folder_t folder)
{
    if ((size_t)folder >= MODULUS_SD_VOL_FOLDER_COUNT) {
        return false;
    }
    const int n = snprintf(out, cap, "%s/%s", SD_VOL_ROOT, k_sd_folders[folder]);
    return n > 0 && (size_t)n < cap;
}

static void sd_vol_sort_desc(void)
{
    for (size_t i = 0; i + 1 < s_sd_vol.count; i++) {
        for (size_t j = i + 1; j < s_sd_vol.count; j++) {
            if (strcasecmp(s_sd_vol.names[i], s_sd_vol.names[j]) < 0) {
                char tmp[SD_VOL_NAME];
                memcpy(tmp, s_sd_vol.names[i], SD_VOL_NAME);
                memcpy(s_sd_vol.names[i], s_sd_vol.names[j], SD_VOL_NAME);
                memcpy(s_sd_vol.names[j], tmp, SD_VOL_NAME);
            }
        }
    }
}

size_t modulus_sd_volume_refresh(modulus_sd_vol_folder_t folder)
{
    s_sd_vol.count = 0;
    if (!s_sd_mounted && !modulus_storage_mount()) {
        return 0;
    }
    char dir[96];
    if (!sd_vol_full_path(dir, sizeof(dir), folder)) {
        return 0;
    }
    (void)modulus_sd_volume_ensure_layout();
    DIR *d = opendir(dir);
    if (!d) {
        return 0;
    }
    struct dirent *ent;
    while ((ent = readdir(d)) != NULL && s_sd_vol.count < SD_VOL_MAX) {
        if (ent->d_name[0] == '.') {
            continue;
        }
#if defined(DT_REG)
        if (ent->d_type != DT_UNKNOWN && ent->d_type != DT_REG && ent->d_type != DT_DIR) {
            continue;
        }
#endif
        strncpy(s_sd_vol.names[s_sd_vol.count], ent->d_name, SD_VOL_NAME - 1);
        s_sd_vol.names[s_sd_vol.count][SD_VOL_NAME - 1] = '\0';
        s_sd_vol.count++;
    }
    closedir(d);
    sd_vol_sort_desc();
    return s_sd_vol.count;
}

bool modulus_sd_volume_name(size_t index, char *buf, size_t cap)
{
    if (!buf || cap == 0 || index >= s_sd_vol.count) {
        return false;
    }
    strncpy(buf, s_sd_vol.names[index], cap - 1);
    buf[cap - 1] = '\0';
    return true;
}

bool modulus_sd_volume_delete(modulus_sd_vol_folder_t folder, size_t index)
{
    if (index >= s_sd_vol.count) {
        return false;
    }
    char dir[96];
    char path[160];
    if (!sd_vol_full_path(dir, sizeof(dir), folder)) {
        return false;
    }
    snprintf(path, sizeof(path), "%s/%s", dir, s_sd_vol.names[index]);
    if (unlink(path) != 0) {
        return false;
    }
    modulus_sd_volume_refresh(folder);
    return true;
}

static bool sd_vol_stamp_path(char *out, size_t cap, const char *subdir, const char *prefix, const char *suffix)
{
    if (!modulus_sd_volume_ensure_layout()) {
        return false;
    }
    time_t now = time(NULL);
    struct tm tm = {0};
    localtime_r(&now, &tm);
    const int n = snprintf(out, cap, "%s/%s/%s_%04d%02d%02d_%02d%02d%02d%s",
                           SD_VOL_ROOT, subdir, prefix,
                           tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday,
                           tm.tm_hour, tm.tm_min, tm.tm_sec, suffix);
    return n > 0 && (size_t)n < cap;
}

bool modulus_sd_volume_backup_path(char *out, size_t cap)
{
    return sd_vol_stamp_path(out, cap, "backups", "settings", ".json");
}

bool modulus_sd_volume_log_path(char *out, size_t cap)
{
    return sd_vol_stamp_path(out, cap, "logs", "diag", ".txt");
}

bool modulus_sd_volume_entry_path(modulus_sd_vol_folder_t folder, size_t index, char *out, size_t cap)
{
    if (index >= s_sd_vol.count) {
        return false;
    }
    char dir[96];
    if (!sd_vol_full_path(dir, sizeof(dir), folder)) {
        return false;
    }
    const int n = snprintf(out, cap, "%s/%s", dir, s_sd_vol.names[index]);
    return n > 0 && (size_t)n < cap;
}

bool modulus_storage_format_sd(void)
{
    if (!s_sd_mounted && !modulus_storage_mount() && !sd_remount_with_format()) {
        ESP_LOGW(TAG, "SD format: card not mountable");
        return false;
    }

    sdmmc_card_t *card = s_sd_card;
    if (!card) {
        ESP_LOGW(TAG, "SD format: no card handle");
        return false;
    }

    esp_err_t err = esp_vfs_fat_sdcard_format(s_mount_point, card);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "esp_vfs_fat_sdcard_format: %s — trying format-on-mount", esp_err_to_name(err));
        if (!sd_remount_with_format()) {
            return false;
        }
        card = s_sd_card;
        if (!card) {
            return false;
        }
    }

    s_sd_vol.count = 0;
    if (!modulus_sd_volume_ensure_layout()) {
        ESP_LOGW(TAG, "SD formatted but modulus layout failed");
        return false;
    }
    ESP_LOGI(TAG, "SD formatted (FAT32); modulus folders ready");
    return true;
}
