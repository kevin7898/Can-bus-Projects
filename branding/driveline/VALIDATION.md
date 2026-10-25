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

- iOS core: 75 passed, 1 hardware-dependent test skipped. Includes nine new deterministic regeneration tests: completed/partial cycles, single-response blips, interrupted end, status gaps, duplicate replies/imports, stale metrics, baseline/vehicle isolation, live draft/recovery, and old-state decoding.
- iOS UI: six passed; two opt-in Live Activity presentation checks skipped. Includes comparison navigation with zero invented sample cycles, unchanged soot-card bounds, onboarding and TCP scanner recording.
- Signed build 15 installed on the existing iPhone bundle ID. Before first launch, all 22 trips, three vehicles, one fill, scanner/server settings, preferences and 15 transfer records matched the private pre-install backup. Launch was initially blocked by the locked phone.
- Mac: 20 tests passed. Mixed scanner/GPS tests additionally verify coordinates and precise timestamps through import, export and library reload. The isolated receiver test uses separate GPS and OBD rows, verifies the imported route and readings, and compares the saved original with the exact upload. API integration passed authentication, setup, upload, processing receipt, exact-byte deduplication, retrieval, vehicle validation and durable original storage.

## Acceptance limits

A real ECU regeneration start/end must still be observed on the Jetta. Synthetic tests validate classification logic, not the vehicle's regeneration behavior. Collect the next 5–10 complete observations through ordinary scanner recordings; interrupted/incomplete observations are separate. No adaptation writes or forced regeneration are used. Percentage calibration is unchanged.

Older OS runtimes are not installed locally; fallback artifact generation is verified, but iOS 17 and macOS 14 display behavior still needs an actual older OS. Home Screen/Settings/Dock and Clear/Tinted behavior against light, dark and busy wallpapers require on-device visual acceptance. Static renderer previews alone do not establish that acceptance.
