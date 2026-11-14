// Phone link: Wi-Fi Aware (NAN) service "quadcan" + optional WPA2 soft-AP, and a TCP server on port 7777.
//
// Protocol (one command per line):
//   LIVE        -> stream QCL records as they are logged (binary, same layout as the .qcl files)
//   LIST        -> "name size\n" for every log file, then "END\n"
//   GET <name>  -> "SIZE <n>\n" followed by the raw file
//   MARK [text] -> drop an event marker into the log
//   SEND <ch> <id-hex> <data-hex>  -> transmit (only on channels opened with can<n>_listen=0)
#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include "app.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_netif.h"
#include "esp_nan.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/stream_buffer.h"
#include "freertos/task.h"
#include "io.h"
#include "lwip/sockets.h"

static const char *TAG = "net";
#define PORT 7777
static StreamBufferHandle_t s_live;
static volatile bool s_live_on;
static volatile bool s_net_stop, s_server_done = true;

static void tap(const qcl_rec_t *r, const uint8_t *payload)
{
    if (!s_live_on) return;
    size_t sz = qcl_rec_size(r->len);
    if (xStreamBufferSpacesAvailable(s_live) >= sz) xStreamBufferSend(s_live, r, sz, 0);   // drop if the phone is slow
}

static void ndp_indication(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    wifi_event_ndp_indication_t *evt = data;
    wifi_nan_datapath_resp_t resp = {.accept = true, .ndp_id = evt->ndp_id};
    memcpy(resp.peer_mac, evt->peer_nmi, 6);
    esp_wifi_nan_datapath_resp(&resp);
}

static void ndp_confirm(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    wifi_event_ndp_confirm_t *evt = data;
    ESP_LOGI(TAG, "Wi-Fi Aware data path %s", evt->status == NDP_STATUS_ACCEPTED ? "up" : "rejected");
    io_led(XP_LED_LINK_N, evt->status == NDP_STATUS_ACCEPTED);
}

static void send_all(int s, const void *p, size_t n)
{
    const uint8_t *b = p;
    while (n && !s_net_stop) {
        int w = send(s, b, n, 0);
        if (w <= 0) return;
        b += w;
        n -= (size_t)w;
    }
}

static int hex2bytes(const char *h, uint8_t *out, int max)
{
    int n = 0;
    while (h[0] && h[1] && n < max) {
        unsigned v;
        if (sscanf(h, "%2x", &v) != 1) break;
        out[n++] = (uint8_t)v;
        h += 2;
    }
    return n;
}

static void client(int s)
{
    char line[160];
    int n = 0;
    while (!s_net_stop) {
        char c;
        int got = recv(s, &c, 1, 0);
        if (got < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) continue;
        if (got <= 0) break;
        if (c != '\n' && n < (int)sizeof(line) - 1) { line[n++] = c; continue; }
        line[n] = 0;
        n = 0;
        if (!strncmp(line, "LIVE", 4)) {
            xStreamBufferReset(s_live);
            s_live_on = true;
            uint8_t buf[2048];
            while (!s_net_stop) {
                size_t got = xStreamBufferReceive(s_live, buf, sizeof(buf), pdMS_TO_TICKS(200));
                if (got && send(s, buf, got, 0) <= 0) break;
            }
            s_live_on = false;
            break;
        } else if (!strncmp(line, "LIST", 4)) {
            DIR *d = opendir(logger_dir());
            struct dirent *e;
            char path[300], out[300];
            while (!s_net_stop && d && (e = readdir(d))) {
                struct stat st;
                snprintf(path, sizeof(path), "%s/%s", logger_dir(), e->d_name);
                if (stat(path, &st) == 0) {
                    int k = snprintf(out, sizeof(out), "%s %ld\n", e->d_name, (long)st.st_size);
                    send_all(s, out, k);
                }
            }
            if (d) closedir(d);
            send_all(s, "END\n", 4);
        } else if (!strncmp(line, "GET ", 4) && !strchr(line + 4, '/')) {
            char path[300], hdr[40];
            snprintf(path, sizeof(path), "%s/%s", logger_dir(), line + 4);
            FILE *f = fopen(path, "rb");
            struct stat st;
            if (!f || stat(path, &st) != 0) { send_all(s, "ERR\n", 4); if (f) fclose(f); continue; }
            int k = snprintf(hdr, sizeof(hdr), "SIZE %ld\n", (long)st.st_size);
            send_all(s, hdr, k);
            static uint8_t fb[4096];
            size_t r;
            while (!s_net_stop && (r = fread(fb, 1, sizeof(fb), f)) > 0) send_all(s, fb, r);
            fclose(f);
        } else if (!strncmp(line, "MARK", 4)) {
            const char *txt = line[4] == ' ' ? line + 5 : "";
            log_push(QCL_REC_MARK, 0, 0, 0, esp_timer_get_time(), txt, (uint8_t)strnlen(txt, 64));
            send_all(s, "OK\n", 3);
        } else if (!strncmp(line, "SEND ", 5)) {
            int ch; unsigned long id; char hex[140] = "";
            uint8_t data[64];
            if (sscanf(line + 5, "%d %lx %139s", &ch, &id, hex) >= 2) {
                int len = hex2bytes(hex, data, 64);
                uint8_t fl = (id > 0x7FF ? QCL_F_EXT : 0) | (len > 8 ? QCL_F_FD : 0);
                esp_err_t err = can_send(ch - 1, (uint32_t)id, fl, data, (uint8_t)len);
                send_all(s, err == ESP_OK ? "OK\n" : "ERR listen-only or closed\n", err == ESP_OK ? 3 : 26);
            }
        }
    }
    close(s);
}

