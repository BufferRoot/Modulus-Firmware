# Modulus OS — Tab5 Zig host firmware (ESP32-P4)
# ESP-IDF v6.0 + espressif/m5stack_tab5 BSP + modulus_zig static lib
cmake_minimum_required(VERSION 3.16)

# esp-dsp + hosted stack exceed Windows CreateProcess cmdline limit without response files
set(CMAKE_NINJA_FORCE_RESPONSE_FILE ON CACHE INTERNAL "")
set(CMAKE_C_USE_RESPONSE_FILE_FOR_OBJECTS 1)
set(CMAKE_CXX_USE_RESPONSE_FILE_FOR_OBJECTS 1)

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(modulus_tab5)

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
