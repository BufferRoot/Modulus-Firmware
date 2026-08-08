/*
 * WebSocket + Telnet CNC transports — lwIP TCP over esp_wifi_remote (C6).
 * Ported from C++ hal_websocket.cpp / hal_telnet.cpp.
 */
#include "transport_shim.h"
#include "wireless_shim.h"

#include <errno.h>
#include <esp_log.h>
#include <esp_tls.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <lwip/netdb.h>
#include <lwip/sockets.h>
#include <string.h>

static const char *TAG = "tcp_transport";

typedef enum {
    MODE_NONE = 0,
    MODE_WS,
    MODE_TELNET,
} tcp_mode_t;

static tcp_mode_t s_mode = MODE_NONE;
static int s_sock = -1;
static volatile TaskHandle_t s_rx_task = NULL;
static volatile bool s_running = false;
static volatile bool s_connected = false;
static esp_tls_t *s_tls = NULL;

static char s_host[64] = "192.168.1.100";
static uint16_t s_port = 81;
static char s_path[32] = "/";
static bool s_tls_on = false;

#define WS_ACC_MAX 2048
static uint8_t s_ws_acc[WS_ACC_MAX];
static size_t s_ws_acc_len = 0;

static int sock_send(const void *data, size_t len)
{
    if (s_tls) {
        return esp_tls_conn_write(s_tls, data, len);
    }
    if (s_sock >= 0) {
        return send(s_sock, data, len, 0);
    }
    return -1;
}

static int sock_recv(void *buf, size_t len)
{
    if (s_tls) {
        int ret = esp_tls_conn_read(s_tls, buf, len);
        if (ret == ESP_TLS_ERR_SSL_WANT_READ || ret == ESP_TLS_ERR_SSL_WANT_WRITE) {
            errno = EAGAIN;
            return -1;
        }
        return ret;
    }
    if (s_sock >= 0) {
        return recv(s_sock, buf, len, 0);
    }
    return -1;
}

static void sock_shutdown(void)
{
    if (s_sock >= 0) {
        shutdown(s_sock, SHUT_RDWR);
    }
}

static void sock_close(void)
{
    if (s_tls) {
        esp_tls_conn_destroy(s_tls);
        s_tls = NULL;
        s_sock = -1;
    } else if (s_sock >= 0) {
        close(s_sock);
        s_sock = -1;
    }
}

static void join_rx_task(void)
{
    if (s_rx_task == NULL) {
        return;
    }
    /* recv timeout is 100 ms; shutdown unblocks immediately. */
    while (s_rx_task != NULL) {
        vTaskDelay(pdMS_TO_TICKS(5));
    }
}

static int ws_build_frame(uint8_t *out, size_t out_max, const uint8_t *payload, size_t len, uint8_t opcode)
{
    if (len + 10 > out_max) {
        return -1;
    }
    size_t pos = 0;
    out[pos++] = 0x80 | (opcode & 0x0F);
    if (len < 126) {
        out[pos++] = 0x80 | (uint8_t)len;
    } else {
        out[pos++] = 0x80 | 126;
        out[pos++] = (uint8_t)(len >> 8);
        out[pos++] = (uint8_t)(len & 0xFF);
    }
    const uint8_t mask[4] = {0x12, 0x34, 0x56, 0x78};
    memcpy(&out[pos], mask, 4);
    pos += 4;
    for (size_t i = 0; i < len; i++) {
        out[pos++] = payload[i] ^ mask[i & 3];
    }
    return (int)pos;
}

static bool ws_send_pong(const uint8_t *payload, size_t len)
{
    uint8_t frame[128];
    if (len > sizeof(frame) - 10) {
        len = sizeof(frame) - 10;
    }
    int flen = ws_build_frame(frame, sizeof(frame), payload, len, 0x0A);
    if (flen <= 0) {
        return false;
    }
    return sock_send(frame, (size_t)flen) == flen;
}

/** Returns consumed frame bytes, 0 if incomplete, -1 on close/error.
 *  Unmasks in place (buf is the private accumulator) — the previous 512 B
 *  stack copy hard-failed any frame >512 B, disconnect-looping on large
 *  grbl responses ($$ dumps). Server->client frames are unmasked per
 *  RFC 6455, so the in-place path is normally a zero-copy passthrough. */
