/* Material recipes + shift/battery shop helpers. See shop_recipe.h. */
#include "shop_recipe.h"

#include "audio_shim.h"
#include "battery_shim.h"
#include "cnc_cmd_exports.h"
#include "nvs_shim.h"
#include "ui_shim.h"
#include "wireless_shim.h"
#include "zb_automation.h"

#include "esp_log.h"

#include <stdio.h>

static const char *TAG = "recipe";

typedef struct {
    const char *name;
    uint8_t feed_ovr;    /* % after reset-to-100 */
    uint8_t spindle_ovr;
    uint8_t scene;       /* MODULUS_ZB_SCENE_* */
    uint8_t mist;        /* 1 = ensure mist on */
    int16_t clog_raw;    /* ActivePower raw (W*10); clog if <30% of this */
} recipe_t;

static const recipe_t k_rec[MODULUS_RECIPE_COUNT] = {
    { "Aluminum", 90, 100, MODULUS_ZB_SCENE_CUT, 0, 800 },  /* ~80 W */
    { "Wood", 100, 100, MODULUS_ZB_SCENE_CUT, 0, 500 },     /* ~50 W */
    { "Acrylic", 80, 90, MODULUS_ZB_SCENE_CUT, 1, 400 },    /* ~40 W + mist */
};

static void bump_ovr(bool feed, uint8_t target)
{
    if (target < 10) {
        target = 10;
    }
    if (target > 200) {
        target = 200;
    }
    /* grblHAL realtime: 0 = reset to 100, then ±1/±10. */
    if (feed) {
        modulus_zig_cmd_feed_override(0);
    } else {
        modulus_zig_cmd_spindle_override(0);
    }
    int need = (int)target - 100;
    while (need >= 10) {
        if (feed) {
            modulus_zig_cmd_feed_override(10);
        } else {
            modulus_zig_cmd_spindle_override(10);
        }
        need -= 10;
    }
    while (need <= -10) {
        if (feed) {
            modulus_zig_cmd_feed_override(-10);
        } else {
            modulus_zig_cmd_spindle_override(-10);
        }
        need += 10;
    }
    while (need > 0) {
        if (feed) {
            modulus_zig_cmd_feed_override(1);
        } else {
            modulus_zig_cmd_spindle_override(1);
        }
        need--;
    }
    while (need < 0) {
        if (feed) {
            modulus_zig_cmd_feed_override(-1);
        } else {
            modulus_zig_cmd_spindle_override(-1);
        }
        need++;
    }
}

static void ensure_mist(bool want_on)
{
    modulus_cnc_status_t st = {};
    modulus_zig_fill_cnc_status(&st);
    const bool mist_on = (st.accessories & (1u << 2)) != 0; /* k_acc_mist */
    if (want_on == mist_on) {
        return;
    }
    modulus_zig_cmd_mist_toggle();
}

uint8_t modulus_recipe_get(void)
{
    uint8_t v = modulus_nvs_get_u8("mat_rec", MODULUS_RECIPE_WOOD);
    return v < MODULUS_RECIPE_COUNT ? v : MODULUS_RECIPE_WOOD;
}

const char *modulus_recipe_name(uint8_t idx)
{
    if (idx >= MODULUS_RECIPE_COUNT) {
        return "Wood";
    }
    return k_rec[idx].name;
}

int16_t modulus_recipe_clog_base_raw(void)
{
    return k_rec[modulus_recipe_get()].clog_raw;
}

void modulus_recipe_maybe_wifi_off_for_espnow(void)
{
    if (modulus_nvs_get_u8("shop_wifioff", 1) == 0) {
        return;
    }
    /* cnc_conn 0 = ESP-NOW */
    if (modulus_nvs_get_u8("cnc_conn", 4) != 0) {
        return;
    }
    if (modulus_wireless_wifi_is_enabled()) {
        ESP_LOGI(TAG, "Wi-Fi off (CNC is ESP-NOW)");
        modulus_wireless_wifi_disable();
    }
}

void modulus_recipe_apply(void)
{
    const recipe_t *r = &k_rec[modulus_recipe_get()];
    bump_ovr(true, r->feed_ovr);
    bump_ovr(false, r->spindle_ovr);
    ensure_mist(r->mist != 0);
    modulus_zb_scene_apply(r->scene);
    modulus_recipe_maybe_wifi_off_for_espnow();
    ESP_LOGI(TAG, "applied %s feed=%u spind=%u mist=%u", r->name, (unsigned)r->feed_ovr,
             (unsigned)r->spindle_ovr, (unsigned)r->mist);
}

void modulus_recipe_set(uint8_t idx)
{
    if (idx >= MODULUS_RECIPE_COUNT) {
        idx = MODULUS_RECIPE_WOOD;
    }
    modulus_nvs_set_u8("mat_rec", idx);
    modulus_recipe_apply();
    modulus_audio_play_ui(MODULUS_UI_SOUND_POP);
}

bool modulus_recipe_battery_blocks_cycle(void)
{
    modulus_battery_status_t b = {};
    if (!modulus_battery_get_status(&b)) {
        return false;
    }
    if (b.charge_state != 0) { /* charging / full — don't block */
        return false;
    }
    const uint8_t floor = modulus_nvs_get_u8("bat_warn", 20);
    return b.percent > 0 && b.percent < floor;
}

const char *modulus_recipe_shift_text(void)
{
    static char buf[40];
    modulus_battery_status_t b = {};
    if (!modulus_battery_get_status(&b)) {
        return "Battery --";
    }
    if (b.charge_state != 0) {
        if (b.time_to_full > 0) {
            snprintf(buf, sizeof(buf), "Charge %u%% (~%ld m)", (unsigned)b.percent,
                     (long)(b.time_to_full / 60));
        } else {
            snprintf(buf, sizeof(buf), "Charge %u%%", (unsigned)b.percent);
        }
        return buf;
    }
    if (b.time_to_empty > 0) {
        const long min = b.time_to_empty / 60;
        if (min >= 60) {
            snprintf(buf, sizeof(buf), "Shift ~%ld.%ld h (%u%%)", min / 60, (min % 60) / 6,
                     (unsigned)b.percent);
        } else {
            snprintf(buf, sizeof(buf), "Shift ~%ld m (%u%%)", min, (unsigned)b.percent);
        }
    } else {
        snprintf(buf, sizeof(buf), "Pack %u%%", (unsigned)b.percent);
    }
    return buf;
}
