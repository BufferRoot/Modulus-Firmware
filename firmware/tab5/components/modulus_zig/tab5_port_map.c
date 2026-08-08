/*
 * Tab5 expansion connector reference — single source for UI + diagnostics export.
 * See docs/hardware/tab5/pinmap.md and interconnect.md.
 */
#include "tab5_port_map.h"

#include <stddef.h>
#include <stdio.h>

static const tab5_port_map_row_t k_rows[] = {
    {"Port A Grove (4p)",
     "GND | EXT5V | G53 SDA | G54 SCL — hw I2C1 (schematic STD_GPIO)"},
    {"Port A power",
     "EXT5V from PI4IOE1 P2 — enable in Power settings"},
    {"Port A CAN mode",
     "TWAI TX G54 RX G53 — conflicts with I2C1 / ExtEncoder"},
    {"ExtPort2 (6p)",
     "GND | HVIN | 485A | 485B | G31 SDA | G32 SCL"},
    {"Int I2C0 (M-Bus)",
     "G31 SDA G32 SCL — onboard + ExtPort2 + M5-Bus 17-18"},
    {"ExtPort1 (10p)",
     "Top: HVIN GND 3V3 G1 G50 / Bot: GND GND EXT5V G0 G49"},
    {"RS-485 SIT3088",
     "UART1 TX G20 RX G21 DE G34 — 120R term switch"},
    {"M5-Bus rear (30p)",
     "Pin2 G16 wired E-stop (NO toggle to GND); Int I2C pins 17-18; SPI G5/18/19; UART G37/38"},
    {"USB Type-A host",
     "GND D+ D- USB5V out"},
    {"USB Type-C OTG",
     "USB1 D+ D- GND 5VIN"},
    {"COM.X STAMP",
     "G46 G6 G31 G32 G33 G19 G18 G5 GND 3V3 SYS-5V"},
};

size_t tab5_port_map_row_count(void)
{
    return sizeof(k_rows) / sizeof(k_rows[0]);
}

const tab5_port_map_row_t *tab5_port_map_row(size_t index)
{
    if (index >= tab5_port_map_row_count()) {
        return NULL;
    }
    return &k_rows[index];
}

void tab5_port_map_write_diag(FILE *f)
{
    if (!f) {
        return;
    }
    fprintf(f, "\n--- Expansion port map ---\n");
    for (size_t i = 0; i < tab5_port_map_row_count(); ++i) {
        fprintf(f, "%s: %s\n", k_rows[i].title, k_rows[i].detail);
    }
    fprintf(f, "Docs: docs/hardware/tab5/pinmap.md\n");
}
