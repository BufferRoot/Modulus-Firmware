/*
 * Phase 11 — Thread (802.15.4) on C6 via esp_openthread native radio.
 * Milestone: stack init, network name "Modulus", detached (no attach/join).
 * Wi-Fi must be up first (esp_hosted RPC) for RF coex — poll like ESP-NOW.
 * Coex: CONFIG_ESP_COEX_SW_COEXIST_ENABLE (esp_hosted slave default).
 */
#include "modulus_c6_thread.h"

#include "esp_log.h"
#include "esp_wifi.h"
#include "sdkconfig.h"

#if CONFIG_MODULUS_C6_THREAD && CONFIG_OPENTHREAD_ENABLED
#include "esp_openthread.h"
#include "esp_openthread_lock.h"
#include "esp_openthread_netif_glue.h"
#include "esp_openthread_types.h"
#include "esp_vfs_eventfd.h"
#include "openthread/instance.h"
#include "openthread/thread.h"

#if SOC_IEEE802154_SUPPORTED
#define MODULUS_OT_DEFAULT_RADIO_CONFIG() \
    { .radio_mode = RADIO_MODE_NATIVE }
#else
#define MODULUS_OT_DEFAULT_RADIO_CONFIG() \
    { .radio_mode = RADIO_MODE_UART_RCP, \
      .radio_uart_config = { .port = 1, .uart_config = { .baud_rate = 115200 }, .rx_pin = 4, .tx_pin = 5 } }
#endif

#define MODULUS_OT_DEFAULT_HOST_CONFIG() \
    { .host_connection_mode = HOST_CONNECTION_MODE_NONE }

#define MODULUS_OT_DEFAULT_PORT_CONFIG() \
    { .storage_partition_name = "nvs", .netif_queue_size = 10, .task_queue_size = 10 }

#define MODULUS_THREAD_NETWORK_NAME "Modulus"
#endif

static const char *TAG = "modulus_c6_thread";

static bool s_init_attempted;
static uint8_t s_status; /* 0 off/deferred, 1 ready, 2 error */

#if CONFIG_MODULUS_C6_THREAD && CONFIG_OPENTHREAD_ENABLED
static bool s_stack_started;
static bool s_eventfd_registered;

static bool modulus_c6_thread_wifi_up(void)
{
    wifi_mode_t mode = WIFI_MODE_NULL;
    if (esp_wifi_get_mode(&mode) != ESP_OK) {
        return false;
    }
    return mode != WIFI_MODE_NULL;
}

static const char *modulus_c6_thread_role_str(otDeviceRole role)
{
    switch (role) {
    case OT_DEVICE_ROLE_DISABLED:
        return "disabled";
    case OT_DEVICE_ROLE_DETACHED:
        return "detached";
    case OT_DEVICE_ROLE_CHILD:
        return "child";
    case OT_DEVICE_ROLE_ROUTER:
        return "router";
    case OT_DEVICE_ROLE_LEADER:
        return "leader";
    default:
        return "unknown";
    }
}

static esp_err_t modulus_c6_thread_register_eventfd(void)
{
    if (s_eventfd_registered) {
        return ESP_OK;
    }
    esp_vfs_eventfd_config_t eventfd_config = {
        .max_fds = 3,
    };
    esp_err_t err = esp_vfs_eventfd_register(&eventfd_config);
    if (err == ESP_OK || err == ESP_ERR_INVALID_STATE) {
        s_eventfd_registered = true;
        return ESP_OK;
    }
    return err;
}

static void modulus_c6_thread_mark_error(const char *step, esp_err_t err)
{
    ESP_LOGE(TAG, "%s failed: %s", step, esp_err_to_name(err));
    s_status = 2;
}

static void modulus_c6_thread_apply_network_name(otInstance *instance)
{
    otError ot_err = otThreadSetNetworkName(instance, MODULUS_THREAD_NETWORK_NAME);
    if (ot_err != OT_ERROR_NONE) {
        ESP_LOGW(TAG, "otThreadSetNetworkName failed: %d", (int)ot_err);
    }
}

