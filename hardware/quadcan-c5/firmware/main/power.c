// VIN monitor, power-fail shutdown, idle sleep, MARK button, status LED, periodic status records.
#include "app.h"
#include "esp_adc/adc_cali.h"
#include "esp_adc/adc_cali_scheme.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_log.h"
#include "esp_sleep.h"
#include "esp_system.h"
#include "driver/gpio.h"
#include "esp_attr.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "io.h"
#include "power_policy.h"

static const char *TAG = "power";

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

// ---------------------------------------------------------------- key-off sleep
// What stays powered in sleep: the 5 V buck, the 3.3 V LDO, four transceivers in standby
// (each still watches its bus), the IO expander holding its outputs, the RTC, and the ESP32 in
// deep sleep. Switched off: SD card, GPS, 40 MHz oscillator, MCP2518FD (sleep mode), LEDs, radio.
//
// Wake sources:
//   1. activity on any of the four CAN buses  (PIN_CAN1_RX, PIN_CAN2_RX, PIN_WAKE_N)
//   2. the ignition wire, if the cable has one (PIN_WAKE_N)
//   3. battery voltage above wake_vin_mv = engine running (sampled every sleep_check_s)
// Source 3 needs nothing but the two power pins of the OBD plug, which matters on cars whose
// diagnostic CAN is silent until a tester talks (VW MQB and others).
static RTC_DATA_ATTR uint32_t s_rtc_wake_mv;      // survives deep sleep
static RTC_DATA_ATTR uint32_t s_rtc_check_s;
static RTC_DATA_ATTR bool s_backup_sleep;

static void arm_and_sleep(void)
{
    if (s_backup_sleep) {
        // Ignore CAN while saving the backup cell; restart on vehicle input restoration.
        esp_sleep_enable_timer_wakeup(5000000ULL);
        esp_deep_sleep_start();
    }
    esp_sleep_enable_ext1_wakeup_io(WAKE_PIN_MASK, ESP_EXT1_WAKEUP_ANY_LOW);
    if (s_rtc_wake_mv) esp_sleep_enable_timer_wakeup((uint64_t)(s_rtc_check_s ? s_rtc_check_s : 30) * 1000000ULL);
    esp_deep_sleep_start();
}

static void enter_sleep(float vin)
{
    ESP_LOGW(TAG, "key off (buses idle, no ignition, %.1f V) -> sleeping", vin);
    s_backup_sleep = false;
    can_stop();               // controllers off, all four transceivers to standby
    gps_stop();               // GPS rail off
    net_stop();
    logger_shutdown();        // producers stopped; flush, close, unmount, SD power off
    xp_write(XP_OSC_EN, false);
    for (int b = XP_LED_STAT_N; b <= XP_LED_LINK_N; b++) xp_write(b, true);
    // 24 V vehicles charge at ~27-28 V: scale the engine-running threshold
    s_rtc_wake_mv = g_cfg.wake_vin_mv * (vin > 18.0f ? 2 : 1);
    s_rtc_check_s = g_cfg.sleep_check_s;
    arm_and_sleep();
}

