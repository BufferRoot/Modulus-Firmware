#pragma once

#include <stdint.h>

#include "cnc_cmd_exports.h"

#ifdef __cplusplus
extern "C" {
#endif

const char *modulus_zig_version(void);
const char *modulus_zig_toolchain_version(void);
uint32_t modulus_zig_abi_epoch(void);
void modulus_zig_boot(void);
/** 1 = boot OK, 0 = failed (c_int — Zig/RISC-V bool ABI). */
int modulus_zig_boot_ok(void);
void modulus_zig_system_tick(uint32_t tick_ms);
int modulus_zig_system_task_spawned(void);
int modulus_zig_event_dispatch_spawned(void);
int modulus_zig_factory_reset(void);
int modulus_zig_ota_available(void);
const char *modulus_zig_ota_status_text(void);

#ifdef __cplusplus
}
#endif
