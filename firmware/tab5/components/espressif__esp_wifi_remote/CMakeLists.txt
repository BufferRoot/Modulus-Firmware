# ESP-IDF 6+ provides esp_wifi/remote in-tree (CONFIG_ESP_WIFI_REMOTE_IN_IDF).
# Managed esp_wifi_remote would reference missing idf_v6.x/esp_wifi_remote_weak.c.
if(EXISTS "$ENV{IDF_PATH}/components/esp_wifi/remote/Kconfig.wifi.in")
    idf_component_register()
    return()
endif()

idf_component_register()
