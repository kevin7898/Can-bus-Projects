# CAN / CONNECT Pocket Recorder

The launcher now opens a small, platform-native recorder for the OnePlus 6T and OBDLink MX+. It uses standard PID requests observed in the supplied Car Scanner log, preserves raw replies, records phone GPS, and queues completed files for an authenticated HTTPS endpoint. It does not require Car Scanner or copy its app/database.

See [Pocket Recorder setup, limitations and upload contract](docs/POCKET_RECORDER.md).

The source below documents the earlier Compose acquisition checkpoint, which remains in the project for development. Its foreground-only limitation applies to that legacy screen, not the new foreground recorder service.

---

## Legacy Jetta Recorder — Android hardware proof

This checkpoint turns the Phase 1 telemetry contract into the first native
Android acquisition slice for the user's OnePlus 6T and OBDLink MX+.

## What works in this checkpoint

- Lists already-paired classic Bluetooth devices and favors OBDLink/MX names.
- Connects to the MX+ with the standard RFCOMM Serial Port Profile UUID.
- Initializes the ELM/STN command interface and automatically selects protocol.
- Polls and decodes SAE Mode 01 RPM, speed, coolant, MAP and barometric pressure.
- Calculates gauge boost as `MAP absolute − BARO absolute`.
- Shows a responsive portrait/landscape VW-style live proof screen.
- Reports the achieved successful-sample rate.
- Includes a manual AT/OBD console for on-car diagnosis.
- Includes JVM tests for Mode 01 decoding and boost math.
- Includes a receive-only raw CAN probe for the MX+ using STN protocol 31
  (ISO 11898, 11-bit, 500 kbit/s).
- Displays frame rate, unique identifiers and a live frame sample.
- Exports the exact webCAN CSV schema consumed by the CSS Electronics
  reverse-engineering scripts.
- Runs a curated, read-only UDS discovery pack against engine ECU `7E0/7E8`.
- Preserves every raw diagnostic reply alongside candidate decoded values and
  exports a validation CSV before any signal is promoted to the dashboard.
- Builds and retains a debug APK through GitHub Actions.

## Toolchain

- Android Gradle Plugin 8.7.3
- Kotlin Android + Compose plugins 2.0.21
- Gradle 8.9
- compile/target SDK 35; minimum SDK 26
- Compose BOM 2024.12.01
- JDK 17

The wrapper properties are included, but the binary wrapper JAR is intentionally
not hand-vendored. Open the project in a compatible Android Studio installation, or run
`gradle wrapper --gradle-version 8.9` once with a local Gradle installation.
GitHub Actions does not require the wrapper JAR; the workflow installs the
pinned Gradle version before running tests and assembling the APK.

## Build

1. Open this folder as a project in Android Studio.
2. Let Gradle sync and install SDK 35 when prompted.
3. Connect the OnePlus 6T with USB debugging enabled.
4. Run the `app` debug configuration.
5. Follow [`docs/ON_CAR_TEST.md`](docs/ON_CAR_TEST.md).

## Architecture

```text
Compose UI / MainViewModel
          ↓
      ObdRepository       polling, state and derived boost
          ↓
      Elm327Client        initialization and commands
          ↓
   ObdLinkTransport       Bluetooth RFCOMM socket
```

The UI never parses adapter replies. The transport never knows PID formulas.
That separation is important: the next slice can add the persistent recorder,
GPS and Volkswagen UDS profile without rebuilding the dashboard.

## Raw CAN probe

While connected, choose **Start probe**. Diagnostic PID polling pauses and the
adapter is configured for ISO 11898 raw CAN at 11-bit/500 kbit/s. `STCMM0` keeps
the MX+ receive-only (no CAN acknowledgements) and `STM` preserves raw frame
boundaries. Stop the probe before exporting.

The exported header is exactly:

```text
TimestampEpoch;BusChannel;ID;IDE;DLC;DataLength;Dir;EDL;BRS;ESI;RTR;DataBytes
```

That file feeds the CSS Electronics `survey.py`, `correlate.py`, `bitsearch.py`,
`build_dbc.py` and `verify.py` pipeline directly. After stopping, the app
restores ordinary ELM/STN initialization and resumes dashboard polling.

## Jetta sensor discovery

Choose **Run discovery** while the engine is running. Dashboard polling pauses,
the MX+ targets engine ECU `7E0`, and the app sequentially sends only UDS
service `0x22` (ReadDataByIdentifier). The initial pack checks sixteen
high-value candidates: boost, oil temperature, fuel flow and DPF temperatures,
pressure, soot, ash and regeneration counters. It does not enter a diagnostic
session, perform an actuator test, clear faults, code a module or write data.

Results distinguish positive replies, UDS negative responses, no-data replies
and transport errors. **Found** means that the ECU answered; it does not yet
prove that OBDb's candidate scaling or engineering unit is correct. Export the
result CSV after the run so the raw bytes and decoded preview can be compared
against driving conditions. Normal Mode 01 polling is restored automatically.

The candidate definitions are kept in a single attributed profile. See
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

## Known boundaries

- The app must be in the foreground in this checkpoint.
- Only bonded classic-Bluetooth devices are listed; pairing remains in Android
  settings for now.
- Commands are serialized, so manual console commands safely wait behind a
  current poll request.
- The manual console is unavailable while the raw monitor owns the adapter
  stream; stop capture before issuing a command.
- The console and raw CAN monitor are unavailable while Jetta sensor discovery
  owns the adapter request stream.
- The poller proves the path and measures throughput; the full priority/freshness
  scheduler from Phase 1 comes next.
- GPS, Room storage, trip lifecycle, reconnection and background recording are
  intentionally not claimed yet.

## Next acceptance gate

Run the on-car proof and collect:

- connection and initialization success;
- adapter identity/firmware and detected CAN protocol;
- RPM/speed response;
- MAP, BARO and idle gauge-boost values;
- achieved sample rate with five active signals.

Once those values are real, the next code pass adds persistent recording,
phone GPS and a foreground recorder service around the proven transport.

