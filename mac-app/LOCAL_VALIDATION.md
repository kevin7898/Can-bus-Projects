# Local Mac validation

Validated October 23, 2026 with Xcode 27.2, Swift 6.4.2, and the project in Swift 5 language mode. The approved design files pass their existing SHA-256 checks unchanged.

## Passed

- 18 core XCTest cases, including active SQLite WAL capture, preserved-original hashes, ZIP extraction, chart-gap segmentation and endpoints, VIN parsing, and demo cleanup that retains profiles with real import receipts.
- Ad-hoc signed Debug build for arm64 and x86_64. Native arm64 execution from Xcode, CANConnect scheme, My Mac destination.
- Authenticated HTTP integration: vehicle setup, upload, processing receipt, duplicate detection, retrieval, invalid vehicle rejection, and preserved original.
- User-supplied Pelican ZIP processed through the real AppStore queue, including unchanged original hash, duplicate receipt reuse, library reload, backup, and interrupted-import recovery. An independent local SQLite comparison checked every source timestamp and supported standard diagnostic value. No proprietary response formulas or GPS coordinates were invented.
- All seven native workspaces inspected at 1920×1080, 1440×900, and 1080×760. Real imports display historical source labels and explicit absent GPS/signals. Playback, import pause/resume, and server controls exercised locally.
- Loopback server started from the UI, rejected unauthenticated requests, and remained available after closing the window. The menu-bar action reopened the window. Server stopped after validation; LAN access remained disabled.

Personal archives, screenshots, logs, libraries, VINs, and source traces are excluded from Git. Local evidence is kept under `~/Library/Application Support/CANConnect-Validation/`, with the working library under `~/Library/Application Support/CANConnect/`.

## Fixes made during validation

- Overview uses its actual content height and reflows the inspector below the dashboard at smaller widths.
- Comparison statistics wrap within their panels. Signals retains the approved three-column widescreen / two-column narrow composition.
- The map footer no longer covers native zoom controls or map attribution.
- Charts use `plotFrame`, retain the final display sample, and do not connect lines across missing intervals. Source samples remain unchanged.
- Import selection uses a native sheet and retains the vehicle selected when the picker opened. Size errors identify the selected item.
- Selecting SQLite directly preserves WAL/SHM sidecars. SQLite parsing uses a working copy, so SQLite cannot mutate the acknowledged original's SHM bytes.
- Scanner request completion is protected against duplicate continuation resumes; exchange buffers are confined to the connection's serial queue. Scanner parsing and file preparation are in the core target for regression tests.
- Demo removal retains profiles and receipts associated with real imports. Invalid server-port input no longer starts the server with an old setting. Native form fields, comparison pickers, signal pickers, and playback controls have accessible names.

## Reproduce

From the repository root:

```sh
swift test --package-path mac-app
xcodebuild -project mac-app/CANConnect.xcodeproj -scheme CANConnect \
  -configuration Debug -derivedDataPath mac-app/DerivedData \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
python3 mac-app/scripts/api_integration.py \
  mac-app/DerivedData/Build/Products/Debug/CANConnect.app/Contents/MacOS/CANConnect
(cd mac-app/design && shasum -a 256 -c SHA256SUMS)
```

Optional real-import validation compiles the same AppStore used by the application. Supply an archive and a **private, separate validation library**, both outside the checkout. It prints only aggregate diagnostics, retains its originals, and tests recovery in a temporary backup.

```sh
swiftc -parse-as-library mac-app/Sources/CANConnectCore/*.swift \
  mac-app/Sources/CANConnectMac/AppStore.swift \
  mac-app/Sources/CANConnectMac/LocalServer.swift \
  mac-app/Sources/CANConnectMac/Theme.swift \
  mac-app/scripts/validate_import.swift -lsqlite3 -o /tmp/canconnect-validate-import
/tmp/canconnect-validate-import /absolute/path/to/archive.zip \
  "$HOME/Library/Application Support/CANConnect-Import-Validation"
```

## Remaining

Manual file-picker acceptance remains: accessibility automation selected the containing folder rather than the ZIP. The actual AppStore queue, archive parser, originals, and recovery were validated separately with the supplied archive. Physical scanner communication, real vehicle behavior, companion-device networking, start-at-login registration, logout/reboot acceptance, notarization, and Intel execution need their own validation. GPS map playback must be checked using an actual GPS-bearing recording; the supplied Pelican diagnostic archive contains no GPS. The handoff's missing transports, proprietary/DBC decoding, road-corridor aggregation, automatic 5,000 km retention, and high-volume storage architecture remain product work.

The installed toolchain still emits the benign App Intents metadata-extraction warning because this app does not use App Intents. Source-level scanner concurrency, Combine import, and Charts deprecation warnings were resolved. Swift 6 language-mode migration is a separate change.
