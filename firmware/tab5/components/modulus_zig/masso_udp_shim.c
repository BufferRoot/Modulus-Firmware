/*
 * Masso Link UDP transport — send on masso_tx (11000–11050), recv on masso_rx (65535).
 * Wi-Fi via C6 (esp_wifi_remote). Feeds RX datagrams into Zig CNC engine.
 */
#include "transport_shim.h"
#include "wireless_shim.h"

#include <esp_log.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <lwip/netdb.h>
#include <lwip/sockets.h>
#include <lwip/inet.h>
#include <string.h>

static const char *TAG = "masso_udp";

static int s_tx_sock = -1;
static int s_rx_sock = -1;
static volatile TaskHandle_t s_rx_task = NULL;
static volatile bool s_running = false;
static volatile bool s_connected = false;
static char s_host[64] = "192.168.1.100";
static uint16_t s_tx_port = 11000;
static uint16_t s_rx_port = 65535;
static struct sockaddr_in s_peer;

static void masso_udp_rx_task(void *arg)
{
    (void)arg;
    uint8_t buf[512];
    while (s_running) {
        struct sockaddr_in from;
        socklen_t flen = sizeof(from);
        int n = recvfrom(s_rx_sock, buf, sizeof(buf), 0, (struct sockaddr *)&from, &flen);
        if (n > 0) {
            modulus_zig_serial_rx(buf, (size_t)n);
        } else {
            vTaskDelay(pdMS_TO_TICKS(20));
        }
    }
    s_rx_task = NULL;
    vTaskDelete(NULL);
}

bool modulus_masso_udp_start(const char *host, uint16_t tx_port, uint16_t rx_port)
{
    modulus_masso_udp_stop();
    if (!host || !host[0]) {
        return false;
    }
    strncpy(s_host, host, sizeof(s_host) - 1);
    s_host[sizeof(s_host) - 1] = '\0';
    s_tx_port = tx_port ? tx_port : 11000;
    s_rx_port = rx_port ? rx_port : 65535;

    memset(&s_peer, 0, sizeof(s_peer));
    s_peer.sin_family = AF_INET;
    s_peer.sin_port = htons(s_tx_port);
    if (inet_pton(AF_INET, s_host, &s_peer.sin_addr) != 1) {
        ESP_LOGE(TAG, "bad host %s", s_host);
        return false;
    }

    s_tx_sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    s_rx_sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (s_tx_sock < 0 || s_rx_sock < 0) {
        ESP_LOGE(TAG, "socket fail");
        modulus_masso_udp_stop();
        return false;
    }

    int yes = 1;
    (void)setsockopt(s_tx_sock, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    (void)setsockopt(s_rx_sock, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

    struct sockaddr_in local_tx = {0};
    local_tx.sin_family = AF_INET;
    local_tx.sin_addr.s_addr = htonl(INADDR_ANY);
    local_tx.sin_port = htons(s_tx_port);
    if (bind(s_tx_sock, (struct sockaddr *)&local_tx, sizeof(local_tx)) != 0) {
        /* try next ports in range */
        bool bound = false;
        for (uint16_t p = 11000; p <= 11050; p++) {
            local_tx.sin_port = htons(p);
            if (bind(s_tx_sock, (struct sockaddr *)&local_tx, sizeof(local_tx)) == 0) {
                s_tx_port = p;
                bound = true;
                break;
            }
        }
        if (!bound) {
            ESP_LOGE(TAG, "bind tx fail");
            modulus_masso_udp_stop();
            return false;
        }
    }

    struct sockaddr_in local_rx = {0};
    local_rx.sin_family = AF_INET;
    local_rx.sin_addr.s_addr = htonl(INADDR_ANY);
    local_rx.sin_port = htons(s_rx_port);
    if (bind(s_rx_sock, (struct sockaddr *)&local_rx, sizeof(local_rx)) != 0) {
        ESP_LOGE(TAG, "bind rx %u fail", (unsigned)s_rx_port);
        modulus_masso_udp_stop();
        return false;
    }

    s_running = true;
    s_connected = true;
    if (xTaskCreate(masso_udp_rx_task, "masso_udp_rx", 4096, NULL, 5,
                    (TaskHandle_t *)&s_rx_task) != pdPASS) {
        ESP_LOGE(TAG, "rx task fail");
        modulus_masso_udp_stop();
        return false;
    }
    ESP_LOGI(TAG, "Masso UDP %s tx=%u rx=%u", s_host, (unsigned)s_tx_port, (unsigned)s_rx_port);
    modulus_zig_transport_on_connect();
    return true;
}

void modulus_masso_udp_stop(void)
{
    s_running = false;
    s_connected = false;
    if (s_tx_sock >= 0) {
        close(s_tx_sock);
        s_tx_sock = -1;
    }
    if (s_rx_sock >= 0) {
        close(s_rx_sock);
        s_rx_sock = -1;
    }
    for (int i = 0; i < 50 && s_rx_task; i++) {
        vTaskDelay(pdMS_TO_TICKS(10));
    }
    modulus_zig_transport_on_disconnect();
}

bool modulus_masso_udp_send(const uint8_t *data, size_t len)
{
    if (!s_connected || s_tx_sock < 0 || !data || len == 0) {
        return false;
    }
    return sendto(s_tx_sock, data, len, 0, (struct sockaddr *)&s_peer, sizeof(s_peer)) == (int)len;
}

bool modulus_masso_udp_is_connected(void)
{
    return s_connected;
}
