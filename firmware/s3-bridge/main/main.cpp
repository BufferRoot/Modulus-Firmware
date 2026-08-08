/*
 * ESP32-S3 ESP-NOW ↔ UART Bridge - USB shell entry (UART0 / USB-CDC).
 * See bridge_config.h for full command list.
 */
#include "bridge_config.h"
#include "espnow_link.h"
#include "uart_bridge.h"
#include "halt_gpio.h"

#include <nvs_flash.h>
#include <esp_event.h>
#include <esp_netif.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <driver/uart.h>
#include <cstdio>
#include <cstring>
#include <cstdlib>

static void print_boot_self_check()
{
    bool espnow_ok = espnow_self_check();
    bool uart_ok = uart_bridge_self_check();
    bool all_ok = espnow_ok && uart_ok;

    printf("--- Boot self-check ---\r\n");
    printf("  ESP-NOW stack    : %s (ch %d, queue depth %d)\r\n",
           espnow_ok ? "PASS" : "FAIL",
           espnow_get_channel(), ESPNOW_QUEUE_DEPTH);
    printf("  UART bridge      : %s (TX=GPIO%d RX=GPIO%d)\r\n",
           uart_ok ? "PASS" : "FAIL",
           uart_bridge_tx_gpio(), uart_bridge_rx_gpio());
    printf("  Overall          : %s\r\n\r\n", all_ok ? "PASS" : "FAIL");
}

static void print_link_health()
{
    const char* mac = espnow_tab5_mac_str();
    uint32_t fails = espnow_fail_count();
    uint32_t drops = espnow_inbound_drops();
    uint32_t pending = espnow_inbound_pending();
    const char* health = "OK";

    if (strcmp(mac, "not seen yet") == 0) {
        health = "WAIT - no Tab5 peer yet";
    } else if (fails > 100 || drops > 50 || pending > (ESPNOW_QUEUE_DEPTH / 2)) {
        health = "FAULT - check channel / power / Tab5";
    } else if (fails > 0 || drops > 0 || pending > 8) {
        health = "DEGRADED";
    }

    printf("  Link health      : %s\r\n", health);
    if (espnow_tx_count() > 0) {
        uint32_t pct = (fails * 100U) / (espnow_tx_count() + fails);
        printf("  ESP-NOW fail rate: %lu%% (%lu ok / %lu fail)\r\n",
               (unsigned long)pct,
               (unsigned long)espnow_tx_count(),
               (unsigned long)fails);
    }
    printf("  Inbound queue    : %lu waiting, %lu drops\r\n",
           (unsigned long)pending, (unsigned long)drops);
    printf("  UART RX buffered : %u bytes\r\n",
           (unsigned)uart_bridge_rx_buffered());
    if (uart_bridge_uart_tx_fails() > 0) {
        printf("  UART TX fails    : %lu\r\n",
               (unsigned long)uart_bridge_uart_tx_fails());
    }
}

static void print_status()
{
    printf("\r\n=== S3 ESP-NOW <-> UART Bridge ===\r\n");
    print_link_health();
    printf("  ESP-NOW channel  : %d\r\n",    espnow_get_channel());
    printf("  Tab5 MAC         : %s\r\n",    espnow_tab5_mac_str());
    printf("  ESP-NOW RX pkts  : %lu\r\n",   (unsigned long)espnow_rx_count());
    printf("  ESP-NOW TX pkts  : %lu\r\n",   (unsigned long)espnow_tx_count());
    printf("  ESP-NOW TX fails : %lu\r\n",   (unsigned long)espnow_fail_count());
    printf("  UART port        : UART%d\r\n", UART_PORT_NUM);
    printf("  UART baud        : %lu\r\n",   (unsigned long)uart_bridge_baud());
    printf("  UART TX GPIO     : %d\r\n",    uart_bridge_tx_gpio());
    printf("  UART RX GPIO     : %d\r\n",    uart_bridge_rx_gpio());
    printf("  Batch trigger    : %lu ms\r\n", (unsigned long)uart_bridge_batch_ms());
    printf("  Activity LEDs    : %s\r\n",    uart_bridge_led_enabled() ? "on" : "off");
    printf("  LED TX (red)     : GPIO%d\r\n", LED_TX_GPIO);
    printf("  LED RX (green)   : GPIO%d\r\n", LED_RX_GPIO);
    printf("  HALT_host        : GPIO%d (%s)\r\n", HALT_HOST_GPIO,
           halt_gpio_is_asserted() ? "ASSERTED" : "released");
    printf("  Bytes -> grblHAL : %lu\r\n",   (unsigned long)uart_bridge_bytes_tx());
    printf("  Bytes -> Tab5    : %lu\r\n",   (unsigned long)uart_bridge_bytes_rx());
    printf("================================\r\n\r\n");
}

