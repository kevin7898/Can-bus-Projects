idf_component_register(
    SRCS "main.c" "can.c" "mcp2518fd.c" "logger.c" "gps.c" "power.c" "net.c" "io.c"
    INCLUDE_DIRS "."
    REQUIRES esp_driver_twai esp_driver_spi esp_driver_sdspi esp_driver_i2c esp_driver_uart
             esp_driver_gpio esp_adc esp_wifi esp_netif esp_event esp_timer esp_ringbuf fatfs sdmmc nvs_flash lwip)
