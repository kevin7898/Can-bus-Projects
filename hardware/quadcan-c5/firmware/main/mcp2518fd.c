// MCP2518FD driver - register layout per Microchip DS20006027 (same as Linux mcp251xfd).
#include "mcp2518fd.h"

#include <string.h>
#include "esp_log.h"
#include "esp_rom_sys.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "qcl_format.h"

static const char *TAG = "mcp2518fd";

// ---- SPI instructions / registers
#define INS_RESET 0x0
#define INS_WRITE 0x2
#define INS_READ  0x3

#define REG_CON      0x000
#define REG_NBTCFG   0x004
#define REG_DBTCFG   0x008
#define REG_TDC      0x00C
#define REG_TBC      0x010
#define REG_TSCON    0x014
#define REG_INT      0x01C
#define REG_TREC     0x034
#define REG_FIFOCON(n) (0x050 + 0x0C * (n))
#define REG_FIFOSTA(n) (0x054 + 0x0C * (n))
#define REG_FIFOUA(n)  (0x058 + 0x0C * (n))
#define REG_FLTCON0  0x1D0
#define REG_FLTOBJ0  0x1F0
#define REG_MASK0    0x1F4
#define RAM_START    0x400
#define RAM_SIZE     2048
#define REG_OSC      0xE00
#define REG_IOCON    0xE04
#define REG_ECCCON   0xE0C
#define REG_DEVID    0xE14

#define CON_REQOP_SHIFT 24
#define CON_OPMOD_SHIFT 21
#define CON_OPMOD_MASK  (7u << 21)
#define CON_ISOCRCEN    (1u << 5)
#define CON_STEF        (1u << 19)
#define CON_TXQEN       (1u << 20)
#define CON_BRSDIS      (1u << 12)
enum { MODE_MIXED = 0, MODE_SLEEP = 1, MODE_LISTEN = 3, MODE_CONFIG = 4, MODE_CAN20 = 6 };

#define FIFO_PLSIZE_SHIFT 29
#define FIFO_FSIZE_SHIFT  24
#define FIFO_FRESET (1u << 10)
#define FIFO_TXREQ  (1u << 9)
#define FIFO_UINC   (1u << 8)
#define FIFO_TXEN   (1u << 7)
#define FIFO_RXTSEN (1u << 5)
#define FIFO_TFNRFNIE (1u << 0)
#define FIFOSTA_TFNRFNIF (1u << 0)
#define FIFOSTA_RXOVIF   (1u << 3)
#define INT_RXIE (1u << 17)
#define OSC_OSCRDY (1u << 10)
#define IOCON_XSTBYEN (1u << 6)
#define IOCON_TRIS0   (1u << 0)

#define RX_FIFO 1
#define TX_FIFO 2

static esp_err_t xfer(mcp2518fd_t *d, uint8_t ins, uint16_t addr, const uint8_t *tx, uint8_t *rx, size_t n)
{
    uint8_t buf[2 + 80] = {0};
    uint8_t in[2 + 80];
    if (n > 80) return ESP_ERR_INVALID_SIZE;
    buf[0] = (uint8_t)((ins << 4) | ((addr >> 8) & 0x0F));
    buf[1] = (uint8_t)(addr & 0xFF);
    if (tx) memcpy(buf + 2, tx, n);
    spi_transaction_t t = {.length = (2 + n) * 8, .tx_buffer = buf, .rx_buffer = in};
    esp_err_t err = spi_device_polling_transmit(d->spi, &t);
    if (err == ESP_OK && rx) memcpy(rx, in + 2, n);
    return err;
}

static esp_err_t wr32(mcp2518fd_t *d, uint16_t a, uint32_t v)
{
    uint8_t b[4] = {v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, v >> 24};
    return xfer(d, INS_WRITE, a, b, NULL, 4);
}

static uint32_t rd32(mcp2518fd_t *d, uint16_t a)
{
    uint8_t b[4] = {0};
    xfer(d, INS_READ, a, NULL, b, 4);
    return b[0] | (b[1] << 8) | (b[2] << 16) | ((uint32_t)b[3] << 24);
}

