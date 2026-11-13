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

## What is powered in sleep

| Block | State | Estimate at 3.3 / 5 V |
|---|---|---|
| ESP32-C5 module | deep sleep (PSRAM in standby) | ~50–100 µA |
| 4 × TCAN1044AV | standby, bus wake armed | ≤ 60 µA total |
| 2 × MCP2518FD | sleep mode, 40 MHz oscillator disabled | ~20 µA |
| TCA9535, PCF8523, pull-ups, VIN divider | holding state | ~40 µA |
| AP7361C LDO | quiescent | ~60 µA |
| NEO-M9N (if fitted) | main rail off, backup rail on for hot starts | ~45 µA |
| microSD card | **rail switched off** (Q3) | 0 |
| GPS main rail, LEDs, Wi-Fi | off | 0 |
| TPS54360 buck | light-load pulse skipping | ~150 µA at VIN |

**Estimated draw: about 0.4–0.6 mA at 12 V**, plus roughly 0.1 mA average for the periodic
voltage check. That's well under the 20–50 mA parasitic draw most car makers allow. A 60 Ah
battery would take years to notice it.

These are datasheet-based estimates, not measurements. Measure the first assembled board with
a meter in series with harness pin 1 before leaving it in a car for weeks.

## Config keys (`/sd/quadcan.cfg`)

```ini
idle_sleep_min=10     # 0 = never sleep
wake_vin_mv=13200     # 0 = disable the voltage wake (CAN / ignition wake only)
sleep_check_s=30      # how often a parked logger samples the battery
```
