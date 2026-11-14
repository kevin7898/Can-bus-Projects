# Key-off sleep and wake-up

The logger is meant to stay plugged in. When the vehicle shuts down it drops into a low-power
state by itself and wakes when the vehicle does.

## When it goes to sleep

All of these must hold for `idle_sleep_min` minutes (default 10):

* no CAN frame received on any channel,
* the ignition wire (harness pin 9), if fitted, is off,
* battery voltage is below the engine-running threshold (`wake_vin_mv`, default 13.2 V; doubled
  automatically on 24 V systems).

Before sleeping the firmware flushes and closes the log, unmounts the card and powers it off.

## What wakes it

| Source | Needs | Hardware path |
|---|---|---|
| **Activity on any of the 4 CAN buses** | nothing extra | Transceivers stay in standby (~15 µA each) and pull RXD low on bus traffic. CAN1/CAN2 RXD go straight to wake-capable ESP32 pins. CAN3/CAN4 RXD are diode-ORed (D40) onto `WAKE_N`. |
| **Ignition wire** | optional pigtail on harness pin 9 | Q1 → D41 → `WAKE_N` |
| **Battery voltage rise** (engine running) | only the OBD plug's power pins | ESP32 wakes for a fraction of a second every `sleep_check_s` (default 30 s), samples VIN, and goes back to sleep if the car is still parked |

Wake-on-CAN is immediate. On some cars the bus at the OBD port is **silent with no tester
attached**. On VW MQB the diagnostic CAN sits behind the gateway. There the voltage-rise wake
(or the ignition wire, or a tapped bus on CAN2–4) brings the logger up within `sleep_check_s`
of the engine starting.

If you poll the car over CAN1 (`can1_listen=0`), stop polling when replies stop: a tester that
keeps talking can hold the car's own gateway awake. The firmware never polls on its own.

## Rev 1.1 backup and sleep

The charger status, not the vehicle ADC alone, determines whether external power is available. A continuous absence shorter than 30 seconds keeps logging. Restoration resets that timer. A cell measurement below 3.45 V for one second requests shutdown sooner. An unavailable status expander is treated as absent power; an unavailable battery ADC does not disable the 30-second limit.

Shutdown stops Wi-Fi, CAN and GPS, stops the external oscillator, flushes/closes the SD log, then enters deep sleep. Backup shutdown disables CAN wake and samples vehicle VIN every five seconds; VIN above approximately 8 V restarts the logger. USB-only restoration after backup sleep currently requires RESET. This is a software limitation, not seamless USB wake support.

Deep sleep is not a hard battery disconnect. The always-on circuitry and ADC still consume power until the UVLO cuts the boost off near 3.16 V. Its nominal restart threshold is 3.66 V. Pack protection remains the final independent safeguard. An exact cell, charger temperature limits, real peak load and sleep current must be validated before installation.

The rev 1.0 estimate of 0.4–0.6 mA at vehicle VIN is withdrawn for this revision: it omitted the added charger, boost, comparator, ADC, second expander and dividers. Measure both VIN and pack current in active, key-off, backup-sleep and UVLO-off states.

## Config keys (`/sd/quadcan.cfg`)

```ini
idle_sleep_min=10     # 0 = never sleep
wake_vin_mv=13200     # 0 = disable the voltage wake (CAN / ignition wake only)
sleep_check_s=30      # how often a parked logger samples the battery
```