static esp_err_t wr8(mcp2518fd_t *d, uint16_t a, uint8_t v) { return xfer(d, INS_WRITE, a, &v, NULL, 1); }

static esp_err_t set_mode(mcp2518fd_t *d, int mode)
{
    uint32_t con = rd32(d, REG_CON);
    con = (con & ~(7u << CON_REQOP_SHIFT)) | ((uint32_t)mode << CON_REQOP_SHIFT);
    wr32(d, REG_CON, con);
    for (int i = 0; i < 100; i++) {
        if (((rd32(d, REG_CON) & CON_OPMOD_MASK) >> CON_OPMOD_SHIFT) == (uint32_t)mode) return ESP_OK;
        vTaskDelay(1);
    }
    ESP_LOGE(TAG, "mode %d request timed out", mode);
    return ESP_ERR_TIMEOUT;
}

esp_err_t mcp2518fd_init(mcp2518fd_t *d, spi_host_device_t host, int cs, uint32_t spi_hz)
{
    memset(d, 0, sizeof(*d));
    spi_device_interface_config_t dev = {
        .clock_speed_hz = (int)spi_hz,   // <= 17 MHz with a 40 MHz SYSCLK
        .mode = 0,
        .spics_io_num = cs,
        .queue_size = 2,
    };
    esp_err_t err = spi_bus_add_device(host, &dev, &d->spi);
    if (err != ESP_OK) return err;
    xfer(d, INS_RESET, 0, NULL, NULL, 0);
    esp_rom_delay_us(500);
    for (int i = 0; i < 50 && !(rd32(d, REG_OSC) & OSC_OSCRDY); i++) vTaskDelay(1);
    if (!(rd32(d, REG_OSC) & OSC_OSCRDY)) {
        ESP_LOGE(TAG, "no 40 MHz clock (Y1 / OSC_EN?)");
        return ESP_ERR_NOT_FOUND;
    }
    uint32_t devid = rd32(d, REG_DEVID);
    ESP_LOGI(TAG, "DEVID 0x%08lx", (unsigned long)devid);
    // ECC on; RAM must be initialised once ECC is enabled
    wr32(d, REG_ECCCON, 1);
    uint8_t zero[64] = {0};
    for (int a = RAM_START; a < RAM_START + RAM_SIZE; a += sizeof(zero)) xfer(d, INS_WRITE, a, zero, NULL, sizeof(zero));
    // INT0/GPIO0 drives the transceiver STB pin: high in sleep, low otherwise
    uint32_t io = rd32(d, REG_IOCON);
    io = (io | IOCON_XSTBYEN) & ~IOCON_TRIS0;
    wr32(d, REG_IOCON, io);
    return ESP_OK;
}

typedef struct { uint32_t br; uint8_t brp, tseg1, tseg2, sjw; } timing_t;
// 40 MHz SYSCLK, sample point ~80 %
static const timing_t NOMINAL[] = {
    {1000000, 0, 30, 7, 7}, {500000, 0, 62, 15, 15}, {250000, 0, 126, 31, 31},
    {125000, 1, 126, 31, 31}, {100000, 1, 158, 39, 39},
};
static const timing_t DATA[] = {
    {5000000, 0, 4, 1, 1}, {4000000, 0, 6, 1, 1}, {2000000, 0, 14, 3, 3}, {1000000, 0, 30, 7, 7},
};

static const timing_t *find(const timing_t *t, size_t n, uint32_t br)
{
    for (size_t i = 0; i < n; i++) if (t[i].br == br) return &t[i];
    return NULL;
}

