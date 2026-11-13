// QuadCAN-C5 firmware entry point.
//
// Boot order matters for the bus-safety story: the IO expander is set up first so the
// transceiver STB lines are held high (standby) until each channel is deliberately opened,
// and every channel opens listen-only unless /sd/quadcan.cfg says otherwise.
#include "app.h"
#include "esp_log.h"
#include "esp_sleep.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "io.h"
#include "nvs_flash.h"
#include <sys/time.h>
#include <time.h>

static const char *TAG = "quadcan";

void app_main(void)
{
    power_early_wake_check();          // timer wake with the vehicle still asleep -> back to sleep
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        nvs_flash_erase();
        nvs_flash_init();
    }
    setenv("TZ", "UTC0", 1);
    tzset();
    io_init();

    // wall clock from the RTC (GPS refines it later)
    time_t t;
    if (rtc_get(&t) == ESP_OK && t > 1700000000) {
        struct timeval tv = {.tv_sec = t};
        settimeofday(&tv, NULL);
    } else {
        ESP_LOGW(TAG, "RTC not set - files get sequential names until GPS/phone sets the time");
    }

    cable_id_t cable = io_cable_id();
    static const char *names[] = {"custom", "J1939", "OBD-II", "none"};
    ESP_LOGI(TAG, "cable: %s, ignition %s, wake cause %d", names[cable], io_ignition_on() ? "on" : "off",
             (int)esp_sleep_get_wakeup_cause());

    cfg_defaults(cable);
    if (logger_init() == ESP_OK) cfg_load("/sd/quadcan.cfg");
    logger_start(cable);
    power_task_start();
    can_start();
    gps_start();
    net_start();
}
