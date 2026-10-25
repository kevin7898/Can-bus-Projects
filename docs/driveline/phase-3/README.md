# DriveLine Phase 3 evidence

Phase 3 starts at pushed Phase 2 commit
`fbd1778996fa7318ab3950486d6d170a9d69c491`. It implements the data-driven
Today and Record surfaces described by the Drive Ledger handoff. It does not
start the Phase 4 Journey Ledger, Trip Story, Fuel Ledger, or Signals redesign.

## Buildable commits

1. `79c08aa828af633b8bf30195c017664b5df1a637` — data-driven iPhone Today.
2. `569a62258955769641db64022cfb6d97724994f2` — active Record and recovery states.
3. `47645cb255e403f8017752c8c5101f493c1faa21` — data-driven Mac Today.
4. The Phase 3 tip adds focused tests, sanitized visual fixtures, screenshots,
   and this evidence record.

## Today and Record behavior

The iPhone Today presentation is derived from the selected vehicle, the current
calendar day, real recordings, real fills, connection readiness, and the
persisted transfer queue. Sample vehicles remain clearly labelled. Sample
recordings and fills are excluded from real totals and from latest-real-trip or
latest-real-fill selection. Optional measured fuel remains unavailable rather
than becoming a false zero.

Record has explicit idle, starting, active, degraded, stopping, and recovered
presentation states. Its active surface shows the current route, elapsed time,
distance, GPS speed, and independently selected RPM, coolant, gauge boost, DSG
temperature, DPF soot mass, and normalized regeneration trigger observations.
Every value carries availability/freshness and source text; an unobserved value
is an em dash. The regen trigger is described as a normalized ECU trigger and
never as physical DPF fullness.

The view does not own recording lifecycle decisions. Existing `AppStore`, GPS,
scanner, recovery, Live Activity, transfer, and persistence code still owns
start, automatic scanner start, delayed GPS, the two-minute reconnect window,
checkpointing, relaunch recovery, finish, and exact-payload queuing. Focused
tests prove duplicate Finish calls save one recording, deep links open Record,
and GPS or scanner loss leaves the remaining source active. Recovery uses amber
for degraded/retryable conditions; red remains reserved for active recording
and faults.

Mac Today is a historical local-library view. It displays the selected vehicle,
today's real totals, the latest recorded route, recent drives, queue/library and
server status, and latest fill. It explicitly makes no claim that the Mac has a
live scanner connection. Imports and Server remain reachable through the
persistent secondary strip and overflow menu.

## Storage and reset decision

No data reset and no migration were needed. Phase 3 does not change archive
schemas, telemetry storage, recording files, vehicle identities, assignments,
fills, receipts, scanner settings, Mac pairing/transfer settings, Keychain
credentials, or appearance preferences. Production launch contains no reset
path. Original recording preservation and all Phase 1 schema-1/schema-2
compatibility remain unchanged.

## Correctness agreement

The shared golden fixture is still consumed by both platform adapters. Both
apps agree on 20 seconds duration, approximately 0.20015 km GPS distance,
0.02000 L measured trip fuel, approximately 9.9925 L/100 km economy, 100%
fuel-rate coverage, synthetic GPS plus synthetic OBD provenance, and 35 kPa
asynchronous gauge boost. Purchased fill quantity remains separate from trip
fuel. Phase 3 Today tests additionally prove that sample content cannot affect
real counts, distance, duration, fuel, latest trip, or latest fill.

## Local validation

Commands were run from the repository root:

