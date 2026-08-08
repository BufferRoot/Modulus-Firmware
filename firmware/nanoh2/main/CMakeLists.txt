idf_component_register(
    SRCS "main.c" "zb_uart_link.c" "zigbee_hub.c"
    INCLUDE_DIRS "."
    REQUIRES esp_driver_gpio esp_driver_uart esp_timer nvs_flash
)
