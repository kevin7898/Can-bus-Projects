#include "io.h"

#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "driver/i2c_master.h"
#include "esp_log.h"

static const char *TAG = "io";
static i2c_master_bus_handle_t s_bus;
static i2c_master_dev_handle_t s_xp, s_rtc, s_power, s_bat_adc;
static SemaphoreHandle_t s_xp_lock;
static uint16_t s_out = 0xFFFF;      // output latch shadow

// TCA9535 registers
#define TCA_IN0 0x00
#define TCA_OUT0 0x02
#define TCA_CFG0 0x06

static esp_err_t tca_w16(uint8_t reg, uint16_t v)
{
    uint8_t b[3] = {reg, v & 0xFF, v >> 8};
    return i2c_master_transmit(s_xp, b, 3, 50);
}

esp_err_t io_init(void)
{
    i2c_master_bus_config_t bus = {
        .i2c_port = 0,
        .sda_io_num = PIN_I2C_SDA,
        .scl_io_num = PIN_I2C_SCL,
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .glitch_ignore_cnt = 7,
        .flags.enable_internal_pullup = false,   // 4.7k on the board
    };
    ESP_ERROR_CHECK(i2c_new_master_bus(&bus, &s_bus));
    i2c_device_config_t xp = {.dev_addr_length = I2C_ADDR_BIT_LEN_7, .device_address = I2C_ADDR_EXPANDER, .scl_speed_hz = 400000};
    i2c_device_config_t rtc = {.dev_addr_length = I2C_ADDR_BIT_LEN_7, .device_address = I2C_ADDR_RTC, .scl_speed_hz = 400000};
    ESP_ERROR_CHECK(i2c_master_bus_add_device(s_bus, &xp, &s_xp));
    ESP_ERROR_CHECK(i2c_master_bus_add_device(s_bus, &rtc, &s_rtc));

    s_xp_lock = xSemaphoreCreateMutex();
    if (!s_xp_lock) return ESP_ERR_NO_MEM;
    i2c_device_config_t power = {.dev_addr_length = I2C_ADDR_BIT_LEN_7, .device_address = I2C_ADDR_POWER, .scl_speed_hz = 400000};
    i2c_device_config_t adc = {.dev_addr_length = I2C_ADDR_BIT_LEN_7, .device_address = I2C_ADDR_BAT_ADC, .scl_speed_hz = 400000};
    ESP_ERROR_CHECK(i2c_master_bus_add_device(s_bus, &power, &s_power));
    ESP_ERROR_CHECK(i2c_master_bus_add_device(s_bus, &adc, &s_bat_adc));
    // U17 MUST remain input-only: spare pins are grounded on the PCB.
    uint8_t inputs[] = {TCA_CFG0, 0xff, 0xff};
    if (i2c_master_transmit(s_power, inputs, sizeof(inputs), 50) != ESP_OK)
        ESP_LOGW(TAG, "power status expander unavailable; assume backup power");
    // ADS1115: AIN0/GND, +/-4.096V, continuous, 128 SPS, comparator disabled.
    uint8_t cfg[] = {0x01, 0xc2, 0x83};
    if (i2c_master_transmit(s_bat_adc, cfg, sizeof(cfg), 50) != ESP_OK)
        ESP_LOGW(TAG, "battery ADC unavailable; backup timeout still enforced");
    vTaskDelay(pdMS_TO_TICKS(10));

    // Output latch first (so pins come up in a safe state), then direction.
    // STB high = transceivers stay in standby; GPS power off (PWR_N high); oscillator on; LEDs off.
    s_out = 0xFFFF & ~(1u << XP_LTE_PWRKEY);
    esp_err_t err = tca_w16(TCA_OUT0, s_out);
    if (err == ESP_OK) err = tca_w16(TCA_CFG0, (uint16_t)~XP_OUTPUT_MASK);
    if (err != ESP_OK) ESP_LOGE(TAG, "TCA9535 not responding");

    // PCF8523: battery switch-over on (Control_3 PM = 000), 7 pF crystal load (CAP_SEL = 0)
    uint8_t c3[2] = {0x02, 0x00};
    if (i2c_master_transmit(s_rtc, c3, 2, 50) != ESP_OK) ESP_LOGW(TAG, "PCF8523 not responding");
    return err;
}

