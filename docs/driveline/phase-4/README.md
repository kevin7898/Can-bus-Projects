# DriveLine Phase 4 evidence

Phase 4 starts at the pushed Phase 3 tip
`268533bce6afd193537e620cefb09c433e9b083d`. Work was performed in a separate
managed worktree on `codex/driveline-phase-4`; the existing dirty
`codex/ios-companion` checkout and its untracked Mac build outputs were not
changed.

## Buildable commits

1. `c2512c99a95c73fa93881c71660fab346d18b614` — shared evidence contracts.
2. `3bffad094772c9f7e3ae8d9e9df3a8705e013322` — cross-platform Journey Ledger.
3. `db756176670d14f80b595dd6d97afd5a33dedb6d` — auditable Trip Story playback.
4. `55cf4535d23a93de936bdb31821eee48735a7cfd` — distinct Fuel Ledger evidence.
5. `55e57369ae227e17a6234aab5b1e78fc4deff35b` — synchronized route and signal cursors.
6. The Phase 4 tip adds final correctness/UI tests, sanitized fixtures,
   accessibility repairs, screenshots, and this evidence record.

## Implemented surfaces and evidence rules

Journey Ledger is backed by the real platform stores on both apps. Rows expose
recording identity, vehicle, time, measured duration and distance, source
combination, known start/finish places, transfer/import state, GPS and OBD
coverage, degraded intervals, fuel availability, purpose, and review state.
Vehicle, date, source, purpose, and quality filters operate on the selected
library. Personal, Business, Commute, Service, Test, and Other are stable
purpose values.

Purpose, review, note, start place, and finish place are local sidecar metadata
keyed by stable recording ID. Editing them does not rewrite an archive, an
original import, or a frozen transfer payload, and the UI makes no cross-device
annotation-sync claim.

Trip Story combines the recorded route, one shared playback position, measured
summary values, coverage, start/finish context, independently chosen signals,
and a chronological factual timeline. GPS/scanner starts, losses and
recoveries, recording boundaries, low fuel-rate coverage, normalized DPF regen
trigger observations, and preserved transfer/import events are derived only
from stored evidence. Timeline selection, the route marker, and charts share
real timestamps. Missing observations remain unavailable; gaps are visible and
are not interpolated or forward-filled.

Fuel Ledger keeps purchased litres, full/partial-fill state, station, date,
odometer, cost, currency, receipt metadata, cost per litre, valid full-fill
boundary economy, measured trip fuel, and OBD-derived trip economy distinct.
Tank economy includes intervening partial fills but never crosses vehicles.
Sample fills and trips are labelled and excluded from real totals.

Signals uses independent selectors, permits duplicate choices, displays real
observation times, breaks lines at gaps, and identifies units, source,
coverage, freshness, and measured/derived provenance. Gauge boost is derived
only from compatible absolute boost/MAP and sufficiently fresh asynchronous
barometric observations and carries algorithm ID `driveline.boost-gauge.v1`.
The regeneration trigger is normalized to an ECU trigger indicator and is
never presented as physical DPF fullness. Preserved command/reply evidence is
available at the shared cursor where recorded.

## Contracts and migrations

- The archive wire schema remains version 2. Schema-1 decoding, schema-2
  round trips, stable vehicle/recording identities, unknown extension data,
  original bytes, hashes, fills, receipts, and exact timestamps remain intact.
- `DriveLineTripEvent` gained additive, backward-compatible optional/defaulted
  evidence fields: end timestamp, source ID, severity, confidence, algorithm
  identifier/version, and evidence references. No competing event store was
  introduced.
- iPhone `StoredState` advances from schema 3 to 4 to store journey annotation
  sidecars. Older states decode with an empty annotation dictionary and are
  upgraded in memory without a reset.
- Mac `LibraryState` advances from schema 2 to 3 for the same sidecar. Older
  libraries decode with empty annotations and are preserved. The API
  integration explicitly exercises a schema-2 archive inside this schema-3
  library.
- No telemetry database migration, cloud dependency, account system, data
  reset, or queued-payload mutation was added.

## Correctness agreement

The unchanged golden archive still produces identical results through the
shared, Mac, and iPhone adapters:

- duration: 20 seconds;
- GPS distance: approximately 0.20015 km;
- measured trip fuel: 0.02000 L;
- trip economy: approximately 9.9925 L/100 km;
- fuel-rate coverage: 100%;
- provenance: synthetic GPS and synthetic OBD; and
- gauge boost: 35 kPa from asynchronous absolute pressure and fresh barometer.

Focused tests also cover schema-1/schema-2 compatibility, unknown extension
data, stable identities, local annotation persistence, unchanged archive and
frozen transfer bytes, sample exclusion, multiple vehicles, GPS-only,
OBD-only, mixed and empty recordings, GPS/scanner loss, low fuel coverage,
long chart/integration gaps, full/partial boundaries, synchronized cursor
selection, normalized DPF evidence, no fabricated events, and duplicate Finish
protection.

## Local validation

Commands were run from the Phase 4 worktree:

