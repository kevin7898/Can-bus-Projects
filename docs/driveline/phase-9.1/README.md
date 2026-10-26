# DriveLine Phase 9.1 field-data polish evidence

Prepared October 26, 2026.

## Classification

**Implementation and automated qualification complete; physical field qualification pending.**

Work started from the fetched `origin/codex/driveline-drive-ledger` commit
`9dfc043a2b733760c7cdf2650445ef7ac2953723`. The unrelated dirty checkout at
`/Users/kevinstuparyk/Documents/ChatGPT/Can connect` and the divergent named
integration worktree were not changed. No app release, tag, distribution upload,
branch merge, database reset, or installed-device replacement was performed.

The installed iPhone build was deliberately left untouched because the app
cannot remotely prove that a recording is inactive. Replacement requires the
user to confirm that any active recording has finished and saved.

## Fuel prefill and additive storage

The shared schema remains version 2 and decodes its earlier shape. Optional
`stationAddress`, `odometerProvenance`, and `stationProvenance` fields were
added to fuel entries. Receipt bytes remain external to primary JSON and the
existing complete archive/restore path still carries them. No saved drive or
observation migration/reset is required.

Odometer provenance records the value, observation time, stable source
identifier, optional recording ID, and scanned/manual/fuel-entry source type.
The selection policy is vehicle-scoped and chooses a fresh current trusted scan,
then a stored trusted scan, then the latest real fill. Unknown stays blank and
trip distance is never added to invent an odometer.

There is no reviewed Pelican/VW odometer decoder in the current registry.
Accordingly, Phase 9.1 implements the persisted pipeline but does **not** guess
a PID or create a scanned value. Existing fuel history is the only current
automatic odometer fallback and is labelled “From last fuel entry.”

The Add Fuel sheet presents immediately, requests location only from that
workflow, accepts a sufficiently recent/accurate one-shot fix, and reverse
geocodes asynchronously. It stores a formatted address and only suggests a POI
name for a single confidently fuel-related match. Raw coordinates are neither
logged nor added to a fuel entry. Denied, restricted, timeout, offline,
unavailable, and no-result states retain manual entry. Typing or explicitly
clearing either odometer or station claims that field, so a late async result
cannot overwrite it. Refresh/Use Current Location and Clear remain explicit.

## Freshness semantics

The live-card contradiction was confirmed in source: `MetricTile` replaced the
real timestamp with `Date()` for every available value. The actual observation
timestamp and semantic state now flow through `MetricTile`, `AvailabilityValue`,
and `FreshnessLabel`. Heading icon, value style, footer icon, and footer text
therefore resolve from one state.

Fresh values are labelled Live or by recent age. Stale last-known values remain
visible and are labelled `Stale` with age. Never observed, unsupported, and
scanner disconnected are distinct textual/icon states. Derived gauge boost is
reported supported only when both a compatible absolute pressure input and
barometric pressure are scheduled.

## OBD scheduling and diagnostics

The source-level starvation hypothesis was confirmed: the prior recorder ran
every due standard PID in one serialized batch before VW enhanced work. A slow
or nonresponding optional request could therefore push RPM and speed far past
their intended opportunity.

`OBDPollScheduler` now issues one deadline-selected request at a time:

- Core: engine RPM and vehicle speed.
- Secondary: coolant, MAP/absolute boost, fuel rate, load, voltage, MAF, and
  other useful live values.
- Slow/diagnostic: barometric pressure, fuel level, environmental values,
  optional extended Mode 01 PIDs, and separately bounded VW windows.

Core gets frequent opportunities, while bounded tier fairness prevents a
continuously overdue core set from permanently starving secondary/slow work.
Round-robin selection is used inside each tier. Timeout, NO DATA, malformed,
and ambiguous responses apply exponential per-PID backoff capped at five
minutes; periodic probes allow recovery. One transient failure never marks a
signal permanently unsupported.

