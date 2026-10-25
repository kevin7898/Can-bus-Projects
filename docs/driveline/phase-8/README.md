# DriveLine Phase 8 — Empty, Offline, Stale, Failure and Recovery States

Phase 8 starts from `c7d5d45662eacd98c5a243a8b96ce7f0b2945700` on `codex/driveline-drive-ledger`. It extends the existing recording draft, transfer queue, import receipt, original-preservation, semantic component and platform-state persistence paths. It does not add a second lifecycle, queue, issue database or recovery store.

All committed evidence uses a visibly labelled, debug-only fictional **2013 Volkswagen Jetta TDI**. It contains no real VIN, location, scanner identity, address, credential, token or receipt content, and it contributes zero to real totals.

## Shared status contract

Both apps use the same 13 states: `ready`, `active`, `waiting`, `queued`, `processing`, `degraded`, `stale`, `unavailable`, `offline`, `failed`, `recovered`, `complete` and `read-only`. Each has a text label and icon; colour is supplementary.

- **Saved** means the local atomic write completed.
- **Transferred** means the destination acknowledged the preserved payload.
- **Processed/complete** means the Mac processing receipt confirmed completion.
- **Recovered** names the recovered object and keeps known missing intervals or sources explicit.
- A transfer retry reuses the exact frozen payload and hash. An import retry uses the preserved original and receipt identity.

`DriveLineStateMatrix.all` is the executable normative matrix. Tests require exactly 119 consecutive IDs, a supported semantic state, non-empty trigger/evidence/wording/recovery fields, and only targeted recovery actions.

## Complete state matrix

The table is normalized to remain reviewable. Every row below inherits its category's exact trigger, persisted evidence and recovery result from the policy table; its state and action are row-specific. `—` means that observation or automatic verified transition, rather than a user command, is the only safe next step.

| Category | Platform | Trigger | Persisted evidence | Recovery result |
|---|---|---|---|---|
| Empty | shared | Absence of the named record in the selected scope | Existing vehicles, recordings, fills, receipt metadata/files, queues and archives | Existing evidence remains intact; state advances only after the named data arrives |
| Recording preflight | iPhone | Current authorization, accepted GPS fix, scanner/runtime vehicle, active draft and writable-store result | Permission/fix timestamps, per-vehicle scanner configuration, runtime vehicle UUID and the vehicle-bound draft; secrets excluded | Only the requested source/action changes; GPS-only remains honest and OBD coverage is never implied |
| Active recording | iPhone | Existing draft, source timestamps, reconnect deadline and final-write state | Checkpointed draft, explicit gap boundary, fixed end request and source-specific observations | Same draft identity and evidenced boundary remain; no outage samples are fabricated |
| Offline and transfer | shared | Persisted queue item, destination acknowledgement and processing receipt | Locally saved recording, immutable bytes/hash, acknowledgement and receipt | Originals remain local; retry never rebuilds or mutates frozen bytes |
| Import and original preservation | Mac | Parser/schema/identity result plus import and ingestion state | Original bytes/hash copied before processing, stable IDs, attachment metadata and import receipt | Retry/restart uses the preserved original and existing receipt identity |
| Signal and coverage | shared | Recorded observations at the cursor and visible range | Finite values, real timestamps, source/provenance, coverage and explicit gaps | Only recorded finite observations contribute; no fill, interpolation or invented rate |
| Library and storage recovery | shared | Filesystem, schema, attachment and backup validation | Original unreadable bytes, validated backup when present, paths, references and schema | No vehicle, fill, receipt, draft, preference, original or queued transfer is reset |
| Mac lifecycle | Mac | Actual window, process, ingestion, listener and shutdown state | Current application/listener state and durable library | Presentation follows the actual process; no background or LAN reachability is promised |

### Empty states

| # | Platform | State | Presentation / what remains safe | Safe action |
|---:|---|---|---|---|
| 1 | shared | unavailable | No vehicles configured; existing library evidence remains preserved | Configure vehicle |
| 2 | shared | ready | Vehicle configured with no recordings; recordings normally arrive from Record or import | Add recording |
| 3 | shared | unavailable | No GPS route was recorded; scanner evidence remains available | View coverage details |
| 4 | shared | unavailable | No scanner telemetry was recorded; GPS route remains available | View coverage details |
| 5 | shared | ready | No fills; trips and measured trip fuel remain separate | Add fuel |
| 6 | shared | unavailable | No receipt attached; the fuel entry remains saved | Attach receipt |
| 7 | shared | unavailable | No signals were recorded for this recording | View coverage details |
| 8 | shared | unavailable | Known signal was not observed in this recording | View coverage details |
| 9 | shared | unavailable | No same-vehicle comparison candidate exists | — |
| 10 | shared | read-only | Archived vehicle history remains readable and unchanged | — |
| 11 | Mac | ready | Import queue is empty; preserved originals and library remain unchanged | — |
| 12 | iPhone | ready | Transfer queue is empty; local recordings remain unchanged | — |

