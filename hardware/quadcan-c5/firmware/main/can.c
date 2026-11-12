// CAN1/CAN2 = ESP32-C5 on-chip CAN-FD (TWAI), CAN3/CAN4 = MCP2518FD on SPI2.
#include <string.h>
#include "app.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_twai.h"
#include "esp_twai_onchip.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "io.h"
#include "mcp2518fd.h"

static const char *TAG = "can";

static twai_node_handle_t s_node[2];
static mcp2518fd_t s_mcp[2];
static bool s_open[NUM_CAN];
static volatile uint32_t s_frames[NUM_CAN];
static volatile int64_t s_last_rx;
static TaskHandle_t s_mcp_task;

uint32_t can_frames(int ch) { return s_frames[ch]; }
int64_t can_last_rx_us(void) { return s_last_rx; }

// ---------------------------------------------------------------- on-chip controllers
static bool IRAM_ATTR onchip_rx(twai_node_handle_t h, const twai_rx_done_event_data_t *e, void *ctx)
{
    int ch = (int)(intptr_t)ctx;
    uint8_t buf[64];
    twai_frame_t f = {.buffer = buf, .buffer_len = sizeof(buf)};
    if (twai_node_receive_from_isr(h, &f) != ESP_OK) return false;
    int64_t now = esp_timer_get_time();
    uint8_t flags = (f.header.ide ? QCL_F_EXT : 0) | (f.header.rtr ? QCL_F_RTR : 0) |
                    (f.header.fdf ? QCL_F_FD : 0) | (f.header.brs ? QCL_F_BRS : 0) | (f.header.esi ? QCL_F_ESI : 0);
    uint8_t len = (uint8_t)twaifd_dlc2len(f.header.dlc);
    if (len > f.buffer_len) len = (uint8_t)f.buffer_len;
    if (f.header.rtr) len = 0;
    s_frames[ch]++;
    s_last_rx = now;
    return log_push_isr(QCL_REC_CAN, (uint8_t)ch, flags, f.header.id, now, buf, len);
}

static bool onchip_error(twai_node_handle_t h, const twai_error_event_data_t *e, void *ctx)
{
    int ch = (int)(intptr_t)ctx;
    log_push_isr(QCL_REC_ERROR, (uint8_t)ch, 0, e->err_flags.val, esp_timer_get_time(), NULL, 0);
    return false;
}

static esp_err_t open_onchip(int ch)
{
    static const gpio_num_t tx[2] = {PIN_CAN1_TX, PIN_CAN2_TX}, rx[2] = {PIN_CAN1_RX, PIN_CAN2_RX};
    twai_onchip_node_config_t cfg = {
        .io_cfg = {.tx = tx[ch], .rx = rx[ch], .quanta_clk_out = GPIO_NUM_NC, .bus_off_indicator = GPIO_NUM_NC},
        .bit_timing = {.bitrate = g_cfg.bitrate[ch], .sp_permill = 800},
        .data_timing = {.bitrate = g_cfg.data_bitrate[ch], .sp_permill = 750},
        .tx_queue_depth = 8,
        .fail_retry_cnt = 3,
        .flags.enable_listen_only = g_cfg.listen_only[ch],
    };
    esp_err_t err = twai_new_node_onchip(&cfg, &s_node[ch]);
    if (err != ESP_OK) return err;
    twai_event_callbacks_t cbs = {.on_rx_done = onchip_rx, .on_error = onchip_error};
    twai_node_register_event_callbacks(s_node[ch], &cbs, (void *)(intptr_t)ch);
    err = twai_node_enable(s_node[ch]);
    if (err == ESP_OK) xp_write(ch == 0 ? XP_CAN1_STB : XP_CAN2_STB, false);   // transceiver -> normal
    return err;
}

// ---------------------------------------------------------------- MCP2518FD channels
static void IRAM_ATTR mcp_isr(void *arg)
{
    BaseType_t woken = pdFALSE;
    vTaskNotifyGiveFromISR(s_mcp_task, &woken);
    portYIELD_FROM_ISR(woken);
}

