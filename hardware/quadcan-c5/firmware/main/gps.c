// u-blox NEO-M9N: UBX-NAV-PVT at up to 25 Hz on UART1, logged raw; also disciplines the RTC.
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include "app.h"
#include "driver/uart.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "io.h"

static const char *TAG = "gps";
#define GPS_UART UART_NUM_1
static TaskHandle_t s_task;

static void ubx_send(uint8_t cls, uint8_t id, const uint8_t *payload, uint16_t len)
{
    uint8_t hdr[6] = {0xB5, 0x62, cls, id, len & 0xFF, len >> 8};
    uint8_t a = 0, b = 0;
    for (int i = 2; i < 6; i++) { a += hdr[i]; b += a; }
    for (int i = 0; i < len; i++) { a += payload[i]; b += a; }
    uint8_t ck[2] = {a, b};
    uart_write_bytes(GPS_UART, hdr, 6);
    uart_write_bytes(GPS_UART, payload, len);
    uart_write_bytes(GPS_UART, ck, 2);
}

// UBX-CFG-VALSET (M9 configuration interface), RAM + BBR layers
static void valset(const uint32_t *keys, const uint32_t *vals, int n)
{
    uint8_t p[4 + 12 * 8];
    int o = 0;
    p[o++] = 0; p[o++] = 0x03; p[o++] = 0; p[o++] = 0;
    for (int i = 0; i < n; i++) {
        memcpy(p + o, &keys[i], 4); o += 4;
        int size = (keys[i] >> 28) & 0x7;           // 1 = bit, 2 = 1 B, 3 = 2 B, 4 = 4 B
        int bytes = size <= 2 ? 1 : size == 3 ? 2 : 4;
        memcpy(p + o, &vals[i], bytes); o += bytes;
    }
    ubx_send(0x06, 0x8A, p, o);
}

static void handle_pvt(const uint8_t *pl)
{
    log_push(QCL_REC_GPS, 0, 0, 0x0107, esp_timer_get_time(), pl, 92);
    uint8_t valid = pl[11], fix = pl[20], flags = pl[21];
    // valid date + time + fully resolved, and a 3D fix -> discipline system clock + RTC
    if ((valid & 0x07) == 0x07 && fix >= 3 && (flags & 1)) {
        struct tm tm = {
            .tm_year = (pl[4] | (pl[5] << 8)) - 1900, .tm_mon = pl[6] - 1, .tm_mday = pl[7],
            .tm_hour = pl[8], .tm_min = pl[9], .tm_sec = pl[10],
        };
        time_t t = mktime(&tm);      // TZ is UTC
        struct timeval now;
        gettimeofday(&now, NULL);
        if (llabs((long long)now.tv_sec - t) > 1) {
            int32_t nano = (int32_t)(pl[16] | (pl[17] << 8) | (pl[18] << 16) | ((uint32_t)pl[19] << 24));
            struct timeval tv = {.tv_sec = t, .tv_usec = nano / 1000};
            if (tv.tv_usec < 0) { tv.tv_sec--; tv.tv_usec += 1000000; }
            settimeofday(&tv, NULL);
            rtc_set(t);
            ESP_LOGI(TAG, "clock set from GPS");
        }
    }
}

static void gps_task(void *arg)
{
    uint8_t buf[256], msg[100];
    int st = 0, len = 0, pos = 0;
    uint8_t cls = 0, id = 0, ca = 0, cb = 0;
    for (;;) {
        int n = uart_read_bytes(GPS_UART, buf, sizeof(buf), pdMS_TO_TICKS(200));
        for (int i = 0; i < n; i++) {
            uint8_t c = buf[i];
            switch (st) {
            case 0: st = c == 0xB5; break;
            case 1: st = c == 0x62 ? 2 : 0; break;
            case 2: cls = c; ca = cb = 0; ca += c; cb += ca; st = 3; break;
            case 3: id = c; ca += c; cb += ca; st = 4; break;
            case 4: len = c; ca += c; cb += ca; st = 5; break;
            case 5: len |= c << 8; ca += c; cb += ca; pos = 0; st = len ? 6 : 7; break;
            case 6:
                if (pos < (int)sizeof(msg)) msg[pos] = c;
                pos++; ca += c; cb += ca;
                if (pos >= len) st = 7;
                break;
            case 7: st = c == ca ? 8 : 0; break;
            case 8:
                if (c == cb && cls == 0x01 && id == 0x07 && len == 92) handle_pvt(msg);
                st = 0;
                break;
            }
        }
    }
}

esp_err_t gps_start(void)
{
    if (!g_cfg.gps_enable) return ESP_OK;
    xp_write(XP_GPS_PWR_N, false);                  // power the module
    vTaskDelay(pdMS_TO_TICKS(300));
    uart_config_t uc = {.baud_rate = 38400, .data_bits = UART_DATA_8_BITS, .parity = UART_PARITY_DISABLE,
                        .stop_bits = UART_STOP_BITS_1, .flow_ctrl = UART_HW_FLOWCTRL_DISABLE, .source_clk = UART_SCLK_DEFAULT};
    ESP_ERROR_CHECK(uart_driver_install(GPS_UART, 4096, 0, 0, NULL, 0));
    uart_param_config(GPS_UART, &uc);
    uart_set_pin(GPS_UART, PIN_GPS_TX, PIN_GPS_RX, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);
    // factory default is 38400 baud -> switch to 230400
    const uint32_t k_baud[] = {0x40520001}, v_baud[] = {230400};
    valset(k_baud, v_baud, 1);
    uart_wait_tx_done(GPS_UART, pdMS_TO_TICKS(100));
    vTaskDelay(pdMS_TO_TICKS(100));
    uart_set_baudrate(GPS_UART, 230400);
    uint32_t meas_ms = 1000 / (g_cfg.gps_rate_hz ? g_cfg.gps_rate_hz : 1);
    if (meas_ms < 40) meas_ms = 40;                 // NEO-M9N max 25 Hz
    const uint32_t keys[] = {
        0x30210001,   // CFG-RATE-MEAS (ms)
        0x20910007,   // CFG-MSGOUT-UBX_NAV_PVT_UART1
        0x10740002,   // CFG-UART1OUTPROT-NMEA
        0x20110021,   // CFG-NAVSPG-DYNMODEL
    };
    const uint32_t vals[] = {meas_ms, 1, 0, 4 /* automotive */};
    valset(keys, vals, 4);
    xTaskCreate(gps_task, "gps", 4096, NULL, 8, &s_task);
    ESP_LOGI(TAG, "NEO-M9N at %lu Hz", (unsigned long)(1000 / meas_ms));
    return ESP_OK;
}

void gps_stop(void)
{
    if (s_task) vTaskDelete(s_task);
    s_task = NULL;
    uart_driver_delete(GPS_UART);
    gpio_set_direction(PIN_GPS_TX, GPIO_MODE_INPUT);   // don't back-power the unpowered module
    xp_write(XP_GPS_PWR_N, true);
}
