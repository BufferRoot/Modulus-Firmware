#pragma once
/*
 * Material / job recipes — pendant defaults (not G-code).
 * NVS mat_rec = active index. Hardcoded Aluminum/Wood/Acrylic presets.
 */
#include <stdbool.h>
#include <stdint.h>

#define MODULUS_RECIPE_ALUMINUM 0
#define MODULUS_RECIPE_WOOD     1
#define MODULUS_RECIPE_ACRYLIC  2
#define MODULUS_RECIPE_COUNT    3

uint8_t modulus_recipe_get(void);
void modulus_recipe_set(uint8_t idx); /* persist + apply */
const char *modulus_recipe_name(uint8_t idx);
/* Apply active recipe: overrides, mist, Zigbee scene, clog baseline. */
void modulus_recipe_apply(void);
/* Expected vacuum draw (raw *0.1 W) for clog heuristic; 0 = use generic. */
int16_t modulus_recipe_clog_base_raw(void);
/* Soft warn before Cycle when NP-F estimate <20% (bat_warn NVS floor). */
bool modulus_recipe_battery_blocks_cycle(void);
const char *modulus_recipe_shift_text(void); /* "Shift ~2.5 h" / charging */
/* When CNC is ESP-NOW, optionally kill Wi-Fi (NVS shop_wifioff, default on). */
void modulus_recipe_maybe_wifi_off_for_espnow(void);