esp_err_t xp_write(int bit, bool level)
{
    if (!(XP_OUTPUT_MASK & (1u << bit))) return ESP_ERR_INVALID_ARG;
    xSemaphoreTake(s_xp_lock, portMAX_DELAY);
    uint16_t next = level ? s_out | (1u << bit) : s_out & ~(1u << bit);
    esp_err_t err = tca_w16(TCA_OUT0, next);
    if (err == ESP_OK) s_out = next;
    xSemaphoreGive(s_xp_lock);
    return err;
}

uint16_t xp_read_all(void)
{
    uint8_t reg = TCA_IN0, b[2] = {0xFF, 0xFF};
    i2c_master_transmit_receive(s_xp, &reg, 1, b, 2, 50);
    return b[0] | (b[1] << 8);
}

bool xp_read(int bit) { return (xp_read_all() >> bit) & 1; }

cable_id_t io_cable_id(void)
{
    uint16_t v = xp_read_all();
    return (cable_id_t)((((v >> XP_CABLE_ID1) & 1) << 1) | ((v >> XP_CABLE_ID0) & 1));
}

bool io_ignition_on(void) { return !xp_read(XP_IGN_N); }

void io_led(int led_bit, bool on) { xp_write(led_bit, !on); }

static uint8_t bcd2bin(uint8_t v) { return (v & 0x0F) + 10 * (v >> 4); }
static uint8_t bin2bcd(uint8_t v) { return (uint8_t)(((v / 10) << 4) | (v % 10)); }

esp_err_t rtc_get(time_t *t)
{
    uint8_t reg = 0x03, b[7];
    esp_err_t err = i2c_master_transmit_receive(s_rtc, &reg, 1, b, 7, 50);
    if (err != ESP_OK) return err;
    if (b[0] & 0x80) return ESP_ERR_INVALID_STATE;          // OS flag: clock integrity lost
    struct tm tm = {
        .tm_sec = bcd2bin(b[0] & 0x7F), .tm_min = bcd2bin(b[1] & 0x7F), .tm_hour = bcd2bin(b[2] & 0x3F),
        .tm_mday = bcd2bin(b[3] & 0x3F), .tm_mon = bcd2bin(b[5] & 0x1F) - 1, .tm_year = bcd2bin(b[6]) + 100,
    };
    setenv("TZ", "UTC0", 1);
    tzset();
    *t = mktime(&tm);
    return ESP_OK;
}

esp_err_t rtc_set(time_t t)
{
    struct tm tm;
    gmtime_r(&t, &tm);
    uint8_t b[8] = {0x03, bin2bcd(tm.tm_sec), bin2bcd(tm.tm_min), bin2bcd(tm.tm_hour), bin2bcd(tm.tm_mday),
                    (uint8_t)tm.tm_wday, bin2bcd(tm.tm_mon + 1), bin2bcd(tm.tm_year - 100)};
    return i2c_master_transmit(s_rtc, b, sizeof(b), 50);
}

// No fabricated "good" reading on an I2C error.
esp_err_t io_external_power_good(bool *good)
{
    uint8_t reg = TCA_IN0, b[2];
    esp_err_t err = i2c_master_transmit_receive(s_power, &reg, 1, b, 2, 50);
    *good = err == ESP_OK && !(b[0] & 1);
    return err;
}

esp_err_t io_battery_mv(uint32_t *mv)
{
    uint8_t reg = 0, b[2];
    esp_err_t err = i2c_master_transmit_receive(s_bat_adc, &reg, 1, b, 2, 50);
    if (err != ESP_OK) return err;
    int16_t raw = (int16_t)((b[0] << 8) | b[1]);
    if (raw <= 0) return ESP_ERR_INVALID_RESPONSE;
    *mv = (uint32_t)raw * 125u * 133u / 33000u; // 125uV/LSB, 100k/33k divider
    return ESP_OK;
}