static void modulus_c6_thread_log_state(otInstance *instance)
{
    const char *name = otThreadGetNetworkName(instance);
    otDeviceRole role = otThreadGetDeviceRole(instance);
    ESP_LOGI(TAG,
             "Thread stack OK; network \"%s\"; role %s; attach disabled (802.15.4 coex w/ Wi-Fi+BLE)",
             (name != NULL && name[0] != '\0') ? name : MODULUS_THREAD_NETWORK_NAME,
             modulus_c6_thread_role_str(role));
}

static void modulus_c6_thread_do_init(void)
{
    if (s_stack_started || s_status == 2) {
        return;
    }
    if (!modulus_c6_thread_wifi_up()) {
        return;
    }

    esp_err_t err = modulus_c6_thread_register_eventfd();
    if (err != ESP_OK) {
        modulus_c6_thread_mark_error("eventfd register", err);
        return;
    }

    static esp_openthread_config_t config = {
#if CONFIG_OPENTHREAD_PLATFORM_NETIF
        .netif_config = ESP_NETIF_DEFAULT_OPENTHREAD(),
#endif
        .platform_config = {
            .radio_config = MODULUS_OT_DEFAULT_RADIO_CONFIG(),
            .host_config = MODULUS_OT_DEFAULT_HOST_CONFIG(),
            .port_config = MODULUS_OT_DEFAULT_PORT_CONFIG(),
        },
    };

    err = esp_openthread_start(&config);
    if (err != ESP_OK) {
        modulus_c6_thread_mark_error("esp_openthread_start", err);
        return;
    }

    s_stack_started = true;

    esp_openthread_lock_acquire(portMAX_DELAY);
    otInstance *instance = esp_openthread_get_instance();
    if (instance != NULL) {
        modulus_c6_thread_apply_network_name(instance);
        modulus_c6_thread_log_state(instance);
    } else {
        ESP_LOGW(TAG, "OpenThread instance NULL after start");
    }
    esp_openthread_lock_release();

    s_status = 1;
    ESP_LOGI(TAG, "802.15.4 radio ready (native); no Thread attach");
}
#endif

void modulus_c6_thread_init(void)
{
    if (s_init_attempted) {
        return;
    }
    s_init_attempted = true;

#if !CONFIG_MODULUS_C6_THREAD
    ESP_LOGI(TAG, "Thread disabled (CONFIG_MODULUS_C6_THREAD=n)");
    return;
#elif !CONFIG_OPENTHREAD_ENABLED
    ESP_LOGI(TAG, "Thread unavailable (CONFIG_OPENTHREAD_ENABLED=n)");
    return;
#else
    modulus_c6_thread_do_init();
#endif
}

void modulus_c6_thread_poll(void)
{
#if CONFIG_MODULUS_C6_THREAD && CONFIG_OPENTHREAD_ENABLED
    if (s_status != 1) {
        modulus_c6_thread_do_init();
    }
#endif
}

bool modulus_c6_thread_ready(void)
{
#if CONFIG_MODULUS_C6_THREAD && CONFIG_OPENTHREAD_ENABLED
    return s_status == 1;
#else
    return false;
#endif
}

uint8_t modulus_c6_thread_status(void)
{
    return s_status;
}

esp_err_t modulus_c6_thread_request_attach(void)
{
#if !CONFIG_MODULUS_C6_THREAD || !CONFIG_OPENTHREAD_ENABLED
    ESP_LOGW(TAG, "attach unavailable (Thread disabled)");
    return ESP_ERR_INVALID_STATE;
#else
    ESP_LOGW(TAG, "border-router attach not implemented (MTD detached; 8c coex policy)");
    return ESP_ERR_NOT_SUPPORTED;
#endif
}
