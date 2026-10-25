# DriveLine Phase 6 — Signals Workspace

Phase 6 adds recorded-signal analysis to the existing DriveLine journey evidence model. It does not add a telemetry database, a second cursor, a parallel signal store, or a new calculation path. Both apps use `DriveLineJourneyPolicy` and the synchronized Trip Story recording timestamp.

## Implemented surfaces

### Mac

- Signals has a searchable browser grouped as Driving, Engine, Temperatures, Fuel and economy, Pressure and boost, Emissions and DPF, Transmission, Electrical, GPS and motion, Raw/diagnostic, and Other or unknown.
- Search covers display name, stable identifier, alias, source identifier, and unit. Unknown recorded identifiers remain selectable under Other or unknown with their exact identifiers and unavailable metadata.
- Six independently configured lanes are retained, including intentional duplicate selections. The additive optional `signalKeys` preference migrates legacy enum-backed selections without changing the library schema.
- Every lane identifies the recording, signal, unit, source, measured/derived state, derivation ID/version, coverage, latest observation, cursor freshness/value, visible-range minimum/maximum/arithmetic recorded-observation average/count, and independent comparison provenance.
- All lanes share one recorded-time scrubber and route marker. Zoom, reset, drag/pan, elapsed-time alignment, qualifying recorded-distance alignment, explicit Fit Route, and same-vehicle comparison are available.
- Primary and comparison recordings retain separate names, sources, units, gaps, and statistics. Alignment defaults to elapsed time; no calendar-time alignment is inferred.
- Map state is not refit by cursor movement. It refits only on first load, recording change, Reset/Fit Route, or another explicit route fit.

### iPhone

- More → Settings → Signals opens the grouped Signals overview without adding a sixth tab. Trip Story retains a contextual entry into the same overview and recording.
- Each row shows its stable identifier, latest finite recorded value, unit when known, source, cursor freshness, coverage, observation count, textual/icon status, and a gap-aware sparkline.
- Signal Detail provides the full gap-aware trace, recording/visible ranges, shared cursor, visible-range current/min/max/arithmetic recorded-observation average/count, source/provenance, coverage/freshness, gap intervals, derivation details, and synchronized route position when GPS evidence permits it.
- The historical route marker can move without changing the manually adjusted viewport; Fit Route is explicit.

## Registry and grouping policy

The registry is shared code, not app-local presentation data. Known stable identifiers supply approved display names, units, aliases, and groups. Recorded source identifiers are discovered from the observation metadata. The browser may offer a known signal that is unavailable in one recording, but it never invents an observation.

Unknown stable identifiers are not renamed, rescaled, assigned a unit, or discarded. They are shown verbatim under Other or unknown, with unsupported metadata labelled unavailable. Raw diagnostic command/reply text is shown only when it exists at the qualifying cursor observation; pairing credentials and unrelated transport settings are never copied into the evidence view.

`dpfRegenTrigger` is named **DPF regeneration trigger · normalized** and retains the existing explanation that it is an ECU trigger indicator, never soot loading, ash loading, or physical filter fullness.

## Statistics policy

- Minimum, maximum, arithmetic mean, and count use only finite observations inside the selected visible range.
- “Recorded avg” means arithmetic mean of the actual recorded observations. It is not time-weighted.
- Unavailable and non-finite values are excluded. No value is forward-filled, interpolated, or synthesized across a gap.
- Signal segments split at the existing 10-second signal threshold; GPS evidence uses the existing 30-second threshold. Charts and sparklines render segments independently and preserve isolated recorded points.
- Coverage continues to use the existing shared coverage policy and is never presented as a claimed sample rate.
- The overview displays the latest recorded value when one exists while separately reporting whether that observation is fresh, stale, or unavailable at the recording-end cursor.

Gauge boost remains derived only by `driveline.boost-gauge.v1` (algorithm version 1), using compatible absolute MAP/boost and a sufficiently fresh asynchronous barometric observation. Its derivation and source identifiers remain visible.

## Cursor and alignment semantics

