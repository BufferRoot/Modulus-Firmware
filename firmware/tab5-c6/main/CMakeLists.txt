if(IS_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}/common")
    get_filename_component(common_dir "${CMAKE_CURRENT_LIST_DIR}/common" ABSOLUTE)
else()
    get_filename_component(common_dir "${CMAKE_CURRENT_LIST_DIR}/../common" ABSOLUTE)
endif()

set(srcs
    "espnow_handler.c"
    "zigbee_handler.c"
    "thread_handler.c"
    "slave_control.c"
    "${common_dir}/proto/esp_hosted_rpc.pb-c.c"
    "${common_dir}/utils/esp_hosted_cli.c"
    "protocomm_pserial.c"
    "esp_hosted_coprocessor.c"
    "mempool.c"
    "stats.c"
    "mempool_ll.c"
    "host_power_save.c"
    "slave_light_sleep.c"
    "nw_split_router.c"
    "transport_gpio_pin_guard.c"
)

if(CONFIG_SOC_BT_SUPPORTED)
    list(APPEND srcs "slave_bt.c")
    if(CONFIG_IDF_TARGET_ESP32)
        list(APPEND srcs slave_bt_uart_esp32.c)
    elseif(CONFIG_IDF_TARGET_ESP32C3 OR CONFIG_IDF_TARGET_ESP32S3)
        list(APPEND srcs slave_bt_uart_esp32c3_s3.c)
    else()
        list(APPEND srcs slave_bt_uart_esp32xx.c)
    endif()
endif()

if(CONFIG_ESP_SDIO_HOST_INTERFACE)
    list(APPEND srcs sdio_slave_api.c)
elseif(CONFIG_ESP_SPI_HOST_INTERFACE)
    list(APPEND srcs spi_slave_api.c)
elseif(CONFIG_ESP_SPI_HD_MODE)
    list(APPEND srcs spi_hd_slave_api.c)
else()
    list(APPEND srcs uart_slave_api.c)
endif()

if(CONFIG_ESP_HOSTED_ENABLE_PEER_DATA_TRANSFER)
    list(APPEND srcs example_peer_data_transfer.c)
endif()

if(CONFIG_ESP_HOSTED_COPROCESSOR_EXAMPLE_LIGHT_SLEEP)
    list(APPEND srcs example_light_sleep.c)
endif()

if(CONFIG_ESP_HOSTED_COPROCESSOR_EXAMPLE_MQTT)
    list(APPEND srcs example_mqtt_client.c)
endif()

if(CONFIG_ESP_HOSTED_COPROCESSOR_EXAMPLE_HTTP_CLIENT)
    list(APPEND srcs example_http_client.c)
endif()

idf_component_register(
    SRCS ${srcs}
    INCLUDE_DIRS
        "."
        "${common_dir}"
        "${common_dir}/log"
        "${common_dir}/proto"
        "${common_dir}/rpc"
        "${common_dir}/transport"
        "${common_dir}/utils"
    PRIV_REQUIRES openthread esp_event vfs ieee802154 esp_driver_sdio esp_driver_gpio
                  esp_driver_uart esp_driver_spi esp_hal_sd esp_wifi protocomm bt nvs_flash
                  esp_timer esp_netif console protobuf-c app_update wpa_supplicant heap esp_hw_support mqtt
)

idf_component_get_property(protocomm_dir protocomm COMPONENT_DIR)
target_include_directories(${COMPONENT_LIB} PRIVATE "${protocomm_dir}/src/common")
target_link_libraries(${COMPONENT_LIB} INTERFACE "-Wl,--wrap=esp_wifi_init")
