/*
 * Zigbee stub (C6 autonomous component).
 *
 * Zigbee moved to the dedicated NanoH2 (ESP32-H2) reached over UART from the
 * P4. The C6 no longer runs any 802.15.4 stack, so this component is inert —
 * kept only so existing init/poll call sites in the C6 runtime link cleanly.
 */
#include "modulus_c6_zigbee.h"

#include "esp_log.h"

static const char *TAG = "modulus_c6_zigbee";

void modulus_c6_zigbee_init(void)
{
    ESP_LOGI(TAG, "Zigbee not on C6 (runs on NanoH2 ESP32-H2 over UART)");
}

void modulus_c6_zigbee_poll(void)
{
}

bool modulus_c6_zigbee_ready(void)
{
    return false;
}

uint8_t modulus_c6_zigbee_status(void)
{
    return 0; /* off/not-present */
}
