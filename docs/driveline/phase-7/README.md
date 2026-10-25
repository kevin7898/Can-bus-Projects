# DriveLine Phase 7 — Garage and Vehicle Onboarding

Phase 7 was implemented from `fc8117b0fa02ae5e52b9c1c3b75d270781aec619` on `codex/driveline-drive-ledger`. It extends the existing vehicle, scanner, archive, transfer, recording and onboarding paths; it does not add a second store or a competing identity model.

All committed Phase 7 examples are sanitized debug fixtures. The onboarding fixture is deliberately a fictional **2013 Volkswagen Jetta TDI**. The successful Identify fixture returns a fictional checksum-valid Volkswagen VIN whose locally decoded model-year evidence suggests 2014. It is not the user's vehicle or VIN. Every sample vehicle is visibly labelled `SAMPLE`, and sample trips/fills remain excluded from real totals.

## Vehicle and capability model

The existing shared `DriveLineVehicle` contract now carries additive, optional Garage fields:

- stable vehicle UUID;
- nickname/year/make/model/class/fuel type;
- optional normalized VIN;
- optional trim, engine, transmission, odometer and tank size;
- preferred units and GPS source;
- configured recording-source roles;
- reviewable identification provenance (source, responding ECU/address, protocol and observation time);
- archive state and archive time.

The iPhone `VehicleProfile` and Mac `Vehicle` map these fields through the same archive contract. Platform runtime configuration remains in the existing platform state: the iPhone stores the existing `ScannerSettings` per vehicle, while the Mac retains its import/server/runtime state. No vehicle behavior is enabled by matching display text. Jetta-specific diagnostics still use the existing explicit validated profile/capability rules.

Garage supports passenger car, light truck, motorcycle, heavy truck and other/custom profiles. The Phase 7 fixture shows the fictional 2013 Jetta draft, a 2021 Ford F-150, a 2023 Honda CB500X ABS and an archived 2025 Kenworth T880. Production can save the reviewed Jetta as 2014 only after the user explicitly accepts the suggestion.

## Identity, ownership and filtering

- The vehicle UUID is authoritative and does not change when descriptive fields, VIN or configuration are edited.
- Trips, fills, receipts, annotations, signal observations, imports and queued transfers keep their original vehicle UUID.
- Choosing another vehicle changes only the selected profile and its runtime preferences; existing data is not reassigned.
- Today, Drives, Fuel, Signals, Garage, imports and transfer creation resolve through the selected vehicle.
- A recording draft remains pinned to the vehicle that started it. Switching, editing, archiving or removing vehicles is disabled/rejected while recording or GPS acquisition is active.
- Exact duplicate normalized VIN ownership is rejected unless the existing owner profile is being edited.
- A missing VIN is valid. Make/model/year similarity never merges profiles.
- Real counts, last-drive dates and storage summaries exclude sample trips and fills.
- Unsupported or missing values are rendered as unavailable; saved scanner configuration is not presented as a live connection.

## Garage, archive and removal

Mac and iPhone Garage cards show identity, class/fuel, VIN availability, configured sources, real drive/fill counts, last real drive, storage/receipt summary, transfer queue state and current/archive status. The iPhone shows a live scanner state only when the existing scanner runtime confirms a connection for the selected vehicle. Mac labels scanner/runtime evidence as configured, imported/historical or live unavailable.

Archiving is the normal non-destructive action. Archived profiles and all owned history remain readable and can be restored. Permanent removal is limited to an empty profile. The store rejects removal if trips, fills, receipts, queued transfers or other owned data exist; there is no cascading delete or orphan reassignment.

Vehicle detail surfaces include identity, sources, scanner/GPS state, units, storage, transfer/data summaries, capability status, archive controls and contextual Drives/Fuel/Signals links.

## Four-stage onboarding

### 1. Vehicle

Manual entry accepts nickname, class, year, make, model, trim, engine, transmission, fuel/power type, optional VIN, preferred units, optional odometer and tank size. Unknown fields remain optional and visible as unavailable.

### 2. Scanner

The user can configure iPhone GPS, imported recordings, the existing Wi-Fi/TCP ELM path or the existing paired OBDLink MX+ path. Scanner settings are stored on the draft vehicle. External CAN recorder, generic USB/BLE scanner and external GPS are explicitly labelled planned/unavailable rather than reporting false success.

Legacy global scanner settings migrate once into the selected vehicle only when that vehicle does not already own scanner settings. Another vehicle's settings are never overwritten. Selecting a vehicle switches the existing runtime scanner settings to that vehicle's configuration.

### 3. Identify

Identification is optional. The scanner path temporarily enables headers, performs the existing read-only Mode 09 VIN request, records the responding ECU/address where the adapter supplies it, restores header-free replies, then retains protocol, supported PIDs and observation time. Partial/unsupported VIN replies remain unavailable.