```sh
(cd shared/DriveLineShared && swift test)
(cd mac-app && swift test)
xcodebuild build -project mac-app/CANConnect.xcodeproj -scheme CANConnect \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/driveline-p3-mac-final CODE_SIGNING_ALLOWED=NO
python3 mac-app/scripts/api_integration.py \
  /tmp/driveline-p3-mac-final/Build/Products/Debug/CANConnect.app/Contents/MacOS/CANConnect
xcodebuild test -parallel-testing-enabled NO \
  -project can-connect-ios/CANConnect.xcodeproj -scheme CANConnect \
  -destination 'platform=iOS Simulator,name=DriveLine iPhone 17 Pro Max' \
  CODE_SIGNING_ALLOWED=NO
xcodebuild test -parallel-testing-enabled NO \
  -project can-connect-ios/CANConnect.xcodeproj -scheme CANConnect \
  -destination 'platform=iOS Simulator,name=DriveLine compact layout check' \
  -only-testing:CANConnectUITests/SmokeTests/testDriveLedgerPrimaryDestinationsAndMoreRoutesAreReachable \
  CODE_SIGNING_ALLOWED=NO
```

- Shared package: 11 passed, 0 failed.
- Mac Swift package: 23 passed, 0 failed. The existing non-failing
  `pkg-config` / sqlite3 metadata warning remains; SQLite tests pass.
- Mac Xcode Debug build: passed.
- Mac isolated API integration: passed authentication, schema-2 mixed GPS/OBD
  and fill transfer, stable identities, exact-original preservation, hash
  deduplication/conflict handling, receipt processing, trip retrieval, and
  vehicle validation.
- iPhone 17 Pro Max / iOS 27.2 complete unit and UI suite: 118 passed,
  0 failed, and 3 expected skips (121 total).
- Compact iPhone / iOS 27.2 at
  `accessibility-extra-extra-extra-large`: the primary navigation, Garage,
  connections, transfers, and appearance route check passed, 1 passed and
  0 failed.

The expected skips are the opt-in native-Mac loopback integration and the two
Live Activity presentation checks that require lock-screen or Dynamic Island
surfaces. The iOS and Mac GitHub Actions workflows are also run on the pushed
Phase 3 tip; their exact run results are reported with the final commit.

## Layout and accessibility checks

- iPhone 17 Pro Max was inspected in light and dark appearances for Today,
  Record idle, Record active, and a degraded scanner-loss recovery state.
- The compact simulator was inspected at the largest accessibility Dynamic
  Type category. Its Record header, status, source selector, Start control, and
  all five tabs remain reachable; the detail content scrolls instead of being
  clipped.
- Mac Today was inspected at the 1080 by 720 minimum and the 1540 by 1000
  widescreen size in light and dark. Navigation, vehicle selection,
  Imports/Server, metrics, route, recent drives, and fill/library cards remain
  reachable. Phase 2 keyboard focus order remains unchanged.
- All status is paired with text and an icon rather than colour alone. Light
  and dark semantic contrast remains within the Phase 2 validated palette.
- Screenshot fixtures are debug-only, sanitized, and isolated from production
  storage. They never contribute to a user's totals.

## Screenshots

- [iPhone Today empty, light](screenshots/iphone-17-pro-max-today-empty-light.png)
- [iPhone Today empty, dark](screenshots/iphone-17-pro-max-today-empty-dark.png)
- [iPhone Record idle, light](screenshots/iphone-17-pro-max-record-idle-light.png)
- [iPhone Record idle, dark](screenshots/iphone-17-pro-max-record-idle-dark.png)
- [iPhone Record active, dark](screenshots/iphone-17-pro-max-record-active-dark.png)
- [iPhone Record scanner loss, light](screenshots/iphone-17-pro-max-record-degraded-light.png)
- [Compact iPhone Record, largest Dynamic Type](screenshots/iphone-compact-record-large-type-light.png)
- [Mac Today, light, 1080 by 720](screenshots/mac-today-light-1080x720.png)
- [Mac Today, light, widescreen](screenshots/mac-today-light-widescreen.png)
- [Mac Today, dark, widescreen](screenshots/mac-today-dark-widescreen.png)

## Remaining hardware validation

Physical iPhone, OBDLink MX+, Jetta, Bluetooth discovery and reconnection,
background and delayed GPS, scanner loss while driving, GPS loss while scanner
telemetry continues, lock-screen Live Activity, Dynamic Island, real
Mac-to-iPhone LAN delivery/receipt handling, and a complete on-road recording
remain hardware checks. Simulator and synthetic TCP coverage prove the software
paths but do not replace those checks.