```sh
(cd shared/DriveLineShared && swift test)
(cd mac-app && swift test)

xcodebuild build \
  -project mac-app/CANConnect.xcodeproj \
  -scheme CANConnect \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/driveline-p4-mac-final-20261025b \
  CODE_SIGNING_ALLOWED=NO

python3 mac-app/scripts/api_integration.py \
  /tmp/driveline-p4-mac-final-20261025b/Build/Products/Debug/CANConnect.app/Contents/MacOS/CANConnect

xcodebuild test -parallel-testing-enabled NO \
  -project can-connect-ios/CANConnect.xcodeproj \
  -scheme CANConnect \
  -destination 'platform=iOS Simulator,name=DriveLine iPhone 17 Pro Max,OS=27.2' \
  CODE_SIGNING_ALLOWED=NO

xcodebuild test -parallel-testing-enabled NO \
  -project can-connect-ios/CANConnect.xcodeproj \
  -scheme CANConnect \
  -destination 'platform=iOS Simulator,name=DriveLine compact layout check,OS=27.2' \
  -only-testing:CANConnectUITests/SmokeTests/testPhase4JourneyStoryFuelAndSignalsAreReachable \
  CODE_SIGNING_ALLOWED=NO
```

- Shared package: 19 passed, 0 failed.
- Mac Swift package: 24 passed, 0 failed. The existing non-failing optional
  `pkg-config` / sqlite3 metadata warning remains; SQLite tests pass.
- Mac Xcode Debug build: passed. The only build diagnostics were destination
  disambiguation and App Intents metadata-not-used warnings.
- Mac isolated API integration: passed authentication, schema-2 mixed GPS/OBD
  and receipt transfer into a schema-3 sidecar library, stable identities,
  exact-original preservation, hash deduplication/conflict handling, receipt
  processing, trip retrieval, and vehicle validation.
- iPhone 17 Pro Max / iOS 27.2 complete unit and UI suite: 123 executed,
  120 passed, 0 failed, and 3 expected skips.
- Compact iPhone / iOS 27.2 at
  `accessibility-extra-extra-extra-large`: focused Journey Ledger, Trip Story,
  synchronized Signals, and Fuel Ledger route passed, 1 passed and 0 failed.

The expected skips are the opt-in native-Mac loopback integration and the two
Live Activity checks requiring physical lock-screen or Dynamic Island surfaces.

## Layout and accessibility checks

- iPhone 17 Pro Max Journey Ledger, Trip Story, and Fuel Ledger were inspected
  in explicit light and dark appearance. Status always includes text or an icon
  in addition to colour, and sample totals remain zero in both appearances.
- The compact simulator was checked at the largest accessibility Dynamic Type
  category. The Trip Story header, source/status stack, Done action, scrollable
  map, playback, evidence, signals, and Fuel filters remain readable and
  reachable without horizontally clipped controls.
- Mac was inspected at the 1080 by 720 minimum and 1540 by 1000 widescreen
  sizes in light and dark. Journey filters, ledger selection, route, Fuel
  evidence, all six independent Signal cards, vehicle selection, and secondary
  navigation remain reachable. Native controls retain keyboard focus semantics
  and accessibility labels; Phase 4 adds no custom key interception.
- Empty, populated, GPS-only, OBD-only, mixed-source, degraded, and unavailable
  states were exercised by focused policy/platform tests. The screenshots use
  debug-only sanitized fixtures in isolated temporary libraries. Every fixture
  journey/fill is labelled sample and contributes zero to real totals.

## Screenshots

- [iPhone Journey Ledger, light](screenshots/iphone-17-pro-max-journey-ledger-light.png)
- [iPhone Journey Ledger, dark](screenshots/iphone-17-pro-max-journey-ledger-dark.png)
- [iPhone Trip Story, light](screenshots/iphone-17-pro-max-trip-story-light.png)
- [iPhone Trip Story, dark](screenshots/iphone-17-pro-max-trip-story-dark.png)
- [iPhone Fuel Ledger, light](screenshots/iphone-17-pro-max-fuel-ledger-light.png)
- [iPhone Fuel Ledger, dark](screenshots/iphone-17-pro-max-fuel-ledger-dark.png)
- [Compact iPhone Trip Story, largest Dynamic Type](screenshots/iphone-compact-trip-story-largest-type-light.png)
- [Mac Journey Ledger and Trip Story, light, 1080 by 720](screenshots/mac-journey-story-light-1080x720.png)
- [Mac Fuel Ledger, light, widescreen](screenshots/mac-fuel-ledger-light-widescreen.png)
- [Mac synchronized Signals, dark, widescreen](screenshots/mac-signals-dark-widescreen.png)

## CI

The iOS companion and CAN CONNECT Mac workflows are run from the pushed Phase 4
tip. Their exact run identifiers and conclusions are reported with the final
commit.

## Remaining hardware validation

Physical iPhone background behavior; OBDLink MX+ discovery/reconnection; Jetta
signal accuracy; scanner loss during a real drive; GPS loss while OBD continues;
lock-screen Live Activity and Dynamic Island; real LAN delivery and receipt
processing; and a complete on-road Journey Ledger/Trip Story remain hardware
checks. Simulator, synthetic TCP, isolated local server, and fixture evidence
do not replace those checks.