static void print_help()
{
    printf("\r\nCommands:\r\n");
    printf("  channel <1-13>               - ESP-NOW channel (live apply)\r\n");
    printf("  baud <115200|230400|460800|921600>  - UART baud rate\r\n");
    printf("  txgpio <n>                   - UART TX GPIO (default %d)\r\n", UART_TX_GPIO);
    printf("  rxgpio <n>                   - UART RX GPIO (default %d)\r\n", UART_RX_GPIO);
    printf("  uartping                     - UART wiring test (? to grblHAL, not ESP-NOW)\r\n");
    printf("  mpgactivate                  - send 0x8B MPG mode toggle to grblHAL\r\n");
    printf("  batchms <1-20>               - UART->ESP-NOW first-byte wait (ms)\r\n");
    printf("  led on|off                   - activity LED pulses\r\n");
    printf("  stats reset                  - clear traffic / fail counters\r\n");
    printf("  status                       - config, counters, link health\r\n");
    printf("  help                         - this list\r\n\r\n");
}

static void handle_command(const char* line)
{
    char cmd[32] = {};
    char arg[32] = {};
    sscanf(line, "%31s %31s", cmd, arg);

    if (strcmp(cmd, "status") == 0) {
        print_status();

    } else if (strcmp(cmd, "help") == 0) {
        print_help();

    } else if (strcmp(cmd, "channel") == 0) {
        int ch = atoi(arg);
        if (ch < 1 || ch > 13) {
            printf("  Error: channel must be 1-13\r\n");
            return;
        }
        if (espnow_set_channel((uint8_t)ch)) {
            printf("  Channel set to %d (live - Tab5 must match)\r\n", ch);
        } else {
            printf("  Error: failed to apply channel %d\r\n", ch);
        }

    } else if (strcmp(cmd, "baud") == 0) {
        uint32_t baud = (uint32_t)atol(arg);
        if (baud != 115200 && baud != 230400 && baud != 460800 && baud != 921600) {
            printf("  Error: supported rates: 115200 / 230400 / 460800 / 921600\r\n");
            return;
        }
        uart_bridge_reinit(baud, uart_bridge_tx_gpio(), uart_bridge_rx_gpio());
        printf("  Baud set to %lu\r\n", (unsigned long)baud);

    } else if (strcmp(cmd, "txgpio") == 0) {
        int gpio = atoi(arg);
        if (gpio < 0 || gpio > 48) {
            printf("  Error: invalid GPIO number\r\n");
            return;
        }
        uart_bridge_reinit(uart_bridge_baud(), gpio, uart_bridge_rx_gpio());
        printf("  TX GPIO set to %d\r\n", gpio);

    } else if (strcmp(cmd, "rxgpio") == 0) {
        int gpio = atoi(arg);
        if (gpio < 0 || gpio > 48) {
            printf("  Error: invalid GPIO number\r\n");
            return;
        }
        uart_bridge_reinit(uart_bridge_baud(), uart_bridge_tx_gpio(), gpio);
        printf("  RX GPIO set to %d\r\n", gpio);

    } else if (strcmp(cmd, "uartping") == 0) {
        /* UART-only path - does not exercise Tab5 / ESP-NOW */
        const char* probe = "?\n";
        uart_bridge_send((const uint8_t*)probe, 2);
        printf("  Sent '?' to grblHAL (UART only - not ESP-NOW path)...\r\n");
        uint32_t before = uart_bridge_bytes_rx();
        vTaskDelay(pdMS_TO_TICKS(500));
        uint32_t after  = uart_bridge_bytes_rx();
        uint32_t delta  = after - before;
        if (delta > 0)
            printf("  grblHAL replied: %lu byte(s) received\r\n", (unsigned long)delta);
        else
            printf("  No response - check wiring (TX=GPIO%d -> grblHAL RX, RX=GPIO%d <- grblHAL TX) and baud (%lu)\r\n",
                   uart_bridge_tx_gpio(), uart_bridge_rx_gpio(), (unsigned long)uart_bridge_baud());

    } else if (strcmp(cmd, "mpgactivate") == 0) {
        uart_bridge_mpg_activate();
        printf("  Sent 0x8B - MPG mode toggle (controller must be IDLE/ALARM/ESTOP)\r\n");

    } else if (strcmp(cmd, "batchms") == 0) {
        int ms = atoi(arg);
        if (ms < 1 || ms > 20) {
            printf("  Error: batchms must be 1-20\r\n");
            return;
        }
        uart_bridge_set_batch_ms((uint32_t)ms);
        printf("  Batch trigger set to %d ms\r\n", ms);

    } else if (strcmp(cmd, "led") == 0) {
        if (strcmp(arg, "on") == 0) {
            uart_bridge_set_led_enabled(true);
            printf("  Activity LEDs on\r\n");
        } else if (strcmp(arg, "off") == 0) {
            uart_bridge_set_led_enabled(false);
            printf("  Activity LEDs off\r\n");
        } else {
            printf("  Error: use 'led on' or 'led off'\r\n");
            return;
        }

    } else if (strcmp(cmd, "stats") == 0) {
        if (strcmp(arg, "reset") == 0) {
            espnow_reset_stats();
            uart_bridge_reset_stats();
            printf("  Traffic / fail counters cleared\r\n");
        } else {
            printf("  Use: stats reset\r\n");
            return;
        }

    } else if (cmd[0] != '\0') {
        printf("  Unknown command '%s' - type 'help'\r\n", cmd);
    }
    printf("> ");
    fflush(stdout);
}

