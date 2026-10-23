# CAN / CONNECT Mac

A native SwiftUI macOS application based on the [locked widescreen design](design/). Requires **macOS 14 or later and Xcode 15 or later**. There are no external Swift package dependencies. This initial implementation needs a local Xcode run and hardware validation before being called production-ready.

## Open in Xcode

Open **`mac-app/CANConnect.xcodeproj`**, select the **CANConnect** scheme and **My Mac**, and run. The project defaults to ad-hoc local signing; a paid developer account is not required for a local development build. Distribution, notarization, and login-item behavior need separate signing/setup.

```sh
open mac-app/CANConnect.xcodeproj
```

CLI validation from the repository root:

```sh
cd mac-app
swift test
cd ..
xcodebuild -project mac-app/CANConnect.xcodeproj -scheme CANConnect -configuration Debug -derivedDataPath mac-app/DerivedData CODE_SIGNING_ALLOWED=NO build
python3 mac-app/scripts/api_integration.py mac-app/DerivedData/Build/Products/Debug/CANConnect.app/Contents/MacOS/CANConnect
```

## Implemented

- Native dark desktop shell and seven workspaces: Overview, Trips, Compare, Signals, Garage, Imports, Server.
- Empty first-launch garage; vehicle identity, selection, per-vehicle map state, periods, signal selections, and summary-widget layout saved locally.
- Overview summary widgets can be added, removed, reordered, resized on a four-column grid, and configured independently. Map/trip placement is saved.
- Native MapKit recorded-GPS routes, saved view state, independent trip selection, linked comparison maps, timestamp playback, and Swift Charts signal inspection.
- Source-aware imported readings; absent signals stay blank. No live scanner readings are simulated.
- Local CSV/JSON, classic-CAN candump, webCAN, and Pelican `.scanlogs` / SQLite / ZIP imports. Standard Mode 01 values are decoded from Pelican command responses; proprietary diagnostic responses stay in the preserved original.
- Original preservation, SHA-256 deduplication per vehicle, durable queue and receipts, interrupted-import recovery, pause/resume, and error/retry states.
- Authenticated local HTTP API with vehicle setup, canonical JSON uploads, asynchronous processing receipts, and trip retrieval. Optional trusted-LAN binding and Bonjour advertisement. Default binding is loopback.
- Keychain pairing token, backup/export actions, a menu-bar entry, window-close background behavior, and optional login registration.
- Read-only VIN requests through ELM-compatible Wi-Fi/TCP scanners; manually review identity before saving. Requires real scanner testing.

## First run

1. Add a vehicle in Garage.
2. Import a recording. Keep a Pelican `db.sqlite` together with its WAL sidecar in the `.scanlogs` folder, or select the complete ZIP archive.
3. Check Imports for the actual processing result. Trips without coordinates have no recorded map path; raw CAN is not automatically vehicle telemetry.
4. Server is stopped by default. Start it to enable API uploads, and copy its pairing token only to a trusted companion client.
5. Demo data is opt-in, visibly labeled, and removable from Garage.

The application library is stored under `~/Library/Application Support/CANConnect/`. Originals are copied to `Originals/`; metadata, recordings, preferences, and receipts are in an atomic `library.json` manifest. Use Server → Back up library before manual library changes. A library read failure never silently creates a replacement over the existing manifest.

## Supported telemetry contract

A canonical JSON recording contains `schemaVersion: 1`, a `vehicleID`, a `source`, a `name`, and non-empty `samples`. Each sample has an absolute ISO-8601 / Unix timestamp, optional `latitude` and `longitude`, and a `signals` object. Signal keys and units are defined in `Sources/CANConnectCore/Models.swift`.

CSV uses an absolute `timestamp` column, optional `latitude` / `longitude`, and signal columns such as `speedKph`, `rpm`, `coolantC`, `fuelRateLph`, `mapKpa`, `barometricKpa`, `fuelPercent`, or `voltage`. Selected common human-readable aliases are recognized. Unknown names and relative-only timestamps are rejected rather than guessed. Human-readable dates without a time-zone offset use the Mac's local time zone. Import errors report unsupported formats; this is not universal support for every Car Scanner export variant.

Original bytes retain the source sampling cadence. Distance calculations omit GPS gaps over 30 seconds and speed integration gaps over 10 seconds. Fuel consumption needs at least 80% time coverage. Charts downsample for display; original imports remain intact. The initial manifest-based storage is suitable for the first working app, not the final high-volume CAN archive architecture.

See [API.md](API.md) and [CODEX_HANDOFF.md](CODEX_HANDOFF.md).

## Known boundaries

No BLE/USB scanner integration, raw-CAN signal decoder, cellular transport policy, real device pairing UI, reverse geocoded road-corridor aggregation, automatic raw-CAN retention deletion, independent launch daemon, or distribution package is implemented. The 5,000 km raw retention policy remains a future requirement; this version retains originals. Native MapKit provides the basemap; it needs network connectivity for uncached map tiles. Closing the window leaves the app running; quitting or logging out stops its service.

Locked design files remain unchanged. The native app is a functional implementation candidate, not a claim that all locked future platform features are complete. Consult the handoff for validation status and next steps.
