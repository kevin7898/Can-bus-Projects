# DriveLine Phase 5 evidence and roadmap reconciliation

Phase 4 intentionally delivered parts of the original Fuel Ledger and Signals
roadmap early. The accepted Phase 4 tip
`92922b37f549a5337df117a7c6d8a9b215c1fd2a` was merged without rewriting either
branch by merge commit `af421ad617c9f998a7d749d063a3a850b9cfe780`.
The pre-implementation reconciliation is commit
`5131a9cf32166d8e028087e22088fdf4f9e4e580` and the receipt storage/transfer
milestone is `20afab0`.

The existing dirty `codex/ios-companion` checkout and every unrelated worktree
remained untouched. Work was performed only in the managed
`codex/driveline-drive-ledger` worktree.

## Original Phase 5 — Fuel Ledger

| Requirement | Final status | Evidence |
| --- | --- | --- |
| Migration-safe `FuelEntry` with station/location, currency, price per unit, notes, and optional receipt metadata | complete and tested | Schema-1/2 archive decoding remains supported. The additive schema-2 attachment map keeps metadata in the contract while station/location text, currency, notes, and calculated cost per litre round-trip on both platforms. |
| Mac month summary | complete and tested | The selected vehicle shows calendar-month fill count, purchased litres, and spend grouped without cross-currency conversion. |
| Mac cost/economy chart | complete and tested | Purchased cost, valid full-fill tank economy, and qualifying measured-trip fuel render as three explicitly sourced series. |
| Mac fill ledger | complete and tested | Full/partial state, amount, currency, odometer, station, sample status, cost per litre, valid boundary economy, and receipt availability are shown from library state. |
| Mac selected receipt detail | complete and tested | Selecting a fill shows station, notes, receipt name/type, verified availability or missing-file status, and an enabled Open action only for a valid stored file. |
| iPhone fuel history | complete and tested | Vehicle-scoped history and Fuel Ledger use real store state; sample rows remain labelled and excluded from real totals. |
| iPhone compact Add/Edit Fuel form | complete and tested | Add and edit expose litres, total cost, three-letter currency, odometer, date, full/partial state, station/location, notes, receipt selection/removal, and explicit odometer correction. Light, dark, compact, and largest Dynamic Type routes pass. |
| Tank-to-tank economy only across valid full-fill boundaries, including intervening partial fills | complete and tested | Shared policy groups by stable vehicle ID, starts and ends only on full fills, and includes every intervening partial purchase. |
| Purchased fuel, measured trip fuel, and OBD-derived economy remain distinct | complete and tested | Separate contract fields, policies, labels, charts, transfer tests, and mutation tests prevent one evidence series from changing another. |
| Receipt files live outside primary JSON state | complete and tested | Files are content-addressed by SHA-256 in platform `Receipts/` directories. Primary state retains only `DriveLineReceiptMetadata`. |
| Complete backup/export and restore include receipts | complete and tested | Complete archives carry verified attachment bytes; Mac directory backup copies the external receipt directory; iPhone and Mac restore recreate verified files. Missing files preserve metadata and remain unavailable. |
| A fill added on iPhone transfers to Mac and survives backup/restore without changing trip telemetry | complete and tested | A fuel-only schema-2 transfer imports stable fill/vehicle IDs and receipt bytes without requiring a trip. Reopen and backup/restore tests preserve the receipt; the source trip archive and measured fuel remain byte-for-byte/value unchanged. |
| Validate litres, cost, odometer ordering, and currency without blocking legitimate corrections | complete and tested | Finite positive litres/cost, exactly three ASCII currency letters, non-negative odometer, vehicle-scoped ordering, add/edit identity, and explicit correction override are covered. |

## Original Phase 6 — Signals workspace

Phase 5 does not implement or redesign the remaining Signals scope.