VW work is one controller per explicit window and is admitted only after fresh
core success. Normal RPM/speed is immediately reprioritized afterward. Existing
ECU/header validation remains authoritative: conflicting anonymous 7E8/7E9
values are rejected instead of combined. MAP/absolute boost and barometric
pressure remain scheduled when the ECU reports support; gauge boost remains
unavailable without sufficiently fresh compatible inputs.

In-memory privacy-safe diagnostics include request deadline delay, response
latency, timeout/NO DATA/malformed/ambiguous counts, missed deadlines, effective
successful cadence, evidence coverage, backoff remaining, and enhanced-window
count/total/maximum duration. They contain PID numbers and aggregate timing only,
not VINs, credentials, addresses, coordinates, adapter serials, or payloads.

## Trip Story responsiveness

Trip selection now shows the destination shell and cancellable loading state
immediately. `TripStorySnapshotBuilder` prepares immutable summary, evidence
timeline, signal metadata, bounded display series, route geometry, event markers,
and a cursor index off the main actor. A deterministic recording-content
fingerprint keys a three-entry LRU. Cancelled rapid selections are not cached or
presented as another trip.

Cursor lookup uses pre-indexed timestamp arrays and binary search without
interpolation or forward-fill. Cursor movement changes only the selected marker
and chart rule; it does not rebuild/refit route geometry or regenerate the full
chart. Long evidence lists use lazy layout. Annotation sidecar changes are
excluded from the immutable telemetry fingerprint. Display reduction remains
visual only; archives and in-memory source observations stay byte/value exact.

Trip Story now includes the recorded source identifier beside cursor values, so
GPS and OBD evidence with different coverage cannot be mistaken for one source.

## Automated evidence

Toolchain: Xcode 27.2 (27B48), Swift 6.4.2.

| Gate | Result |
| --- | --- |
| Shared package | 39 passed, 0 failed, 0 skipped |
| Mac Swift package | 34 passed, 0 failed, 0 skipped |
| Mac Debug build | Passed |
| Mac API integration | Passed recording/fuel-only schema-2 transfer, external receipt bytes, stable IDs, exact originals, authentication, receipts, deduplication/conflict, trip isolation, retrieval, and vehicle validation |
| iPhone unit tests | 150 executed, 149 passed, 1 expected skip, 0 failed |
| iPhone UI tests | 22 executed, 20 passed, 2 expected skips, 0 failed |
| iPhone total | 172 executed, 169 passed, 3 expected skips, 0 failed |
| Compact largest-accessibility rerun | 2 passed, 0 failed |
| Complete strict-concurrency builds | Mac and iPhone passed |
| Static analysis | Mac and iPhone passed |
| Unsigned Release archives | Mac and iPhone passed |

The three expected skips are the pre-existing host-loopback transfer test and
two Live Activity checks that require a signed physical device.

Unsigned outputs are `/tmp/DriveLinePhase91Release/DriveLine-Mac.xcarchive`
(33 MB) and `/tmp/DriveLinePhase91Release/DriveLine-iPhone.xcarchive` (25 MB).

The local qualification commands include:

