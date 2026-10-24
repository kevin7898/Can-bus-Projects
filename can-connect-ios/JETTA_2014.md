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

A later build 7 recording transferred successfully and both phone and Mac receipts completed. The cancellation fix drains the current reply, reuses the foreground MFi session, and keeps the previous-task teardown barrier even after explicit Disconnect; build 7 closed it on backgrounding or failure; build 8 retains it while backgrounded. Regression tests cover opening and pending-read cancellation; latest repeated physical cancel/reconnect results are tracked in PR #7. Still required: trusted-scanner comparison, moving/load conditions, ignition-off/recovery, extended driving, and battery/heat measurements. Build 8 passed stationary physical app-switch, screen-lock and foreground ignition-cycle acceptance; simultaneous GPS+OBD is outside this build. See HARDWARE_VERIFICATION.md.


## Build 8: reviewed TP 2.0 measurements

Mode 09 identification matched engine calibration `03L997030M  9983` and transmission `02E300062B  9430`. Read-only physical probes established that these controllers answer KWP2000 through VW TP 2.0, while the tested UDS reads did not supply values. The implementation enables this path only after the matching profile, 11-bit CAN protocol and exact controller calibration are confirmed.

Engine measuring block 108 returned a typed ash-volume field (39 mL in the probe); the adjacent soot fields were blank, not zero. DSG block 19 returned a typed fluid-temperature field (81 °C, later 79 °C). Independent decoders expose ash volume and DSG fluid temperature through the existing signal picker and retain the negotiated ECU addresses and raw frames in each sample. At build 8, soot mass and detailed regeneration history remained unavailable: engine blocks 240/241 returned out-of-range and the tested service-22 reads were unsupported. Build 11 adds the separately verified block-114 soot field below. No regeneration, adaptation, programming, security or actuator commands are used.

TP 2.0 validates sequence, length, acknowledgments and negotiated timing. Each short measurement batch restores normal engine OBD configuration, including cancellation cleanup; unsupported blocks are not repeatedly queried. Synthetic tests cover controller gating, complete-frame decoding, blank fields, negative replies, cancellation/restoration and archive/wire provenance. These early single-shot probes did not establish integrated polling acceptance. Subsequent build-8 background/lock checks verified DSG polling; build-11 engine acceptance is recorded below.

