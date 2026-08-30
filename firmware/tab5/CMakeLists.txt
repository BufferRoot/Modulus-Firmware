# Modulus OS — Tab5 Zig host firmware (ESP32-P4)
# ESP-IDF v6.0 + espressif/m5stack_tab5 BSP + modulus_zig static lib
cmake_minimum_required(VERSION 3.16)

# esp-dsp + hosted stack exceed Windows CreateProcess cmdline limit without response files
set(CMAKE_NINJA_FORCE_RESPONSE_FILE ON CACHE INTERNAL "")
set(CMAKE_C_USE_RESPONSE_FILE_FOR_OBJECTS 1)
set(CMAKE_CXX_USE_RESPONSE_FILE_FOR_OBJECTS 1)

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(modulus_tab5)

# Zig UI engine owns the panel: no LVGL display, indev, port task or draw
# buffer is ever created (display_shim uses bsp_display_new_with_handles() +
# bsp_touch_new() directly). Tell the BSP to build without a graphics library
# so bsp_display.c stops compiling its lvgl_port_* paths — otherwise it needs
# LVGL purely because our component pulls it in transitively (the BSP's own
# CMakeLists lists no lvgl at all). config.h honours a -D override.
#
# Only bsp_display_lock/unlock, enter_sleep/exit_sleep and bsp_display_rotate
# live behind this guard (m5stack_tab5.h:421-514); everything we use —
# bsp_display_new_with_handles, bsp_touch_new, brightness/backlight, i2c,
# sdcard, audio, usb — is outside it.
if(CONFIG_MODULUS_ZIG_UI_ENGINE)
    idf_build_set_property(COMPILE_DEFINITIONS "BSP_CONFIG_NO_GRAPHIC_LIB=1" APPEND)
endif()

# esp_hosted may need IDF 6 esp_driver_sdmmc legacy includes on older releases.
if(EXISTS "$ENV{IDF_PATH}/components/esp_driver_sdmmc/legacy/include/driver/sdmmc_host.h")
    idf_component_get_property(_modulus_hosted espressif__esp_hosted COMPONENT_LIB)
    if(TARGET ${_modulus_hosted})
        target_include_directories(${_modulus_hosted} PRIVATE
            "$ENV{IDF_PATH}/components/esp_driver_sdmmc/legacy/include")
        target_link_libraries(${_modulus_hosted} PRIVATE
            idf::esp_driver_sdmmc idf::esp_driver_sdio idf::sdmmc)
    endif()
endif()
