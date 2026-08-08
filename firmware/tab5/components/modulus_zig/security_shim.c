#include "security_shim.h"
#include "display_shim.h"
#include "nvs_shim.h"
#include "event_shim.h"

#include <esp_log.h>
#include <esp_timer.h>
#include <psa/crypto.h>
#include <stdio.h>
#include <string.h>

static const char *TAG = "modulus_security";

static bool s_locked = false;
static char s_pin_hash[65] = {};
static bool s_psa_ready = false;

/* L2: PIN brute-force throttle. The fail count is persisted so a power-cycle
 * cannot reset it, and the lockout window is re-armed from the persisted count
 * at init, so rebooting does not bypass an active lockout. */
#define PIN_FAIL_THRESHOLD 5
static uint8_t s_fail_count = 0;
static int64_t s_lockout_until_us = 0;

static uint32_t pin_lockout_seconds(uint8_t fails)
{
    if (fails < PIN_FAIL_THRESHOLD) {
        return 0;
    }
    uint32_t over = (uint32_t)(fails - PIN_FAIL_THRESHOLD);
    if (over > 5) {
        over = 5;
    }
    return 30u << over; /* 30, 60, 120, 240, 480, 960 s (capped) */
}

static void ensure_psa(void)
{
    if (!s_psa_ready) {
        psa_crypto_init();
        s_psa_ready = true;
    }
}

static bool sha256_hex(const char *input, char out[65])
{
    if (!input) {
        return false;
    }
    ensure_psa();
    uint8_t digest[32] = {};
    size_t digest_len = 0;
    const psa_status_t st = psa_hash_compute(
        PSA_ALG_SHA_256,
        (const uint8_t *)input,
        strlen(input),
        digest,
        sizeof(digest),
        &digest_len);
    if (st != PSA_SUCCESS || digest_len != 32) {
        return false;
    }
    for (size_t i = 0; i < 32; i++) {
        snprintf(&out[i * 2], 3, "%02x", digest[i]);
    }
    out[64] = '\0';
    return true;
}

void modulus_security_init(void)
{
    s_pin_hash[0] = '\0';
    char buf[65] = {};
    if (modulus_nvs_get_str("pin_hash", buf, sizeof(buf))) {
        memcpy(s_pin_hash, buf, sizeof(s_pin_hash));
    }

    s_fail_count = modulus_nvs_get_u8("pin_fails", 0);
    if (s_fail_count >= PIN_FAIL_THRESHOLD) {
        s_lockout_until_us = esp_timer_get_time() +
                             (int64_t)pin_lockout_seconds(s_fail_count) * 1000000LL;
    }

    if (modulus_security_has_pin() && modulus_security_lock_on_boot()) {
        s_locked = true;
        ESP_LOGI(TAG, "Boot lock active");
    }
    ESP_LOGI(TAG, "Security init (PIN %s)", modulus_security_has_pin() ? "set" : "none");
    /* display_init runs before security_init; re-arm idle-lock timer once PIN state is loaded. */
    modulus_display_refresh_activity_monitor();
}

bool modulus_security_has_pin(void)
{
    return s_pin_hash[0] != '\0';
}

bool modulus_security_lock_on_boot(void)
{
    return modulus_nvs_get_u8("pin_boot", 0) != 0;
}

bool modulus_security_lock_on_sleep(void)
{
    return modulus_nvs_get_u8("pin_slp", 0) != 0;
}

uint16_t modulus_security_lock_timeout(void)
{
    return modulus_nvs_get_u16("pin_tmo", 0);
}

bool modulus_security_is_locked(void)
{
    return s_locked;
}

void modulus_security_lock(void)
{
    if (modulus_security_has_pin()) {
        s_locked = true;
        ESP_LOGI(TAG, "Device locked");
    }
}

void modulus_security_unlock(void)
{
    s_locked = false;
    ESP_LOGI(TAG, "Device unlocked");
}