static void shell_task(void* arg)
{
    char line[64];
    int  pos = 0;

    printf("\r\nS3 ESP-NOW <-> UART Bridge (type 'help' for commands)\r\n");
    print_status();
    printf("> ");
    fflush(stdout);

    while (1) {
        int ch = fgetc(stdin);
        if (ch == EOF) { vTaskDelay(pdMS_TO_TICKS(10)); continue; }

        if (ch == '\r' || ch == '\n') {
            if (pos == 0) { printf("> "); fflush(stdout); continue; }
            line[pos] = '\0';
            pos = 0;
            printf("\r\n");
            handle_command(line);
        } else if ((ch == 127 || ch == 8) && pos > 0) {
            /* Backspace */
            pos--;
            printf("\b \b");
            fflush(stdout);
        } else if (ch >= 0x20 && pos < (int)(sizeof(line) - 1)) {
            line[pos++] = (char)ch;
            fputc(ch, stdout);
            fflush(stdout);
        }
    }
}

// ── app_main ─────────────────────────────────────────────────────────────────
extern "C" void app_main()
{
    /* NVS - must initialise before any component reads settings */
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES ||
        err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    ESP_ERROR_CHECK(err);

    /* Default event loop - required by esp_wifi/esp_now */
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    ESP_ERROR_CHECK(esp_netif_init());

    /* Initialise ESP-NOW link first (WiFi STA, channel, peer auto-learn).
     * Must complete before the UART RX task starts so that esp_now_send()
     * is never called before esp_now_init() has run. */
    espnow_init();

    halt_gpio_init();

    /* Initialise UART bridge (sets up driver + RX task) */
    uart_bridge_init();

    print_boot_self_check();

    /* Launch interactive shell on UART0 / USB-CDC */
    xTaskCreatePinnedToCore(shell_task, "shell", 4096, NULL, 3, NULL, 1);
}
