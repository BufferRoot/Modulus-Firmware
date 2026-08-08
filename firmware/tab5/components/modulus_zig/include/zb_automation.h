#pragma once
/*
 * CNC-linked Zigbee automation + QS scenes.
 * Modes (NVS zbN_auto): 0 manual, 1 follow RUN, 2 inverse of RUN.
 * Hard-off (no delay): ALARM, DOOR, disconnect. HOLD keeps follow ON.
 * Off-delay seconds: NVS zb_off_s (default 10). Door soft-interlock: zb_door_il.
 */
#include <stdbool.h>
#include <stdint.h>

#define MODULUS_ZB_AUTO_OFF     0
#define MODULUS_ZB_AUTO_FOLLOW  1
#define MODULUS_ZB_AUTO_INVERSE 2

/* QS / dashboard scene IDs */
#define MODULUS_ZB_SCENE_CUT       0 /* follow ON, lights dim, covers open */
#define MODULUS_ZB_SCENE_CLEANUP   1 /* vacuum/follow ON, lights mid */
#define MODULUS_ZB_SCENE_IDLE      2 /* follow OFF, lights bright, covers close */
#define MODULUS_ZB_SCENE_EMERGENCY 3 /* everything OFF now */

uint8_t modulus_zb_auto_get(int idx);
void modulus_zb_auto_set(int idx, uint8_t mode);
const char *modulus_zb_auto_mode_text(uint8_t mode);

/* Call from the 802.15.4 poll loop OR always-on zb_auto task; self-rate-limits to ~1 Hz. */
void modulus_zb_auto_poll(void);
/** Start Core-0 background task so automation runs with wireless settings page closed. */
void modulus_zb_auto_start_task(void);

/* Apply a named scene (walks registry; no ZCL group dependency). */
void modulus_zb_scene_apply(uint8_t scene);

/* Soft interlock: IAS door/contact Alarm1 while zb_door_il!=0. */
bool modulus_zb_door_blocks_cycle(void);

/* Non-NULL while RUN and a metered follow device lost ~70%+ draw. */
const char *modulus_zb_power_warn_text(void);
/* Soft advisory: Identify the metered follow device that triggered clog warn. */
int modulus_zb_clog_device_idx(void);
void modulus_zb_job_complete(void); /* beep + Idle scene when SD job finishes */

void modulus_zb_auto_on_remove(int removed_idx, int new_count);
void modulus_zb_auto_clear_all(int old_count);
