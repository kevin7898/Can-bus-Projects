// Shared application interfaces
#pragma once
#include <stdbool.h>
#include <stdint.h>
#include "esp_err.h"
#include "board.h"
#include "qcl_format.h"

// ---------------------------------------------------------------- config (/sd/quadcan.cfg)
typedef struct {
    uint32_t bitrate[NUM_CAN];       // 0 = channel off
    uint32_t data_bitrate[NUM_CAN];  // 0 = classic CAN
    bool listen_only[NUM_CAN];       // true = never ACK or transmit (default)
    uint32_t idle_sleep_min;         // sleep after this long with no frames, IGN off, engine off (0 = never)
    uint32_t wake_vin_mv;            // wake / stay awake while VIN is above this (0 = no voltage wake)
    uint32_t sleep_check_s;          // how often a sleeping logger samples VIN
    uint32_t file_max_mb;            // rotate log files at this size
    bool gps_enable;
    uint32_t gps_rate_hz;
    bool wifi_aware;                 // publish the "quadcan" Wi-Fi Aware service
    bool wifi_ap;                    // also run a WPA2 soft-AP for phones without Wi-Fi Aware
    char ap_pass[64];
} app_cfg_t;

extern app_cfg_t g_cfg;
void cfg_defaults(cable_id_t cable);
void cfg_load(const char *path);     // overrides defaults with key=value lines

// ---------------------------------------------------------------- logging
esp_err_t logger_init(void);         // mounts the SD card
esp_err_t logger_start(cable_id_t cable);
// Queue one record (task context / ISR). Never blocks; drops (and counts) when full.
bool log_push(uint8_t type, uint8_t chan, uint8_t flags, uint32_t id, int64_t ts_us, const void *data, uint8_t len);
bool log_push_isr(uint8_t type, uint8_t chan, uint8_t flags, uint32_t id, int64_t ts_us, const void *data, uint8_t len);
void logger_shutdown(void);          // flush + close (power fail / sleep)
uint32_t logger_dropped(void);
bool logger_card_ok(void);
const char *logger_dir(void);

// live tap for the network streamer: called by the logger task for every record
typedef void (*log_tap_fn)(const qcl_rec_t *rec, const uint8_t *payload);
void logger_set_tap(log_tap_fn fn);

// ---------------------------------------------------------------- CAN
esp_err_t can_start(void);           // opens all enabled channels from g_cfg
void can_stop(void);                 // controllers off, transceivers to standby
uint32_t can_frames(int ch);
int64_t can_last_rx_us(void);
esp_err_t can_send(int ch, uint32_t id, uint8_t flags, const uint8_t *data, uint8_t len);

// ---------------------------------------------------------------- GPS / power / network
esp_err_t gps_start(void);
void gps_stop(void);
void power_task_start(void);         // VIN monitor, power-fail, sleep, MARK button, status LED
// Call first thing in app_main: after a periodic timer wake-up this samples VIN and the wake
// lines, and goes straight back to deep sleep (never returns) unless the vehicle has woken up.
void power_early_wake_check(void);
esp_err_t net_start(void);
