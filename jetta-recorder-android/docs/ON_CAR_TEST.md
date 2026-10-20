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
3. Wait for initialization: the first `0100` request allows up to 60 seconds for
   automatic protocol search. Confirm the console records a valid `4100` ECU
   response and then the detected protocol from `ATDP` before the state is LIVE.
   Normal live requests retain their 2.5-second deadline. A missing or invalid
   ECU response leaves a connection fault with the command and reply in the log.
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

After a connection or polling failure, scroll below the paired-adapter card to
**Connection log** and tap **Copy report**. The report remains available after
disconnecting. Command timeouts identify the command, deadline, and exact bytes
received before the adapter prompt was missed. Failures are also written to
Android Logcat under the `JettaRecorder` tag. No timeout is automatically retried.

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

Mode changes wait for the in-flight polling reply and its `>` prompt before
sending setup commands. A cancelled poll still consumes its bounded reply,
then propagates cancellation. A transport timeout or I/O failure closes the
connection rather than allowing later commands to consume an old response.

Run this as a separate parked test; do not run the raw CAN monitor at the same
time.

1. Start the engine and let it idle. Connect until the normal dashboard is live.
2. Tap **Run discovery** under **Jetta sensor discovery**.
3. The app first requires OK replies to its setup commands and a valid `0100`
   response through `7E0`/`7E8`. If this control fails, it stops without testing
   any sensor identifiers and displays the setup failure. Export this result too.
   Discovery uses `ATAT0` and `STPTO 1000` to give the adapter a fixed one-second
   response window; Android's four-second deadline is a separate outer limit.
   Leave the engine running until all sixteen candidates have finished.
4. Confirm the dashboard resumes normal RPM and speed polling automatically.
5. Note which rows say **FOUND** and whether each preview is physically
   plausible. A response alone does not validate its scale or unit.
6. Tap **Export results** and retain the CSV unchanged.

The run sends a read-only Mode 01 `0100` control followed by `22xxxx` UDS
ReadDataByIdentifier requests to engine request ID `7E0` and accepts replies
from `7E8`. The CSV retains its original probe columns and adds `record_type`,
`command`, `app_version`, and `run_error`. Rows marked `setup` preserve every
completed setup exchange and the control reply; `probe` rows retain the sixteen
candidate results. An early setup failure exports cancelled candidates and the
error, without labeling them unsupported. Normal initialization restores the
adapter timing settings afterward. The run does not clear DTCs, change coding,
run actuators or write ECU data. If the app fails to restore normal polling,
disconnect and reconnect; preserve the console and exported CSV for diagnosis.

