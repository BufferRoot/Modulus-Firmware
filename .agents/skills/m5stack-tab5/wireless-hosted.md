# Tab5 — ESP-Hosted Wireless Setup

## Architecture

P4 = **host** (runs your app + `esp_hosted` host port)  
C6 = **slave** (runs ESP-Hosted slave FW + real Wi-Fi/BT/802.15.4)

Transport: **SDIO 4-bit** on Tab5 **SDIO2** pins (not ESP32-P4-EV default).

## IDF dependencies

```yaml
# main/idf_component.yml
dependencies:
  espressif/esp_hosted: "*"
  espressif/esp_wifi_remote: "*"
  espressif/m5stack_tab5: "*"
```

```bash
idf.py add-dependency "espressif/esp_hosted"
idf.py add-dependency "espressif/esp_wifi_remote"
idf.py add-dependency "espressif/m5stack_tab5"
```

## menuconfig highlights

`Component config → ESP-Hosted config`:

- Transport: **SDIO**
- Slave chipset: **ESP32-C6**
- SDIO bus width: **4-bit**
- **Host SDIO GPIOs** → Tab5 mapping:
  - CLK=12, CMD=13, D0=11, D1=10, D2=9, D3=8, Reset=15

Enable C6 power via BSP/expander before `esp_hosted_init`.

## Boot sequence

```
1. bsp_board_init() / M5.begin()
      → PI4IOE: WLAN_PWR_EN, resets
2. esp_hosted_init() / transport bring-up
      → sdmmc init on SDIO2, slave probe
3. esp_wifi_remote init (if using Wi-Fi)
4. esp_netif, event loop, app HTTP/MQTT
```

Failure signatures:

- `sdmmc_card_init failed` / `0x107` → wrong pins, C6 unpowered, or slave FW mismatch
- `ESP-Hosted link not yet up` → init order or transport config
- MAC `00:00:00:00:00:00` → hosted link not established

## C6 slave firmware

Tab5 ships C6 pre-flashed with hosted slave. Reflash only when:

- Updating `esp_hosted` major version
- Using Thread/Zigbee co-processor features requiring new slave build

Use Espressif `esp_hosted` slave example built for `esp32c6` + SDIO.

## Application code pattern (IDF)

After BSP + hosted init, use **standard** networking:

```c
#include "esp_wifi.h"
#include "esp_netif.h"
#include "esp_http_client.h"

// Wi-Fi APIs hit esp_wifi_remote → RPC → C6
// No separate "send to C6" API for normal TCP/HTTP
```

## Arduino / M5Unified pattern

Hosted stack is inside Arduino-ESP32 + board support. **Must** call before `WiFi.mode()`:

```cpp
WiFi.setPins(12, 13, 11, 10, 9, 8, 15);  // CLK,CMD,D0,D1,D2,D3,RST
```

Or board macros when `M5Tab5` selected in Arduino IDE.

M5Unified `M5.begin()` initializes display/power; WiFi pins still required explicitly in current examples.

## Thread / Zigbee

802.15.4 radio is on **C6**, not P4. Use Espressif co-processor / OpenThread hosted paths — same "no direct RF on P4" rule. Consult ESP-Hosted docs for coprocessor feature flags.

## References

- https://github.com/espressif/esp-hosted-mcu
- https://docs.m5stack.com/en/arduino/m5tab5/wifi
- M5 Tab5 C6 factory restore guide (M5 docs)
