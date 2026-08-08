#include "ui_zero_confirm.h"
#include "ui_confirm_policy.h"
#include "cnc_cmd_exports.h"

enum {
    k_state_disconnected = 0,
    k_zero_all = 0xFE,
};

static uint8_t s_pending_axis;

static void zero_apply(void *user)
{
    const uintptr_t pending = (uintptr_t)user;
    if (pending == k_zero_all) {
        modulus_zig_cmd_zero_all();
    } else if (pending < 6) {
        modulus_zig_cmd_zero_axis((uint8_t)pending);
    }
}

bool modulus_ui_zero_needs_confirm(uint8_t machine_state)
{
    return modulus_ui_cnf_needs(MOD_CNF_ACT_ZERO, machine_state);
}

bool modulus_ui_zero_confirm_visible(void)
{
    return modulus_ui_cnf_busy();
}

void modulus_ui_zero_axis_request(uint8_t axis_idx, uint8_t machine_state)
{
    if (machine_state == k_state_disconnected) {
        return;
    }
    s_pending_axis = axis_idx;
    modulus_ui_cnf_request(MOD_CNF_ACT_ZERO, machine_state, "Zero axis?",
                           "Work offset will be updated.", zero_apply,
                           (void *)(uintptr_t)axis_idx);
}

void modulus_ui_zero_all_request(uint8_t machine_state)
{
    if (machine_state == k_state_disconnected) {
        return;
    }
    (void)s_pending_axis;
    modulus_ui_cnf_request(MOD_CNF_ACT_ZERO, machine_state, "Zero all axes?",
                           "Work offsets will be updated.", zero_apply,
                           (void *)(uintptr_t)k_zero_all);
}
