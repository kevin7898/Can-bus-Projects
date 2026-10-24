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

A later build 7 recording transferred successfully and both phone and Mac receipts completed. The cancellation fix drains the current reply, reuses the foreground MFi session, and keeps the previous-task teardown barrier even after explicit Disconnect; build 7 closed it on backgrounding or failure; build 8 retains it while backgrounded. Regression tests cover opening and pending-read cancellation; latest repeated physical cancel/reconnect results are tracked in PR #7. Still required: trusted-scanner comparison, moving/load conditions, ignition-off/recovery, extended driving, and battery/heat measurements. Build 8 adds External Accessory background recording, pending a new physical switch/lock acceptance run; simultaneous GPS+OBD is outside this build. See HARDWARE_VERIFICATION.md.


## Build 8: reviewed TP 2.0 measurements

Mode 09 identification matched engine calibration `03L997030M  9983` and transmission `02E300062B  9430`. Read-only physical probes established that these controllers answer KWP2000 through VW TP 2.0, while the tested UDS reads did not supply values. The implementation enables this path only after the matching profile, 11-bit CAN protocol and exact controller calibration are confirmed.

Engine measuring block 108 returned a typed ash-volume field (39 mL in the probe); the adjacent soot fields were blank, not zero. DSG block 19 returned a typed fluid-temperature field (81 °C, later 79 °C). Independent decoders expose ash volume and DSG fluid temperature through the existing signal picker and retain the negotiated ECU addresses and raw frames in each sample. Soot mass and detailed regeneration history remain unavailable: engine blocks 240/241 returned out-of-range and the tested service-22 reads were unsupported. No regeneration, adaptation, programming, security or actuator commands are used.

TP 2.0 validates sequence, length, acknowledgments and negotiated timing. Each short measurement batch restores normal engine OBD configuration, including cancellation cleanup; unsupported blocks are not repeatedly queried. Synthetic tests cover controller gating, complete-frame decoding, blank fields, negative replies, cancellation/restoration and archive/wire provenance. The integrated polling loop still needs a sustained on-car check alongside standard RPM and background acquisition; the earlier single-shot probes do not establish that acceptance.

Protocol and unit references: [TP 2.0 description](https://jazdw.net/tp20), [Ross-Tech 02E measuring block 019](https://wiki.ross-tech.com/wiki/index.php/6-Speed_Direct_Shift_Gearbox_%28DSG/02E%29), and [KWP typed measurement formula reference](https://github.com/domnulvlad/KLineKWP1281Lib). No third-party transport implementation was copied.