```sh
cd shared/DriveLineShared && swift test
cd mac-app && swift test
xcodebuild -project mac-app/CANConnect.xcodeproj -scheme CANConnect -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/driveline-phase91-mac CODE_SIGNING_ALLOWED=NO build
python3 mac-app/scripts/api_integration.py /tmp/driveline-phase91-mac/Build/Products/Debug/CANConnect.app/Contents/MacOS/CANConnect
xcodebuild -project can-connect-ios/CANConnect.xcodeproj -scheme CANConnect -destination 'platform=iOS Simulator,id=C975E238-AE3A-4B13-9FE8-477B69F94928' -derivedDataPath /tmp/driveline-phase91-ios-final CODE_SIGNING_ALLOWED=NO test
xcodebuild analyze -project mac-app/CANConnect.xcodeproj -scheme CANConnect -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild analyze -project can-connect-ios/CANConnect.xcodeproj -scheme CANConnect -destination 'platform=iOS Simulator,id=C975E238-AE3A-4B13-9FE8-477B69F94928' CODE_SIGNING_ALLOWED=NO
xcodebuild -project mac-app/CANConnect.xcodeproj -scheme CANConnect -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO SWIFT_STRICT_CONCURRENCY=complete build
xcodebuild -project can-connect-ios/CANConnect.xcodeproj -scheme CANConnect -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO SWIFT_STRICT_CONCURRENCY=complete build
xcodebuild archive -project mac-app/CANConnect.xcodeproj -scheme CANConnect -configuration Release -destination 'generic/platform=macOS' -archivePath /tmp/DriveLinePhase91Release/DriveLine-Mac.xcarchive CODE_SIGNING_ALLOWED=NO
xcodebuild archive -project can-connect-ios/CANConnect.xcodeproj -scheme CANConnect -configuration Release -destination 'generic/platform=iOS' -archivePath /tmp/DriveLinePhase91Release/DriveLine-iPhone.xcarchive CODE_SIGNING_ALLOWED=NO
```

Focused tests cover vehicle-scoped odometer priority/fallback/rejection,
pristine-field behavior, location success/failures/clear/refresh, additive
contract decode, all freshness transitions, scheduling fairness/backoff/recovery,
pressure scheduling, ECU separation, VW-window isolation, bounded snapshot LRU,
content invalidation, cancellation, display bounds, binary cursor parity,
annotation isolation, and the existing sanitized 500-trip/1,000,000-observation
corpus. Every large fixture is debug-only, labelled sample, and contributes zero
to real totals.

## GitHub Actions

| Workflow | Run ID | Commit | Result |
| --- | --- | --- | --- |
| iOS companion | `40321563768` | `5a8cc10eaee0a7eab1894518cddff52fd19ef05a` | Passed: 150 unit tests (1 expected skip) and 22 UI tests (2 expected skips) |
| CAN CONNECT Mac | `40314583949` | `b8fe5a759bff31f3e36ac8c9ebb55b4c9fcd49e5` | Passed |

The first iOS run, `40314583974`, was cancelled by the former 25-minute job
limit while still executing the serial suite. Run `40318089628` then exposed a
persisted simulator-TCC interaction: an earlier fuel-form permission case left
location unavailable for the final synthetic scanner/GPS test. The workflow now
builds and installs first, grants only the CI simulator a known location state,
then runs the unmodified production app with `test-without-building`. The
previously failing focused test passed locally in 64.767 seconds before the full
CI rerun passed. Production permission requests and denied-state behavior were
not bypassed or changed.

The implementation was published as a non-forced fast-forward from the verified
remote head. Its Git tree `5587762ee745bc8f7af32f9207343255cd9b0779`
matches the locally tested implementation tree exactly. A separate user-authored
documentation commit that arrived during validation was preserved in history;
neither branch was rewritten or force-pushed.

## Physical acceptance still required

The user-observed baseline is retained without exaggeration: speed had 100%
coverage, RPM 27% with large gaps, and gauge boost 0%. No after-drive coverage
number is claimed until the actual Jetta and adapter complete the parked-idle,
20-minute mixed-drive, ignition-cycle, safely parked fuel form, and large-trip
interaction run.

The physical run must capture aggregate per-PID cadence/latency/failure counts,
resulting RPM/speed/boost coverage, fresh/stale/unavailable screenshots,
odometer/address provenance and location failure behavior, plus Time Profiler,
SwiftUI, and Core Animation baseline/final measurements. Acceptance targets are
an immediate Trip Story shell, no unexplained normal-use main-thread stall over
100 ms, cursor p95 below 50 ms, correct rapid switching, and bounded memory.

Private VINs, routes, coordinates, addresses, adapter serials, credentials, and
raw personal recordings must remain outside Git and screenshots. Physical
numbers and screenshots will be appended only after that controlled run.