static void mcp_task(void *arg)
{
    mcp_frame_t f;
    int64_t last_sync = 0;
    for (;;) {
        ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(20));
        int64_t now = esp_timer_get_time();
        for (int i = 0; i < 2; i++) {
            int ch = 2 + i;
            if (!s_open[ch]) continue;
            if (now - last_sync > 500000) mcp2518fd_sync_time(&s_mcp[i]);
            int n = 0;
            while (n++ < 64 && mcp2518fd_read(&s_mcp[i], &f) == ESP_OK) {
                int64_t ts = mcp2518fd_ts_us(&s_mcp[i], f.tbc);
                s_frames[ch]++;
                s_last_rx = ts;
                log_push(QCL_REC_CAN, (uint8_t)ch, f.flags, f.id, ts, f.data, f.len);
            }
        }
        if (now - last_sync > 500000) last_sync = now;
    }
}

static esp_err_t open_mcp(int i)
{
    static const int cs[2] = {PIN_CAN3_CS, PIN_CAN4_CS}, irq[2] = {PIN_CAN3_INT, PIN_CAN4_INT};
    int ch = 2 + i;
    esp_err_t err = mcp2518fd_init(&s_mcp[i], SPI2_HOST, cs[i], 17 * 1000 * 1000);
    if (err == ESP_OK) err = mcp2518fd_start(&s_mcp[i], g_cfg.bitrate[ch], g_cfg.data_bitrate[ch], g_cfg.listen_only[ch]);
    if (err != ESP_OK) return err;
    gpio_config_t io = {.pin_bit_mask = 1ULL << irq[i], .mode = GPIO_MODE_INPUT, .intr_type = GPIO_INTR_NEGEDGE};
    gpio_config(&io);
    gpio_isr_handler_add(irq[i], mcp_isr, NULL);
    return ESP_OK;
}

esp_err_t can_start(void)
{
    gpio_install_isr_service(0);
    xTaskCreate(mcp_task, "mcp", 4096, NULL, 12, &s_mcp_task);
    for (int ch = 0; ch < NUM_CAN; ch++) {
        if (!g_cfg.bitrate[ch]) continue;
        esp_err_t err = ch < 2 ? open_onchip(ch) : open_mcp(ch - 2);
        s_open[ch] = err == ESP_OK;
        ESP_LOGI(TAG, "CAN%d %lu/%lu bit/s %s: %s", ch + 1, (unsigned long)g_cfg.bitrate[ch],
                 (unsigned long)g_cfg.data_bitrate[ch], g_cfg.listen_only[ch] ? "listen-only" : "normal",
                 esp_err_to_name(err));
    }
    return ESP_OK;
}

void can_stop(void)
{
    for (int ch = 0; ch < 2; ch++) {
        if (s_open[ch]) {
            twai_node_disable(s_node[ch]);
            twai_node_delete(s_node[ch]);
        }
        xp_write(ch == 0 ? XP_CAN1_STB : XP_CAN2_STB, true);
        s_open[ch] = false;
    }
    for (int i = 0; i < 2; i++) {
        if (s_open[2 + i]) mcp2518fd_sleep(&s_mcp[i]);   // XSTBY puts the transceiver in standby
        s_open[2 + i] = false;
    }
}

esp_err_t can_send(int ch, uint32_t id, uint8_t flags, const uint8_t *data, uint8_t len)
{
    if (ch < 0 || ch >= NUM_CAN || !s_open[ch]) return ESP_ERR_INVALID_STATE;
    if (g_cfg.listen_only[ch]) return ESP_ERR_NOT_ALLOWED;
    esp_err_t err;
    if (ch < 2) {
        twai_frame_t f = {
            .header = {.id = id, .dlc = (uint16_t)twaifd_len2dlc(len), .ide = !!(flags & QCL_F_EXT),
                       .fdf = !!(flags & QCL_F_FD), .brs = !!(flags & QCL_F_BRS)},
            .buffer = (uint8_t *)data, .buffer_len = len,
        };
        err = twai_node_transmit(s_node[ch], &f, 10);
    } else {
        err = mcp2518fd_send(&s_mcp[ch - 2], id, flags, data, len);
    }
    if (err == ESP_OK) log_push(QCL_REC_CAN, (uint8_t)ch, flags | QCL_F_TX, id, esp_timer_get_time(), data, len);
    return err;
}
