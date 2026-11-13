// SD-card logger: ISR/task producers -> PSRAM ring buffer -> 64 KB write batches -> FAT file.
#include <dirent.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <time.h>
#include "app.h"
#include "driver/sdspi_host.h"
#include "driver/spi_master.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_vfs_fat.h"
#include "freertos/FreeRTOS.h"
#include "freertos/ringbuf.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "io.h"
#include "sdmmc_cmd.h"

static const char *TAG = "logger";
#define MOUNT "/sd"
#define LOG_DIR MOUNT "/LOGS"
#define RB_SIZE (2 * 1024 * 1024)       // ~25 s of four saturated 500 kbit/s buses
#define WBUF_SIZE (64 * 1024)

static RingbufHandle_t s_rb;
static sdmmc_card_t *s_card;
static volatile uint32_t s_dropped;
static volatile bool s_stop;
static bool s_card_ok;
static log_tap_fn s_tap;
static SemaphoreHandle_t s_closed;
static cable_id_t s_cable;

uint32_t logger_dropped(void) { return s_dropped; }
bool logger_card_ok(void) { return s_card_ok; }
const char *logger_dir(void) { return LOG_DIR; }
void logger_set_tap(log_tap_fn fn) { s_tap = fn; }

esp_err_t logger_init(void)
{
    spi_bus_config_t bus = {
        .mosi_io_num = PIN_SPI_MOSI, .miso_io_num = PIN_SPI_MISO, .sclk_io_num = PIN_SPI_SCK,
        .quadwp_io_num = -1, .quadhd_io_num = -1, .max_transfer_sz = 16 * 1024,
    };
    ESP_ERROR_CHECK(spi_bus_initialize(SPI2_HOST, &bus, SPI_DMA_CH_AUTO));
    s_rb = xRingbufferCreateWithCaps(RB_SIZE, RINGBUF_TYPE_NOSPLIT, MALLOC_CAP_SPIRAM);
    s_closed = xSemaphoreCreateBinary();
    if (xp_read(XP_SD_DET)) {
        ESP_LOGW(TAG, "no microSD card detected");
        return ESP_ERR_NOT_FOUND;
    }
    xp_write(XP_SD_PWR_N, false);              // switch the card's 3.3 V rail on
    vTaskDelay(pdMS_TO_TICKS(100));
    sdmmc_host_t host = SDSPI_HOST_DEFAULT();
    host.slot = SPI2_HOST;
    host.max_freq_khz = 20000;
    sdspi_device_config_t slot = SDSPI_DEVICE_CONFIG_DEFAULT();
    slot.gpio_cs = PIN_SD_CS;
    slot.host_id = SPI2_HOST;
    esp_vfs_fat_sdmmc_mount_config_t mcfg = {
        .format_if_mount_failed = false, .max_files = 4, .allocation_unit_size = 32 * 1024,
    };
    esp_err_t err = esp_vfs_fat_sdspi_mount(MOUNT, &host, &slot, &mcfg, &s_card);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "mount failed: %s", esp_err_to_name(err));
        return err;
    }
    mkdir(LOG_DIR, 0775);
    s_card_ok = true;
    return ESP_OK;
}

static bool push(bool isr, uint8_t type, uint8_t chan, uint8_t flags, uint32_t id, int64_t ts, const void *data, uint8_t len)
{
    if (!s_rb || s_stop) return false;
    uint8_t buf[sizeof(qcl_rec_t) + 96];
    if (len > 92) len = 92;
    qcl_rec_t *r = (qcl_rec_t *)buf;
    r->ts_us = (uint64_t)ts;
    r->type = type;
    r->chan = chan;
    r->flags = flags;
    r->len = len;
    r->id = id;
    if (len) memcpy(buf + sizeof(*r), data, len);
    size_t sz = qcl_rec_size(len);
    BaseType_t woken = pdFALSE;
    BaseType_t ok = isr ? xRingbufferSendFromISR(s_rb, buf, sz, &woken) : xRingbufferSend(s_rb, buf, sz, 0);
    if (ok != pdTRUE) s_dropped++;
    return woken == pdTRUE;
}

