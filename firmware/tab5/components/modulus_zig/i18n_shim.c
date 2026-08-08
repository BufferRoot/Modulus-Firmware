/*
 * Minimal i18n — English catalog + stub langs (ASCII-safe, small ROM).
 */
#include "i18n_shim.h"
#include "nvs_shim.h"

#include <esp_log.h>
#include <stdio.h>
#include <string.h>

static const char *TAG = "modulus_i18n";

static modulus_lang_t s_lang = MOD_LANG_EN;

static const char *const k_en[MOD_I18N_COUNT] = {
    [MOD_I18N_SYSTEM_SETTINGS] = "System Settings",
    [MOD_I18N_LANGUAGE] = "Language",
    [MOD_I18N_LANGUAGE_CHANGED] = "Language changed",
    [MOD_I18N_APPLY_LANGUAGE] = "Apply language and refresh screens?",
    [MOD_I18N_APPLY] = "Apply",
    [MOD_I18N_CANCEL] = "Cancel",
    [MOD_I18N_CATALOG_PENDING] = "catalog pending",
};

static const char *lookup(modulus_lang_t lang, modulus_i18n_id_t id)
{
    if (id >= MOD_I18N_COUNT) {
        return "";
    }
    if (lang == MOD_LANG_EN) {
        return k_en[id];
    }
    if (id == MOD_I18N_CATALOG_PENDING) {
        return k_en[id];
    }
    return NULL;
}

void modulus_i18n_init(void)
{
    uint8_t v = modulus_nvs_get_u8("ui_lang", MOD_LANG_EN);
    if (v >= MOD_LANG_COUNT) {
        v = MOD_LANG_EN;
    }
    s_lang = (modulus_lang_t)v;
    ESP_LOGI(TAG, "Locale: %s", modulus_i18n_lang_label(s_lang));
}

const char *modulus_i18n_tr(modulus_i18n_id_t id)
{
    const char *s = lookup(s_lang, id);
    if (s && s[0]) {
        return s;
    }
    return k_en[id];
}

modulus_lang_t modulus_i18n_current(void)
{
    return s_lang;
}

void modulus_i18n_set_lang(modulus_lang_t lang, bool persist)
{
    if (lang >= MOD_LANG_COUNT) {
        lang = MOD_LANG_EN;
    }
    s_lang = lang;
    if (persist) {
        modulus_nvs_set_u8("ui_lang", (uint8_t)lang);
    }
    ESP_LOGI(TAG, "Locale set: %s", modulus_i18n_lang_label(lang));
}

const char *modulus_i18n_lang_label(modulus_lang_t lang)
{
    switch (lang) {
    case MOD_LANG_FR:
        return "Francais (pending)";
    case MOD_LANG_ES:
        return "Espanol (pending)";
    case MOD_LANG_ZH:
        return "Chinese (pending)";
    default:
        return "English";
    }
}

void modulus_i18n_build_lang_options(char *buf, size_t len)
{
    if (!buf || len == 0) {
        return;
    }
    buf[0] = '\0';
    for (uint8_t i = 0; i < MOD_LANG_COUNT; ++i) {
        const char *lbl = modulus_i18n_lang_label((modulus_lang_t)i);
        if (buf[0]) {
            strncat(buf, "\n", len - strlen(buf) - 1);
        }
        strncat(buf, lbl, len - strlen(buf) - 1);
    }
}
