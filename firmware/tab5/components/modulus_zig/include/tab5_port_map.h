#pragma once

#include <stddef.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    const char *title;
    const char *detail;
} tab5_port_map_row_t;

/** Rows for Settings → Storage expansion map (stable order). */
size_t tab5_port_map_row_count(void);
const tab5_port_map_row_t *tab5_port_map_row(size_t index);

/** Append connector / bus reference to diagnostics export. */
void tab5_port_map_write_diag(FILE *f);

#ifdef __cplusplus
}
#endif