The cursor is an exact recorded timestamp shared by lane charts, Trip Story, raw diagnostic evidence, and the route marker. Cursor values use the latest qualifying observation at or before that timestamp only within the applicable freshness window. A later GPS-only observation cannot suppress an older scanner signal, and an old scanner value is shown as stale/unavailable rather than current.

Elapsed-time comparison uses seconds from each recording start. Travelled-distance comparison uses cumulative progress calculated only between qualifying recorded GPS points. It is available only when the recording establishes positive route progress with at least 50% GPS coverage. OBD-only, stationary, sparse, or inadequately covered recordings receive a written explanation and cannot select distance alignment. Gaps add no inferred distance.

Comparison is restricted to recordings with the same stable vehicle identity. Differing lengths and differing signal availability remain visible independently; provenance and missing intervals are never merged.

## Preservation and schema statement

No archive, transfer, iPhone state, or Mac library schema version changed in Phase 6. Schema-1 and schema-2 archive decoding, stable recording/vehicle/fill identities, exact original bytes and hashes, fuel entries, externally stored receipt files and receipt metadata, annotations, recovery state, and queued transfer payloads continue through the existing paths unchanged. Mac library schema remains version 3 and iPhone local state remains version 4. The optional Mac lane-key preference is migration-safe when absent.

The Phase 6 fixtures are debug-only, sanitized, visibly labelled sample recordings. Their trips and fills use the sample/demo flags and contribute zero to real distance, fuel, cost, economy, or vehicle totals.

## Validation

Commands run from the repository root unless noted:

```sh
swift test --package-path shared/DriveLineShared
swift test --package-path mac-app

xcodebuild -project mac-app/CANConnect.xcodeproj \
  -scheme CANConnect -configuration Debug \
  -derivedDataPath /tmp/driveline-phase6-mac-final-derived \
  build CODE_SIGNING_ALLOWED=NO

python3 mac-app/scripts/api_integration.py \
  /tmp/driveline-phase6-mac-final-derived/Build/Products/Debug/CANConnect.app/Contents/MacOS/CANConnect

xcodebuild build-for-testing \
  -project can-connect-ios/CANConnect.xcodeproj \
  -scheme CANConnect \
  -destination 'platform=iOS Simulator,id=C975E238-AE3A-4B13-9FE8-477B69F94928' \
  -derivedDataPath /tmp/driveline-phase6-ios-final-derived \
  CODE_SIGNING_ALLOWED=NO

xcodebuild test-without-building -parallel-testing-enabled NO \
  -project can-connect-ios/CANConnect.xcodeproj \
  -scheme CANConnect \
  -destination 'platform=iOS Simulator,id=C975E238-AE3A-4B13-9FE8-477B69F94928' \
  -derivedDataPath /tmp/driveline-phase6-ios-final-derived \
  -resultBundlePath /tmp/driveline-phase6-ios-final-full.xcresult

xcrun simctl ui 'DriveLine compact layout check' \
  content_size accessibility-extra-extra-extra-large
xcodebuild test-without-building -parallel-testing-enabled NO \
  -project can-connect-ios/CANConnect.xcodeproj \
  -scheme CANConnect \
  -destination 'platform=iOS Simulator,id=1C049B43-E5EA-437F-BBDE-52C159051934' \
  -derivedDataPath /tmp/driveline-phase6-ios-final-derived \
  -only-testing:CANConnectUITests/SmokeTests/testPhase6SignalsOverviewDetailAndTripStoryEntryAreReachable \
  CODE_SIGNING_ALLOWED=NO
```

- Shared package: 26 passed, 0 failed.
- Mac Swift package: 28 passed, 0 failed. The existing non-failing optional `pkg-config` / sqlite3 metadata warning remains; SQLite import coverage passes.
- Mac Xcode Debug build: passed at the 1080×720 minimum and the normal 1540×1000 evidence size.
- Mac API integration: passed authenticated recording and fuel-only schema-2 transfers, external receipt bytes, stable identities, exact originals, hash deduplication/conflict handling, processing receipts, isolation, retrieval, and validation.
- iPhone 17 Pro Max / iOS 27.2 complete suite: 134 executed, 131 passed, 3 expected skips, 0 failures (119 unit tests plus 15 UI tests).
- Compact iPhone / iOS 27.2 at `accessibility-extra-extra-extra-large`: the focused overview, detail, and Trip Story entry test passed (1 passed, 0 failed).
- Expected skips: the opt-in native-Mac loopback transfer check and the two Live Activity checks that require physical lock-screen or Dynamic Island surfaces.