### Recording preflight

| # | State | Presentation / what remains safe | Safe action |
|---:|---|---|---|
| 13 | waiting | Location permission has not been decided; no location is assumed | Open Settings |
| 14 | unavailable | Location permission denied; scanner recording may remain available | Open Settings |
| 15 | unavailable | Location permission restricted; no bypass is claimed | Open Settings |
| 16 | waiting | GPS is waiting for its first acceptable, fresh fix | — |
| 17 | ready | An acceptable GPS fix exists with its real timestamp | — |
| 18 | unavailable | Scanner not configured; GPS-only recording remains available | Retry connection; Continue GPS-only |
| 19 | offline | Scanner is configured but currently unavailable | Retry connection; Continue GPS-only |
| 20 | processing | Scanner connection is in progress | — |
| 21 | failed | Scanner authentication/pairing was rejected | Open Settings |
| 22 | failed | Scanner connection timed out | Retry connection; Continue GPS-only |
| 23 | ready | Scanner runtime is connected to the selected vehicle UUID | — |
| 24 | degraded | Scanner is connected to a different vehicle; recording is blocked to avoid misassignment | Choose correct vehicle |
| 25 | failed | Local storage is unavailable/unwritable; the existing draft is retained | — |
| 26 | degraded | Free space may be too low for reliable recording; no exact remaining-drive estimate is invented | — |
| 27 | active | A vehicle-bound recording already exists | Finish recording |
| 28 | active | Vehicle switch is blocked by active acquisition/recording | Finish recording |

### Active recording degradation

| # | State | Presentation / what remains safe | Safe action |
|---:|---|---|---|
| 29 | degraded | Scanner unavailable; GPS continues locally inside the existing grace period | Finish recording |
| 30 | processing | Scanner reconnecting; GPS continues and retries do not extend the original deadline | Finish recording |
| 31 | recovered | Scanner recovered; the outage remains an explicit signal gap | — |
| 32 | degraded | Scanner missed the deadline; the recording ends at last scanner evidence | — |
| 33 | degraded | GPS unavailable; scanner continues and the route retains a visible gap | Finish recording |
| 34 | recovered | GPS recovered; the missing route interval remains visible and unbridged | — |
| 35 | degraded | Both sources unavailable; checkpointed draft remains and no samples are fabricated | Finish recording |
| 36 | active | App backgrounded; the same existing recording remains active | Finish recording |
| 37 | recovered | Interrupted checkpointed draft recovered once | — |
| 38 | recovered | Draft recovered with complete local evidence | — |
| 39 | recovered | Draft recovered with a known final gap explicitly retained | — |
| 40 | processing | Finish requested while a persistence write is pending | — |
| 41 | processing | Duplicate Finish is coalesced; no second trip is created | — |
| 42 | failed | Final write failed; the only recoverable draft and fixed end boundary remain | Retry save |

### Offline and transfer

| # | State | Presentation / what remains safe | Safe action |
|---:|---|---|---|
| 43 | offline | Recording is saved locally and has not transferred | Retry transfer |
| 44 | unavailable | Mac destination is not configured | Configure Mac destination |
| 45 | offline | Configured Mac is unreachable; frozen payload remains queued | Retry transfer |
| 46 | failed | Destination rejected authentication; no completion is claimed | Retry transfer |
| 47 | queued | Immutable payload bytes and content hash are durably queued | Retry transfer |
| 48 | processing | Preserved bytes are uploading; bytes sent is not acknowledgement or processing | Retry transfer |
| 49 | processing | Mac acknowledged the original and is still processing it | Check processing receipt |
| 50 | degraded | Mac restart interrupted processing; acknowledgement remains recorded | Check processing receipt |
| 51 | recovered | Existing receipt/original was recovered and requeued after restart | Check processing receipt |
| 52 | failed | Transfer failed before acknowledgement; frozen local payload remains | Retry transfer |
| 53 | failed | Original was acknowledged, but Mac processing failed | Check processing receipt |
| 54 | stale | Receipt polling timed out; processing completion is unknown | Check processing receipt |
| 55 | failed | Receipt identity does not match this transfer; completion was rejected | Check processing receipt |
| 56 | complete | Exact bytes already have an authoritative receipt; no duplicate is created | — |
| 57 | failed | Same stable identity has conflicting bytes; neither original is overwritten | — |
| 58 | complete | Destination acknowledgement and processing receipt both confirm completion | — |
| 59 | complete | Transfer completed and the original remains on iPhone | — |
| 60 | ready | Retry sends identical frozen bytes without rebuilding or mutation | Retry transfer |

