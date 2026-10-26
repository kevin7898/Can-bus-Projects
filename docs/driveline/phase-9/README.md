# DriveLine Phase 9 evidence

Prepared October 25, 2026.

## Classification

**Automated release candidate; physical qualification pending.**
The automated, simulator, unsigned archive, and signed physical Debug build/install/launch gates pass. The later GPS-status and trip-selection correction is automatically tested but has not yet replaced the installed app because an active recording must not be interrupted. This is not a physically qualified release candidate: an actual Jetta/OBDLink acceptance drive, background recording, lock-screen/Live Activity observation, physical LAN transfer, and signed distribution credentials were not fully exercised. The project still deliberately has no committed development team; the successful device build used the locally signed-in team only as a command-line override. No upload, submission, release, or tag was created.

## Starting state and commit inventory

Work began from `codex/driveline-drive-ledger` at `12b93a1765781fb1d2ed00569fe7cc25dc12afe8`. The remote still matched that commit before Phase 9 was published. The separate dirty checkout at `/Users/kevinstuparyk/Documents/ChatGPT/Can connect` remained on `codex/ios-companion`; its untracked Mac build products were not read, changed, stashed, or removed.

| Commit | Purpose |
| --- | --- |
| `4f522e53f09d0bfc4f563ff5340316cb436947e9` | Sanitized performance corpus, display-only rendering policy, evidence-integrity and performance tests |
| `2d9a8c43f10d499ef949f92ac5fbb16b43a11532` | Cross-platform signposts, bounded chart adoption, concurrency cleanup, privacy manifests, release-build repair and version configuration |
| `ea187d580069cd09e696891b0a50116dddd327ea` | Split one debug-fixture expression so the Xcode 26.6 / Swift 6.3.3 CI compiler can type-check it deterministically |
| `e0c644f0be33645f9a1e226571372afed955f977` | Exercise representative zoom, pan, scrub, map-cursor and vehicle-switch interactions; select cursor evidence in one gap-aware pass |
| `eb6617c05746d8d40201a029f7abb9495864df3f` | Keep active stationary GPS sessions connected without reusing stale speed, add honest acquiring/weak-signal states and retry, and move trip signal preparation off the main actor |
| Final documentation commit | Phase 9 evidence, release checklist, limitations and release notes; reported with delivery because a commit cannot contain its own final hash |

The GitHub connector was used to publish byte-identical Git trees after the local HTTPS credential helper proved unavailable. Each branch update was a non-forced fast-forward from the previously verified remote head.

## Automated results

Toolchain: Xcode 27.2 (27B48), Swift 6.4.2, macOS 27.0.1.

| Gate | Result |
| --- | --- |
| Shared package | 37 passed, 0 failed, 0 skipped; 7.375 s final test time while run concurrently with iPhone analysis |
| Mac Swift package | 34 passed, 0 failed, 0 skipped; 0.309 s final test time |
| Mac Xcode Debug build | Passed |
| Mac API integration | Passed recording and fuel-only schema-2 transfers, external receipt bytes, stable identities, exact originals, authentication, processing receipts, hash deduplication/conflict, trip isolation, retrieval and vehicle validation |
| iPhone unit tests | 127 executed, 126 passed, 1 expected skip, 0 failed |
| iPhone UI tests | 20 executed, 18 passed, 2 expected skips, 0 failed |
| iPhone total | 147 executed, 144 passed, 3 expected skips, 0 failed |
| Compact accessibility rerun | 2 passed, 0 failed on iPhone SE (3rd generation) at accessibility extra-extra-extra-large |
| Mac static analysis | Passed |
| iPhone static analysis | Passed |
| Complete Swift concurrency audit build | Both projects passed with `SWIFT_STRICT_CONCURRENCY=complete`; no source warnings |
| Mac unsigned Release archive | Passed |
| iPhone unsigned Release archive | Passed after debug-only fixture bootstrap was excluded from Release |
| iPhone signed physical Debug build/install/launch | The corrected app and Live Activity extension build and signature verification pass; installation/launch remains on the preceding code candidate until the active recording is confirmed saved |

The three expected iPhone skips are one loopback-network test that requires a host endpoint and two physical Live Activity checks. They are not counted as passes.

Primary commands:

