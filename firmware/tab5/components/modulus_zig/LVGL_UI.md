# LVGL UI sources (archive / compile-out)

When `CONFIG_MODULUS_ZIG_UI_ENGINE=y` (production default), CMake **does not
compile** the `MODULUS_LVGL_UI_SRCS` list in `CMakeLists.txt`. Zig Engine owns
MIPI scanout; `ui_zig_stubs.c` satisfies leftover symbols.

Sources stay in this folder as the LVGL reference tree (agents/grep still see
them). They are not linked into the Zig-UI firmware image.

| Profile | Flag | How |
|---------|------|-----|
| Zig production | `CONFIG_MODULUS_ZIG_UI_ENGINE=y` | `.\scripts\build_tab5.ps1` |
| LVGL lab | `=n` + fonts | `.\scripts\build_tab5.ps1 -Lab` |

Do not move these files into a separate directory without updating
`MODULUS_LVGL_UI_SRCS` and lab CI. Prefer git tags for historical LVGL-only
snapshots.