bool modulus_security_verify_pin(const char *pin)
{
    if (!modulus_security_has_pin() || !pin) {
        return false;
    }
    /* L2: reject during an active lockout window without even hashing. */
    if (s_lockout_until_us > 0 && esp_timer_get_time() < s_lockout_until_us) {
        ESP_LOGW(TAG, "PIN entry locked out");
        return false;
    }
    char hex[65] = {};
    if (!sha256_hex(pin, hex)) {
        return false;
    }
    if (strcmp(hex, s_pin_hash) == 0) {
        if (s_fail_count != 0) {
            s_fail_count = 0;
            modulus_nvs_set_u8("pin_fails", 0);
        }
        s_lockout_until_us = 0;
        return true;
    }
    if (s_fail_count < 255) {
        s_fail_count++;
    }
    modulus_nvs_set_u8("pin_fails", s_fail_count);
    const uint32_t secs = pin_lockout_seconds(s_fail_count);
    if (secs > 0) {
        s_lockout_until_us = esp_timer_get_time() + (int64_t)secs * 1000000LL;
        ESP_LOGW(TAG, "PIN lockout %u s (%u fails)", (unsigned)secs, (unsigned)s_fail_count);
    }
    return false;
}

static bool is_valid_pin(const char *pin)
{
    if (!pin) {
        return false;
    }
    const size_t len = strlen(pin);
    if (len < 4 || len > 8) {
        return false;
    }
    for (size_t i = 0; i < len; i++) {
        if (pin[i] < '0' || pin[i] > '9') {
            return false;
        }
    }
    return true;
}

bool modulus_security_set_pin(const char *pin)
{
    if (!is_valid_pin(pin)) {
        return false;
    }
    char hex[65] = {};
    if (!sha256_hex(pin, hex)) {
        return false;
    }
    memcpy(s_pin_hash, hex, sizeof(s_pin_hash));
    modulus_nvs_set_str("pin_hash", hex);
    s_fail_count = 0;
    s_lockout_until_us = 0;
    modulus_nvs_set_u8("pin_fails", 0);
    ESP_LOGI(TAG, "PIN set");
    return true;
}

bool modulus_security_clear_pin(const char *current_pin)
{
    if (!modulus_security_has_pin()) {
        return true;
    }
    if (!current_pin || !modulus_security_verify_pin(current_pin)) {
        return false;
    }
    s_pin_hash[0] = '\0';
    modulus_nvs_set_str("pin_hash", "");
    modulus_nvs_set_u8("pin_boot", 0);
    modulus_nvs_set_u8("pin_slp", 0);
    modulus_nvs_set_u8("pin_idle", 0);
    modulus_nvs_set_u16("pin_idle_tmo", 0);
    modulus_security_unlock();
    modulus_display_refresh_activity_monitor();
    ESP_LOGI(TAG, "PIN cleared, lock policies disabled");
    return true;
}

void modulus_security_on_sleep_wake(int64_t sleep_start_us)
{
    if (!modulus_security_has_pin() || !modulus_security_lock_on_sleep()) {
        return;
    }
    const uint16_t tmo = modulus_security_lock_timeout();
    if (tmo == 0) {
        return; /* Never — no auto-lock on display wake */
    }
    if (tmo == 65535) {
        modulus_security_lock();
        modulus_event_publish(EVT_SCREEN_CHANGE, NULL, 0);
        ESP_LOGI(TAG, "PIN lock on sleep wake (immediate)");
        return;
    }
    const int64_t elapsed_sec = (esp_timer_get_time() - sleep_start_us) / 1000000LL;
    if (elapsed_sec >= (int64_t)tmo) {
        modulus_security_lock();
        modulus_event_publish(EVT_SCREEN_CHANGE, NULL, 0);
        ESP_LOGI(TAG, "PIN lock after sleep wake (%lld s asleep)", (long long)elapsed_sec);
    }
}

bool modulus_security_idle_lock_enabled(void)
{
    return modulus_security_has_pin() && modulus_nvs_get_u8("pin_idle", 0) != 0;
}

uint16_t modulus_security_idle_lock_timeout(void)
{
    return modulus_nvs_get_u16("pin_idle_tmo", 0);
}

void modulus_security_idle_lock_tick(uint32_t inactive_ms)
{
    if (!modulus_security_idle_lock_enabled() || modulus_security_is_locked()) {
        return;
    }
    const uint16_t tmo = modulus_security_idle_lock_timeout();
    if (tmo == 0 || tmo == 65535) {
        return;
    }
    if (inactive_ms >= (uint32_t)tmo * 1000U) {
        modulus_security_lock();
        modulus_event_publish(EVT_SCREEN_CHANGE, NULL, 0);
        ESP_LOGI(TAG, "PIN idle lock (%u sec)", (unsigned)tmo);
    }
}
