/*
 * Thread handler for ESP-Hosted slave (C6)
 * Bridges Thread (OpenThread FTD) operations between the P4 host and the C6's
 * native 802.15.4 radio via the ESP_THREAD_IF SDIO channel.
 */
#include "sdkconfig.h"
#include "thread_handler.h"

#if CONFIG_OPENTHREAD_ENABLED

#include "esp_log.h"
#include "esp_event.h"
#include "esp_openthread.h"
#include "esp_openthread_lock.h"
#include "esp_openthread_types.h"
#include "esp_vfs_eventfd.h"
#include "esp_hosted_interface.h"
#include "esp_hosted_header.h"
#include "interface.h"
#include "openthread/thread.h"
#include "openthread/udp.h"
#include "openthread/ip6.h"
#include "openthread/dataset_ftd.h"
#include "openthread/coap.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "esp_heap_caps.h"
#include <string.h>
#include <stdlib.h>

static const char *TAG = "thread_hdl";

/* Forward declaration – defined in app_main.c */
extern int send_to_host_queue(interface_buffer_handle_t *buf_handle, uint8_t queue_type);

/* ── State ──────────────────────────────────────────────────────────────── */
static bool              s_ot_inited        = false;
static bool              s_ot_networking     = false;  /* Thread networking active (radio in use) */
static bool              s_eventfd_done     = false;
static otUdpSocket       s_udp_socket;
static bool              s_udp_open         = false;
static TaskHandle_t      s_ot_task          = NULL;

/* ── Helper: send an event frame to the P4 host ─────────────────────────── */
static void send_evt_to_host(uint8_t evt, const uint8_t *data, uint16_t data_len)
{
    uint16_t total = 1 + data_len;
    uint8_t *buf = (uint8_t *)malloc(total);
    if (!buf) {
        ESP_LOGE(TAG, "malloc failed for evt 0x%02x", evt);
        return;
    }
    buf[0] = evt;
    if (data && data_len)
        memcpy(buf + 1, data, data_len);

    interface_buffer_handle_t bh = {0};
    bh.if_type            = ESP_THREAD_IF;
    bh.if_num             = 0;
    bh.payload            = buf;
    bh.payload_len        = total;
    bh.priv_buffer_handle = buf;
    bh.free_buf_handle    = free;

    if (send_to_host_queue(&bh, PRIO_Q_OTHERS) != 0) {
        ESP_LOGE(TAG, "Failed to queue thread evt 0x%02x", evt);
        free(buf);
    }
}

/* ── Build and send a STATE event from the current OT instance ──────────── */
static void send_state_event(otInstance *inst)
{
    otDeviceRole role = otThreadGetDeviceRole(inst);

    /* Get mesh-local IPv6 address */
    const otIp6Address      *rloc = otThreadGetRloc(inst);
    uint8_t ip6[16] = {0};
    if (rloc) {
        memcpy(ip6, rloc->mFields.m8, 16);
    }

    uint8_t payload[20];
    payload[0] = (uint8_t)role;
    payload[1] = otLinkGetChannel(inst);
    uint16_t panid = otLinkGetPanId(inst);
    payload[2] = (panid >> 8) & 0xFF;
    payload[3] = panid & 0xFF;
    memcpy(payload + 4, ip6, 16);

    send_evt_to_host(THREAD_EVT_STATE, payload, sizeof(payload));
}

/* ── UDP receive callback ────────────────────────────────────────────────── */
static void udp_recv_cb(void *ctx, otMessage *msg, const otMessageInfo *msg_info)
{
    if (!msg || !msg_info) return;

    uint16_t len = otMessageGetLength(msg) - otMessageGetOffset(msg);
    if (len == 0 || len > 512) return;

    /* EVT_UDP_RECV: [src_ip6:16][port:2][data:N] */
    uint16_t payload_len = 16 + 2 + len;
    uint8_t *payload = (uint8_t *)malloc(payload_len);
    if (!payload) return;

    memcpy(payload, msg_info->mSockAddr.mFields.m8, 16);
    payload[16] = (msg_info->mPeerPort >> 8) & 0xFF;
    payload[17] = msg_info->mPeerPort & 0xFF;
    otMessageRead(msg, otMessageGetOffset(msg), payload + 18, len);

    send_evt_to_host(THREAD_EVT_UDP_RECV, payload, payload_len);
    free(payload);
}