bool log_push(uint8_t type, uint8_t chan, uint8_t flags, uint32_t id, int64_t ts, const void *d, uint8_t len)
{
    return push(false, type, chan, flags, id, ts, d, len);
}

bool IRAM_ATTR log_push_isr(uint8_t type, uint8_t chan, uint8_t flags, uint32_t id, int64_t ts, const void *d, uint8_t len)
{
    return push(true, type, chan, flags, id, ts, d, len);
}

static FILE *open_new_file(size_t *written)
{
    char name[96];
    time_t now = time(NULL);
    if (now > 1700000000) {
        struct tm tm;
        gmtime_r(&now, &tm);
        strftime(name, sizeof(name), LOG_DIR "/%Y%m%d_%H%M%S.qcl", &tm);
    } else {
        // no wall clock yet: sequential names
        int max = 0;
        DIR *d = opendir(LOG_DIR);
        struct dirent *e;
        while (d && (e = readdir(d))) {
            int n;
            if (sscanf(e->d_name, "N%06d", &n) == 1 && n > max) max = n;
        }
        if (d) closedir(d);
        snprintf(name, sizeof(name), LOG_DIR "/N%06d.qcl", max + 1);
    }
    FILE *f = fopen(name, "wb");
    if (!f) {
        ESP_LOGE(TAG, "cannot create %s", name);
        return NULL;
    }
    setvbuf(f, NULL, _IOFBF, 8192);
    struct timeval tv;
    gettimeofday(&tv, NULL);
    qcl_file_header_t h = {
        .magic = QCL_MAGIC, .version = 1, .header_len = sizeof(h),
        .t0_unix_us = (now > 1700000000) ? (uint64_t)tv.tv_sec * 1000000ull + tv.tv_usec - esp_timer_get_time() : 0,
        .cable_id = (uint8_t)s_cable,
    };
    for (int i = 0; i < NUM_CAN; i++) {
        h.bitrate[i] = g_cfg.bitrate[i];
        h.data_bitrate[i] = g_cfg.data_bitrate[i];
        if (g_cfg.listen_only[i]) h.listen_only_mask |= 1u << i;
    }
    strncpy(h.hw, "QuadCAN-C5 1.0", sizeof(h.hw) - 1);
    fwrite(&h, sizeof(h), 1, f);
    *written = sizeof(h);
    ESP_LOGI(TAG, "logging to %s", name);
    return f;
}

static void logger_task(void *arg)
{
    uint8_t *wbuf = heap_caps_malloc(WBUF_SIZE, MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL);
    size_t fill = 0, file_bytes = 0;
    FILE *f = s_card_ok ? open_new_file(&file_bytes) : NULL;
    int64_t last_flush = esp_timer_get_time(), last_sync = last_flush;
    for (;;) {
        size_t sz;
        uint8_t *item = xRingbufferReceive(s_rb, &sz, pdMS_TO_TICKS(100));
        if (item) {
            if (s_tap) s_tap((const qcl_rec_t *)item, item + sizeof(qcl_rec_t));
            if (f && fill + sz > WBUF_SIZE) {
                io_led(XP_LED_SD_N, true);
                fwrite(wbuf, 1, fill, f);
                file_bytes += fill;
                fill = 0;
                io_led(XP_LED_SD_N, false);
            }
            memcpy(wbuf + fill, item, sz);
            fill += sz;
            vRingbufferReturnItem(s_rb, item);
        }
        int64_t now = esp_timer_get_time();
        if (f && fill && (now - last_flush > 1000000 || s_stop)) {
            fwrite(wbuf, 1, fill, f);
            file_bytes += fill;
            fill = 0;
            last_flush = now;
        }
        if (f && (now - last_sync > 5000000 || s_stop)) {
            fflush(f);
            fsync(fileno(f));      // bounded data loss if power vanishes without warning
            last_sync = now;
        }
        if (f && file_bytes > (size_t)g_cfg.file_max_mb * 1024 * 1024) {
            fclose(f);
            f = open_new_file(&file_bytes);
        }
        if (s_stop) {
            if (f) fclose(f);
            f = NULL;
            ESP_LOGW(TAG, "log closed");
            xSemaphoreGive(s_closed);
            vTaskSuspend(NULL);
        }
    }
}

