#include "ui_confirm_policy.h"
#include "ui_settings_common.h"
#include "ui_internal.h"
#include "nvs_shim.h"

enum {
    k_state_disconnected = 0,
    k_state_run = 2,
};

static bool s_busy;
static mod_cnf_apply_fn s_apply;
static void *s_user;

static const char *policy_key(mod_cnf_action_t act)
{
    switch (act) {
    case MOD_CNF_ACT_CYCLE:
        return "cnf_cycle";
    case MOD_CNF_ACT_SPIN:
        return "cnf_spin";
    case MOD_CNF_ACT_ZERO:
        return "cnf_zero";
    case MOD_CNF_ACT_HOME:
        return "cnf_home";
    case MOD_CNF_ACT_MAC:
        return "cnf_mac";
    default:
        return "cnf_cycle";
    }
}

static uint8_t policy_default(mod_cnf_action_t act)
{
    return (act == MOD_CNF_ACT_ZERO) ? (uint8_t)MOD_CNF_WHEN_RUN : (uint8_t)MOD_CNF_NEVER;
}

uint8_t modulus_ui_cnf_policy(mod_cnf_action_t act)
{
    const uint8_t v = modulus_nvs_get_u8(policy_key(act), policy_default(act));
    if (v > MOD_CNF_WHEN_RUN) {
        return policy_default(act);
    }
    return v;
}

bool modulus_ui_cnf_needs(mod_cnf_action_t act, uint8_t machine_state)
{
    if (machine_state == k_state_disconnected) {
        return false;
    }
    switch (modulus_ui_cnf_policy(act)) {
    case MOD_CNF_ALWAYS:
        return true;
    case MOD_CNF_WHEN_RUN:
        return machine_state == k_state_run;
    default:
        return false;
    }
}

bool modulus_ui_cnf_busy(void)
{
    return s_busy;
}

static void cnf_dismissed(void)
{
    s_busy = false;
    s_apply = NULL;
    s_user = NULL;
    modulus_ui_resume_dashboard_refresh();
}

static void cnf_cancel(void)
{
    cnf_dismissed();
}

static void cnf_apply(void)
{
    mod_cnf_apply_fn fn = s_apply;
    void *user = s_user;
    cnf_dismissed();
    if (fn) {
        fn(user);
    }
}

void modulus_ui_cnf_request(mod_cnf_action_t act, uint8_t machine_state, const char *title,
                            const char *body, mod_cnf_apply_fn apply, void *user)
{
    if (!apply) {
        return;
    }
    if (machine_state == k_state_disconnected && act != MOD_CNF_ACT_MAC) {
        return;
    }
    if (!modulus_ui_cnf_needs(act, machine_state)) {
        apply(user);
        return;
    }
    if (s_busy) {
        return;
    }
    s_busy = true;
    s_apply = apply;
    s_user = user;
    modulus_ui_pause_dashboard_refresh();
    settings_confirm_show(title, body, "Apply", false, cnf_apply, cnf_cancel);
}
