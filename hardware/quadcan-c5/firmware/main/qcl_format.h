// QCL v1 - QuadCAN log format (little endian). Decoded by tools/qcl2candump.py
//
// File  = qcl_file_header_t, then a stream of records.
// Record = qcl_rec_t header (16 bytes) followed by `len` payload bytes, padded to 4 bytes.
// Timestamps are microseconds since `t0_unix_us` in the file header.
#pragma once
#include <stdint.h>

#define QCL_MAGIC   0x314C4351u   // "QCL1"

typedef struct __attribute__((packed)) {
    uint32_t magic;
    uint16_t version;          // 1
    uint16_t header_len;       // sizeof(qcl_file_header_t)
    uint64_t t0_unix_us;       // wall-clock time of ts=0 (RTC/GPS), 0 if unknown
    uint32_t bitrate[4];       // nominal bitrate per channel (0 = channel off)
    uint32_t data_bitrate[4];  // CAN-FD data-phase bitrate (0 = classic only)
    uint8_t  cable_id;
    uint8_t  listen_only_mask; // bit n = channel n+1 opened listen-only
    char     hw[22];           // "QuadCAN-C5 1.0"
} qcl_file_header_t;

enum {
    QCL_REC_CAN = 1,     // payload = CAN data (0..64 bytes)
    QCL_REC_GPS = 2,     // payload = raw UBX-NAV-PVT payload (92 bytes)
    QCL_REC_MARK = 3,    // payload = none (MARK button) or text
    QCL_REC_STATUS = 4,  // payload = qcl_status_t
    QCL_REC_ERROR = 5,   // id = error flags, chan = channel
};

// CAN flags
#define QCL_F_EXT  0x01  // 29-bit identifier
#define QCL_F_RTR  0x02
#define QCL_F_FD   0x04  // CAN-FD frame
#define QCL_F_BRS  0x08  // bit-rate switch
#define QCL_F_ESI  0x10
#define QCL_F_TX   0x20  // frame was sent by this logger

typedef struct __attribute__((packed)) {
    uint64_t ts_us;
    uint8_t  type;
    uint8_t  chan;       // 0..3 = CAN1..CAN4
    uint8_t  flags;
    uint8_t  len;        // payload length
    uint32_t id;
} qcl_rec_t;

typedef struct __attribute__((packed)) {
    uint16_t vin_mv;
    uint8_t  ign;
    uint8_t  sd_free_pct;
    uint32_t frames[4];
    uint32_t dropped;
} qcl_status_t;

static inline uint32_t qcl_rec_size(uint8_t len) { return (sizeof(qcl_rec_t) + len + 3u) & ~3u; }
