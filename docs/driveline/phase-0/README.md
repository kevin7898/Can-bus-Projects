# DriveLine Phase 0 baseline evidence

Validated on 25 October 2026 on branch `codex/driveline-drive-ledger`.

## Integrated sources

- Base: `origin/main` at `313dd1bbd55c288ff69023ae9f3a3284785d8adf`
- Mac: `origin/codex/mac-jetta-transfer-signals` at `41d27ad222114b5f91470b96723fad35a2a5b50f`
- iPhone: `origin/codex/ios-companion` at `0876a168abbf83dc81847d2019456b142a3e58d9`
- Mac merge commit: `38ac31749a6d01e8a5b87cd0a31a2bba80144db2`
- iPhone merge commit: `02c2b537c4be5f6afe441e3d7cc4a81043b6cd04`

The Mac merge was clean. The iPhone merge had one add/add conflict in
`branding/driveline/VALIDATION.md`. It was resolved by retaining the newer
iPhone validation record and the Mac API-validation details. Both workflow
files, both Xcode projects, and the complete DriveLine icon assets are present.
The older `codex/driveline-brand-handoff` branch was not merged separately.

## Toolchain and commands

Toolchain:

- Xcode 27.2 (build 27B48)
- Apple Swift 6.4.2
- Developer directory: `/Applications/Xcode.app/Contents/Developer`

Validation commands:

```sh
git fetch origin --prune
git merge --no-ff origin/codex/mac-jetta-transfer-signals
git merge --no-ff origin/codex/ios-companion

cd mac-app && swift test
xcodebuild \
  -project mac-app/CANConnect.xcodeproj \
  -scheme CANConnect \
  -configuration Debug \
  -derivedDataPath mac-app/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
python3 mac-app/scripts/api_integration.py \
  mac-app/DerivedData/Build/Products/Debug/CANConnect.app/Contents/MacOS/CANConnect

xcodebuild test \
  -parallel-testing-enabled NO \
  -project can-connect-ios/CANConnect.xcodeproj \
  -scheme CANConnect \
  -destination "platform=iOS Simulator,id=249B80CF-9BCF-419E-9118-BFE3AB036F86" \
  -derivedDataPath can-connect-ios/build \
  -resultBundlePath can-connect-ios/TestResults.xcresult \
  CODE_SIGNING_ALLOWED=NO
```

## Results

- Mac Swift package: 20 passed, 0 failed, 0 skipped.
- Mac Xcode Debug build: passed.
- Mac isolated API integration: passed authentication, vehicle setup, mixed
  GPS/OBD upload, receipt processing, exact-byte deduplication, trip retrieval,
  invalid-vehicle rejection, and durable original preservation.
- iPhone: 105 passed, 0 failed, 3 skipped, 108 total on the iPhone 18 Pro
  simulator running iOS 27.2.
- Expected iPhone skips: the opt-in native-Mac loopback integration and two
  physical Live Activity presentation checks.
- The result bundle reported no runtime warnings.

Both Xcode projects were opened. The Mac app launched from the validated Debug
product using an isolated temporary library. The iPhone app was installed and
launched in the simulator using its synthetic `--ui-testing` state. No personal
recordings, routes, VINs, or pairing credentials were used or captured.

## Before screenshots

- [Mac empty Garage baseline](mac-before.jpg), SHA-256
  `229334e4bb2e9460a637308a0c1c95ecd53677a7e8bfc9755b70e0d761894fab`
- [iPhone synthetic Overview baseline](iphone-before.jpg), SHA-256
  `7ebf5810724123d2eb417c19b65ef128170c419c5a4b217bcc5b03349511a75b`

## Visual comparison and remaining acceptance

All seven supplied Drive Ledger visual references were reviewed against the
running apps. The existing apps preserve the working telemetry, archive,
recording, transfer, recovery, maps, charts, vehicle setup, and infrastructure
surfaces, but they intentionally remain the pre-redesign baseline:

- Mac still uses the left workspace sidebar rather than the approved top
  navigation.
- iPhone still uses Overview, Trips, Live, Vehicle, and Connect rather than
  Today, Drives, Record, Garage, and More.
- Production roots still force dark appearance; the approved light theme is
  not yet implemented.
- The new Journey Ledger, Trip Story, Fuel Ledger, synchronized Signals,
  multi-vehicle Garage, and resilient data-state layouts remain future phases.

The non-failing `swift test` run warned that `pkg-config` and its `sqlite3.pc`
file were unavailable, but SQLite compilation and all related tests passed.
Physical iPhone, OBDLink MX+, Jetta, Live Activity, Bluetooth-reconnect, and
real-drive checks were not rerun in this integration-only phase.

Phase 0 is complete. Phase 1 should introduce the shared archive contract and
correctness fixtures without beginning the broad UI redesign.