| Requirement | Status after Phase 5 | Evidence and remaining work |
| --- | --- | --- |
| Mac searchable grouped signal browser | not implemented | The Mac still offers a flat picker per card. |
| Mac configurable synchronized lanes | complete and tested | Six independently configurable cards share one recorded timestamp and duplicate choices remain allowed. |
| Shared vertical scrubber linked to route position | complete and tested | Chart selection updates the shared timestamp and MapKit marker without interpolation. |
| Current/min/max/average inspector where valid | partially implemented | Current cursor values, units, source, freshness, and coverage exist; min/max/average remain Phase 6 work. |
| Elapsed-time/distance switching, zoom/reset, and comparison | not implemented | Existing charts use recorded timestamps; the Compare surface does not provide the requested alignment controls. |
| iPhone grouped Signals overview with sparklines | not implemented | Signals remain contextual rather than a grouped overview. |
| iPhone focused signal detail with trace, range, source, and freshness | partially implemented | Trip Story has gap-aware traces, synchronized cursor, units, source, and coverage; a standalone detail and range inspector remain. |
| Contextual entry from Trip Story and More | implemented but awaiting acceptance evidence | Trip Story embeds synchronized Signals and More exposes vehicle data; final Phase 6 navigation acceptance is outstanding. |
| Missing/stale values stay unavailable and no unsupported sample rate is claimed | complete and tested | Shared gap/freshness policies preserve real timestamps and leave unavailable observations empty. |

## Storage, migrations, and preservation

- The archive wire schema remains version 2. `receiptFiles` is an additive,
  default-empty map keyed by receipt SHA-256, with count, per-file size,
  aggregate size, digest, and metadata byte-count validation. Schema-1 and old
  schema-2 payloads continue to decode.
- No primary-state schema bump, telemetry database migration, or reset was
  needed. iPhone `StoredState` remains schema 4 and Mac `LibraryState` remains
  schema 3. Existing history is not discarded.
- Receipt bytes are outside `state.json` / `library.json`. Duplicate content is
  stored once; duplicate metadata safely resolves to the same content-addressed
  file; missing receipt files do not invalidate the fill or archive metadata.
- Fuel-only queued transfers are immutable schema-2 payloads. A later edit
  creates a new payload unless an existing queued trip payload already covers
  the same current fills.
- Existing vehicles, scanner settings, server pairing, credentials, appearance
  preferences, originals, and queued transfer payloads keep their established
  storage paths and decoding behavior. No production recording, recovery,
  scanner, server, or import lifecycle was replaced.

## Focused correctness evidence

- Shared full/partial/full and multi-vehicle fixtures prove the economy boundary
  rule and sample exclusion.
- iPhone tests cover add/edit identity, odometer rejection and explicit
  correction, currencies, receipt restore/deduplication/missing files, fuel-only
  transfer, sample exclusion, and unchanged recorded trip telemetry.
- Mac tests import an iPhone fuel-only archive, verify stable identity and
  receipt bytes, reopen the library, copy/restore a complete backup, deduplicate
  receipt content, and preserve metadata when a file is missing.
- API integration posts a recording transfer followed by an iPhone-style
  fuel-only update with receipt bytes, retrieves the merged trip, checks the
  attachment hash, verifies exact original preservation, and confirms that the
  trip's measured fuel did not change.

## Local validation

Commands were run from the Phase 5 worktree:

```sh
(cd shared/DriveLineShared && swift test)
(cd mac-app && swift test)

xcodebuild build \
  -project mac-app/CANConnect.xcodeproj \
  -scheme CANConnect \
  -configuration Debug \
  -derivedDataPath /tmp/driveline-p5-mac-ui \
  CODE_SIGNING_ALLOWED=NO

python3 mac-app/scripts/api_integration.py \
  /tmp/driveline-p5-mac-ui/Build/Products/Debug/CANConnect.app/Contents/MacOS/CANConnect

xcodebuild test -parallel-testing-enabled NO \
  -project can-connect-ios/CANConnect.xcodeproj \
  -scheme CANConnect \
  -destination 'platform=iOS Simulator,name=DriveLine iPhone 17 Pro Max,OS=27.2' \
  CODE_SIGNING_ALLOWED=NO

xcrun simctl ui 'DriveLine compact layout check' \
  content_size accessibility-extra-extra-extra-large
xcodebuild test -parallel-testing-enabled NO \
  -project can-connect-ios/CANConnect.xcodeproj \
  -scheme CANConnect \
  -destination 'platform=iOS Simulator,name=DriveLine compact layout check,OS=27.2' \
  -only-testing:CANConnectUITests/SmokeTests/testPhase4JourneyStoryFuelAndSignalsAreReachable \
  -only-testing:CANConnectUITests/SmokeTests/testPhase5FuelLedgerAddAndEditAreReachable \
  CODE_SIGNING_ALLOWED=NO
```