esp_err_t logger_start(cable_id_t cable)
{
    s_cable = cable;
    xTaskCreate(logger_task, "logger", 6144, NULL, 10, NULL);
    return ESP_OK;
}

void logger_shutdown(void)
{
    if (s_stop) return;
    s_stop = true;
    xSemaphoreTake(s_closed, pdMS_TO_TICKS(1500));
    if (s_card_ok) esp_vfs_fat_sdcard_unmount(MOUNT, s_card);
    s_card_ok = false;
    xp_write(XP_SD_PWR_N, true);               // card off: an idle card can draw ~1 mA
}

// ---------------------------------------------------------------- config file
app_cfg_t g_cfg;

void cfg_defaults(cable_id_t cable)
{
    memset(&g_cfg, 0, sizeof(g_cfg));
    for (int i = 0; i < NUM_CAN; i++) {
        g_cfg.bitrate[i] = 500000;
        g_cfg.listen_only[i] = true;          // never disturb a bus unless configured to
    }
    if (cable == CABLE_J1939) {
        g_cfg.bitrate[0] = 250000;            // J1939 backbone (use 500000 for J1939-14 trucks)
        g_cfg.bitrate[1] = 250000;
    }
    g_cfg.idle_sleep_min = 10;
    g_cfg.wake_vin_mv = 13200;            // engine running (alternator charging); doubled on 24 V systems
    g_cfg.sleep_check_s = 30;
    g_cfg.file_max_mb = 256;
    g_cfg.gps_enable = true;
    g_cfg.gps_rate_hz = 20;
    g_cfg.wifi_aware = true;
    g_cfg.wifi_ap = false;
    strcpy(g_cfg.ap_pass, "quadcan-logger");
}

void cfg_load(const char *path)
{
    FILE *f = fopen(path, "r");
    if (!f) {
        ESP_LOGI(TAG, "no %s, using defaults", path);
        return;
    }
    char line[128], key[32], val[80];
    while (fgets(line, sizeof(line), f)) {
        if (line[0] == '#' || sscanf(line, " %31[^= ] = %79s", key, val) != 2) continue;
        int ch;
        unsigned long v = strtoul(val, NULL, 10);
        if (sscanf(key, "can%d_fd", &ch) == 1 && ch >= 1 && ch <= NUM_CAN) g_cfg.data_bitrate[ch - 1] = v;
        else if (sscanf(key, "can%d_listen", &ch) == 1 && ch >= 1 && ch <= NUM_CAN) g_cfg.listen_only[ch - 1] = v != 0;
        else if (sscanf(key, "can%d", &ch) == 1 && ch >= 1 && ch <= NUM_CAN) g_cfg.bitrate[ch - 1] = v;
        else if (!strcmp(key, "idle_sleep_min")) g_cfg.idle_sleep_min = v;
        else if (!strcmp(key, "wake_vin_mv")) g_cfg.wake_vin_mv = v;
        else if (!strcmp(key, "sleep_check_s")) g_cfg.sleep_check_s = v < 5 ? 5 : v;
        else if (!strcmp(key, "file_max_mb")) g_cfg.file_max_mb = v ? v : 256;
        else if (!strcmp(key, "gps")) g_cfg.gps_enable = v != 0;
        else if (!strcmp(key, "gps_rate_hz")) g_cfg.gps_rate_hz = v ? v : 1;
        else if (!strcmp(key, "wifi_aware")) g_cfg.wifi_aware = v != 0;
        else if (!strcmp(key, "wifi_ap")) g_cfg.wifi_ap = v != 0;
        else if (!strcmp(key, "ap_pass")) strlcpy(g_cfg.ap_pass, val, sizeof(g_cfg.ap_pass));
    }
    fclose(f);
}
