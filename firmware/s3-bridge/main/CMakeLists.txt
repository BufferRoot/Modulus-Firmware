idf_component_register(
    SRCS
        "main.cpp"
        "espnow_link.cpp"
        "uart_bridge.cpp"
        "halt_gpio.cpp"
    INCLUDE_DIRS "."
    REQUIRES
        nvs_flash
        esp_wifi
        esp_event
        esp_netif
        esp_timer
        esp_driver_uart
        esp_driver_gpio
        freertos
        log
)