VIN normalization, forbidden-character checks, the North American checksum, Volkswagen WMI recognition and model-year character decoding are local. There is no cloud VIN request or account dependency. The 30-year model-year cycle is resolved only when known entered context yields a single nearby candidate; otherwise every candidate is shown as ambiguous and no year suggestion is made.

Detected year and manufacturer are suggestions. DriveLine does not infer Jetta model, TDI engine, DSG transmission or trim from the VIN. The manually entered 2013 year remains unchanged until the user chooses **Accept 2014**; **Keep 2013** is equally explicit. Accepting or retaining the suggestion preserves the same UUID. Cancelling returns the untouched original profile/store.

Connection failure, timeout, unsupported Mode 09, a partial VIN or invalid VIN leaves the manual draft intact. The user may retry or continue manually.

### 4. Finish

Finish reviews the stable UUID, entered details, VIN storage status, sources, scanner/GPS choices, units, transfer availability and supported/unavailable capabilities. The store changes only after explicit Save/Add Vehicle succeeds. Saving uses the existing atomic state-file replacement, then selects the new vehicle.

## Schema and preservation

Phase 7 does not change any persisted schema number:

- shared archive schema: version 2;
- Mac library schema: version 3;
- iPhone state schema: version 4.

New shared vehicle fields use additive optional/default decoding, so schema-1/schema-2 archives and older platform state remain readable. The only migration behavior added is the guarded global-to-selected-vehicle scanner-settings adoption described above. It does not reset data.

Exact original archive bytes and hashes, recording/fill/receipt UUIDs, external receipt files, annotations, queued transfer payloads, recording recovery, signal registry/cursor behavior and per-vehicle preferences are preserved. No saved history was discarded.

## Automated coverage

Focused shared, Mac and iPhone coverage proves:

- additive legacy contract decoding and round-trip Garage fields;
- checksum-valid fictional 2014 Volkswagen VIN evidence beside a 2013 draft;
- invalid length, invalid characters and invalid checksum rejection;
- ambiguous model-year cycle, recognized Volkswagen WMI and unknown WMI handling;
- indexed, headed, fragmented and partial Mode 09 replies plus responding ECU capture;
- explicit year acceptance, explicit entered-year retention, stable UUID and cancel-without-mutation;
- manual profiles without VIN/scanner, duplicate VIN rejection and atomic save;
- four vehicle classes, vehicle selection and per-vehicle trip/fill/signal/scanner isolation;
- global scanner migration without overwriting per-vehicle configuration;
- active-recording selection lock, import targeting and queued-transfer preservation;
- archive/unarchive, empty-profile deletion and refusal to delete profiles with data;
- sample exclusion and Phase 7 navigation/accessibility identifiers.

## Validation

Commands were run from the repository root:

```sh
swift test --package-path shared/DriveLineShared
swift test --package-path mac-app

xcodebuild -project mac-app/CANConnect.xcodeproj \
  -scheme CANConnect -configuration Debug \
  -derivedDataPath /tmp/driveline-phase7-mac-final-derived \
  build CODE_SIGNING_ALLOWED=NO

python3 mac-app/scripts/api_integration.py \
  /tmp/driveline-phase7-mac-final-derived/Build/Products/Debug/CANConnect.app/Contents/MacOS/CANConnect

xcodebuild build-for-testing \
  -project can-connect-ios/CANConnect.xcodeproj \
  -scheme CANConnect \
  -destination 'platform=iOS Simulator,id=C975E238-AE3A-4B13-9FE8-477B69F94928' \
  -derivedDataPath /tmp/driveline-phase7-ios-final-derived \
  CODE_SIGNING_ALLOWED=NO

xcodebuild test-without-building -parallel-testing-enabled NO \
  -project can-connect-ios/CANConnect.xcodeproj \
  -scheme CANConnect \
  -destination 'platform=iOS Simulator,id=C975E238-AE3A-4B13-9FE8-477B69F94928' \
  -derivedDataPath /tmp/driveline-phase7-ios-final-derived \
  -resultBundlePath /tmp/driveline-phase7-ios-final-full-2.xcresult \
  CODE_SIGNING_ALLOWED=NO

xcrun simctl ui 'DriveLine compact layout check' \
  content_size accessibility-extra-extra-extra-large
xcodebuild test-without-building -parallel-testing-enabled NO \
  -project can-connect-ios/CANConnect.xcodeproj \
  -scheme CANConnect \
  -destination 'platform=iOS Simulator,id=1C049B43-E5EA-437F-BBDE-52C159051934' \
  -derivedDataPath /tmp/driveline-phase7-ios-final-derived \
  -resultBundlePath /tmp/driveline-phase7-ios-compact.xcresult \
  -only-testing:CANConnectUITests/SmokeTests/testPhase7CompactLargestAccessibilityOnboarding \
  CODE_SIGNING_ALLOWED=NO
```

Results:

