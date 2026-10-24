# 2014 Jetta TDI DSG readings

The real vehicle profile must contain year 2014, make Volkswagen (or VW), model Jetta, diesel/TDI engine, and DSG transmission. The user's existing profile was updated through the native vehicle editor, preserving its ID and history. Engine requests use `7E0`, responses `7E8`, headers enabled, no DLC column, and ISO-TP reassembly. Other profiles retain the generic scanner path.

The old header-free RPM reply contained two slightly different values from the engine and transmission. The old decoder correctly rejected that ambiguity, leaving RPM unavailable. Selecting and attributing engine ECU `7E8` resolves it without guessing which value is first or averaging ECU replies.

Support discovery now follows continuation bits through all Mode 01 pages, including `60` and `80`. The previous limit at page `40` omitted the Jetta's advertised boost, exhaust, DPF pressure and regeneration PIDs. Live polling schedules fast and slower signals separately. Each reply keeps its original bytes, receipt timestamp, command, request ECU and response ECU; recordings and Mac transfers preserve those fields. Unsupported flags clear the corresponding field rather than carrying readings forward.

## Confirmed on the car

On October 23, 2026, the MX+ returned these 13 PIDs and 20 fields in a physical iPhone recording:

| PID | Available readings |
| --- | --- |
| 0C / 0D | Engine RPM / vehicle speed |
| 05 / 46 / 33 | Coolant / outside temperature / barometric pressure |
| 5E / 42 / 04 / 10 | Fuel rate / ECU voltage / engine load / mass airflow |
| 70 | Boost A actual and commanded, absolute kPa |
| 78 | Four separately identified exhaust temperatures |
| 7A | DPF differential pressure, signed kPa |
| 8B | Regeneration status, type, normalized trigger, average regeneration distance |

Gauge boost uses fresh measured actual boost minus measured barometric pressure. Legacy MAP PID `0B` was not advertised and is not substituted with a fabricated value. Fuel use in L/100 km requires measured fuel rate and nontrivial vehicle speed; it remains unavailable while parked. Fuel rate in L/h is independently selectable.

Tap any existing Live card to choose the new signals. Layout, typography, colours, navigation and default card choices are unchanged. The normalized DPF regeneration trigger is **not soot mass or soot percentage**. An unsupported field, including average regeneration interval in this capture, remains unavailable.

## VW-specific candidates

The Android app's curated read-only UDS candidates were tested using engine `7E0/7E8`, plus DSG temperature candidate `2238BF` using `7E1/7E9`. Captured candidate replies were NO DATA; none are enabled in normal polling or displayed with unverified engineering units. The user-supplied jverkoey fork's generic transmission temperature and gear definitions are restricted to 2015 and newer, so they were not applied to this 2014 DSG. No actuator tests, fault clearing, security access or regeneration commands were issued.

References: [Android observed standard profile](https://github.com/kevin7898/Can-bus-Projects/blob/feature/jetta-pocket-recorder/jetta-recorder-android/app/src/main/java/ca/jettatelemetry/app/pocket/ObservedJettaProfile.kt), [Android VW candidate pack](https://github.com/kevin7898/Can-bus-Projects/blob/main/jetta-recorder-android/app/src/main/java/ca/jettatelemetry/app/obd/JettaDiagnosticDiscovery.kt), [user-supplied Jetta signal set](https://github.com/jverkoey/Volkswagen-Jetta/blob/main/signalsets/v3/default.json). Attribution and bundled licenses: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Evidence and remaining checks

Physical captures, phone backups, Mac originals, screenshots and diagnostic journals stay outside Git. The bounded last-session journal is protected in the iPhone app's private Application Support/CANConnect directory, contains real diagnostic replies, and is never automatically uploaded or added to transfer payloads. Old recordings decode without ECU metadata.

A later build 6 recording transferred successfully and both phone and Mac receipts completed. The cancellation fix releases the MFi session and keeps the previous-task teardown barrier even after explicit Disconnect. Regression tests cover opening and pending-read cancellation; latest repeated physical cancel/reconnect results are tracked in PR #7. Still required: trusted-scanner comparison, moving/load conditions, ignition-off/recovery, extended driving, and battery/heat measurements. Backgrounding saves/stops scanner recording; simultaneous GPS+OBD is outside this build. See HARDWARE_VERIFICATION.md.
