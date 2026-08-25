#include "bridge_board.h"
#include "bridge_config.h"
#include "bridge_nvs.h"
#include "halt_gpio.h"
#include "uart_bridge.h"
#include "sdkconfig.h"

#include <cstdio>
#include <cstring>

#include <esp_log.h>

static const char *TAG = "board";

/* Pin order: UART TX, RX, LED TX, LED RX, LED active-high, HALT.
 * UART1 to grblHAL. Shell is USB Serial/JTAG. Avoid GPIO33-37 on octal-PSRAM S3. */
static const bridge_board_t kBoards[] = {
    { "mini1", "Modulus", "ESP32-S3-MINI-1 handwheel", 8, 9, 45, 46, 1, 37 },
    { "ws-s3-zero", "Waveshare", "ESP32-S3-Zero (SKU 25081 / 33879)", 43, 44, -1, -1, 1, 1 },
    { "s3-supermini", "Generic", "ESP32-S3 Super Mini", 43, 44, -1, -1, 1, 1 },
    { "qtpy-s3", "Adafruit", "QT Py ESP32-S3 (no PSRAM)", 5, 16, -1, -1, 1, 8 },
    { "feather-s3", "Adafruit", "Feather ESP32-S3 (2MB PSRAM)", 39, 38, 13, 13, 1, 5 },
    { "feather-s3-np", "Adafruit", "Feather ESP32-S3 (no PSRAM)", 39, 38, 13, 13, 1, 5 },
    { "xiao", "Seeed", "XIAO ESP32-S3", 43, 44, 21, 21, 0, 1 },
    { "xiao-plus", "Seeed", "XIAO ESP32-S3 Plus", 43, 44, 1, 1, 1, 2 },
    { "um-feathers3", "Unexpected Maker", "FeatherS3", 43, 44, 13, 13, 1, 1 },
    { "um-tinys3", "Unexpected Maker", "TinyS3", 43, 44, -1, -1, 1, 1 },
    { "s3-devkitm1", "Espressif", "ESP32-S3-DevKitM-1", 17, 18, -1, -1, 1, 1 },
};

static int s_idx;

static int n_s3(void)
{
    return (int)(sizeof(kBoards) / sizeof(kBoards[0]));
}

static int find_s3(const char *id)
{
    if (!id || !id[0]) return -1;
    for (int i = 0; i < n_s3(); i++) {
        if (strcmp(kBoards[i].id, id) == 0) return i;
    }
    return -1;
}

static int default_idx(void)
{
#if CONFIG_S3_BRIDGE_BOARD_XIAO
    int i = find_s3("xiao");
    return i >= 0 ? i : 0;
#else
    int i = find_s3("mini1");
    return i >= 0 ? i : 0;
#endif
}

static void save_id(void)
{
    bridge_nvs_t nvs = bridge_nvs_open(NVS_READWRITE);
    if (!nvs.ok) return;
    esp_err_t err = nvs_set_str(nvs.h, NVS_KEY_BOARD, kBoards[s_idx].id);
    if (err == ESP_OK) err = nvs_commit(nvs.h);
    bridge_nvs_close(&nvs);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "save board: %s", esp_err_to_name(err));
    }
}

void bridge_board_init(void)
{
    s_idx = default_idx();
    bridge_nvs_t nvs = bridge_nvs_open(NVS_READONLY);
    if (nvs.ok) {
        char id[NVS_KEY_BOARD_MAX] = {};
        size_t len = sizeof(id);
        if (nvs_get_str(nvs.h, NVS_KEY_BOARD, id, &len) == ESP_OK) {
            int i = find_s3(id);
            if (i >= 0) s_idx = i;
        }
        bridge_nvs_close(&nvs);
    }
    ESP_LOGI(TAG, "board %s", kBoards[s_idx].id);
}

const bridge_board_t *bridge_board_get(void)
{
    return &kBoards[s_idx];
}

void bridge_board_print_list(void)
{
    printf("\r\n  ESP32-S3 boards — board <id>\r\n");
    const char *vend = "";
    for (int i = 0; i < n_s3(); i++) {
        const bridge_board_t *b = &kBoards[i];
        if (strcmp(vend, b->vendor) != 0) {
            vend = b->vendor;
            printf("  -- %s --\r\n", vend);
        }
        printf("    %s%-14s  %s\r\n", i == s_idx ? "*" : " ", b->id, b->name);
        printf("                   TX=GPIO%-2d RX=GPIO%-2d HALT=GPIO%-2d ",
               b->uart_tx, b->uart_rx, b->halt);
        if (b->led_tx < 0) {
            printf("LED=n/a\r\n");
        } else {
            printf("LED=%d/%d\r\n", b->led_tx, b->led_rx);
        }
    }
    printf("  Current: %s\r\n\r\n", kBoards[s_idx].id);
}

int bridge_board_set(const char *id)
{
    int i = find_s3(id);
    if (i >= 0) {
        s_idx = i;
        save_id();
        halt_gpio_rebind(kBoards[s_idx].halt);
        uart_bridge_apply_board();
        printf("  Board %s (%s) — UART TX=GPIO%d RX=GPIO%d  HALT=GPIO%d\r\n",
               kBoards[s_idx].id, kBoards[s_idx].name,
               kBoards[s_idx].uart_tx, kBoards[s_idx].uart_rx,
               kBoards[s_idx].halt);
        return 0;
    }
    return -1;
}
