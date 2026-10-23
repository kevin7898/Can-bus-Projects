# Codex handoff — native CAN / CONNECT Mac app

## Goal and current branch

Continue this work in **local Codex on Kevin's Mac**, with Xcode already open. Repository: `https://github.com/kevin7898/Can-bus-Projects`. Implementation branch: **`feature/mac-native-app`**. Open **`mac-app/CANConnect.xcodeproj`**, scheme **CANConnect**, destination **My Mac**.

The approved Mac design is immutable in `mac-app/design/`; start with `DESIGN_LOCK.md` and `preview.html`. Preserve the widescreen sidebar / map-first dashboard / right inspector / graphite and VW-blue direction. The native source is under `mac-app/Sources/`. This is a substantial initial implementation that needs compile, runtime, and visual validation on the Mac, not a completed production system.

## Start here

1. Locate Kevin's existing checkout before cloning a second copy. Inspect `git status` and preserve all unrelated work.
2. Fetch GitHub, switch to `feature/mac-native-app`, and read any repository or parent `AGENTS.md` instructions now present. No AGENTS.md was present in the source tree used for this implementation.
3. Read this handoff, `README.md`, `API.md`, and the design lock. Inspect the current GitHub Actions run for this branch.
4. Run `xcodebuild -version` and `swift --version`; choose the active full Xcode developer directory if needed.
5. Execute the validation commands below. Fix build errors on this branch; do not reinterpret uncompiled code as a working app.
6. Open Xcode, build and run, exercise all seven workspaces, compare the native UI against the locked preview, and refine fidelity without redesigning it.

```sh
cd mac-app
swift test
cd ..
xcodebuild -project mac-app/CANConnect.xcodeproj -scheme CANConnect -configuration Debug -derivedDataPath mac-app/DerivedData CODE_SIGNING_ALLOWED=NO build
python3 mac-app/scripts/api_integration.py mac-app/DerivedData/Build/Products/Debug/CANConnect.app/Contents/MacOS/CANConnect
open mac-app/CANConnect.xcodeproj
```

For normal local running, keep the project's ad-hoc signing identity or choose Kevin's local development team if Xcode requires it. This setup does not require paid distribution signing. The UI targets macOS 14+. No external Swift package dependency resolution is required.

## What was written

- Core Codable models, source-aware derived statistics, atomic manifest persistence, canonical JSON/CSV export, and explicit missing-signal behavior.
- CSV/JSON, webCAN, classic candump, and Pelican Core Data SQLite importers. Pelican schema was inspected privately from Kevin's actual archive: `ZCOMMANDRESPONSE` with `ZSESSION`, `ZTIMESTAMP`, `ZCOMMAND`, `ZRESPONSE`. Timestamps are Apple reference-date seconds. The archive also has WAL/SHM sidecars.
- No private archive, VIN, scanner name, or actual location trace is committed. SQLite tests synthesize their own schema and responses.
- An AppStore with copied originals, per-vehicle SHA-256 deduplication, queue processing/recovery, receipts, local preferences, import/retry/pause, backup, and export.
- Native SwiftUI shell and workspaces, MapKit routes and linked compare views, Charts readings/playback, configurable summary grid, vehicle editor, historical signal cards, queue and server screens.
- A Network.framework HTTP server, bearer authentication, Keychain token, optional LAN/Bonjour binding, and companion JSON upload / receipt routes.
- A read-only TCP ELM VIN reader, with unsupported/timeout paths and manual profile review. No hardware session was available to validate it.
- Menu-bar controls, window-close background lifecycle, and optional ServiceManagement login registration.
- Deterministic project generator, checked-in shared Xcode scheme, core XCTest suite, and a real HTTP integration script using the built app in an isolated temporary library.

## Verify carefully

- This chat ran in Linux, with no `swift`, `xcodebuild`, or connection to Kevin's local Xcode. XML/plist/Python structural checks were performed locally. Treat native compilation, UI runtime, and hardware behavior as unverified unless the current macOS CI result proves otherwise. Check actual CI conclusions rather than this document's creation-time status.
- The app compiles core source files directly into its app target. The separate `Package.swift` only builds/tests CANConnectCore via CSQLite. If adding/removing Swift files, run `python3 mac-app/scripts/generate_project.py` and commit the regenerated `.pbxproj` and shared scheme.
- Verify SwiftUI type-checking and API availability, actor/thread handoffs in Network and scanner callbacks, headless service startup, MapKit delegate update loops, and keyboard / focus behavior.
- Check duplicate detection and recovery after termination, interrupted manifest writes, permissions/read errors, and .scanlogs WAL handling. Never overwrite a corrupt manifest with an empty library.
- Test UI resize on Kevin's MacBook Air and his widescreen display. The initial native layout may need refinement; particularly check overview height, right inspector thresholds, Charts layout, and comparison statistics at narrower widths.
- Check source-aware calculations against known recordings. Sparse fuel values, GPS jumps, long gaps, source units, and fractional timestamps must not yield fabricated precision. Keep a record of which intervals contribute to distance and fuel.
- A demo profile is opt-in and labeled; real imports must never be mixed into demo data or deleted by demo cleanup.
- ELM VIN responses vary. Read-only TCP support is a starting implementation and needs validation against the real adapter before claiming compatibility. Do not send writes or coding commands.

## Remaining product work

Complete the above validation first. Then prioritize importing Kevin's Pelican archive on the Mac and verifying the decoded signal timeline. Preserve proprietary responses rather than guessing undocumented VW signal formulas. Add actual Car Scanner format variants only from inspected examples. Keep real recordings outside the public repository.

The app has no BLE/USB/CAN-X2 hardware transport, DBC/proprietary signal decoder, cellular/Wi-Fi upload scheduler, independent launch daemon, automatic retention deletion, completed companion-device pairing UI, or true road-corridor aggregation / unexplored-roads overlay. The 5,000 km retention target remains in the locked design and is explicitly not active. Do not call this first version fully feature-complete until those items have been agreed and implemented.

Manifest-based sample storage is an initial implementation; sustained high-rate raw CAN should use indexed/chunked storage, with the original archive retained outside a giant JSON manifest. Preserve iOS-first and future Android compatibility in API and receipt contracts.

Use the existing branch, keep work committed and pushed, and report exactly what ran, what passed, and what remains. Do not stop after describing fixes that local Codex can carry out.
