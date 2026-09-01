# ESP-IDF 6.0.1+ ships esp_wifi/remote in-tree (weak API + injected headers).
# esp_hosted provides the strong RPC implementations. Managed registry
# esp_wifi_remote expects idf_v6.x weak sources that are not laid out the way
# that package expects — keep this no-op name placeholder instead.
# (BufferRoot/Modulus-Firmware#2 — reporter used 1.6.4; that fights in-tree remote here.)
if(EXISTS "$ENV{IDF_PATH}/components/esp_wifi/remote/Kconfig.wifi.in")
    idf_component_register()
    return()
endif()

message(WARNING "esp_wifi/remote missing from IDF — wifi_remote override is empty; add espressif/esp_wifi_remote from the registry")
idf_component_register()