Focused shared/Mac/iPhone coverage proves registry grouping and alias/source/unit search, unknown identifiers, duplicate lanes, causal shared cursor and route-marker synchronization, irregular/sparse/non-finite observations, explicit long gaps, visible-range statistics, freshness, asynchronous boost/barometer expiry, normalized DPF language, GPS-only/OBD-only/empty states, distance availability, elapsed alignment, same-vehicle comparison with differing lengths/availability, sample exclusion, viewport persistence, accessibility navigation identifiers, and Trip Story/Signal Detail parity. The parity test compares the exact shared value, unit, observation timestamp, coverage, and provenance rather than separately formatted approximations.

Keyboard traversal reaches the Mac recording/comparison selectors, alignment, scrub/pan mode, zoom/reset/pan/Fit Route controls, search, target lane, and grouped choices. Light/dark semantic roles remain legible, status includes text/icons as well as colour, 1080×720 uses the single-column lane layout without clipped navigation, and compact largest-Dynamic-Type iPhone controls remain reachable by scrolling.

## Screenshots

- [Mac Signals — widescreen light](screenshots/mac-signals-widescreen-light.png)
- [Mac Signals — widescreen dark](screenshots/mac-signals-widescreen-dark.png)
- [Mac Signals — 1080×720 light](screenshots/mac-signals-1080x720-light.png)
- [Mac Signals — 1080×720 dark](screenshots/mac-signals-1080x720-dark.png)
- [Mac Signals — comparison](screenshots/mac-signals-compare-light.png)
- [iPhone Signals overview — light](screenshots/iphone-signals-overview-light.png)
- [iPhone Signals overview — dark](screenshots/iphone-signals-overview-dark.png)
- [iPhone Signal detail — light](screenshots/iphone-signal-detail-light.png)
- [iPhone Signal detail — dark](screenshots/iphone-signal-detail-dark.png)
- [iPhone Trip Story contextual entry](screenshots/iphone-trip-story-entry.png)
- [Compact iPhone — largest Dynamic Type](screenshots/iphone-compact-signals-largest-type-light.png)
- [iPhone GPS-only state](screenshots/iphone-gps-only.png)
- [iPhone OBD-only state](screenshots/iphone-obd-only.png)
- [iPhone missing-signal state](screenshots/iphone-missing-signal.png)

## GitHub Actions

Both push workflows validated implementation tip `83d78f431c753ee240bc8986c50e9d3e213c9388`:

- [CAN CONNECT Mac · run 40233565607](https://github.com/kevin7898/Can-bus-Projects/actions/runs/40233565607) — run 32, completed successfully. Core tests, Xcode build, API integration, packaging, and artifact upload passed.
- [iOS companion · run 40233565630](https://github.com/kevin7898/Can-bus-Projects/actions/runs/40233565630) — run 51, completed successfully. Simulator selection, complete native build/test, screenshot export, and retained test evidence passed.

## Remaining physical-device validation

- Record a real mixed GPS/scanner drive and confirm the shared cursor, route marker, stale transitions, and raw command/reply provenance against the source timestamps.
- Exercise real asynchronous MAP/absolute-boost and barometric observations to confirm the `driveline.boost-gauge.v1` freshness boundary on vehicle hardware.
- Verify OBD-only and degraded/disconnected periods from the paired scanner preserve gaps through background/foreground transitions and transfer to Mac.
- Exercise long real recordings and a same-vehicle comparison with trackpad/mouse zoom and pan on the target Mac, including explicit Fit Route after a manual map pan.
- Recheck compact/large Dynamic Type, VoiceOver descriptions, and route gestures on a physical iPhone; lock-screen and Dynamic Island Live Activity checks remain physical-device-only.

No Phase 7 Garage/onboarding, Phase 8 recovery completion, or Phase 9 release work is included.
