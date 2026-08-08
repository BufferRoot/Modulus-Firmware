if(NOT DEFINED MODULUS_REPO_ROOT OR "${MODULUS_REPO_ROOT}" STREQUAL "")
    if(DEFINED ENV{MODULUS_REPO_ROOT} AND NOT "$ENV{MODULUS_REPO_ROOT}" STREQUAL "")
        file(TO_CMAKE_PATH "$ENV{MODULUS_REPO_ROOT}" MODULUS_REPO_ROOT)
    else()
        get_filename_component(MODULUS_REPO_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
    endif()
endif()

set(MODULUS_ZIG_C6_SRC "${MODULUS_REPO_ROOT}/src/modulus/main_c6.zig")
set(MODULUS_ZIG_C6_OBJ "${CMAKE_CURRENT_BINARY_DIR}/modulus_main_c6.o")

file(GLOB_RECURSE MODULUS_ZIG_C6_SOURCES "${MODULUS_REPO_ROOT}/src/modulus/*.zig")

find_program(ZIG_EXECUTABLE zig)

if(CONFIG_MODULUS_ZIG_C6_RUNTIME AND NOT ZIG_EXECUTABLE)
    message(FATAL_ERROR "CONFIG_MODULUS_ZIG_C6_RUNTIME is enabled but zig was not found in PATH")
endif()

if(ZIG_EXECUTABLE AND CONFIG_MODULUS_ZIG_C6_RUNTIME)
    add_custom_command(
        OUTPUT ${MODULUS_ZIG_C6_OBJ}
        COMMAND ${ZIG_EXECUTABLE} build-obj ${MODULUS_ZIG_C6_SRC}
            -target riscv32-freestanding-none
            -mcpu generic_rv32+m+a+c
            -OReleaseSafe
            -femit-bin=${MODULUS_ZIG_C6_OBJ}
        DEPENDS ${MODULUS_ZIG_C6_SOURCES}
        COMMENT "Building Modulus C6 Zig object (main_c6.zig -> riscv32 freestanding)"
        VERBATIM
    )

    add_custom_target(modulus_zig_c6_obj DEPENDS ${MODULUS_ZIG_C6_OBJ})

    set(MODULUS_ZIG_C6_REQUIRES freertos bt esp_wifi openthread)
    if(CONFIG_MODULUS_C6_ZIGBEE_EXCLUSIVE)
        list(APPEND MODULUS_ZIG_C6_REQUIRES esp-zigbee-lib)
    endif()

    idf_component_register(
        SRCS "shim.c" "modulus_bridge_c6.c" "modulus_c6_ble.c" "modulus_c6_espnow.c" "modulus_c6_thread.c" "modulus_c6_zigbee.c" "modulus_c6_hosted_hook.c"
        INCLUDE_DIRS "include"
        REQUIRES ${MODULUS_ZIG_C6_REQUIRES}
    )

    add_dependencies(${COMPONENT_LIB} modulus_zig_c6_obj)
    target_link_libraries(${COMPONENT_LIB} INTERFACE ${MODULUS_ZIG_C6_OBJ})
else()
    set(MODULUS_ZIG_C6_REQUIRES freertos bt esp_wifi openthread)
    if(CONFIG_MODULUS_C6_ZIGBEE_EXCLUSIVE)
        list(APPEND MODULUS_ZIG_C6_REQUIRES esp-zigbee-lib)
    endif()

    idf_component_register(
        SRCS "shim.c" "modulus_bridge_c6.c" "modulus_c6_ble.c" "modulus_c6_espnow.c" "modulus_c6_thread.c" "modulus_c6_zigbee.c" "modulus_c6_hosted_hook.c"
        INCLUDE_DIRS "include"
        REQUIRES ${MODULUS_ZIG_C6_REQUIRES}
    )
endif()
