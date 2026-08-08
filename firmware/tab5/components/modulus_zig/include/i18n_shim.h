#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    MOD_I18N_SYSTEM_SETTINGS = 0,
    MOD_I18N_LANGUAGE,
    MOD_I18N_LANGUAGE_CHANGED,
    MOD_I18N_APPLY_LANGUAGE,
    MOD_I18N_APPLY,
    MOD_I18N_CANCEL,
    MOD_I18N_CATALOG_PENDING,
    MOD_I18N_COUNT,
} modulus_i18n_id_t;

typedef enum {
    MOD_LANG_EN = 0,
    MOD_LANG_FR,
    MOD_LANG_ES,
    MOD_LANG_ZH,
    MOD_LANG_COUNT,
} modulus_lang_t;

void modulus_i18n_init(void);
const char *modulus_i18n_tr(modulus_i18n_id_t id);
modulus_lang_t modulus_i18n_current(void);
void modulus_i18n_set_lang(modulus_lang_t lang, bool persist);
const char *modulus_i18n_lang_label(modulus_lang_t lang);
void modulus_i18n_build_lang_options(char *buf, size_t len);

#ifdef __cplusplus
}
#endif