/* ── OpenThread event handler ────────────────────────────────────────────── */
static void ot_event_handler(void *ctx, esp_event_base_t base,
                              int32_t id, void *data)
{
    otInstance *inst = esp_openthread_get_instance();
    if (!inst) return;

    switch ((esp_openthread_event_t)id) {
    case OPENTHREAD_EVENT_ATTACHED:
    case OPENTHREAD_EVENT_ROLE_CHANGED:
        ESP_LOGI(TAG, "Thread role changed → %d", (int)otThreadGetDeviceRole(inst));
        send_state_event(inst);
        /* Open UDP socket if not already open */
        if (!s_udp_open) {
            otSockAddr addr = {0};
            addr.mPort = 1234;  /* default listen port */
            if (otUdpOpen(inst, &s_udp_socket, udp_recv_cb, NULL) == OT_ERROR_NONE &&
                otUdpBind(inst, &s_udp_socket, &addr, OT_NETIF_THREAD_HOST) == OT_ERROR_NONE) {
                s_udp_open = true;
                ESP_LOGI(TAG, "UDP socket opened on port 1234");
            }
        }
        break;
    case OPENTHREAD_EVENT_DETACHED:
        ESP_LOGI(TAG, "Thread detached");
        send_state_event(inst);
        break;
    case OPENTHREAD_EVENT_STOP:
        ESP_LOGI(TAG, "Thread stopped");
        s_udp_open = false;
        break;
    default:
        break;
    }
}

/* ── OpenThread main loop task ───────────────────────────────────────────── */
static void ot_main_task(void *arg)
{
    esp_openthread_platform_config_t cfg = {
        .radio_config = {
            .radio_mode = RADIO_MODE_NATIVE,
        },
        .host_config = {
            .host_connection_mode = HOST_CONNECTION_MODE_NONE,
        },
        .port_config = {
            .storage_partition_name = "nvs",
            .netif_queue_size      = 10,
            .task_queue_size        = 10,
        },
    };

    ESP_LOGI(TAG, "Free heap before OT init: %lu",
             (unsigned long)heap_caps_get_free_size(MALLOC_CAP_DEFAULT));

    esp_err_t err = esp_openthread_init(&cfg);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "esp_openthread_init failed: 0x%x (%d)", err, err);
        uint8_t payload[6];
        payload[0] = 0x02;  /* reason: OT init failed */
        payload[1] = (uint8_t)(err & 0xFF);
        uint32_t free_heap = heap_caps_get_free_size(MALLOC_CAP_DEFAULT);
        memcpy(payload + 2, &free_heap, sizeof(free_heap)); /* LE */
        send_evt_to_host(THREAD_EVT_FAIL, payload, sizeof(payload));
        /* Try to clean up partially-initialized platform */
        esp_openthread_deinit();
        s_ot_task = NULL;
        vTaskDelete(NULL);
        return;
    }

    /* Register for role-change events */
    esp_event_handler_register(OPENTHREAD_EVENT, ESP_EVENT_ANY_ID,
                                ot_event_handler, NULL);

    /* Auto-form/join network using Kconfig defaults (lock required) */
    esp_openthread_lock_acquire(portMAX_DELAY);
    err = esp_openthread_auto_start(NULL);
    esp_openthread_lock_release();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "esp_openthread_auto_start: %d", err);
        /* not fatal — network may form after mainloop starts */
    }

    s_ot_inited = true;
    s_ot_networking = true;
    ESP_LOGI(TAG, "OpenThread FTD started");
    send_evt_to_host(THREAD_EVT_OK, NULL, 0);

    /* Block on the OpenThread main event loop */
    err = esp_openthread_launch_mainloop();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "OpenThread mainloop exited: %d", err);
    }
    s_ot_inited = false;
    s_ot_task = NULL;
    vTaskDelete(NULL);
}