### Import and original preservation

| # | State | Presentation / what remains safe | Safe action |
|---:|---|---|---|
| 61 | failed | Unsupported file type; no library mutation occurs | — |
| 62 | failed | Malformed archive; original bytes are preserved and no partial data commits | Retry import |
| 63 | read-only | Schema is newer than this app; source remains preserved unchanged | — |
| 64 | recovered | Schema 1 decoded through the version-2 adapter without rewriting the original | — |
| 65 | ready | Schema 2 decoded and validated | — |
| 66 | complete | Content hash matches an existing receipt; no duplicate data is created | — |
| 67 | failed | Stable identity conflicts with different bytes; existing data is not overwritten | Retry import |
| 68 | failed | Archive vehicle differs from target; data is not reassigned | Choose correct vehicle |
| 69 | degraded | Receipt metadata remains, but the external file is missing | — |
| 70 | failed | Receipt SHA-256/byte count mismatch; bytes are not installed | Retry import |
| 71 | queued | Import queued only after the original is durably preserved | — |
| 72 | processing | Preserved original is parsing; library changes only after success | — |
| 73 | failed | Import failed with original retained for targeted retry | Retry import |
| 74 | recovered | Interrupted processing requeued with the same receipt and original | — |
| 75 | complete | Import committed with processing receipt and preserved original | — |
| 76 | waiting | Ingestion is paused without discarding the queue | Resume ingestion |
| 77 | active | Ingestion resumed and reflects the running processor | — |

### Signal and coverage

| # | State | Presentation / what remains safe | Safe action |
|---:|---|---|---|
| 78 | ready | Fresh recorded observation at the cursor | View coverage details |
| 79 | stale | Latest observation is outside its freshness interval at this cursor | View coverage details |
| 80 | unavailable | No recorded observation exists at this cursor | View coverage details |
| 81 | unavailable | Non-finite source evidence is retained but excluded from statistics | View coverage details |
| 82 | degraded | Only sparse recorded points are shown; no rate is inferred | View coverage details |
| 83 | degraded | Chart breaks across the long gap; no forward-fill/interpolation | View coverage details |
| 84 | degraded | GPS evidence exists; OBD coverage is unavailable and not implied | View coverage details |
| 85 | degraded | OBD evidence exists; route and distance alignment are unavailable | View coverage details |
| 86 | complete | Mixed recording has evidenced full coverage | View coverage details |
| 87 | degraded | Mixed recording has partial GPS coverage and explicit route gaps | View coverage details |
| 88 | degraded | Mixed recording has partial scanner coverage and explicit signal gaps | View coverage details |
| 89 | unavailable | Distance alignment lacks sufficient recorded route progress | View coverage details |
| 90 | unavailable | Gauge boost lacks compatible fresh asynchronous barometric evidence | View coverage details |
| 91 | ready | Normalized DPF regen trigger is an indicator, never physical fullness | View coverage details |
| 92 | unavailable | Raw stable ID is shown; name, unit and scaling remain unavailable | View coverage details |

### Library and storage recovery

| # | State | Presentation / what remains safe | Safe action |
|---:|---|---|---|
| 93 | ready | Missing state file is treated as first launch, not corruption | — |
| 94 | ready | Empty new library is valid | Configure vehicle |
| 95 | read-only | Corrupt JSON bytes are preserved and never replaced by an empty library | — |
| 96 | read-only | Future schema remains preserved unchanged | — |
| 97 | recovered | Interrupted atomic replacement detected; primary and last valid backup remain | Restore backup |
| 98 | ready | A decoded, validated backup is available | Restore backup |
| 99 | recovered | Validated backup restored after damaged source was preserved | — |
| 100 | failed | Primary and backup invalid; both remain preserved and no reset is created | — |
| 101 | read-only | Library is readable but unwritable; history remains readable | — |
| 102 | degraded | Originals directory is missing; library is not reset | — |
| 103 | degraded | Receipt directory is missing; receipt metadata remains | — |
| 104 | unavailable | Individual receipt metadata remains but external file is missing | — |
| 105 | degraded | State references an unavailable attachment without cascading deletion | — |
| 106 | read-only | Migration failed before commit; pre-migration bytes remain | — |
| 107 | degraded | Missing vehicle UUID reference remains retained, not reassigned/deleted | Choose correct vehicle |
| 108 | degraded | Selected vehicle is unavailable; other profiles/history remain | Choose correct vehicle |
| 109 | offline | Storage path is temporarily unavailable | — |
| 110 | failed | Mac server could not bind/start; no listener is claimed | Open Settings |