Protocol and unit references: [TP 2.0 description](https://jazdw.net/tp20), [Ross-Tech 02E measuring block 019](https://wiki.ross-tech.com/wiki/index.php/6-Speed_Direct_Shift_Gearbox_%28DSG/02E%29), and [KWP typed measurement formula reference](https://github.com/domnulvlad/KLineKWP1281Lib). No third-party transport implementation was copied.

## Build 11: engine channel timing and soot

An on-car A/B test isolated the engine's D7 channel rejection: immediately after an ordinary engine RPM request, and after a three-second quiet interval, channel setup was rejected. After six seconds without OBD requests, setup returned D0 and block 108 repeatedly supplied ash. This is a diagnostic-session availability conflict, not proof that ash is unsupported. The reader waits six seconds before opening the engine TP 2.0 channel and treats D7/D8 as temporary; it retries on the next scheduled engine read instead of disabling the engine for the entire trip. It does not force-close another diagnostic client's channel.

Block 114 (hex 72), sixth typed field (zero-based index 5), returned type 7E and a grams value. The mapping was checked against the published 2013 Jetta TDI display reference below and observed on this exact engine calibration. `dpfSootG` is labelled **DPF soot mass**; we do not claim an independently measured mass or assign an unverified calculated-versus-measured subtype. Blank fields remain unavailable. The adjacent typed field is not exposed without a verified meaning. Blocks 240/241 remain unsupported and are no longer probed during normal polling.

Engine ash/soot refresh once per minute. The necessary six-second OBD quiet interval creates a real gap in ordinary RPM/speed samples; the recording remains open and no synthetic samples or timestamps fill the gap. The display uses a 75-second freshness window only for these two slower engine fields. DSG and other signals keep their shorter schedules and freshness windows. Disconnect clears all live readings. An attempt to read ordinary RPM inside the TP 2.0 session returned a negative response, so this build retains the validated separate protocols. Extended driving and comparison against a trusted diagnostic tool remain outstanding.

Physical probe values were 39 mL ash and 11.1 g soot; these are private acceptance observations, never hard-coded defaults. The interface uses the existing signal picker; default cards and layout are unchanged.

Signal-reference facts: [2013 Jetta TDI display](https://github.com/seishuku/teensycanbusdisplay/tree/e6df5a54c18a8ede47ad4dcdc2f86aab48bff339), `main.c` selects block 72 hex/index 5 for soot and `vwtpkwp2k.c` identifies typed grams. No transport implementation was copied.

The installed standalone build 11 subsequently recorded four consecutive normal polling cycles at 39 mL ash and 11.1 g soot, alongside actual engine RPM and DSG temperature in the same active recording. The cycles were roughly 67–70 seconds apart, including protocol switching and other work. All 20 pre-update saved trips were retained. Background/lock continuity with this new quiet interval and trusted-tool accuracy remain to be verified.

## Build 13: polling by rate of change

Ash and soot retain their 60-second post-completion schedule. Ambient temperature and barometric pressure now use 60 seconds; tank fuel level uses 30 seconds. Each is read immediately on connection, and its display freshness includes 15 seconds of scheduling/protocol-switch allowance. Disconnect or a missing response clears the value; recordings contain only actual received samples. RPM, speed, fuel rate, engine load, airflow, boost, DPF differential pressure and exhaust temperatures keep their faster schedule; regeneration status/trigger remains on the three-second schedule.

Soot mass in grams, ECU regeneration trigger in percent, and ash volume in mL remain distinct. No calibrated soot-mass denominator or ash capacity has been verified for this ECU software, so the app does not label either as physical DPF fullness or remaining filter life. General VW training describes load-dependent regeneration and separate soot models, but is not a verified threshold for this calibration: [VW SSP 826803](https://www.vaglinks.com/docs/ssp/VWUSA.COM_SSP_826803_2.0L_TDI.pdf). A future derived percentage must identify its reference threshold and keep the raw grams.

Synthetic transport checks cover immediate slow readings, repeated fast RPM without repeated slow queries, expiration, disconnect clearing and absence of fabricated recording samples. The new cadence still needs a timed on-car check. Layout, default cards and styling are unchanged.

## Build 14: combined soot card

At the user's request, the existing soot-mass card also shows the ECU's `dpfRegenTrigger` under the label **% full**. Grams and percentage remain separately sourced; the picker and accessibility label identify the percentage as the ECU regeneration trigger. There is no inferred soot-capacity denominator and no display clamp. The currently verified Mode 01 field itself encodes only 0–100%; a physically meaningful value above 100% would require a separately verified reference threshold. Each reading retains its own freshness window and unavailable state. Card dimensions, default choices and surrounding layout stay unchanged.

## Build 23: recover enhanced readings within the same trip

A real drive retained ordinary OBD and DSG samples after engine ash/soot stopped. The exact historical failure is unavailable, but inspection found two permanent-disable paths: most TP 2.0 errors disabled that controller until the scanner was recreated, and outer measurement/cleanup errors disabled all enhanced controllers. Both paths now retry without requiring Finish, a new trip or a new Bluetooth connection when ordinary OBD remains healthy.

Controller failures use bounded exponential backoff: engine starts at 60 seconds, DSG at 30 seconds, doubling to a maximum of five minutes. A successful batch clears that controller's failure escalation. D7/D8, missing/malformed setup, lost channels and acknowledgment/assembly failures use the same recoverable path. Healthy controllers continue. Each retry still uses the reviewed software fingerprint, read-only group allowlist and six-second engine quiet interval.

An explicit `7F2131` group rejection clears that value and defers that group for five minutes rather than permanently marking it unsupported. It does not suppress another group's valid reading. Blank or undecodable replies likewise remain unavailable with delayed retry. Groups 240/241 remain outside normal polling. No stale values or zero placeholders are inserted into recordings, and successful values retain their receipt timestamps and raw CAN frames.

Standard engine OBD settings are restored between batches and failures. If batch cleanup itself fails, the scanner explicitly restores all normal settings and verifies a real RPM reply before continuing. If that also fails, normal scanner-disconnect handling protects the current trip; unsafe raw-CAN state is never treated as successful recovery. This change leaves normal healthy polling intervals, cards, soot percentage and trip boundaries unchanged.

A separate bounded local `scanner-events.json` retains 256 recovery/error/session events across scanner reconnects. Routine raw exchanges still use the 512-entry diagnostics file. Both remain in private app storage and are excluded from recordings/transfers and Git. This makes the next physical dropout diagnosable after routine polling has overwritten its raw trace.

Synthetic tests cover repeated bounded failures, successful recovery/reset, explicit group rejection and delayed re-probe, partial ash before soot channel loss, DSG independence, cancellation/restoration, event-log retention and a full scanner/AppStore trip that loses enhanced cleanup, continues RPM, then records fresh ash/soot with the same trip ID and one transport open. Physical long-drive recovery on the Jetta/MX+ still needs verification; software tests do not establish the original on-car failure cause.

Build-23 local validation: 96 unit tests passed, one hardware-only test skipped; the signed iPhone build succeeded. The app was installed and launched with all 32 saved recordings, profiles, transfers, server settings and regeneration baseline unchanged. The design was not edited. GitHub CI and physical recovery acceptance are tracked separately in PR #7.