esp_err_t mcp2518fd_start(mcp2518fd_t *d, uint32_t bitrate, uint32_t data_bitrate, bool listen_only)
{
    const timing_t *nt = find(NOMINAL, sizeof(NOMINAL) / sizeof(NOMINAL[0]), bitrate);
    const timing_t *dt = data_bitrate ? find(DATA, sizeof(DATA) / sizeof(DATA[0]), data_bitrate) : NULL;
    if (!nt || (data_bitrate && !dt)) return ESP_ERR_NOT_SUPPORTED;
    ESP_ERROR_CHECK_WITHOUT_ABORT(set_mode(d, MODE_CONFIG));
    d->bitrate = bitrate;
    d->data_bitrate = data_bitrate;
    d->listen_only = listen_only;

    wr32(d, REG_NBTCFG, ((uint32_t)nt->brp << 24) | ((uint32_t)nt->tseg1 << 16) | ((uint32_t)nt->tseg2 << 8) | nt->sjw);
    if (dt) {
        wr32(d, REG_DBTCFG, ((uint32_t)dt->brp << 24) | ((uint32_t)dt->tseg1 << 16) | ((uint32_t)dt->tseg2 << 8) | dt->sjw);
        uint32_t tdco = (dt->brp + 1u) * (dt->tseg1 + 1u);
        wr32(d, REG_TDC, (2u << 16) | ((tdco & 0x7F) << 8));     // automatic TDC
    }
    // time base: 1 us ticks, timestamp at SOF
    wr32(d, REG_TSCON, (1u << 16) | 39u);
    // CON: ISO CRC, no TXQ, no TEF, BRS allowed
    uint32_t con = rd32(d, REG_CON);
    con &= ~(CON_TXQEN | CON_STEF | CON_BRSDIS);
    con |= CON_ISOCRCEN;
    wr32(d, REG_CON, con);
    // FIFO1: RX, 64-byte payload, timestamps, 20 objects (20 * (12 + 64) = 1520 B)
    wr32(d, REG_FIFOCON(RX_FIFO), (7u << FIFO_PLSIZE_SHIFT) | (19u << FIFO_FSIZE_SHIFT) | FIFO_RXTSEN | FIFO_TFNRFNIE | FIFO_FRESET);
    // FIFO2: TX, 64-byte payload, 6 objects (6 * 72 = 432 B)
    wr32(d, REG_FIFOCON(TX_FIFO), (7u << FIFO_PLSIZE_SHIFT) | (5u << FIFO_FSIZE_SHIFT) | FIFO_TXEN | FIFO_FRESET);
    // filter 0 -> FIFO1, mask 0 = accept everything (standard + extended)
    wr8(d, REG_FLTCON0, 0);
    wr32(d, REG_FLTOBJ0, 0);
    wr32(d, REG_MASK0, 0);
    wr8(d, REG_FLTCON0, 0x80 | RX_FIFO);
    wr32(d, REG_INT, INT_RXIE);
    int mode = listen_only ? MODE_LISTEN : (data_bitrate ? MODE_MIXED : MODE_CAN20);
    esp_err_t err = set_mode(d, mode);
    mcp2518fd_sync_time(d);
    return err;
}

esp_err_t mcp2518fd_sleep(mcp2518fd_t *d) { return set_mode(d, MODE_SLEEP); }

static const uint8_t DLC2LEN[16] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 12, 16, 20, 24, 32, 48, 64};