```sh
cd shared/DriveLineShared && /usr/bin/time -l swift test
cd mac-app && /usr/bin/time -l swift test
xcodebuild -project mac-app/CANConnect.xcodeproj -scheme CANConnect -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/driveline-phase9-mac-final CODE_SIGNING_ALLOWED=NO build
python3 mac-app/scripts/api_integration.py /tmp/driveline-phase9-mac-final/Build/Products/Debug/CANConnect.app/Contents/MacOS/CANConnect
xcodebuild analyze -project mac-app/CANConnect.xcodeproj -scheme CANConnect -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild analyze -project can-connect-ios/CANConnect.xcodeproj -scheme CANConnect -configuration Debug -destination 'platform=iOS Simulator,id=C975E238-AE3A-4B13-9FE8-477B69F94928' CODE_SIGNING_ALLOWED=NO
xcodebuild build-for-testing -project can-connect-ios/CANConnect.xcodeproj -scheme CANConnect -destination 'platform=iOS Simulator,id=C975E238-AE3A-4B13-9FE8-477B69F94928' -derivedDataPath /tmp/driveline-phase9-ios-final2 CODE_SIGNING_ALLOWED=NO
xcodebuild test-without-building -parallel-testing-enabled NO -project can-connect-ios/CANConnect.xcodeproj -scheme CANConnect -destination 'platform=iOS Simulator,id=C975E238-AE3A-4B13-9FE8-477B69F94928' -derivedDataPath /tmp/driveline-phase9-ios-final2 -resultBundlePath /tmp/driveline-phase9-ios-final-20261025.xcresult CODE_SIGNING_ALLOWED=NO
xcodebuild -project can-connect-ios/CANConnect.xcodeproj -scheme CANConnect -configuration Debug -destination 'platform=iOS,id=<physical-device-id>' -derivedDataPath /tmp/driveline-phase9-ios-device DEVELOPMENT_TEAM=<local-team-id> CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
xcrun devicectl device install app --device <physical-device-id> /tmp/driveline-phase9-ios-device/Build/Products/Debug-iphoneos/CANConnect.app
xcrun devicectl device process launch --device <physical-device-id> --terminate-existing com.canconnect.companion
```

The exact post-correction iPhone result bundle is `/tmp/driveline-phase9-ios-gps-perf-final.xcresult`; its build, complete suite, compact accessibility rerun, analysis and complete-concurrency logs are kept under `/tmp/driveline-phase9-ios-gps-*`. The final Mac build log is `/tmp/driveline-phase9-mac-gps-final-build.log`.

## GPS-status and journey-selection field correction

The private user-supplied screen recording showed that GPS eventually acquired during the same recording and that measured distance advanced from 0.0 km to 0.1 km. The raw video, frames, route and coordinates were kept outside Git. That evidence ruled out a permanent permission failure and exposed two presentation/performance defects:

- The Record screen used a ten-second last-observation threshold as both evidence freshness and service connectivity. Core Location's existing five-metre movement filter may legitimately produce no new route point while the vehicle is stopped, so the UI could flash between connected and unavailable even though the location session remained active.
- Journey selection repeatedly derived summaries, timelines and signal series on the main actor, creating a visible temporary stall on telemetry-rich recordings.

The corrected policy keeps these concepts separate. A running location session remains connected while its last recorded observation may become stale; stale GPS speed is never presented as current, and no coordinate, route distance or observation is forward-filled. Initial acquisition is labelled `GPS acquiring`; rejected fixes worse than 50 m are labelled `GPS signal weak` with reported accuracy; authorization/service failure remains `GPS unavailable`. `Retry GPS` restarts normal authorization/acquisition checks and does not retry the scanner. Signal-series preparation is cancellable detached work, while the existing shared evidence policies remain authoritative. Focused tests cover initial acquisition, weak-fix rejection/retry, a stationary active session after 60 seconds, and proof that stale speed is unavailable.

## Concurrency and warning audit

- GPS foreground state is now a `@MainActor` closure. Notification tokens have a deliberately documented `@unchecked Sendable` wrapper whose only cross-boundary operation is thread-safe observer removal.
- MX+ notification ownership uses the same constrained wrapper. ActivityKit is imported with `@preconcurrency` because the framework type lacks the annotation required by complete checking.
- The loopback fixture's mutable network state is lock-protected instead of captured as mutable local state by `@Sendable` callbacks.
- Mac HTTP, model, import and scanner result values are `Sendable`. Network listener and connection mutation remains on its private queue and is explicitly documented.
- Detached Mac import work owns immutable URLs and IDs in a non-actor processor; it no longer captures the main-actor store.
- Recording, GPS, scanner, persistence, transfer, processing and shutdown paths compile cleanly at complete strictness. The committed language/concurrency settings were not raised.
- `.healthy` semantic-state deprecation warnings were removed; the palette colour named `healthy` remains intentionally.