static void server_task(void *arg)
{
    int ls = socket(AF_INET6, SOCK_STREAM, IPPROTO_TCP);
    int one = 1;
    setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    struct sockaddr_in6 a = {.sin6_family = AF_INET6, .sin6_port = htons(PORT), .sin6_addr = IN6ADDR_ANY_INIT};
    bind(ls, (struct sockaddr *)&a, sizeof(a));
    listen(ls, 2);
    ESP_LOGI(TAG, "TCP server on port %d", PORT);
    while (!s_net_stop && ls >= 0) {
        fd_set readfds;
        FD_ZERO(&readfds); FD_SET(ls, &readfds);
        struct timeval poll = {.tv_sec = 0, .tv_usec = 200000};
        if (select(ls + 1, &readfds, NULL, NULL, &poll) <= 0) continue;
        int s = accept(ls, NULL, NULL);
        if (s >= 0) {
            struct timeval timeout = {.tv_sec = 0, .tv_usec = 200000};
            setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
            setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
            client(s); // closes any file/DIR before returning, including stop requests
        }
    }
    if (ls >= 0) close(ls);
    s_server_done = true;
    vTaskDelete(NULL);
}

esp_err_t net_start(void)
{
    s_live = xStreamBufferCreate(64 * 1024, 1);
    logger_set_tap(tap);
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    wifi_init_config_t wcfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&wcfg));
    esp_wifi_set_storage(WIFI_STORAGE_RAM);
    if (g_cfg.wifi_ap) {   // note: soft-AP and NAN at the same time depend on IDF/chip support
        esp_netif_create_default_wifi_ap();
        uint8_t mac[6];
        esp_read_mac(mac, ESP_MAC_WIFI_SOFTAP);
        wifi_config_t ap = {.ap = {.max_connection = 2, .authmode = WIFI_AUTH_WPA2_PSK, .channel = 36}};
        ap.ap.ssid_len = (uint8_t)snprintf((char *)ap.ap.ssid, sizeof(ap.ap.ssid), "QuadCAN-%02X%02X", mac[4], mac[5]);
        strlcpy((char *)ap.ap.password, g_cfg.ap_pass, sizeof(ap.ap.password));
        esp_wifi_set_mode(WIFI_MODE_AP);
        esp_wifi_set_config(WIFI_IF_AP, &ap);
        ESP_ERROR_CHECK(esp_wifi_start());
    }
    if (g_cfg.wifi_aware) {
        esp_event_handler_register(WIFI_EVENT, WIFI_EVENT_NDP_INDICATION, ndp_indication, NULL);
        esp_event_handler_register(WIFI_EVENT, WIFI_EVENT_NDP_CONFIRM, ndp_confirm, NULL);
        esp_netif_create_default_wifi_nan();
        wifi_nan_sync_config_t nan = WIFI_NAN_SYNC_CONFIG_DEFAULT();
        esp_wifi_nan_sync_start(&nan);
        wifi_nan_publish_cfg_t pub = {
            .service_name = "quadcan",
            .type = NAN_PUBLISH_UNSOLICITED,
            .matching_filter = "",
            .single_replied_event = 1,
            .datapath_reqd = 1,
            .ndp_resp_needed = 1,
        };
        if (!esp_wifi_nan_publish_service(&pub)) ESP_LOGE(TAG, "NAN publish failed");
        else ESP_LOGI(TAG, "Wi-Fi Aware service 'quadcan' published");
    }
    s_net_stop = false;
    s_server_done = false;
    if (xTaskCreate(server_task, "tcp", 6144, NULL, 5, NULL) != pdPASS) {
        s_server_done = true;
        return ESP_ERR_NO_MEM;
    }
    return ESP_OK;
}

void net_stop(void)
{
    s_net_stop = true;
    s_live_on = false;
    esp_wifi_stop();
    // Wait for active GET/LIST operations to release the card before unmount.
    while (!s_server_done) vTaskDelay(pdMS_TO_TICKS(10));
}
