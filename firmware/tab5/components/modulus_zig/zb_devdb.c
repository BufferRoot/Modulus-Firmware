/* Zigbee device database lookup. Table lives in zb_devdb_data.c (generated,
 * sits in flash .rodata — zero RAM cost; the P4 XIPs it from PSRAM-mapped
 * flash). Binary search: ~12 compares over the full ~4k-entry dataset. */
#include "zb_devdb.h"

#include <string.h>

const zb_devdb_entry_t *zb_devdb_find(const char *model_identifier)
{
    if (!model_identifier || !model_identifier[0] || zb_devdb_count == 0) {
        return NULL;
    }
    /* Normalize probe: copy + right-trim spaces (vendor padding). */
    char key[33];
    size_t n = strlen(model_identifier);
    if (n >= sizeof(key)) {
        n = sizeof(key) - 1;
    }
    memcpy(key, model_identifier, n);
    while (n > 0 && key[n - 1] == ' ') {
        n--;
    }
    key[n] = '\0';
    if (n == 0) {
        return NULL;
    }

    unsigned lo = 0, hi = zb_devdb_count;
    while (lo < hi) {
        const unsigned mid = lo + (hi - lo) / 2;
        const int c = strcmp(key, zb_devdb_table[mid].zigbee_model);
        if (c == 0) {
            return &zb_devdb_table[mid];
        }
        if (c < 0) {
            hi = mid;
        } else {
            lo = mid + 1;
        }
    }
    return NULL;
}
