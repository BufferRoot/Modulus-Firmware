---
name: m5stack-tab5-ui
description: >-
  M5Unified and M5GFX setup for M5Stack Tab5 — M5.begin(), 1280x720 display,
  ST7123 compatibility, WiFi.setPins for C6. Use when building Tab5 UI, LVGL,
  or Arduino sketches on ESP32-P4.
---

# Tab5 — M5Unified / M5GFX

## Minimum versions (M5 docs)

| Library | Version |
|---------|---------|
| M5Unified | ≥ 0.2.8 |
| M5GFX | ≥ 0.2.11 |
| M5 board package | ≥ 3.2.2 (Arduino) |

## Skeleton

```cpp
#include <M5Unified.h>
#include <M5GFX.h>
#include <WiFi.h>

static constexpr gpio_num_t TAB5_SDIO_CLK = GPIO_NUM_12;
static constexpr gpio_num_t TAB5_SDIO_CMD = GPIO_NUM_13;
static constexpr gpio_num_t TAB5_SDIO_D0  = GPIO_NUM_11;
static constexpr gpio_num_t TAB5_SDIO_D1  = GPIO_NUM_10;
static constexpr gpio_num_t TAB5_SDIO_D2  = GPIO_NUM_9;
static constexpr gpio_num_t TAB5_SDIO_D3  = GPIO_NUM_8;
static constexpr gpio_num_t TAB5_SDIO_RST = GPIO_NUM_15;

void setup() {
    auto cfg = M5.config();
    M5.begin(cfg);

    M5.Display.setRotation(0);
    M5.Display.setTextSize(2);
    M5.Display.println("Tab5 ready");

    WiFi.setPins(TAB5_SDIO_CLK, TAB5_SDIO_CMD, TAB5_SDIO_D0,
                 TAB5_SDIO_D1, TAB5_SDIO_D2, TAB5_SDIO_D3, TAB5_SDIO_RST);
}

void loop() {
    M5.update();  // touch, buttons
}
```

## Display notes

- Native resolution **1280×720** — allocate draw buffers in PSRAM.
- ST7123 units: use latest M5GFX; ensure **120ms+ delay** after panel SLPOUT if writing custom DSI init (IDF 5.5+ timing).
- Check back sticker for ILI9881C vs ST7123 vs ST7121 hardware generation.

## Board selection (Arduino)

- Preferred: **M5Tab5** board target when package supports hosted pins
- Fallback: **ESP32P4 Dev Module** + manual `WiFi.setPins()` (documented community workaround)

## ESP-IDF + LVGL

Use `espressif/m5stack_tab5` BSP + `esp_lvgl_port` instead of M5Unified when staying on pure IDF 6.0.

## Dependencies (PlatformIO example)

```ini
lib_deps =
    https://github.com/M5Stack/M5Unified.git
    https://github.com/M5Stack/M5GFX.git
build_flags =
    -DBOARD_HAS_PSRAM
    -DARDUINO_USB_CDC_ON_BOOT=1
```

Platform: pioarduino espressif32 with ESP32-P4 support (see M5 Tab5 docs).

## Shutdown hook

Before power-off UI action, call app teardown then allow M5/power manager to complete soft shutdown — protect BMI270 (see `m5stack-tab5` skill).