### Mac lifecycle

| # | State | Presentation / what remains safe | Safe action |
|---:|---|---|---|
| 111 | active | Main window is open | — |
| 112 | active | Closing the window leaves the currently running in-process server active | — |
| 113 | active | Ingestion processor is active | — |
| 114 | waiting | Ingestion is paused with queue/originals retained | Resume ingestion |
| 115 | processing | App is quitting and stopping local services | — |
| 116 | complete | Server listener stopped after quit | — |
| 117 | failed | Server failed to start; no availability is claimed | Open Settings |
| 118 | offline | LAN access is unavailable; local-only service may still exist if listening | Open Settings |
| 119 | ready | Server is available on this Mac only; LAN reachability is not claimed | — |

## Persistence and recovery semantics

The iPhone `LocalStore` and Mac `LibraryRepository` validate encoded state before atomic replacement. Before replacing an existing valid primary file they retain its last valid bytes as `state.backup.json`. A corrupt primary is copied, byte-for-byte, into a timestamped `recovery/` item before the app exposes read-only recovery. Restore is offered only when the backup itself decodes and validates. An invalid primary plus invalid backup remains untouched; DriveLine does not create an empty replacement.

Recording recovery continues to use the existing checkpointed `RecordingDraft`. Duplicate Finish requests are coalesced. A failed final write retains the draft and fixed end boundary for an explicit save retry. Independent GPS and scanner outages continue only the still-evidenced source and create visible route/signal gaps.

Transfers keep local source data and immutable queued payload bytes after acknowledgement and after processing success. Upload, acknowledgement and processing are distinct. Mac imports preserve originals before parse/processing, bind retries to the existing receipt, and commit library changes only after successful validation. Missing external receipt files do not delete receipt metadata or fuel entries.

## Schema and migration statement

Phase 8 adds no persisted schema migration:

- shared archive schema: version 2, with schema-1 decoding preserved;
- Mac library schema: version 3;
- iPhone state schema: version 4.

The new state matrix is a shared code contract, not a stored telemetry model. Existing vehicle/recording/fill UUIDs, exact original archives and hashes, external receipts, annotations, scanner settings, credentials, appearance, queued transfer payloads and recorded route/telemetry evidence are preserved. No saved history is discarded.

## Accessibility behavior

Every state card exposes its status word, icon, preservation explanation and recovery result without relying on colour. Buttons name the actual target, disabled fixture buttons demonstrate non-actionable states, and identifiers use `phase8.evidence` plus `phase8.state.<id>`. Native Mac controls retain keyboard focus; the compact iPhone fixture reflows headings and remains vertically scrollable at `accessibility-extra-extra-extra-large`.

## Validation

Commands were run from the repository root:

```sh
swift test --package-path shared/DriveLineShared
swift test --package-path mac-app

xcodebuild -project mac-app/CANConnect.xcodeproj \
  -scheme CANConnect -configuration Debug \
  -derivedDataPath /tmp/driveline-phase8-mac-final-derived \
  build CODE_SIGNING_ALLOWED=NO

python3 mac-app/scripts/api_integration.py \
  /tmp/driveline-phase8-mac-final-derived/Build/Products/Debug/CANConnect.app/Contents/MacOS/CANConnect

xcodebuild build-for-testing \
  -project can-connect-ios/CANConnect.xcodeproj \
  -scheme CANConnect \
  -destination 'platform=iOS Simulator,id=C975E238-AE3A-4B13-9FE8-477B69F94928' \
  -derivedDataPath /tmp/driveline-phase8-ios-final-derived \
  CODE_SIGNING_ALLOWED=NO

xcodebuild test-without-building -parallel-testing-enabled NO \
  -project can-connect-ios/CANConnect.xcodeproj \
  -scheme CANConnect \
  -destination 'platform=iOS Simulator,id=C975E238-AE3A-4B13-9FE8-477B69F94928' \
  -derivedDataPath /tmp/driveline-phase8-ios-final-derived \
  -resultBundlePath /tmp/driveline-phase8-ios-full-2.xcresult \
  CODE_SIGNING_ALLOWED=NO

xcrun simctl ui 1C049B43-E5EA-437F-BBDE-52C159051934 \
  content_size accessibility-extra-extra-extra-large
xcodebuild test-without-building -parallel-testing-enabled NO \
  -project can-connect-ios/CANConnect.xcodeproj \
  -scheme CANConnect \
  -destination 'platform=iOS Simulator,id=1C049B43-E5EA-437F-BBDE-52C159051934' \
  -derivedDataPath /tmp/driveline-phase8-ios-final-derived \
  -resultBundlePath /tmp/driveline-phase8-ios-compact.xcresult \
  -only-testing:CANConnectUITests/SmokeTests/testPhase8CompactLargestAccessibilityStateCardsRemainReachable \
  CODE_SIGNING_ALLOWED=NO
```

