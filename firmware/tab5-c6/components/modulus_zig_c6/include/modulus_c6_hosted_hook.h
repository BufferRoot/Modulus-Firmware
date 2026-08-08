#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/** Call once from esp_hosted coprocessor app_main after esp_hosted_coprocessor_init(). */
void modulus_c6_hosted_after_init(void);

#ifdef __cplusplus
}
#endif
