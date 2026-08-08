#pragma once
/*
 * ZBOSS Zigbee 3.0 coordinator hub on the NanoH2 (ESP32-H2, dedicated
 * 802.15.4 radio — no Wi-Fi silicon, no coexistence).
 * Ported from firmware/tab5-c6/main/zigbee_handler.c (PATH C) with all
 * coex / ESP-NOW channel-arbitration code removed: it existed only because
 * the C6 shared one radio between Wi-Fi and 802.15.4.
 */
#include <stdbool.h>
#include <stdint.h>

/* Start the ZBOSS coordinator task (idempotent). channel 11-26 forces that
 * channel; 0 = energy-scan pick on factory-new form. */
void zigbee_hub_start(uint8_t channel);

/* Process one host command: payload = [seq:1][cmd:1][args...]. */
void zigbee_hub_process_cmd(const uint8_t *payload, uint16_t len);

/* True once the network is formed (drives the status LED). */
bool zigbee_hub_formed(void);

/* Call ~every 100 ms from main — pushes HUB_STATE heartbeat when formed. */
void zigbee_hub_poll(void);