Results:

- Shared package: **33 passed, 0 failed**. Three focused Phase 8 tests cover the 13-value vocabulary, all 119 matrix rows, exact trigger/evidence/wording/recovery presence, targeted actions, acknowledgement-versus-processing language, frozen retry bytes, gap honesty and corrupt-library wording.
- Mac Swift package: **34 passed, 0 failed**. The existing optional `pkg-config`/sqlite3 metadata warning remains non-failing; SQLite import coverage passes.
- Mac Xcode Debug build: **passed**.
- Mac API integration: **passed** recording and fuel-only schema-2 transfer, external receipt bytes, stable identities, exact originals, authentication, processing receipts, hash deduplication/conflict, trip isolation, retrieval and vehicle validation.
- iPhone 17 Pro Max / iOS 27.2 complete suite: **146 total, 143 passed, 3 expected skips, 0 failed** (**126 unit + 20 UI**).
- Compact iPhone / iOS 27.2 at `accessibility-extra-extra-extra-large`: **1 passed, 0 failed**.
- Expected skips: opt-in native-Mac loopback transfer and the two physical Live Activity/Dynamic Island checks.
- The iOS 27.2 simulator emits an existing duplicate WebKit accessibility-loader warning; it did not fail or skip any Phase 8 test.

## Screenshot inventory

All files are under `docs/driveline/phase-8/screenshots/`:

- `iphone-empty-garage-light.png`
- `iphone-empty-today-light.png`
- `iphone-empty-drives-light.png`
- `iphone-empty-fuel-light.png`
- `iphone-empty-signals-light.png`
- `iphone-location-denied-light.png`
- `iphone-scanner-unavailable-light.png`
- `iphone-scanner-lost-gps-continues-light.png`
- `iphone-gps-lost-obd-continues-light.png`
- `iphone-recovered-recording-gap-light.png`
- `iphone-offline-queued-transfer-light.png`
- `iphone-transfer-processing-failed-complete-light.png`
- `iphone-recovery-representative-dark.png`
- `iphone-compact-largest-dynamic-type-dark.png`
- `mac-empty-library-1080x720-light.png`
- `mac-empty-library-1080x720-dark.png`
- `mac-library-recovery-1540x1000-light.png`
- `mac-library-recovery-1540x1000-dark.png`
- `mac-import-states-1540x1000-light.png`
- `mac-import-states-1540x1000-dark.png`
- `mac-missing-receipt-1080x720-light.png`
- `mac-missing-receipt-1080x720-dark.png`
- `mac-server-states-1540x1000-light.png`
- `mac-server-states-1540x1000-dark.png`

The Mac renderer covers both 1080×720 minimum and 1540×1000 widescreen layouts. Representative light/dark renders include ready/complete, degraded, failed, read-only, offline, queued and processing states.

## GitHub Actions

Pending final evidence push.

## Remaining physical-device validation

- [ ] Exercise location not-determined/denied/restricted and first acceptable fix on a physical iPhone.
- [ ] Confirm GPS-only recording, independent GPS/scanner loss, in-grace scanner recovery, grace expiry and explicit visible gaps during an actual drive.
- [ ] Interrupt/terminate during recording and during final persistence, then verify the same draft UUID and honest final-gap presentation.
- [ ] Queue offline transfer, retry identical bytes, interrupt Mac processing, restart, and confirm acknowledgement/processing receipts against physical devices.
- [ ] Disconnect the Mac library/originals/receipts volume, restore it, and confirm read-only/offline recovery without reset.
- [ ] Validate missing/corrupt external receipt files using expendable sanitized local files.
- [ ] Confirm Mac main-window-close/server behavior, port conflict, local-only listener, LAN denial, pause/resume and quit shutdown with the actual firewall/network configuration.
- [ ] Traverse every actionable Mac state using a physical keyboard and VoiceOver; repeat the iPhone recovery flows with VoiceOver.
- [ ] Recheck light/dark contrast and largest Dynamic Type on physical iPhone hardware.
- [ ] Complete the existing real-vehicle checklist without recording the VIN, adapter serial, network address, credentials or personal route.

Phase 8 does not include Phase 9 optimization, distribution, signing, notarization or TestFlight work.
