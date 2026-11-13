# QuadCAN-C5 firmware (ESP-IDF v6.0)

Set-and-forget 4-channel CAN / CAN-FD logger for the QuadCAN-C5 board.

> **Status: written against the ESP-IDF v6.0.3 headers but not yet compiled or run on hardware.**
> It wasn't compiled because the session that wrote it couldn't run the ESP-IDF installer.
> Expect a short round of compile fixes on first build.

## Build and flash

```sh
# ESP-IDF v6.0.x installed and exported (. $IDF_PATH/export.sh)
cd hardware/quadcan-c5/firmware
idf.py set-target esp32c5
idf.py build
idf.py -p /dev/ttyACM0 flash monitor     # native USB Serial/JTAG, no buttons needed
```

If auto-reset into the bootloader ever fails: hold **BOOT**, tap **RESET**, release BOOT.

## What it does

| Area | Behaviour |
|---|---|
| CAN1, CAN2 | ESP32-C5 on-chip CAN-FD controllers (`esp_twai_onchip`) |
| CAN3, CAN4 | MCP2518FD over SPI (17 MHz), 20-deep RX FIFO with 1 µs hardware timestamps |
| Safety | All transceivers stay in **standby** until their channel opens. Channels open **listen-only** by default. A channel can only transmit with `can<n>_listen=0` **and** its TX_EN jumper fitted. |
| Logging | ISR/task → 2 MB PSRAM ring buffer → 64 KB batches → `/sd/LOGS/YYYYMMDD_HHMMSS.qcl`, `fsync` every 5 s, new file at `file_max_mb` |
| Time | PCF8523 RTC (CR1220 backup) at boot, then disciplined from GPS. Files are named `N000001.qcl` until the clock is valid. |
| GPS | u-blox NEO-M9N, UBX-NAV-PVT at `gps_rate_hz` (default 20, max 25), automotive dynamic model, raw PVT logged |
| Power fail | VIN is watched every 5 ms. When it falls below 6 V the log is flushed and closed on supercap energy (~4 s budget). The board restarts when power returns. |
| Sleep | Key off (buses idle, no ignition, engine not charging) for `idle_sleep_min` → SD card and GPS powered off, transceivers in standby, ESP32 deep sleep (est. ~0.5 mA at 12 V). Wakes on activity on **any** of the four buses, the ignition wire, or battery voltage rising above `wake_vin_mv`. See [../docs/LOW_POWER.md](../docs/LOW_POWER.md). |
| MARK button | Writes an event marker record (for "that noise just happened") |
| Phone link | Wi-Fi Aware service **`quadcan`** (+ optional WPA2 soft-AP), TCP port 7777: `LIVE`, `LIST`, `GET <file>`, `MARK [text]`, `SEND <ch> <id> <hex>` |
| LEDs | STAT heartbeat (fast = no SD card), SD = write activity, LINK = phone data path up, GPS = 1 pps with a fix, RX1–4 = bus activity (hardware) |

## `/sd/quadcan.cfg`

Plain `key=value` lines, `#` for comments. Anything omitted keeps the cable-ID default.

```ini
# nominal bitrate per channel (0 = off); CAN-FD data rate with can<n>_fd
can1=500000
can1_fd=0
can1_listen=1          # 1 = never ACK or transmit (default)
can2=500000
can2_fd=2000000        # e.g. a CAN-FD bus at 500k / 2M
can3=500000
can4=0                 # off
idle_sleep_min=10      # 0 = never sleep
wake_vin_mv=13200      # engine-running voltage; 0 = CAN/ignition wake only
sleep_check_s=30       # how often a parked logger samples the battery
file_max_mb=256
gps=1
gps_rate_hz=20
wifi_aware=1
wifi_ap=0              # 1 = also run a WPA2 AP "QuadCAN-xxxx" for phones without Wi-Fi Aware
ap_pass=change-me-please
```

Supported MCP2518FD (CAN3/4) rates: nominal 100k/125k/250k/500k/1M, data 1M/2M/4M/5M.
The on-chip controllers (CAN1/2) accept any rate the IDF timing solver can hit.

## Log format and tools

`.qcl` is a simple binary format (`main/qcl_format.h`). Convert with:

```sh
python3 tools/qcl2candump.py LOGS/20261112_160000.qcl > drive.log        # candump -L
python3 tools/qcl2candump.py LOGS/20261112_160000.qcl --gps track.csv    # + GPS CSV
python3 tools/qcl2candump.py LOGS/20261112_160000.qcl --summary
```

`candump -L` files open in SavvyCAN, `python-can` and `cantools`. Channel n appears as `can(n-1)`.

## Bandwidth sanity check

Four classic buses at 500 kbit/s and 60 % load ≈ 4 × 2,600 frames/s ≈ 10,400 records/s ×
~28 B ≈ **290 KB/s** to the SD card. That's well inside SPI-mode SD at 20 MHz (~1.5–2 MB/s) and
inside what Wi-Fi Aware / the soft-AP can stream live. The 2 MB PSRAM buffer covers ~7 s of
SD-card write stalls at that rate.

## Files

| File | Purpose |
|---|---|
| `main/board.h` | Pin map (must match `gen/design.py`) |
| `main/can.c` | Channel bring-up, RX paths, TX gate |
| `main/mcp2518fd.c` | MCP2518FD register driver |
| `main/logger.c` | SD mount, ring buffer, file writer, config parser |
| `main/gps.c` | NEO-M9N configuration (UBX-CFG-VALSET) and NAV-PVT parser |
| `main/power.c` | VIN ADC, power-fail, deep sleep, MARK button, status records |
| `main/net.c` | Wi-Fi Aware / soft-AP and the TCP command server |
| `main/io.c` | TCA9535 expander and PCF8523 RTC |
| `tools/qcl2candump.py` | Log converter |