void power_early_wake_check(void)
{
    // Only shortcut a timer-only wake. A simultaneous CAN/ignition wake must boot.
    if (esp_sleep_get_wakeup_causes() != (1UL << ESP_SLEEP_WAKEUP_TIMER)) return;
    gpio_config_t io = {.pin_bit_mask = WAKE_PIN_MASK, .mode = GPIO_MODE_INPUT};
    gpio_config(&io);
    bool line_low = !gpio_get_level(PIN_CAN1_RX) || !gpio_get_level(PIN_CAN2_RX) || !gpio_get_level(PIN_WAKE_N);
    adc_unit_t unit;
    adc_channel_t ch;
    adc_oneshot_unit_handle_t adc;
    adc_oneshot_io_to_channel(PIN_VIN_SENSE, &unit, &ch);
    adc_oneshot_unit_init_cfg_t ucfg = {.unit_id = unit};
    adc_oneshot_new_unit(&ucfg, &adc);
    adc_oneshot_chan_cfg_t ccfg = {.atten = ADC_ATTEN_DB_12, .bitwidth = ADC_BITWIDTH_DEFAULT};
    adc_oneshot_config_channel(adc, ch, &ccfg);
    int sum = 0, raw = 0;
    for (int i = 0; i < 8; i++) { adc_oneshot_read(adc, ch, &raw); sum += raw; }
    adc_oneshot_del_unit(adc);
    uint32_t vin_mv = (uint32_t)((sum / 8.0f) * 3300.0f / 4095.0f * VIN_DIVIDER + VIN_DIODE_DROP_V * 1000.0f);
    if (s_backup_sleep) {
        if (vin_mv >= 8000) { s_backup_sleep = false; return; }
        arm_and_sleep();
    }
    if (line_low || (s_rtc_wake_mv && vin_mv >= s_rtc_wake_mv)) return;   // vehicle is awake: boot
    arm_and_sleep();                                                       // still parked
}

static void backup_shutdown(void)
{
    ESP_LOGW(TAG, "backup timeout or low cell: stop producers, flush log, sleep");
    net_stop();
    can_stop();
    gps_stop();
    xp_write(XP_OSC_EN, false);
    logger_shutdown();
    for (int b = XP_LED_STAT_N; b <= XP_LED_LINK_N; b++) xp_write(b, true);
    s_backup_sleep = true;
    arm_and_sleep();
}

static void power_task(void *arg)
{
    bool armed = false, mark_prev = false, external_good = false;
    backup_policy_t backup = {0};
    int64_t last_power = esp_timer_get_time();
    int64_t last_status = 0, boot = esp_timer_get_time();
    float vin = vin_read();
    for (int tick = 0;; tick++) {
        vin = 0.8f * vin + 0.2f * vin_read();
        if (vin > VIN_OK_V) armed = true;
        int64_t now = esp_timer_get_time();
        if (now - last_power >= 100000) {
            uint32_t elapsed_ms = (uint32_t)((now - last_power) / 1000);
            last_power = now;
            uint32_t battery_mv = 0;
            io_external_power_good(&external_good); // read error becomes "absent"
            bool battery_valid = io_battery_mv(&battery_mv) == ESP_OK;
            if (backup_policy_step(&backup, external_good, battery_valid, battery_mv, elapsed_ms))
                backup_shutdown();
        }
        if (tick % 10 == 0) {                   // 50 ms: button + LEDs
            bool mark = !xp_read(XP_BTN_MARK_N);
            if (mark && !mark_prev) {
                log_push(QCL_REC_MARK, 0, 0, 0, now, NULL, 0);
                ESP_LOGI(TAG, "MARK");
            }
            mark_prev = mark;
            io_led(XP_LED_STAT_N, ((now / 100000) % (logger_card_ok() ? 10 : 3)) == 0);
        }
        if (now - last_status > 10000000) {
            last_status = now;
            qcl_status_t st = {.vin_mv = (uint16_t)(vin * 1000), .ign = io_ignition_on(), .dropped = logger_dropped()};
            for (int i = 0; i < NUM_CAN; i++) st.frames[i] = can_frames(i);
            log_push(QCL_REC_STATUS, 0, 0, 0, now, &st, sizeof(st));
            // idle sleep: no frames for idle_sleep_min, ignition off, on vehicle power
            int64_t idle = now - (can_last_rx_us() ? can_last_rx_us() : boot);
            bool engine = g_cfg.wake_vin_mv && vin * 1000.0f >= g_cfg.wake_vin_mv * (vin > 18.0f ? 2 : 1);
            if (g_cfg.idle_sleep_min && armed && external_good && !io_ignition_on() && !engine &&
                idle > (int64_t)g_cfg.idle_sleep_min * 60 * 1000000) {
                enter_sleep(vin);
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
