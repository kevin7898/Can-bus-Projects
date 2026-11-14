// I2C peripherals: TCA9535 IO expander + PCF8523 RTC
#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <time.h>
#include "esp_err.h"
#include "board.h"

esp_err_t io_init(void);
esp_err_t xp_write(int bit, bool level);   // only bits in XP_OUTPUT_MASK
bool xp_read(int bit);
uint16_t xp_read_all(void);
cable_id_t io_cable_id(void);
bool io_ignition_on(void);
void io_led(int led_bit, bool on);          // XP_LED_*_N (active low)

esp_err_t rtc_get(time_t *t);               // ESP_ERR_INVALID_STATE if the RTC lost power
esp_err_t rtc_set(time_t t);

esp_err_t io_external_power_good(bool *good);
esp_err_t io_battery_mv(uint32_t *mv);