/* ── Command handlers (called from app_main.c / process_rx_pkt) ─────────── */
static void cmd_enable(void)
{
    if (s_ot_inited) {
        /* OT platform is alive — just (re-)enable Thread networking */
        otInstance *inst = esp_openthread_get_instance();
        if (inst) {
            esp_openthread_lock_acquire(portMAX_DELAY);
            otThreadSetEnabled(inst, true);
            esp_openthread_lock_release();
        }
        s_ot_networking = true;
        ESP_LOGI(TAG, "Thread networking re-enabled");
        send_evt_to_host(THREAD_EVT_OK, NULL, 0);
        return;
    }

    /* Register eventfd — required by OpenThread's internal event system */
    if (!s_eventfd_done) {
        esp_vfs_eventfd_config_t eventfd_config = {
            .max_fds = 4,
        };
        esp_err_t efd_err = esp_vfs_eventfd_register(&eventfd_config);
        if (efd_err == ESP_OK) {
            s_eventfd_done = true;
        } else {
            ESP_LOGW(TAG, "eventfd_register: 0x%x (may be OK if already done)", efd_err);
            if (efd_err == ESP_ERR_INVALID_STATE) {
                s_eventfd_done = true;  /* already registered */
            }
        }
    }

    uint32_t free_heap = heap_caps_get_free_size(MALLOC_CAP_DEFAULT);
    ESP_LOGI(TAG, "Free heap before task create: %lu", (unsigned long)free_heap);

    /* Create OT worker task — init, auto_start, and mainloop all run inside */
    if (xTaskCreate(ot_main_task, "ot_mainloop", 8192, NULL, 5, &s_ot_task) != pdPASS) {
        ESP_LOGE(TAG, "Failed to create OT task (heap=%lu)", (unsigned long)free_heap);
        uint8_t payload[5];
        payload[0] = 0x01;  /* reason: task create failed */
        memcpy(payload + 1, &free_heap, 4);
        send_evt_to_host(THREAD_EVT_FAIL, payload, sizeof(payload));
        return;
    }
    /* Response (THREAD_EVT_OK or THREAD_EVT_FAIL) sent from within ot_main_task */
}

static void cmd_disable(void)
{
    if (!s_ot_inited) {
        send_evt_to_host(THREAD_EVT_OK, NULL, 0);
        return;
    }

    otInstance *inst = esp_openthread_get_instance();
    if (inst) {
        esp_openthread_lock_acquire(portMAX_DELAY);
        if (s_udp_open) {
            otUdpClose(inst, &s_udp_socket);
            s_udp_open = false;
        }
        otThreadSetEnabled(inst, false);
        esp_openthread_lock_release();
    }

    s_ot_networking = false;
    /* Keep OT platform + mainloop task alive for fast, safe re-enable.
     * The 802.15.4 radio is idle — Zigbee raw mode can now use it. */
    ESP_LOGI(TAG, "Thread networking disabled (OT platform kept alive)");
    send_evt_to_host(THREAD_EVT_OK, NULL, 0);
}

static void cmd_get_state(void)
{
    otInstance *inst = esp_openthread_get_instance();
    if (!inst || !s_ot_inited) {
        uint8_t role = 0;
        uint8_t payload[20] = {0};
        payload[0] = role;
        send_evt_to_host(THREAD_EVT_STATE, payload, sizeof(payload));
        return;
    }
    esp_openthread_lock_acquire(portMAX_DELAY);
    send_state_event(inst);
    esp_openthread_lock_release();
}

static void cmd_send_udp(const uint8_t *payload, uint16_t len)
{
    /* [dst_ip6:16][port:2][data:N] */
    if (!s_ot_inited || !s_udp_open || len < 19) {
        send_evt_to_host(THREAD_EVT_FAIL, (const uint8_t*)"\x01", 1);
        return;
    }

    otInstance *inst = esp_openthread_get_instance();
    if (!inst) return;

    otIp6Address dst_addr;
    memcpy(dst_addr.mFields.m8, payload, 16);
    uint16_t port = ((uint16_t)payload[16] << 8) | payload[17];
    const uint8_t *data  = payload + 18;
    uint16_t data_len    = len - 18;

    esp_openthread_lock_acquire(portMAX_DELAY);

    otMessage *msg = otUdpNewMessage(inst, NULL);
    if (!msg) {
        esp_openthread_lock_release();
        send_evt_to_host(THREAD_EVT_FAIL, (const uint8_t*)"\x02", 1);
        return;
    }

    otError err = otMessageAppend(msg, data, data_len);
    if (err != OT_ERROR_NONE) {
        otMessageFree(msg);
        esp_openthread_lock_release();
        send_evt_to_host(THREAD_EVT_FAIL, (const uint8_t*)"\x03", 1);
        return;
    }

    otMessageInfo mi = {0};
    memcpy(mi.mPeerAddr.mFields.m8, dst_addr.mFields.m8, 16);
    mi.mPeerPort = port;

    err = otUdpSend(inst, &s_udp_socket, msg, &mi);
    esp_openthread_lock_release();

    if (err == OT_ERROR_NONE) {
        send_evt_to_host(THREAD_EVT_OK, NULL, 0);
    } else {
        ESP_LOGW(TAG, "udp_send error %d", err);
        send_evt_to_host(THREAD_EVT_FAIL, (const uint8_t*)"\x04", 1);
    }
}

