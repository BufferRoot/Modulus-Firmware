#pragma once
/*
 * Zigbee device database — generated from zigbee-herdsman-converters (the
 * dataset behind zigbee2mqtt.io/supported-devices).
 *
 * Lookup key: the device's ZCL Basic ModelIdentifier (attr 0x0005) exactly as
 * reported over the air (the "zigbeeModel" field upstream). Result: vendor,
 * commercial model number, human description.
 *
 * zb_devdb_data.c is GENERATED — run tools/gen_zb_devdb.py to (re)build it
 * from the upstream repo. Without generation an empty table is linked and
 * every lookup misses (graceful: UI falls back to mfr/model strings).
 */
#include <stdint.h>

typedef struct {
    const char *zigbee_model; /* over-the-air ModelIdentifier (sort key) */
    const char *vendor;       /* e.g. "IKEA" */
    const char *model;        /* commercial model, e.g. "LED1545G12" */
    const char *description;  /* e.g. "TRADFRI bulb E27 WS opal 980lm" */
} zb_devdb_entry_t;

extern const zb_devdb_entry_t zb_devdb_table[];
extern const unsigned zb_devdb_count;

/* Binary search by ModelIdentifier. Trailing spaces/padding in the probe are
 * ignored (several vendors pad the ZCL string). NULL on miss. */
const zb_devdb_entry_t *zb_devdb_find(const char *model_identifier);