static int ws_consume_one(uint8_t *buf, size_t len, bool *closed_out)
{
    if (len < 2) {
        return 0;
    }
    const uint8_t opcode = buf[0] & 0x0F;
    const bool masked = (buf[1] & 0x80) != 0;
    size_t plen = buf[1] & 0x7F;
    size_t hdr = 2;

    if (plen == 126) {
        if (len < 4) {
            return 0;
        }
        plen = ((size_t)buf[2] << 8) | buf[3];
        hdr = 4;
    } else if (plen == 127) {
        return -1;
    }

    if (masked) {
        hdr += 4;
    }
    if (hdr + plen > WS_ACC_MAX) {
        return -1; /* can never complete inside the accumulator */
    }
    if (len < hdr + plen) {
        return 0;
    }

    const size_t frame_len = hdr + plen;
    uint8_t *payload = &buf[hdr];

    if (masked) {
        const uint8_t mask[4] = {buf[hdr - 4], buf[hdr - 3], buf[hdr - 2], buf[hdr - 1]};
        for (size_t i = 0; i < plen; i++) {
            payload[i] ^= mask[i & 3];
        }
    }

    if (opcode == 0x08) {
        if (closed_out) {
            *closed_out = true;
        }
        return -1;
    }
    if (opcode == 0x09) {
        (void)ws_send_pong(payload, plen);
        return (int)frame_len;
    }
    if (opcode == 0x0A) {
        return (int)frame_len;
    }
    if (opcode == 0x01 || opcode == 0x02 || opcode == 0x00) {
        if (plen > 0) {
            modulus_zig_serial_rx(payload, plen);
        }
        return (int)frame_len;
    }

    return (int)frame_len;
}

static bool ws_process_accumulator(bool *closed_out)
{
    size_t off = 0;
    while (off < s_ws_acc_len) {
        const int consumed =
            ws_consume_one(s_ws_acc + off, s_ws_acc_len - off, closed_out);
        if (consumed == 0) {
            break;
        }
        if (consumed < 0) {
            return false;
        }
        off += (size_t)consumed;
    }
    if (off > 0) {
        memmove(s_ws_acc, s_ws_acc + off, s_ws_acc_len - off);
        s_ws_acc_len -= off;
    }
    if (s_ws_acc_len >= WS_ACC_MAX) {
        ESP_LOGW(TAG, "WS accumulator full — resync");
        s_ws_acc_len = 0;
        return false;
    }
    return true;
}

static void ws_acc_reset(void)
{
    s_ws_acc_len = 0;
}

static int ws_build_data_frame(uint8_t *out, size_t out_max, const uint8_t *payload, size_t len)
{
    return ws_build_frame(out, out_max, payload, len, 0x01);
}

static bool ws_handshake(const char *host, uint16_t port, const char *path)
{
    char req[384];
    int n = snprintf(req, sizeof(req),
                     "GET %s HTTP/1.1\r\n"
                     "Host: %s:%u\r\n"
                     "Upgrade: websocket\r\n"
                     "Connection: Upgrade\r\n"
                     "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
                     "Sec-WebSocket-Version: 13\r\n"
                     "\r\n",
                     path, host, port);
    if (sock_send(req, (size_t)n) != n) {
        return false;
    }
    char resp[512];
    int rlen = sock_recv(resp, sizeof(resp) - 1);
    if (rlen <= 0) {
        return false;
    }
    resp[rlen] = '\0';
    return strstr(resp, "101") != NULL;
}

static int tcp_connect(const char *host, uint16_t port)
{
    struct addrinfo hints = {};
    struct addrinfo *res = NULL;
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    char port_str[8];
    snprintf(port_str, sizeof(port_str), "%u", port);
    if (getaddrinfo(host, port_str, &hints, &res) != 0 || !res) {
        return -1;
    }
    int sock = socket(res->ai_family, res->ai_socktype, 0);
    if (sock < 0) {
        freeaddrinfo(res);
        return -1;
    }
    struct timeval tv = {.tv_sec = 5, .tv_usec = 0};
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    if (connect(sock, res->ai_addr, res->ai_addrlen) != 0) {
        close(sock);
        freeaddrinfo(res);
        return -1;
    }
    freeaddrinfo(res);
    tv.tv_sec = 0;
    tv.tv_usec = 100000;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    return sock;
}

static void on_link_up(void)
{
    if (!s_connected) {
        s_connected = true;
        modulus_zig_transport_on_connect();
    }
}

static void on_link_down(void)
{
    if (s_connected) {
        s_connected = false;
        modulus_zig_transport_on_disconnect();
    }
}