esp_err_t mcp2518fd_read(mcp2518fd_t *d, mcp_frame_t *f)
{
    uint32_t sta = rd32(d, REG_FIFOSTA(RX_FIFO));
    if (sta & FIFOSTA_RXOVIF) {
        d->rx_overflows++;
        wr8(d, REG_FIFOSTA(RX_FIFO), (uint8_t)(sta & ~FIFOSTA_RXOVIF));
    }
    if (!(sta & FIFOSTA_TFNRFNIF)) return ESP_ERR_NOT_FOUND;
    uint16_t ua = (uint16_t)rd32(d, REG_FIFOUA(RX_FIFO));
    uint8_t obj[12 + 64];
    xfer(d, INS_READ, RAM_START + ua, NULL, obj, 12);
    uint32_t w0 = obj[0] | (obj[1] << 8) | (obj[2] << 16) | ((uint32_t)obj[3] << 24);
    uint32_t w1 = obj[4] | (obj[5] << 8) | (obj[6] << 16) | ((uint32_t)obj[7] << 24);
    f->tbc = obj[8] | (obj[9] << 8) | (obj[10] << 16) | ((uint32_t)obj[11] << 24);
    bool ide = w1 & (1u << 4);
    f->flags = 0;
    if (ide) {
        f->id = ((w0 & 0x7FF) << 18) | ((w0 >> 11) & 0x3FFFF);
        f->flags |= QCL_F_EXT;
    } else {
        f->id = w0 & 0x7FF;
    }
    if (w1 & (1u << 5)) f->flags |= QCL_F_RTR;
    if (w1 & (1u << 7)) f->flags |= QCL_F_FD;
    if (w1 & (1u << 6)) f->flags |= QCL_F_BRS;
    if (w1 & (1u << 8)) f->flags |= QCL_F_ESI;
    f->len = DLC2LEN[w1 & 0xF];
    if (!(f->flags & QCL_F_FD) && f->len > 8) f->len = 8;
    if (f->len) xfer(d, INS_READ, RAM_START + ua + 12, NULL, f->data, (f->len + 3) & ~3u);
    wr8(d, REG_FIFOCON(RX_FIFO) + 1, (uint8_t)(FIFO_UINC >> 8));   // UINC
    return ESP_OK;
}

esp_err_t mcp2518fd_send(mcp2518fd_t *d, uint32_t id, uint8_t flags, const uint8_t *data, uint8_t len)
{
    if (d->listen_only) return ESP_ERR_INVALID_STATE;
    uint32_t sta = rd32(d, REG_FIFOSTA(TX_FIFO));
    if (!(sta & FIFOSTA_TFNRFNIF)) return ESP_ERR_NO_MEM;   // TX FIFO full
    uint16_t ua = (uint16_t)rd32(d, REG_FIFOUA(TX_FIFO));
    uint8_t dlc = 0;
    while (dlc < 15 && DLC2LEN[dlc] < len) dlc++;
    uint32_t w0 = (flags & QCL_F_EXT) ? (((id >> 18) & 0x7FF) | ((id & 0x3FFFF) << 11)) : (id & 0x7FF);
    uint32_t w1 = dlc | ((flags & QCL_F_EXT) ? (1u << 4) : 0) | ((flags & QCL_F_RTR) ? (1u << 5) : 0) |
                  ((flags & QCL_F_BRS) ? (1u << 6) : 0) | ((flags & QCL_F_FD) ? (1u << 7) : 0);
    uint8_t obj[8 + 64] = {0};
    memcpy(obj, &w0, 4);
    memcpy(obj + 4, &w1, 4);
    memcpy(obj + 8, data, len);
    xfer(d, INS_WRITE, RAM_START + ua, obj, NULL, 8 + ((DLC2LEN[dlc] + 3) & ~3u));
    return wr8(d, REG_FIFOCON(TX_FIFO) + 1, (uint8_t)((FIFO_UINC | FIFO_TXREQ) >> 8));
}

void mcp2518fd_sync_time(mcp2518fd_t *d)
{
    int64_t before = esp_timer_get_time();
    uint32_t tbc = rd32(d, REG_TBC);
    int64_t after = esp_timer_get_time();
    d->tbc_offset_us = (before + after) / 2 - (int64_t)tbc;
    d->last_tbc = tbc;
}

int64_t mcp2518fd_ts_us(mcp2518fd_t *d, uint32_t tbc)
{
    // TBC wraps every ~71 min; frames are always older than the last sync point + a few ms
    int32_t delta = (int32_t)(tbc - d->last_tbc);
    return d->tbc_offset_us + (int64_t)d->last_tbc + delta;
}

esp_err_t mcp2518fd_error_counters(mcp2518fd_t *d, uint8_t *tec, uint8_t *rec)
{
    uint32_t t = rd32(d, REG_TREC);
    *rec = t & 0xFF;
    *tec = (t >> 8) & 0xFF;
    return ESP_OK;
}
