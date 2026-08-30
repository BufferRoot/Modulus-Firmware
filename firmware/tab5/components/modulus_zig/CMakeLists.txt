# Builds zig-out/lib/libmodulus_zig.a via `zig build tab5-lib`
set(MODULUS_REPO_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../../..")

# HAL + Zig bridge — always linked.
set(MODULUS_CORE_SRCS
    "nvs_shim.c"
    "i2c_coex_shim.c"
    "tab5_pi4ioe.c"
    "tab5_ext_i2c.c"
    "tab5_port_map.c"
    "serial_shim.c"
    "tcp_transport_shim.c"
    "masso_udp_shim.c"
    "i2c_transport_shim.c"
    "canbus_shim.c"
    "c6_sdio_host.c"
    "zb_uart_host.c"
    "zb_devdb.c"
    "zb_devdb_data.c"
    "zb_automation.c"
    "shop_recipe.c"
    "wireless_rpc.c"
    "wireless_shim_802154.c"
    "espnow_transport_shim.c"
    "espnow_debug.c"
    "ble_host.c"
    "ble_transport_shim.c"
    "event_shim.c"
    "display_shim.c"
    "ppa_shim.c"
    "ui_engine_flush_shim.c"
    "touch_shim.c"
    "dsp_shim.c"
    "security_shim.c"
    "imu_shim.c"
    "bmi270_pms_wake.c"
    "wakeup_shim.c"
    "mbus_shim.c"
    "ext_encoder_shim.c"
    "estop_gpio_shim.c"
    "cnc_trace_shim.c"
    "i2c_scan_shim.c"
    "i18n_shim.c"
    "audio_shim.c"
    "battery_shim.c"
    "rx8130.c"
    "rtc_shim.c"
    "storage_shim.c"
    "power_shim.c"
    "wireless_shim.c"
    "wireless_shim_espnow.c"
    "ui_shim.c"
    "ui_cnc_profiles.c"
)

# Full LVGL widget UI — only when Zig does NOT own scanout.
set(MODULUS_LVGL_UI_SRCS
    "ui_theme.c"
    "ui_components.c"
    "ui_motion.c"
    "ui_snackbar.c"
    "ui_icons.c"
    "ui_icons_battery.c"
    "assets/icons/generated/icon_assets_24.c"
    "assets/icons/generated/icon_assets_32.c"
    "assets/icons/generated/icon_assets_40.c"
    "ui_boot.c"
    "ui_dashboard.c"
    "ui_status_bar.c"
    "ui_status_bar_helpers.c"
    "ui_status_bar_data.c"
    "ui_status_bar_build.c"
    "ui_widget_jog.c"
    "ui_widget_actions.c"
    "ui_quick_grid.c"
    "ui_widget_dro.c"
    "ui_widget_dro_build.c"
    "ui_zero_confirm.c"
    "ui_confirm_policy.c"
    "ui_state_modal.c"
    "ui_job_progress.c"
    "ui_widget_overrides.c"
    "ui_quick_settings.c"
    "ui_power_menu.c"
    "ui_power_menu_build.c"
    "ui_power_menu_shell.c"
    "ui_power_menu_confirm.c"
    "ui_settings.c"
    "ui_settings_common.c"
    "ui_settings_modal_kb.c"
    "ui_settings_modal_transport.c"
    "ui_settings_modal_pin.c"
    "ui_settings_modal_incr.c"
    "ui_settings_modal_macro.c"
    "ui_settings_modal_mach_name.c"
    "ui_settings_modal_qbtn.c"
    "ui_settings_modal_grbl_dump.c"
    "ui_settings_modal_wcs.c"
    "ui_settings_modal_mpg.c"
    "ui_settings_modal_maint.c"
    "ui_settings_modal_wl_adv.c"
    "ui_settings_modal_idle_lock.c"
    "ui_settings_modal_probe.c"
    "ui_settings_modals.c"
    "ui_settings_wireless_state.c"
    "ui_settings_wireless_kb.c"
    "ui_settings_wireless_timer.c"
    "ui_settings_wireless_nav.c"
    "ui_settings_wireless_wifi.c"
    "ui_settings_wireless_bt.c"
    "ui_settings_wireless_154.c"
    "ui_settings_wireless_espnow.c"
    "ui_settings_wireless_misc.c"
    "ui_settings_wireless_build.c"
    "ui_settings_wireless_theme.c"
    "ui_settings_widgets.c"
    "ui_settings_widgets_ctl.c"
    "ui_settings_tab_cnc.c"
    "ui_settings_tab_system.c"
    "ui_settings_tab_power.c"
    "ui_settings_tab_audio.c"
    "ui_settings_tab_display.c"
    "ui_settings_tab_dashboard.c"
    "ui_axes_preset.c"
    "ui_settings_tab_storage.c"
    "ui_settings_tab_security.c"
    "ui_settings_tab_machine.c"
    "ui_settings_time.c"
    "ui_pin_lock.c"
    "ui_touch_sound.c"
)

# LVGL is needed only by the widget UI. Under ZIG_UI nothing links it: the
# engine paints the DPI FB itself, display_shim uses bsp_display_new_with_handles
# + bsp_touch_new, and BSP_CONFIG_NO_GRAPHIC_LIB=1 (set in the project
# CMakeLists) stops bsp_display.c compiling its lvgl_port_* paths.
if(CONFIG_MODULUS_ZIG_UI_ENGINE)
    set(MODULUS_LVGL_REQ "")
else()
    set(MODULUS_LVGL_REQ espressif__esp_lvgl_port lvgl__lvgl)
endif()

idf_component_register(
    SRCS ${MODULUS_CORE_SRCS}
    INCLUDE_DIRS "include" "assets/icons/generated"
    PRIV_INCLUDE_DIRS "include"
    EMBED_FILES
        "assets/audio/boot_sound.mp3"
        "assets/audio/shutdown_sfx.mp3"
    REQUIRES nvs_flash esp_driver_uart esp_driver_gpio esp_driver_i2c esp_driver_tsens esp_driver_twai
             esp_driver_ppa esp_mm
             esp_timer mbedtls esp-tls bt
             espressif__m5stack_tab5 espressif__bmi270 espressif__esp-dsp espressif__esp_lcd_touch
             ${MODULUS_LVGL_REQ} esp_lcd espressif__usb
             esp_wifi esp_netif esp_event espressif__esp_hosted
    PRIV_REQUIRES chmorgan__esp-audio-player
)

# C shims are reached only from Zig externs. Without WHOLE_ARCHIVE the linker
# scans libmodulus_zig.a before libmodulus_zig_core.a and drops every .o that
# nothing else has referenced yet — then Zig creates undefined modulus_* refs.
idf_component_set_property(${COMPONENT_NAME} WHOLE_ARCHIVE TRUE)

# esp_hosted keeps common/ and transport/ private; Modulus SDIO/BLE shims need them.
set(ESP_HOSTED_DIR "${MODULUS_REPO_ROOT}/firmware/tab5/managed_components/espressif__esp_hosted")
target_include_directories(${COMPONENT_LIB} PRIVATE
    "${ESP_HOSTED_DIR}/common"
    "${ESP_HOSTED_DIR}/common/transport"
    "${ESP_HOSTED_DIR}/host/drivers/transport"
    "${ESP_HOSTED_DIR}/host/port/esp/freertos/include"
)

# Early expansion (component_get_requirements) must not invoke zig — PATH differs from shell.
if(CMAKE_BUILD_EARLY_EXPANSION)
    return()
endif()

# UI tree selection — CONFIG_* available after early expansion.
if(CONFIG_MODULUS_ZIG_UI_ENGINE)
    message(STATUS "Modulus: Zig UI engine — omitting LVGL widget UI sources")
    target_sources(${COMPONENT_LIB} PRIVATE "ui_zig_stubs.c")
else()
    message(STATUS "Modulus: LVGL UI sources enabled (Zig scanout off)")
    target_sources(${COMPONENT_LIB} PRIVATE ${MODULUS_LVGL_UI_SRCS})
endif()

set(ZIG_EXE "$ENV{ZIG_EXE}")
if(NOT ZIG_EXE)
    find_program(ZIG_EXE zig)
endif()
if(NOT ZIG_EXE)
    message(FATAL_ERROR "zig not found — set ZIG_EXE or add Zig 0.16+ to PATH (scripts/build_tab5.ps1 sets ZIG_EXE)")
endif()

set(MODULUS_ZIG_CORE_LIB "${MODULUS_REPO_ROOT}/zig-out/lib/libmodulus_zig_core.a")
file(GLOB_RECURSE MODULUS_ZIG_SOURCES
    "${MODULUS_REPO_ROOT}/src/modulus/*.zig"
    "${MODULUS_REPO_ROOT}/build.zig"
)
add_custom_command(
    OUTPUT "${MODULUS_ZIG_CORE_LIB}"
    COMMAND "${ZIG_EXE}" build tab5-lib
    WORKING_DIRECTORY "${MODULUS_REPO_ROOT}"
    DEPENDS ${MODULUS_ZIG_SOURCES}
    COMMENT "Building Modulus Zig static library (tab5-lib)"
    VERBATIM
)

add_custom_target(modulus_zig_build DEPENDS "${MODULUS_ZIG_CORE_LIB}")

# Zig exports are referenced from C shims and from main via modulus_zig_boot.
# LINKER: options pass the .a path as its own argv so paths with spaces link on Windows.
add_dependencies(${COMPONENT_LIB} modulus_zig_build)
# Explicit file dependency so app relinks when libmodulus_zig_core.a changes.
set_property(TARGET ${COMPONENT_LIB} APPEND PROPERTY INTERFACE_LINK_DEPENDS "${MODULUS_ZIG_CORE_LIB}")
target_link_options(${COMPONENT_LIB} INTERFACE
    "LINKER:--whole-archive"
    "${MODULUS_ZIG_CORE_LIB}"
    "LINKER:--no-whole-archive")

set(BMI270_SENSOR_ROOT "${MODULUS_REPO_ROOT}/firmware/tab5/managed_components/espressif__bmi270_sensor")
set(BMI270_SENSOR_LIB "${BMI270_SENSOR_ROOT}/${IDF_VERSION_MAJOR}.${IDF_VERSION_MINOR}/${IDF_TARGET}/libbmi270_sensor.a")
if(NOT EXISTS "${BMI270_SENSOR_LIB}")
    foreach(_bmi_ver 5.5 5.4 5.3)
        set(_bmi_try "${BMI270_SENSOR_ROOT}/${_bmi_ver}/${IDF_TARGET}/libbmi270_sensor.a")
        if(EXISTS "${_bmi_try}")
            set(BMI270_SENSOR_LIB "${_bmi_try}")
            break()
        endif()
    endforeach()
endif()
if(EXISTS "${BMI270_SENSOR_LIB}")
    add_prebuilt_library(bmi270_sensor_api "${BMI270_SENSOR_LIB}")
    target_include_directories(bmi270_sensor_api INTERFACE
        "${BMI270_SENSOR_ROOT}/include"
        "${BMI270_SENSOR_ROOT}/firmware")
    target_link_libraries(${COMPONENT_LIB} PRIVATE bmi270_sensor_api)
else()
    message(WARNING "bmi270_sensor prebuilt missing — PMIC any-motion wake disabled")
endif()

# Link contract: WHOLE_ARCHIVE on this component (C shims) + SHELL whole-archive
# on libmodulus_zig_core.a (Zig exports). Do not revert to bare target_link_libraries
# or a hand-maintained -Wl,-u list — both drift and break silently.