- Shared package: **30 passed, 0 failed**.
- Mac Swift package: **31 passed, 0 failed**. The existing optional `pkg-config`/sqlite3 metadata warning remains non-failing; SQLite import coverage passes.
- Mac Xcode Debug build: **passed**.
- Mac API integration: **passed** recording and fuel-only schema-2 transfer, external receipt bytes, stable IDs, exact originals, authentication, processing receipts, hash deduplication/conflict, trip isolation, retrieval and vehicle validation.
- iPhone 17 Pro Max / iOS 27.2 complete suite: **141 total, 138 passed, 3 expected skips, 0 failed** (**123 unit + 18 UI**).
- Compact iPhone / iOS 27.2 at `accessibility-extra-extra-extra-large`: **1 passed, 0 failed**.
- Expected skips: opt-in native-Mac loopback transfer and the two physical Live Activity/Dynamic Island checks.
- Existing non-failing iPhone compiler warnings remain in `GPSRecorder` around the `UIApplication` foreground-state closure; Phase 7 did not alter that path.

The Mac evidence renderer exercised 1080×720 and 1540×1000 light/dark layouts. Native controls expose keyboard focus in the interactive app, but a final physical keyboard traversal remains in the manual checklist. iPhone navigation titles and controls remained reachable by scrolling on the 17 Pro Max and compact largest-Dynamic-Type simulator.

## Screenshot inventory

All files are under `docs/driveline/phase-7/screenshots/`:

- `mac-garage-1080x720-light.png`
- `mac-garage-1080x720-dark.png`
- `mac-garage-widescreen-light.png`
- `mac-garage-widescreen-dark.png`
- `mac-vehicle-detail-light.png`
- `mac-vehicle-detail-dark.png`
- `mac-add-vehicle-light.png`
- `mac-add-vehicle-dark.png`
- `iphone-garage-light.png`
- `iphone-garage-dark.png`
- `iphone-vehicle-detail-light.png`
- `iphone-vehicle-detail-dark.png`
- `iphone-archived-light.png`
- `iphone-archived-dark.png`
- `iphone-onboarding-vehicle-light.png`
- `iphone-onboarding-scanner-light.png`
- `iphone-onboarding-identify-success-light.png`
- `iphone-onboarding-identify-failure-light.png`
- `iphone-onboarding-finish-light.png`
- `iphone-compact-accessibility.png`

No committed screenshot contains a real VIN, adapter serial, pairing credential, token, local address or personal location.

## GitHub Actions

Both push workflows validated implementation/evidence tip `7d0ec956d361db29ac18022644388cf8f918ad51`:

- [CAN CONNECT Mac · run 40238869032](https://github.com/kevin7898/Can-bus-Projects/actions/runs/40238869032) — run 33, completed successfully. Core tests, Xcode build, API integration, application packaging and artifact upload passed.
- [iOS companion · run 40238869050](https://github.com/kevin7898/Can-bus-Projects/actions/runs/40238869050) — run 52, completed successfully. Simulator selection, complete native build/test, screenshot export and retained test evidence passed.

## Physical-device acceptance — actual 2014 Jetta

Do not write the VIN, adapter serial, local address or credentials into this document, screenshots or logs. Perform the following only with local/private runtime data:

- [ ] Record the existing Garage/store fingerprint and draft UUID without recording VIN text.
- [ ] Begin with the deliberately incorrect manual draft: **2013 Volkswagen Jetta TDI**.
- [ ] Connect through the existing supported scanner path to the actual 2014 Volkswagen Jetta TDI DSG.
- [ ] Confirm the app sends only the read-only Mode 09 VIN request for identification.
- [ ] Confirm a complete 17-character VIN is received, normalized and locally checksum-validated; do not capture or transcribe it.
- [ ] Confirm Identify shows detected model year 2014, recognized manufacturer Volkswagen, VIN source, responding ECU/address when supplied, selected protocol and observation timestamp.
- [ ] Confirm entered 2013 and suggested 2014 appear together and the draft remains 2013 before a choice.
- [ ] Choose **Keep 2013**, verify the entered year remains 2013, then cancel and confirm the original store/draft fingerprint is unchanged.
- [ ] Repeat, choose **Accept 2014**, save, and confirm the vehicle UUID is identical before/after review while the saved year becomes 2014.
- [ ] Confirm no model, TDI engine, DSG transmission or trim field was inferred from VIN evidence alone.
- [ ] Confirm scanner live state appears only while the runtime is actually connected to the selected vehicle.
- [ ] Start a recording, verify vehicle switching is unavailable, finish it, then verify it remains owned by the same UUID in Drives, Fuel and Signals.
- [ ] Archive/unarchive the profile and verify trips, fills, receipts, annotations, originals and queued transfers remain readable and unchanged.
- [ ] Inspect local logs/evidence for redaction; confirm no VIN, serial, address, credential or token escaped.

Remaining hardware validation is the checklist above, the paired OBDLink MX+ and/or in-vehicle Wi-Fi adapter paths, actual ECU-header availability, real ignition/timeout/unsupported-command behavior, GPS permission/background delivery, Live Activity/lock-screen surfaces, and a physical Mac keyboard focus traversal. No Phase 8 or Phase 9 work is included.
