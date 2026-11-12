// Minimal MCP2518FD driver: RX FIFO with timestamps, optional TX FIFO, listen-only by default.
#pragma once
#include <stdbool.h>
#include <stdint.h>
#include "driver/spi_master.h"
#include "esp_err.h"

typedef struct {
    spi_device_handle_t spi;
    uint32_t bitrate;        // nominal (arbitration) bitrate
    uint32_t data_bitrate;   // 0 = classic CAN 2.0 only
    bool listen_only;
    // time-base mapping: MCP TBC (1 MHz) -> esp_timer microseconds
    int64_t tbc_offset_us;
    uint32_t last_tbc;
    uint32_t rx_overflows;
} mcp2518fd_t;

typedef struct {
    uint32_t id;
    uint8_t flags;           // QCL_F_* bits
    uint8_t len;
    uint32_t tbc;            // raw MCP timestamp (us)
    uint8_t data[64];
} mcp_frame_t;

esp_err_t mcp2518fd_init(mcp2518fd_t *dev, spi_host_device_t host, int cs_gpio, uint32_t spi_hz);
// Configure bit timing + FIFOs and enter listen-only / normal mode.
esp_err_t mcp2518fd_start(mcp2518fd_t *dev, uint32_t bitrate, uint32_t data_bitrate, bool listen_only);
esp_err_t mcp2518fd_sleep(mcp2518fd_t *dev);        // also raises XSTBY -> transceiver standby
// Read one frame from the RX FIFO. Returns ESP_ERR_NOT_FOUND when the FIFO is empty.
esp_err_t mcp2518fd_read(mcp2518fd_t *dev, mcp_frame_t *f);
esp_err_t mcp2518fd_send(mcp2518fd_t *dev, uint32_t id, uint8_t flags, const uint8_t *data, uint8_t len);
// Refresh the TBC -> esp_timer offset (call from the service task).
void mcp2518fd_sync_time(mcp2518fd_t *dev);
int64_t mcp2518fd_ts_us(mcp2518fd_t *dev, uint32_t tbc);
esp_err_t mcp2518fd_error_counters(mcp2518fd_t *dev, uint8_t *tec, uint8_t *rec);