static void rx_task(void *arg)
{
    (void)arg;
    uint8_t rxbuf[512];

    while (s_running) {
        while (s_running && !modulus_wireless_wifi_is_connected()) {
            vTaskDelay(pdMS_TO_TICKS(1000));
        }
        if (!s_running) {
            break;
        }

        if (s_mode == MODE_WS) {
            ws_acc_reset();
            ESP_LOGI(TAG, "WS connect ws%s://%s:%u%s", s_tls_on ? "s" : "", s_host, s_port, s_path);
            if (s_tls_on) {
                esp_tls_cfg_t cfg = {};
                cfg.timeout_ms = 5000;
                cfg.skip_common_name = true;
                s_tls = esp_tls_init();
                if (!s_tls ||
                    esp_tls_conn_new_sync(s_host, strlen(s_host), s_port, &cfg, s_tls) <= 0) {
                    if (s_tls) {
                        esp_tls_conn_destroy(s_tls);
                        s_tls = NULL;
                    }
                    vTaskDelay(pdMS_TO_TICKS(3000));
                    continue;
                }
                esp_tls_get_conn_sockfd(s_tls, &s_sock);
            } else {
                s_sock = tcp_connect(s_host, s_port);
                if (s_sock < 0) {
                    vTaskDelay(pdMS_TO_TICKS(3000));
                    continue;
                }
            }
            if (!ws_handshake(s_host, s_port, s_path)) {
                sock_close();
                vTaskDelay(pdMS_TO_TICKS(3000));
                continue;
            }
        } else {
            ESP_LOGI(TAG, "Telnet connect %s:%u", s_host, s_port);
            s_sock = tcp_connect(s_host, s_port);
            if (s_sock < 0) {
                vTaskDelay(pdMS_TO_TICKS(3000));
                continue;
            }
        }

        on_link_up();

        while (s_running && s_connected) {
            int len = sock_recv(rxbuf, sizeof(rxbuf));
            if (len > 0) {
                if (s_mode == MODE_WS) {
                    if (s_ws_acc_len + (size_t)len > WS_ACC_MAX) {
                        ESP_LOGW(TAG, "WS RX overflow — disconnect");
                        break;
                    }
                    memcpy(s_ws_acc + s_ws_acc_len, rxbuf, (size_t)len);
                    s_ws_acc_len += (size_t)len;
                    bool closed = false;
                    if (!ws_process_accumulator(&closed) || closed) {
                        break;
                    }
                } else {
                    modulus_zig_serial_rx(rxbuf, (size_t)len);
                }
            } else if (len == 0) {
                break;
            } else {
                int err = errno;
                if (err == EAGAIN || err == EWOULDBLOCK) {
                    continue;
                }
                break;
            }
        }

        on_link_down();
        sock_close();
        ws_acc_reset();
        if (!s_running) {
            break;
        }
        vTaskDelay(pdMS_TO_TICKS(3000));
    }

    /* Self-delete: never vTaskDelete from stop while holding TLS/socket I/O. */
    sock_close();
    ws_acc_reset();
    s_rx_task = NULL;
    vTaskDelete(NULL);
}

static bool tcp_start_common(tcp_mode_t mode, const char *host, uint16_t port)
{
    if (s_running) {
        if (s_mode == mode) {
            return true;
        }
        if (mode == MODE_WS) {
            modulus_ws_stop();
        } else {
            modulus_telnet_stop();
        }
    }
    strncpy(s_host, host ? host : "192.168.1.100", sizeof(s_host) - 1);
    s_port = port;
    s_mode = mode;
    s_running = true;
    if (s_rx_task == NULL) {
        TaskHandle_t handle = NULL;
        (void)xTaskCreatePinnedToCore(rx_task, "tcp_transport", 8192, NULL, 6, &handle, 1);
        s_rx_task = handle;
    }
    return true;
}

bool modulus_ws_start(const char *host, uint16_t port, const char *path, bool tls)
{
    if (path && path[0]) {
        strncpy(s_path, path, sizeof(s_path) - 1);
    } else {
        strncpy(s_path, "/", sizeof(s_path));
    }
    s_tls_on = tls;
    return tcp_start_common(MODE_WS, host, port);
}

void modulus_ws_stop(void)
{
    if (!s_running && s_rx_task == NULL) {
        s_mode = MODE_NONE;
        return;
    }
    s_running = false;
    on_link_down();
    sock_shutdown();
    join_rx_task();
    sock_close();
    ws_acc_reset();
    s_mode = MODE_NONE;
}

bool modulus_ws_send(const uint8_t *data, size_t len)
{
    if (!s_connected || !data || len == 0) {
        return false;
    }
    uint8_t frame[512];
    int flen = ws_build_data_frame(frame, sizeof(frame), data, len);
    if (flen <= 0) {
        return false;
    }
    return sock_send(frame, (size_t)flen) == flen;
}

bool modulus_ws_is_connected(void) { return s_connected; }

bool modulus_telnet_start(const char *host, uint16_t port)
{
    return tcp_start_common(MODE_TELNET, host, port);
}

void modulus_telnet_stop(void)
{
    modulus_ws_stop();
}

bool modulus_telnet_send(const uint8_t *data, size_t len)
{
    if (!s_connected || s_sock < 0 || !data || len == 0) {
        return false;
    }
    return send(s_sock, data, len, 0) == (int)len;
}

bool modulus_telnet_is_connected(void) { return s_connected && s_mode == MODE_TELNET; }