Remaining build messages are tool/environment notices: the optional SwiftPM `sqlite3.pc` metadata is unavailable even though SQLite imports/tests pass; Xcode skips App Intents metadata because neither app links AppIntents; and command-line builds may report multiple matching Mac architectures. No source warning is being suppressed.

## Performance methodology and results

`DriveLinePerformance` emits operation-name-only signposts for launch, decode/save, recording checkpoint/finalization, route processing, chart preparation, signal statistics, map annotation changes, archive import/export, receipt hash/copy, transfer upload, Mac processing, and server lifecycle. Signposts contain no stable IDs, VINs, addresses, coordinates, credentials, receipt content, or payload text.

The debug-only deterministic corpus contains 500 sample journeys across four sample vehicles, exactly 1,000,000 recorded observations, GPS-only/OBD-only/mixed recordings, irregular sampling and gaps longer than 60 seconds, 40 sample fuel entries with external receipt metadata, queued/failed/completed transfer labels, and one archived vehicle. The first vehicle is the fictional sanitized 2013 Volkswagen Jetta TDI. Every recording/fill is marked sample and the real-total policy test returns no real observations.

Measurements are from the local Apple-silicon Mac and are regression evidence, not universal product promises:

| Operation | Fixture | Measured result |
| --- | --- | --- |
| Generate/visit corpus | 500 journeys / 1,000,000 observations, bounded one journey at a time | 477 ms |
| Library filter | 500 journey summaries | 5.457 ms |
| Signal registry search | 100,000-observation mixed recording | 554.437 ms |
| Build signal series | 50,000 actual observations | 310.279 ms |
| Display chart preparation | 50,000 points to at most 2,400 | 14.904 ms |
| Visible-range statistics | 50,000 finite recorded observations | 45.737 ms |
| Twenty chart zoom/pan statistics updates | 50,000 finite recorded observations | 503.126 ms total |
| Twelve linked signal-cursor scrubs | 50,000 actual observations | 208.739 ms total |
| Route preparation | 50,000 recorded GPS points | 17.838 ms |
| Twenty linked map-cursor updates | 50,000 recorded GPS points | 97.379 ms total |
| Four vehicle switches | Four independent 2,000-observation recordings | 24.951 ms total |
| Repeated journey selection | 100 independently generated 2,000-observation journeys | 1,407.890 ms total |
| Archive export | 20,000 observations | 69.665 ms |
| Archive import and validation | 20,000 observations | 92.413 ms |
| Accelerated 30-minute record/playback | 1,801 GPS + 1,801 OBD observations and 361 five-second cursor positions | 0.254 s test time |

The final timed shared test process reported 167,116,800 bytes maximum resident set and a 49,120,096-byte peak memory footprint. Those numbers include the Swift test harness and must not be presented as steady-state app memory. The repeated-selection fixture uses `autoreleasepool` and stores no global recording cache. No unbounded cache was added.

Simulator terminated-process launch handshakes measured 0.12, 0.35, 0.41, 0.43 and 0.41 seconds; these timings end when `simctl launch` returns and are not launch-to-first-frame numbers. UI automation reached its first asserted screen at 4.45 seconds on the compact onboarding run and 3.32 seconds on the following recovery run, including XCTest setup. A normal Mac App Launch trace was captured, but the SwiftUI scene interval remained open until the four-second trace limit; it is retained rather than converted into a false launch-completion claim. Physical cold/warm first-frame measurement remains pending.

Local Instruments evidence:

- `/tmp/DriveLinePhase9Evidence/DriveLine-Mac-App-Launch-Normal.trace`
- `/tmp/DriveLinePhase9Evidence/DriveLine-Mac-Time-Profiler.trace`

An Allocations capture failed to attach and is not counted as evidence. The failed trace is kept locally for diagnosis.

### Display reduction integrity