static void cmd_set_channel(const uint8_t *payload, uint16_t len)
{
    if (len < 1) return;
    uint8_t ch = payload[0];
    if (ch < 11 || ch > 26) {
        send_evt_to_host(THREAD_EVT_FAIL, (const uint8_t*)"\x10", 1);
        return;
    }

    if (!s_ot_inited) {
        send_evt_to_host(THREAD_EVT_FAIL, (const uint8_t*)"\x11", 1);
        return;
    }

    otInstance *inst = esp_openthread_get_instance();
    esp_openthread_lock_acquire(portMAX_DELAY);
    otError err = otLinkSetChannel(inst, ch);
    esp_openthread_lock_release();

    if (err == OT_ERROR_NONE) {
        ESP_LOGI(TAG, "Channel set to %d", ch);
        send_evt_to_host(THREAD_EVT_OK, NULL, 0);
    } else {
        send_evt_to_host(THREAD_EVT_FAIL, (const uint8_t*)"\x12", 1);
    }
}

static void cmd_set_panid(const uint8_t *payload, uint16_t len)
{
    if (len < 2) return;
    uint16_t panid = ((uint16_t)payload[0] << 8) | payload[1];

    if (!s_ot_inited) {
        send_evt_to_host(THREAD_EVT_FAIL, (const uint8_t*)"\x20", 1);
        return;
    }

    otInstance *inst = esp_openthread_get_instance();
    esp_openthread_lock_acquire(portMAX_DELAY);
    otError err = otLinkSetPanId(inst, panid);
    esp_openthread_lock_release();

    if (err == OT_ERROR_NONE) {
        ESP_LOGI(TAG, "PAN ID set to 0x%04x", panid);
        send_evt_to_host(THREAD_EVT_OK, NULL, 0);
    } else {
        send_evt_to_host(THREAD_EVT_FAIL, (const uint8_t*)"\x21", 1);
    }
}

/* ── Public entry point ──────────────────────────────────────────────────── */
void thread_process_host_cmd(const uint8_t *payload, uint16_t len)
{
    if (!payload || len < 1) return;

    uint8_t cmd       = payload[0];
    const uint8_t *args = payload + 1;
    uint16_t args_len   = len  - 1;

    switch (cmd) {
    case THREAD_CMD_ENABLE:      cmd_enable();                       break;
    case THREAD_CMD_DISABLE:     cmd_disable();                      break;
    case THREAD_CMD_GET_STATE:   cmd_get_state();                    break;
    case THREAD_CMD_SEND_UDP:    cmd_send_udp(args, args_len);       break;
    case THREAD_CMD_SET_CHANNEL: cmd_set_channel(args, args_len);    break;
    case THREAD_CMD_SET_PANID:   cmd_set_panid(args, args_len);      break;
    default:
        ESP_LOGW(TAG, "Unknown Thread cmd: 0x%02x", cmd);
        break;
    }
}

bool thread_is_networking(void)
{
    return s_ot_networking;
}

#else /* !CONFIG_OPENTHREAD_ENABLED */

#include "esp_log.h"
#include "esp_hosted_interface.h"
#include "esp_hosted_header.h"
#include "interface.h"
#include <stdlib.h>

static const char *TAG_STUB = "thread_hdl";

extern int send_to_host_queue(interface_buffer_handle_t *buf_handle, uint8_t queue_type);

void thread_process_host_cmd(const uint8_t *payload, uint16_t len)
{
    /* OpenThread disabled in sdkconfig — send FAIL so P4 does not time out */
    (void)payload; (void)len;
    ESP_LOGW(TAG_STUB, "Thread cmd received but OpenThread not compiled in");
    uint16_t total = 2;
    uint8_t *buf = (uint8_t *)malloc(total);
    if (!buf) return;
    buf[0] = 0x82;  /* THREAD_EVT_FAIL */
    buf[1] = 0xFF;  /* reason: not compiled */

    interface_buffer_handle_t bh = {0};
    bh.if_type            = ESP_THREAD_IF;
    bh.if_num             = 0;
    bh.payload            = buf;
    bh.payload_len        = total;
    bh.priv_buffer_handle = buf;
    bh.free_buf_handle    = free;
    if (send_to_host_queue(&bh, PRIO_Q_OTHERS) != 0) {
        free(buf);
    }
}

bool thread_is_networking(void)
{
    return false;  /* OpenThread not compiled in */
}

#endif /* CONFIG_OPENTHREAD_ENABLED */