- Shared package: 21 passed, 0 failed.
- Mac Swift package: 26 passed, 0 failed. The existing non-failing optional
  `pkg-config` / sqlite3 metadata warning remains; SQLite tests pass.
- Mac Xcode Debug build: passed. The ordinary destination-disambiguation and
  App Intents metadata-not-used diagnostics remain non-failing.
- Mac API integration: passed recording and fuel-only schema-2 transfer,
  external receipt bytes, stable IDs, exact originals, authentication, receipt
  processing, hash deduplication/conflict handling, trip isolation, retrieval,
  and vehicle validation.
- iPhone 17 Pro Max / iOS 27.2 complete unit and UI suite: 128 executed,
  125 passed, 0 failed, and 3 expected skips.
- Compact iPhone / iOS 27.2 at
  `accessibility-extra-extra-extra-large`: Phase 4 Journey/Story/Fuel and Phase 5
  Fuel Ledger/Add/Edit routes passed, 2 passed and 0 failed; the final adaptive
  Add/Edit recheck passed, 1 passed and 0 failed.

The expected skips are the opt-in native-Mac loopback integration and the two
Live Activity checks requiring physical lock-screen or Dynamic Island surfaces.

## Layout and accessibility checks

- iPhone 17 Pro Max Fuel Ledger, Add Fuel, and Edit Fuel were captured in
  explicit light and dark appearance. Full/partial and availability states use
  words/icons in addition to colour.
- The compact simulator was checked at the largest accessibility Dynamic Type
  category. Fuel filters, ledger rows, Add/Edit fields, currency, date/time,
  correction toggle, receipt action, and Done action remain scrollable and
  reachable without horizontally clipped controls. The cost/currency row stacks
  and the compact date control is bounded at accessibility sizes.
- Mac evidence uses 1080 by 720 and 1540 by 1000 point canvases. Navigation,
  month summary, ledger selection, boundary economy, measured trip fuel,
  purchased cost, and receipt status remain visible. Native controls retain
  keyboard focus semantics; no custom key interception was added.
- Sanitized debug-only fixtures use fictional values. Sample entries and sample
  journeys are labelled and contribute zero to real totals.

## Screenshots

- [iPhone Fuel Ledger, light](screenshots/iphone-17-pro-max-fuel-ledger-light.png)
- [iPhone Fuel Ledger, dark](screenshots/iphone-17-pro-max-fuel-ledger-dark.png)
- [iPhone Add Fuel, light](screenshots/iphone-17-pro-max-add-fuel-light.png)
- [iPhone Add Fuel, dark](screenshots/iphone-17-pro-max-add-fuel-dark.png)
- [iPhone Edit Fuel, light](screenshots/iphone-17-pro-max-edit-fuel-light.png)
- [iPhone Edit Fuel, dark](screenshots/iphone-17-pro-max-edit-fuel-dark.png)
- [Compact iPhone Add Fuel, largest Dynamic Type](screenshots/iphone-compact-add-fuel-largest-type-light.png)
- [Mac Fuel workspace, light, 1080 by 720](screenshots/mac-fuel-1080x720-light.png)
- [Mac Fuel workspace, light, widescreen](screenshots/mac-fuel-widescreen-light.png)

## CI

The pushed Phase 5 integration branch triggers the iOS companion and CAN
CONNECT Mac workflows. Exact run identifiers and conclusions are added after
the code/evidence commit is available on `origin`.

## Remaining physical-device validation

Receipt selection from Photos/Files and opening a real receipt; iPhone-to-Mac
delivery over the paired LAN server; background transfer retry after an actual
network loss; physical lock-screen Live Activity and Dynamic Island; OBDLink
MX+ discovery/reconnection; Jetta signal/fuel accuracy; GPS/scanner loss during
a real drive; and an on-vehicle full/partial/full cycle remain hardware checks.
Simulator file contracts, synthetic TCP, isolated local server, and sanitized
fixtures do not replace those checks.