Only chart pixels are reduced. Original archive and in-memory observations remain unchanged and are still used for cursor lookup, coverage, min/max/mean/count and transfer. Segments are reduced independently with a min/max envelope. Each segment retains endpoints and per-bucket extrema in timestamp order; isolated points remain isolated; no gap is bridged. The default rendering limit is 2,400 points. The policy is stateless, so it has no cache key or eviction problem. Tests prove source count, gaps, isolated points, endpoints, extrema and original cursor access survive.

## Permissions, privacy and security

- iPhone declares foreground/background location, Bluetooth external-accessory, local-network and Live Activity capabilities already used by recording, scanner and transfer features. Location authorization is requested when recording is prepared, not at arbitrary launch.
- Receipt selection uses the system Files importer/security-scoped URL. There is no Photos-library, camera, microphone, or notification permission declaration added by Phase 9.
- Mac declares local-network/Bonjour usage. User-selected imports/directories use system panels and security-scoped access where applicable.
- Both app targets now include `PrivacyInfo.xcprivacy`, declaring app-private preferences (`UserDefaults`, reason `CA92.1`), no collected data, no tracking and no tracking domains. The manifests pass `plutil` and are present inside both archives. See Apple's [privacy manifest documentation](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files).
- Existing Phase 8 denied/restricted/recovery states remain intact. Phase 9 did not add a permission to silence an error.
- Signposts and new logs never include payload data. Source audit found only explicitly fictional test VINs and raw diagnostic reply strings that merely match VIN-shaped character counts. No real VIN, secret, private key, scanner serial, pairing credential, bearer credential, personal route, receipt bytes, or private address was added.
- Pairing tokens remain device-only Keychain data on Mac. Transfers remain bearer-authenticated and local by default. No cloud decoder or analytics service was introduced.

## Mac lifecycle

Using the built Mac executable and an isolated temporary library, the lifecycle drill passed: local-only listener start, authenticated health check, rejection of a second token on a conflicting port, clean process termination, closed port after quit, and successful restart on the same port. The API integration also proves preserved originals, asynchronous processing receipts, conflict/deduplication and exact receipt bytes. Unit tests prove corrupt-primary/valid-backup restoration and invalid-primary/invalid-backup preservation without creating an empty replacement.

Implemented behavior remains: closing the last main window does not terminate the app; reopening orders its window forward; app termination calls server shutdown. Window close/reopen, logout, disconnected-volume, pause/resume queue and full keyboard behavior still require hands-on Mac observation. Port-conflict state wording is covered by the Phase 8 state matrix, while the separate-token drill proves only the original listener answered.

## Backup and restore drill

All destructive recovery tests used XCTest temporary directories or the API integration's temporary library. No user library was modified.

Automated drill coverage passes for schema-1/schema-2 decode, stable vehicle/recording/fill UUIDs, routes and telemetry, measured-trip fuel separation, fills, receipt metadata/external bytes, duplicate receipt storage, missing receipt metadata, annotations that do not mutate original archives, exact original payloads/hashes, corrupt-primary/valid-backup recovery, and invalid-primary/invalid-backup read-only preservation. Vehicle profiles and signal preferences round-trip additively. A signed-build end-to-end restore on physical devices and a disconnected external Mac volume remain manual gates.

## Accessibility and visual QA

- The complete iPhone UI suite passed on iPhone 17 Pro Max simulator in light/dark fixtures.
- The two compact critical flows passed on iPhone SE (3rd generation) at the largest accessibility category: Phase 7 onboarding and Phase 8 recovery actions remained reachable.
- Existing Phase 2–8 evidence covers Mac 1080×720 and 1540×1000, light/dark, keyboard focus, status text/icons, and iPhone accessibility identifiers. Phase 9 preserved the visual system.
- Physical VoiceOver, increased contrast, reduced motion, rotation, lock-screen/Dynamic Island, Mac VoiceOver/full keyboard access, and hands-on resize/window lifecycle checks remain pending. Simulator evidence is not physical acceptance.

## Physical-device and Jetta matrix

