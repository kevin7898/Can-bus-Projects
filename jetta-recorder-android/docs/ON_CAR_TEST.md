# OBDLink MX+ on-car test

Target hardware: OnePlus 6T, OBDLink MX+, 2014 Volkswagen Jetta TDI.

## Before installing

1. Pair the MX+ in Android Bluetooth settings. Do not pair it inside the app.
2. Confirm no other phone or OBD app is connected to the adapter.
3. Turn the Jetta ignition on; starting the engine is preferable for live RPM.
4. Disable battery optimization for Jetta Recorder during development tests.

## Proof run

1. Open Jetta Recorder and grant the nearby-device permission.
2. Select the paired OBDLink MX+ and tap **Connect**.
3. Confirm the console reports Bluetooth connected, initialization replies and
   a detected CAN protocol.
4. Confirm RPM and speed respond smoothly.
5. Confirm coolant changes plausibly during warm-up.
6. With key-on/engine-off, MAP and BARO should be close and gauge boost should
   be near zero.
7. During a loaded acceleration, gauge boost should rise above zero.
8. Note the displayed successful sample rate with the engine idling and during
   a drive.

## Useful console commands

| Command | Purpose |
| --- | --- |
| `ATI` | Generic ELM identity |
| `STI` | OBDLink/STN identity |
| `STDI` | OBDLink device information when supported |
| `ATDP` | Active OBD protocol description |
| `ATDPN` | Active protocol number |
| `ATRV` | Adapter supply voltage |
| `0100` | Supported Mode 01 PIDs 01–20 |
| `0120` | Supported Mode 01 PIDs 21–40 |
| `0140` | Supported Mode 01 PIDs 41–60 |
| `010C` | Engine RPM |
| `010D` | Vehicle speed |

## Capture when something fails

Leave the console entries intact and record:

- exact failure text;
- adapter identity and firmware;
- active protocol;
- whether another OBD app had recently used the MX+;
- ignition/engine state;
- Android version on the OnePlus.

The next diagnostic feature will export this console plus timing statistics as
a shareable support bundle.

## Raw CAN gateway visibility test

1. Leave the engine running and the phone connected to the MX+.
2. Tap **Start probe**. Confirm the banner says `SILENT • 11-BIT • 500 KBIT/S`.
3. Capture 30 seconds parked without touching controls.
4. Continue while operating one control at a time: brake pedal, accelerator
   blip, indicators, headlights, doors and steering wheel.
5. If safe, make a separate 5–10 minute capture containing a stop, gentle and
   stronger acceleration, steady speeds and deceleration.
6. Tap **Stop capture**, wait for diagnostic polling to return, then export the
   webCAN CSV through Android's document picker.

Interpretation:

- Hundreds of frames per second and many changing IDs means the gateway exposes
  a useful broadcast stream and the CSV is ready for the CSS pipeline.
- Only a few diagnostic-looking IDs or zero traffic does not automatically mean
  the app failed. The Jetta gateway may not forward proprietary broadcasts to
  the diagnostic connector; the next test would tap the relevant CAN network
  behind the gateway using dedicated hardware.

The app deliberately uses `STCMM0`, so the adapter listens without acknowledging
or transmitting CAN frames. Do not change this to normal-node mode in a vehicle.

## Read-only Jetta sensor discovery

Run this as a separate parked test; do not run the raw CAN monitor at the same
time.

1. Start the engine and let it idle. Connect until the normal dashboard is live.
2. Tap **Run discovery** under **Jetta sensor discovery**.
3. Leave the engine running until all sixteen candidates have finished.
4. Confirm the dashboard resumes normal RPM and speed polling automatically.
5. Note which rows say **FOUND** and whether each preview is physically
   plausible. A response alone does not validate its scale or unit.
6. Tap **Export results** and retain the CSV unchanged.

The run sends only `22xxxx` UDS ReadDataByIdentifier requests to engine request
ID `7E0` and accepts replies from `7E8`. It does not clear DTCs, change coding,
run actuators or write ECU data. If the app fails to restore normal polling,
disconnect and reconnect; preserve the console and exported CSV for diagnosis.

