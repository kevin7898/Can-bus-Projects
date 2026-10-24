# DriveLine validation — 2026-10-24

Toolchain: Xcode 27.2 (27B48), Icon Composer 27.2 (143). Installed simulator: iPhone 18 Pro, iOS 27.2. Minimum deployment targets remain iOS 17 / macOS 14.

## Artwork and native integration

- Original 1254 × 1254 reference preserved byte-for-byte from the handoff commit.
- Three editable SVG layers use a shared 1024 canvas, with no baked rounded mask. Production geometry reconstructs the selected reference; it is not the reference PNG renamed into an icon.
- Document schema was checked against saved Icon Composer examples and accepted by Apple's actual renderer. The document was opened with Icon Composer. No dependency on third-party renderer or runtime package was introduced.
- Apple's bundled `Icon Composer.app/Contents/Executables/ictool` rendered Default, Dark, TintedLight, TintedDark, ClearLight, ClearDark and 32/48/60/120-pixel Default previews. These are native renders, not screenshots of the installed app. Static Clear exports do not reproduce live wallpaper refraction.
- Xcode invokes `actool` on `DriveLine.icon`; it is compiled rather than copied as an inert document. Mac output contains `Assets.car` and `DriveLine.icns`. iOS output includes native assets and generated conventional app icons.
- Both project generators run twice with identical results. Public names change; bundle IDs, storage, pairing, protocols, navigation, and existing card geometry remain unchanged.

## Software validation

- iOS build 18 core: 81 passed, one hardware test skipped. Twelve regeneration tests cover complete/partial cycles, blips, interruption and engine stop, status gaps, duplicate replies/imports, stale metrics, baseline/vehicle isolation, live draft/recovery and stored-state decoding. The saved comparison baseline is explicitly decoded and survives repeated relaunches.
- Final local build-18 run: 87 passed across core and six UI scenarios; two opt-in Live Activity presentation checks remain skipped. Includes unchanged soot-card bounds, comparison navigation, onboarding and real TCP scanner recording. The scanner test now delivers three synthetic Core Location points, including two while backgrounded, and checks the saved route map. A MapKit accessibility locator was corrected after the initial GPS UI assertion failed; the points themselves were already durably saved. Synchronous XCTest cleanup avoids an assertion-failure teardown deadlock.
- Scanner recordings now collect GPS alongside OBD samples. Tests cover GPS failure without ending the scanner session, manual/automatic start, background checkpoints, local archive and mixed transfer payload, distance without double counting and visible breaks across missing GPS coverage. See `can-connect-ios/GPS_TRACKING.md`.
- Signed build 18 installed and launched on the existing iPhone bundle after a fresh backup confirmed no active recording. All 23 saved recordings, vehicles, fills, scanner/server settings, preferences, transfer records and regeneration baseline match the pre-install snapshot. The 22 original recordings remain unchanged; the separate 677-response recovered recording from the earlier install remains preserved.
- Mac: 20 core tests and isolated receiver integration passed. Mixed GPS/OBD tests verify coordinates, timestamps, signals, export/reload, processed receipts, exact-byte deduplication and original preservation. The installed receiver resumed after the user's Keychain approval; original trips, vehicles, receipts and server settings remain preserved.
- GitHub CI for iOS build 17 and the latest Mac test update passed. Build-18 CI passed core tests but its foreground-return UI tap used a stale hit point on the Drive tab instead of Finish. The test now taps the current button centre and requires the saved state before navigation; the focused local rerun passed. Build 19 also corrects outdated background-recording help text. Consult PR #7 for the latest CI result.
- Real build-18 Jetta check: automatic scanner recording captured 1,318 responses and four GPS fixes, three after the phone was locked, with roughly 2-metre accuracy. The Bluetooth stream disconnected during a walk away from the car; the trip was saved. This verifies real GPS delivery while locked but not a continuous locked-screen drive. Reconnection after Bluetooth range loss still required user involvement in iOS during this check.

- Build 20 removes the Bluetooth discovery name filter while retaining authenticated MX+ model/protocol validation, and clarifies that Refresh lists connected adapters. Signed device build and all seven focused MX+ transport tests passed. Installed and launched after a fresh no-active-recording backup; all 26 saved trips, vehicle profiles, transfer records and regeneration baseline match the pre-update snapshot. Physical empty-picker and out-of-range reconnection acceptance remains pending.

## Acceptance limits

A real ECU regeneration start/end and a new driven GPS route must still be observed on the Jetta. GPS simulations and receiver fixtures do not establish real reception or locked-screen route continuity in the car. Synthetic tests validate classification logic, not the vehicle's regeneration behavior. Collect the next 5–10 complete observations through ordinary scanner recordings; interrupted/incomplete observations are separate. No adaptation writes or forced regeneration are used. Percentage calibration is unchanged.

Older OS runtimes are not installed locally; fallback artifact generation is verified, but iOS 17 and macOS 14 display behavior still needs an actual older OS. Home Screen/Settings/Dock and Clear/Tinted behavior against light, dark and busy wallpapers require on-device visual acceptance. Static renderer previews alone do not establish that acceptance.