| Qualification | Result | Evidence or blocker |
| --- | --- | --- |
| iPhone 17 Pro Max detected by Xcode | Available | Xcode reported the physical iPhone connected; its device identifier is intentionally omitted from committed evidence |
| Signed physical build/install/launch | Corrected build staged; prior candidate installed/launched | A non-persistent local-team override provisioned and signed the corrected app and Live Activity extension, and signature verification passes. No source signing setting or credential was committed, and no reset or deletion command was issued. The corrected build will not replace a running recording without explicit confirmation that it is saved |
| Fictional 2013 draft to actual 2014 suggestion | Automated behavior passes; physical pending | Decoder/review/cancel/stable-UUID tests pass; actual VIN was not accessed |
| Keep 2013 / cancel / accept 2014 | Automated behavior passes; physical pending | Sanitized fictional VIN tests pass |
| OBDLink MX+ and Wi-Fi scanner | Pending | Actual adapters/vehicle unavailable |
| Ignition/reconnect/grace expiry | Pending | Requires parked actual vehicle |
| GPS-only/mixed/degraded recordings | Simulator/automated pass; physical correction retest pending | Honest evidence/gap policies pass; private field evidence exposed and motivated the stationary-session status correction without weakening route-quality thresholds |
| Background/foreground/interrupted draft/duplicate Finish | Simulator/automated pass; physical pending | Physical OS scheduling not claimed |
| Live Activity/Dynamic Island | Two expected skips; physical pending | Requires signed device build |
| Boost/barometer and normalized DPF language | Automated pass; physical pending | No vehicle observations captured |
| Offline queue and LAN transfer/processing receipt | Automated/API pass; physical pending | Real device-to-Mac LAN path not run |
| Same recording metrics on iPhone/Mac | Golden/transfer tests pass; physical pending | No actual drive compared |

The Phase 7 actual-Jetta checklist must be run parked with the real VIN kept only in memory/local profile. Evidence must record only stable UUID continuity, hashes, timestamps, coverage and pass/fail—not VIN, location, adapter serial, address or credentials.

## Release configuration and archives

The user-facing product and icon remain DriveLine. Internal `CANConnect` projects, targets, modules, bundle identifiers, storage paths and compatibility strings remain unchanged to avoid migration risk. Both products are version `1.0.0` build `25`; Debug and Release remain distinct; both shared schemes archive Release.

Unsigned local archives:

- `/tmp/DriveLinePhase9Release/DriveLine-iPhone-1.0.0-25-final.xcarchive` (24 MB)
- `/tmp/DriveLinePhase9Release/DriveLine-Mac-1.0.0-25-final.xcarchive` (32 MB)

The iPhone archive is intentionally unsigned. A separate physical Debug build succeeded with the signed-in local team as an ephemeral command-line override, provisioned both the app and Live Activity extension, and the preceding candidate was installed/launched on the connected iPhone. The corrected GPS-status build is signed and staged but deliberately not installed over a potentially active recording. This proves development signing and device launch, not App Store distribution validation. The Mac archive is linker/ad-hoc signed, has no team, and the project currently has hardened runtime and App Sandbox disabled. Xcode distribution validation, Mac Developer ID signing and notarization were therefore not claimed as passing. No certificates, provisioning profiles, team IDs or credentials were committed.

## GitHub Actions

| Workflow | Run ID | Commit | Result |
| --- | --- | --- | --- |
| iOS companion | `40252614424` | `eb6617c05746d8d40201a029f7abb9495864df3f` | Passed |
| CAN CONNECT Mac | `40249632442` | `e0c644f0be33645f9a1e226571372afed955f977` | Passed; the later correction changes only `can-connect-ios/**`, so the Mac workflow's path filter correctly did not create another run |
| iOS companion, preceding complete Phase 9 gate | `40249632464` | `e0c644f0be33645f9a1e226571372afed955f977` | Passed |

The first Mac attempt (`40248922896`) exposed an Xcode 26.6 compiler type-check timeout in the large debug fixture. The expression was split into typed intermediate values in `ea187d580069cd09e696891b0a50116dddd327ea`; no fixture values or production behavior changed. The failed attempt is retained as evidence and is not counted as a passing gate.

## Release justification

No known automated data-loss regression remains: schema and store migrations remain additive, corrupt inputs are preserved, receipts stay external to primary JSON, exact originals and hashes remain intact, and sample fixtures contribute zero to real totals. Automated checks, simulator checks and unsigned archives pass. The mandatory signed-device, actual-Jetta/scanner, physical background/reconnect/Live Activity/LAN, full Mac hands-on lifecycle/accessibility, distribution validation and notarization gates remain open. Therefore the only accurate classification is:

**Automated release candidate; physical qualification pending.**
