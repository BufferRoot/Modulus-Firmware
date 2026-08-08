#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    MOD_CNF_NEVER = 0,
    MOD_CNF_ALWAYS = 1,
    MOD_CNF_WHEN_RUN = 2,
};

typedef enum {
    MOD_CNF_ACT_CYCLE = 0,
    MOD_CNF_ACT_SPIN,
    MOD_CNF_ACT_ZERO,
    MOD_CNF_ACT_HOME,
    MOD_CNF_ACT_MAC,
} mod_cnf_action_t;

typedef void (*mod_cnf_apply_fn)(void *user);

uint8_t modulus_ui_cnf_policy(mod_cnf_action_t act);
bool modulus_ui_cnf_needs(mod_cnf_action_t act, uint8_t machine_state);
bool modulus_ui_cnf_busy(void);

/** If policy requires confirm, show modal then call apply; else call apply now. */
void modulus_ui_cnf_request(mod_cnf_action_t act, uint8_t machine_state, const char *title,
                            const char *body, mod_cnf_apply_fn apply, void *user);

#ifdef __cplusplus
}
#endif
