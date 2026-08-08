#!/usr/bin/env python3
"""Split ui_settings_wireless_core.c into protocol-focused modules."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMP = ROOT / "firmware/tab5/components/modulus_zig"
SRC = COMP / "ui_settings_wireless_core.c"
lines = SRC.read_text(encoding="utf-8").splitlines(keepends=True)

COMMON_INCLUDES = """#include "ui_settings_wireless_priv.h"
#include "ui_settings_wireless_kb.h"
#include "ui_settings_common.h"
#include "ui_touch_sound.h"
#include "audio_shim.h"
#include "nvs_shim.h"
#include "wireless_shim.h"
#include "transport_shim.h"
#include "cnc_cmd_exports.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

"""

# 1-based inclusive line ranges from original file
SECTIONS = {
    "ui_settings_wireless_kb.c": [(416, 427)],
    "ui_settings_wireless_timer.c": [(17, 299)],
    "ui_settings_wireless_nav.c": [(308, 332), (1298, 1377)],
    "ui_settings_wireless_wifi.c": [(334, 343), (396, 414), (429, 535), (668, 685)],
    "ui_settings_wireless_bt.c": [(537, 666), (717, 772)],
    "ui_settings_wireless_154.c": [(774, 894), (896, 1124)],
    "ui_settings_wireless_espnow.c": [(301, 306), (345, 371), (1126, 1297)],
    "ui_settings_wireless_misc.c": [(373, 394), (687, 715)],
}

def extract(ranges):
    out = []
    for start, end in ranges:
        out.extend(lines[start - 1:end])
    return "".join(out)

def transform_timer(body: str) -> str:
    body = body.replace("static void wl_timer_stop(", "void wl_timer_stop_activity(")
    body = body.replace("wl_timer_stop();", "wl_timer_stop_activity();")
    body = body.replace("static void wl_refresh_", "void wl_refresh_")
    body = body.replace("static void wl_timer_cb", "static void wl_timer_cb")
    # add wl_timer_tick at end
    body += "\nvoid wl_timer_tick(void)\n{\n    wl_timer_cb(NULL);\n}\n"
    return body

def transform_wifi(body: str) -> str:
    body = body.replace("static void connect_ta_focus_cb", "static void connect_ta_focus_cb")
    body = body.replace("configure_connect_keyboard(", "wl_configure_connect_keyboard(")
    body = body.replace("static void show_connect_modal", "static void wl_show_connect_modal")
    body = body.replace("show_connect_modal(", "wl_show_connect_modal(")
    return body

def transform_bt(body: str) -> str:
    body = body.replace("configure_connect_keyboard(", "wl_configure_connect_keyboard(")
    return body

def transform_154(body: str) -> str:
    body = body.replace("configure_connect_keyboard(", "wl_configure_connect_keyboard(")
    return body

def transform_espnow(body: str) -> str:
    body = body.replace("static void maybe_reinit_espnow_transport", "void wl_maybe_reinit_espnow_transport")
    body = body.replace("maybe_reinit_espnow_transport(", "wl_maybe_reinit_espnow_transport(")
    body = body.replace("wl_timer_stop();", "wl_timer_stop_activity();")
    body = body.replace("configure_connect_keyboard(", "wl_configure_connect_keyboard(")
    return body

def transform_misc(body: str) -> str:
    body = body.replace("maybe_reinit_espnow_transport(", "wl_maybe_reinit_espnow_transport(")
    return body

def transform_nav(body: str) -> str:
    body = body.replace("wl_timer_cb(NULL)", "wl_timer_tick()")
    return body

def transform_kb(body: str) -> str:
    body = body.replace("static void configure_connect_keyboard", "void wl_configure_connect_keyboard")
    return "#include \"ui_settings_wireless_kb.h\"\n#include \"ui_settings_priv.h\"\n#include \"nvs_shim.h\"\n\n" + body

TRANSFORMS = {
    "ui_settings_wireless_timer.c": transform_timer,
    "ui_settings_wireless_nav.c": transform_nav,
    "ui_settings_wireless_wifi.c": transform_wifi,
    "ui_settings_wireless_bt.c": transform_bt,
    "ui_settings_wireless_154.c": transform_154,
    "ui_settings_wireless_espnow.c": transform_espnow,
    "ui_settings_wireless_misc.c": transform_misc,
    "ui_settings_wireless_kb.c": transform_kb,
}

for name, ranges in SECTIONS.items():
    body = extract(ranges)
  if name in TRANSFORMS:
    body = TRANSFORMS[name](body)
  if name != "ui_settings_wireless_kb.c":
    body = COMMON_INCLUDES + body
  (COMP / name).write_text(body, encoding="utf-8")
  print(f"Wrote {name} ({len(body.splitlines())} lines)")

SRC.unlink()
print("Deleted ui_settings_wireless_core.c")
