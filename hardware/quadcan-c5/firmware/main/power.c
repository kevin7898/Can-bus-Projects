// VIN monitor, power-fail shutdown, idle sleep, MARK button, status LED, periodic status records.
#include "app.h"
#include "esp_adc/adc_cali.h"
#include "esp_adc/adc_cali_scheme.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_log.h"
#include "esp_sleep.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "io.h"

static const char *TAG = "power";

#define VIN_FAIL_V   6.0f    // below this (after being above VIN_OK_V) -> close files, wait on hold-up
#define VIN_OK_V     8.0f
#define VIN_USB_V    5.5f    // below this from boot = bench / USB-only power

static adc_oneshot_unit_handle_t s_adc;
static adc_cali_handle_t s_cali;
static adc_channel_t s_chan;

static float vin_read(void)
{
    int raw = 0, mv = 0;
    adc_oneshot_read(s_adc, s_chan, &raw);
    if (s_cali && adc_cali_raw_to_voltage(s_cali, raw, &mv) == ESP_OK) {
        return mv / 1000.0f * VIN_DIVIDER + VIN_DIODE_DROP_V;
    }
    return raw * 3.3f / 4095.0f * VIN_DIVIDER + VIN_DIODE_DROP_V;
}

static void enter_sleep(void)
{
    ESP_LOGW(TAG, "bus idle and ignition off -> sleeping");
    logger_shutdown();
    can_stop();               // transceivers to standby (CAN1 still reports wake-up on RXD)
    gps_stop();
    xp_write(XP_OSC_EN, false);
    for (int b = XP_LED_STAT_N; b <= XP_LED_LINK_N; b++) xp_write(b, true);
    // wake on CAN1 bus activity (TCAN1044 pulls RXD low on a wake-up pattern) or every 15 min
    esp_sleep_enable_ext1_wakeup_io(1ULL << PIN_CAN1_RX, ESP_EXT1_WAKEUP_ANY_LOW);
    esp_sleep_enable_timer_wakeup(15ULL * 60 * 1000000);
    esp_deep_sleep_start();
}

static void power_task(void *arg)
{
    bool armed = false, failed = false, mark_prev = false;
    int low = 0;
    int64_t last_status = 0, boot = esp_timer_get_time();
    float vin = vin_read();
    for (int tick = 0;; tick++) {
        vin = 0.8f * vin + 0.2f * vin_read();
        if (vin > VIN_OK_V) armed = true;
        if (armed && !failed) {
            low = vin < VIN_FAIL_V ? low + 1 : 0;
            if (low >= 4) {                     // ~20 ms below threshold
                failed = true;
                ESP_LOGW(TAG, "power fail (VIN %.1f V) - closing log on hold-up energy", vin);
                logger_shutdown();
                can_stop();
                gps_stop();
            }
        }
        if (failed && vin > VIN_OK_V) {
            ESP_LOGW(TAG, "power back - restarting");
            esp_restart();
        }
        int64_t now = esp_timer_get_time();
        if (tick % 10 == 0) {                   // 50 ms: button + LEDs
            bool mark = !xp_read(XP_BTN_MARK_N);
            if (mark && !mark_prev) {
                log_push(QCL_REC_MARK, 0, 0, 0, now, NULL, 0);
                ESP_LOGI(TAG, "MARK");
            }
            mark_prev = mark;
            io_led(XP_LED_STAT_N, failed ? false : ((now / 100000) % (logger_card_ok() ? 10 : 3)) == 0);
        }
        if (now - last_status > 10000000 && !failed) {
            last_status = now;
            qcl_status_t st = {.vin_mv = (uint16_t)(vin * 1000), .ign = io_ignition_on(), .dropped = logger_dropped()};
            for (int i = 0; i < NUM_CAN; i++) st.frames[i] = can_frames(i);
            log_push(QCL_REC_STATUS, 0, 0, 0, now, &st, sizeof(st));
            // idle sleep: no frames for idle_sleep_min, ignition off, on vehicle power
            int64_t idle = now - (can_last_rx_us() ? can_last_rx_us() : boot);
            if (g_cfg.idle_sleep_min && armed && !io_ignition_on() &&
                idle > (int64_t)g_cfg.idle_sleep_min * 60 * 1000000) {
                enter_sleep();
            }
        }
        vTaskDelay(pdMS_TO_TICKS(5));
    }
}

void power_task_start(void)
{
    adc_unit_t unit;
    ESP_ERROR_CHECK(adc_oneshot_io_to_channel(PIN_VIN_SENSE, &unit, &s_chan));
    adc_oneshot_unit_init_cfg_t ucfg = {.unit_id = unit};
    ESP_ERROR_CHECK(adc_oneshot_new_unit(&ucfg, &s_adc));
    adc_oneshot_chan_cfg_t ccfg = {.atten = ADC_ATTEN_DB_12, .bitwidth = ADC_BITWIDTH_DEFAULT};
    ESP_ERROR_CHECK(adc_oneshot_config_channel(s_adc, s_chan, &ccfg));
#if ADC_CALI_SCHEME_CURVE_FITTING_SUPPORTED
    adc_cali_curve_fitting_config_t cc = {.unit_id = unit, .chan = s_chan, .atten = ADC_ATTEN_DB_12, .bitwidth = ADC_BITWIDTH_DEFAULT};
    if (adc_cali_create_scheme_curve_fitting(&cc, &s_cali) != ESP_OK) s_cali = NULL;
#endif
    float v = vin_read();
    ESP_LOGI(TAG, "VIN %.2f V%s", v, v < VIN_USB_V ? " (USB / bench power)" : "");
    xTaskCreate(power_task, "power", 4096, NULL, 15, NULL);
}
