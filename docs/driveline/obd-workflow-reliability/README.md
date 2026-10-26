# OBD workflow reliability

Starting remote integration commit: `a6024c0bee72dc943229a32360047be7d565302f`.
Audit baseline: `9dfc043a2b733760c7cdf2650445ef7ac2953723`.
Work branch: `codex/obd-workflow-reliability`.

The existing local integration checkout contains divergent Phase 8 history and
was preserved, as was the separate dirty iPhone checkout. This branch starts
from the fetched remote integration tip, including Phase 9.1; no history was
reset or rewritten. No physical app installation is part of this task.

## Baseline reconciliation

Phase 9.1 already passed actual timestamps through MetricTile, added a
three-tier polling scheduler, asynchronous fuel prefill, and bounded historical
Trip Story snapshots. Those implementations are retained. Remaining confirmed
code defects were future-clock manual retry; GPS-first distance regardless of
coverage; stale preferred boost blocking valid MAP; long-session diagnostic
coverage using only the last 256 samples; inherited adapter configuration;
full-history live calculation; and full-library synchronous checkpoints.

The historical RPM coverage report is not proof of scanner starvation: GPS
speed is a different source, and the validated engine quiet interval creates
intentional gaps. No new physical coverage measurement has been made.

## First milestone

- Retry bypasses backoff without advancing observation time or the loss deadline.
- Future observations cannot be labelled Live; disconnected last-known values
  retain their actual timestamp and disconnected status.
- Boost considers fresh alternatives, rejects conflicting explicit ECU IDs and
  future inputs, and uses the oldest contributing observation timestamp.
- Derived metric policy `driveline.metrics.v2` retains separate distance
  candidates and coverage. GPS wins only within five percentage points of the
  most complete candidate. Below 95% coverage the result is marked partial.
  Whole-trip economy requires complete fuel and distance intervals; partial
  measured fuel is never divided by unrelated whole-trip mileage.
- Shared acquisition policy `driveline.acquisition.v1` separates display validity
  from the unchanged ten-second integration limit. Slow 30/60-second signals
  use their existing 45/75-second validity. No synthetic observations are added.
- Discovery uses protocol-neutral AT D before configuring automatic protocol
  selection. It does not force a generic vehicle into 11-bit CAN. The underlying
  MFi session is not reset. Reference: [official ELM327 datasheet, D command](https://www.elmelectronics.com/wp-content/uploads/2017/01/ELM327DS.pdf).
- Transport failures and pending responses cannot fall through to another PID
  with uncertain reply ownership. Framed NO DATA/malformed outcomes retain
  adaptive cooldown; explicit rejections have slower re-probes.
- Live latest observations/distance update incrementally. Scanner diagnostics
  are coalesced and serialized off the main actor.
- Five-second recording checkpoints use length-framed append-only JSON batches
  under the existing local repository. Sequence, recording and vehicle identity,
  offsets and valid tail are checked on recovery. The raw observations are
  unchanged. Full state saves share the serial ordering boundary. Finalized trip
  identity prevents journal resurrection. No database/reset migration is used.

## Validation ledger

Commands run from the branch worktree; logs are temporary and contain synthetic
test evidence only. Simulator: `C975E238-AE3A-4B13-9FE8-477B69F94928`.

| Check | Result |
|---|---|
| Initial timestamp/transport milestone iPhone unit suite | 151 executed, 150 passed, 1 opt-in Mac integration skip |
| Shared after distance repair | 42 passed |
| Mac after distance repair | 34 passed |
| Shared after availability/checkpoint milestone | 43 passed, 0 failures |
| Mac after availability/checkpoint milestone | 34 passed, 0 failures |
| iPhone after availability/checkpoint milestone | 155 executed, 154 passed, 1 opt-in Mac integration skip |
| Final shared suite | 44 passed, 0 failures |
| Final Mac suite | 34 passed, 0 failures |
| Final iPhone unit suite | 165 executed, 164 passed, 1 opt-in Mac integration skip, 0 failures |
| Final iPhone UI suite | 23 executed, 21 passed, 2 physical Live Activity skips, 0 failures |
| Opt-in iPhone → native Mac queue, separately enabled | 1 passed, 0 skips/failures; all 165 unit cases have therefore passed locally across the two configurations |
| Native Mac API integration | Passed: v2 recording/fuel/receipt transfers, exact originals, identities, auth, deduplication/conflict, retrieval and isolation |
| Mac Debug build / Mac and iPhone static analysis | Passed with `SWIFT_STRICT_CONCURRENCY=complete` |
| Mac and iPhone unsigned Release archives | Both passed with complete strict-concurrency checking |

Commands: `swift test --package-path shared/DriveLineShared`,
`swift test --package-path mac-app`, and
`xcodebuild test -project can-connect-ios/CANConnect.xcodeproj -scheme CANConnect -destination 'platform=iOS Simulator,id=C975E238-AE3A-4B13-9FE8-477B69F94928' -parallel-testing-enabled NO -only-testing:CANConnectTests -derivedDataPath /tmp/DriveLineOBDReliabilityBuild CODE_SIGNING_ALLOWED=NO`.

Intermediate regressions were fixed before the milestone: Xcode source lists
needed regeneration, discovery expectations needed the protocol-neutral
baseline, slow-temperature coverage expectations needed availability semantics,
and journal recovery needed to recognize automatically started drafts not yet
present in the main state file. These are not counted as passing runs.

The added large-library fixture initially lacked matching scanner/vehicle
identity; production correctly rejected those samples. The fixture now opens a
synthetic identity-scoped transport before replay. The failed fixture runs are
not counted as passes. No production identity check was relaxed to pass it.

Final command artifacts (outside Git): `/tmp/obd-final-shared.log`,
`/tmp/obd-final-mac.log`, `/tmp/obd-final-all-ios.log`,
`/tmp/OBDWorkflowFinalTests.xcresult`, `/tmp/obd-final-api.log`,
`/tmp/obd-final-analysis.log`, `/tmp/obd-final-mac-analysis.log`,
`/tmp/obd-final-ios-archive.log`, `/tmp/obd-final-mac-archive.log`.

Additional exact commands:

```sh
xcodebuild test -project can-connect-ios/CANConnect.xcodeproj -scheme CANConnect -destination 'platform=iOS Simulator,id=C975E238-AE3A-4B13-9FE8-477B69F94928' -parallel-testing-enabled NO -derivedDataPath /tmp/DriveLineOBDReliabilityBuild -resultBundlePath /tmp/OBDWorkflowFinalTests.xcresult CODE_SIGNING_ALLOWED=NO
xcodebuild -project mac-app/CANConnect.xcodeproj -scheme CANConnect -configuration Debug -derivedDataPath /tmp/DriveLineOBDMacBuild CODE_SIGNING_ALLOWED=NO SWIFT_STRICT_CONCURRENCY=complete build
python3 mac-app/scripts/api_integration.py /tmp/DriveLineOBDMacBuild/Build/Products/Debug/CANConnect.app/Contents/MacOS/CANConnect
xcodebuild -project can-connect-ios/CANConnect.xcodeproj -scheme CANConnect -destination 'generic/platform=iOS' -derivedDataPath /tmp/DriveLineOBDReleaseBuild CODE_SIGNING_ALLOWED=NO SWIFT_STRICT_CONCURRENCY=complete analyze
xcodebuild -project mac-app/CANConnect.xcodeproj -scheme CANConnect -configuration Debug -derivedDataPath /tmp/DriveLineOBDMacBuild CODE_SIGNING_ALLOWED=NO SWIFT_STRICT_CONCURRENCY=complete analyze
xcodebuild archive -project can-connect-ios/CANConnect.xcodeproj -scheme CANConnect -destination 'generic/platform=iOS' -derivedDataPath /tmp/DriveLineOBDReleaseBuild -archivePath /tmp/DriveLineOBDRelease/iPhone-final.xcarchive CODE_SIGNING_ALLOWED=NO SWIFT_STRICT_CONCURRENCY=complete
xcodebuild archive -project mac-app/CANConnect.xcodeproj -scheme CANConnect -destination 'generic/platform=macOS' -derivedDataPath /tmp/DriveLineOBDMacReleaseBuild -archivePath /tmp/DriveLineOBDRelease/Mac-final.xcarchive CODE_SIGNING_ALLOWED=NO SWIFT_STRICT_CONCURRENCY=complete
```

No production concurrency diagnostics were emitted by these analysis/archive
runs. Existing test-fixture Sendable warnings, missing pkg-config/sqlite3
package hints and AppIntents metadata-extraction warnings are not represented
as fixed by this work.

The queue test first failed on the unsigned simulator app with Keychain error
`-34018`. Rebuilding the same code with simulator ad-hoc signing resolved it;
the test then passed against the real Mac server using a temporary library and
synthetic token. No user's pairing token, signing configuration or phone was
changed. Exact additional commands:

```sh
xcodebuild build-for-testing -project can-connect-ios/CANConnect.xcodeproj -scheme CANConnect -destination 'platform=iOS Simulator,id=C975E238-AE3A-4B13-9FE8-477B69F94928' -parallel-testing-enabled NO -derivedDataPath /tmp/DriveLineOBDReliabilityBuild CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
python3 can-connect-ios/scripts/validate_ios_mac_queue.py /tmp/DriveLineOBDMacBuild/Build/Products/Debug/CANConnect.app/Contents/MacOS/CANConnect /tmp/DriveLineOBDReliabilityBuild/Build/Products/CANConnect_iphonesimulator27.2-arm64-x86_64.xctestrun C975E238-AE3A-4B13-9FE8-477B69F94928
xcrun xcresulttool export attachments --path /tmp/OBDWorkflowFinalTests.xcresult --output-path /tmp/OBDWorkflowFinalAttachments
```

Queue log: `/tmp/obd-final-native-queue-signed.log`. The two remaining UI skips
are `testLockScreenPresentationAndOpenRecording` and
`testRecordingActivityOnDynamicIslandAndReturnToLive`, both explicitly opt-in
physical presentation checks. No scanner/vehicle acceptance is inferred.

Native rendered evidence: [stale RPM after three redraws](screenshots/stale-rpm-native-redraw.png).
The screenshot was inspected: heading warning, amber value, stale icon and
`Stale · 32s ago` footer agree. It is an isolated debug-only sample, not a
redesign or a real recording. The result bundle also retains the full existing
navigation, fuel, onboarding, accessibility and synthetic scanner UI evidence.
The same fixture was also launched with `--ui-testing --obd-freshness-fixture
--appearance-dark` and captured with `xcrun simctl io`:
[dark stale RPM](screenshots/stale-rpm-native-dark.png). Its warning, value and
`Stale · 30s ago` footer were visually checked; no physical device was used.

## Preservation

Existing schema 1/2 archives remain decodable. Coverage metadata is additive and
optional. No raw recording bytes, transfer payloads/hashes, stable IDs, controller
fingerprints, diagnostic allowlists or six-second engine quiet interval changed.
Fixtures contain synthetic values and no personal VINs, routes or credentials.

## Integrated reliability milestone

The second milestone completes the software paths without changing the locked
navigation/layout or the default enhanced-polling configuration:

- Request outcomes feed live last-known state, independently of transport
  connection. A debug-only native stale-RPM fixture proves redraws do not turn
  its footer Live. Sanitized aggregate diagnostics are shareable from the
  existing scanner connection sheet; no VIN, serial, reply, route or host is
  included in that export.
- One policy registry supplies request grouping, units, expected cadence,
  display validity and strict integration rules. Optional archive fields carry
  coverage policy/cadence and acquisition interruptions. Cursor availability,
  summary coverage and integration stop at those boundaries. Enhanced session
  reservations become factual events, not invented observations.
- Incremental integration uses timestamp-indexed adjacent trapezoids. An
  out-of-order observation repairs its neighboring intervals without sorting
  the entire history. Raw arrival order, including clock-reordered responses,
  remains preserved. Distinct ECU/source distance candidates are not merged.
- Checkpoint writes have at most one active and one pending snapshot per
  repository. Coalescing does not acknowledge superseded snapshots as durable.
  Framed append writes are synchronized; incomplete unacknowledged tails are
  recoverable. A finalized UUID marker prevents a deleted saved trip from
  reappearing from its old journal. Unrecognized unfinished journals are
  preserved, never overwritten by another recording.
- Finish prepares the immutable trip and serializes state off the main actor.
  A revision guard retries metadata changed during the write; recording saved
  is published only after durable acknowledgement. Repeated Finish is
  idempotent. Acquisition is stopped while finalizing, with failure retaining
  the recoverable draft. Startup decode and occasional explicit metadata saves
  still use the existing synchronous repository interface; this is not a new
  database or a claim that every possible library operation is constant-time.
- Debug/test standard-only, DSG-only and engine-only modes permit controlled
  hardware comparison. Normal remains the shipped default. The validated
  six-second engine quiet interval and fingerprint/allowlist checks are intact.
- Odometer observations carry optional definition/version/controller/validation
  provenance. Regressions and implausible jumps require review; stale trusted
  readings say last-known. No verified Jetta odometer decoder was found, so no
  scanned value is fabricated or enabled. Fuel-entry/manual fallback remains.
- Address lookup has cancellation, eight-second bounds, permission-aware cache
  reuse and historical-entry handling. A placemark name is not proof of a fuel
  station; automatic POI naming remains unavailable without a verified category.
  Late results never replace edited fields. Coordinates are not added to fills.

## Reproducible performance evidence

Local Debug iOS simulator, Apple Silicon host, Xcode 27.2. These are synthetic
measurements, not Time Profiler results from Kevin's physical iPhone. Fixtures
are sample-only, fictional 2013 Jetta context; no personal recording is used.

| Measurement | Audit-style baseline | Repaired path |
|---|---:|---:|
| 30-minute, 3,601-response cumulative distance replay | 2.362913 s, repeatedly sort/reduce history | 0.005181 s, incremental shared accumulator |
| Checkpoint with 500 saved trips / 1,000,000 observations | 5.080413 s, full library encode/verify/write | 0.009968 s, active append checkpoint |
| Acquisition handler during that replay | Not independently timed before repair | p95 0.084084 ms; max 0.120209 ms |
| Finish call returning to UI, 10,000 responses | Previously synchronous preparation/write | 0.008583 ms; durable completion separately awaited |
| Process peak resident high-water, large-library test | 2,096,726,016 bytes after full-library baseline | Same high-water after acquisition/checkpoint |

The memory number includes full-library encode/decode baseline and test corpus;
it is not an incremental allocation measurement, nor a phone memory guarantee.
The test verifies every raw replay response survives checkpoint recovery. The
replay advances sample timestamps by 30 minutes without sleeping for 30 minutes.
The existing Phase 9.1 million-observation snapshot/cache tests remain enabled.

No before/after physical RPM rate or coverage is asserted. The original
27%-RPM/100%-GPS-speed report combines different sources and is not a controlled
polling benchmark. Software tests verify fair deadlines, bounded retry/backoff,
recovery, cumulative diagnostic coverage beyond 256 samples, and exclusive VW
windows. The new export supplies achieved cadence, maximum gaps, response
latency, outcomes and enhanced occupancy for the actual comparison.

## F1–F9 disposition

| Finding | Software status | Remaining physical evidence |
|---|---|---|
| F1 truthful timestamps/state | Phase 9.1 timestamp fix retained; future, failed-read, disconnected and redraw regressions repaired/tested | Real fresh/stale/reconnect screenshots |
| F2 distance/economy | Fixed: coverage-ranked single-source candidates, partial labels, compatible complete economy | Mixed GPS/OBD loss drive and Mac replay |
| F3 manual retry | Fixed: explicit real-time retry, unchanged deadline and stable ID | Ignition-off/retry/on cycle |
| F4 scheduler budget | Software complete: fair single owner, enhanced reservations, achieved-rate diagnostics; existing defaults retained | Standard / +DSG / +engine timed comparison |
| F5 per-request outcomes/cooldown | Fixed/tested: bounded escalation, periodic probes, conservative uncertain-framing reconnect | Adapter latency and transient failures |
| F6 coverage | Fixed/tested: cadence-aware availability separate from strict integration; persisted interruptions | Actual slow engine/DSG response cycles |
| F7 acquisition/persistence | Fixed/tested and replay-measured: incremental computation, bounded append queue, asynchronous Finish | Physical phone Instruments, background/disk pressure |
| F8 discovery/identity | Fixed/tested: neutral discovery baseline, scoped identity and manual/unverified state | Reused MX+ after targeted polling and cancellation |
| F9 fuel suggestions | Consumer/storage/address path complete/tested; authoritative odometer intentionally unavailable without verified source | Cluster comparison before any decoder is enabled; parked location lookup |

## Published milestones and CI

- `9b90b734547203ddf45ffea64e596d58fc8e97da` — observation/discovery,
  distance/coverage policies, initial bounded checkpoints and regressions.
  [iOS CI 40327429102](https://github.com/kevin7898/Can-bus-Projects/actions/runs/40327429102)
  and [Mac CI 40327429153](https://github.com/kevin7898/Can-bus-Projects/actions/runs/40327429153)
  both succeeded.
- `6f3c52dfdf6b93323f7e3f0bdeed23e276facb69` — final software: durable
  coalescing/finalization, interruption/cadence provenance, out-of-order
  integration, native freshness regression, fuel safeguards and replay tests.
  [Mac CI 40332587241](https://github.com/kevin7898/Can-bus-Projects/actions/runs/40332587241)
  succeeded: 34 tests, build and API integration.
  [iOS CI 40332589111](https://github.com/kevin7898/Can-bus-Projects/actions/runs/40332589111)
  succeeded: 165 unit tests (164 passed, one opt-in loopback skip), 23 UI tests
  (21 passed, two physical Live Activity skips), zero failures; native build and
  screenshot artifact export passed. The loopback test passed separately locally
  with simulator signing as described above.

Independent CI replay corroboration (not physical Jetta evidence): full-library
checkpoint 15.995861 s versus append checkpoint 43.516459 ms; acquisition
handler p95 0.314333 ms, max 15.978084 ms. The same 500-trip / 1,000,000-observation
corpus and 3,601-response replay retained all observations. Peak process
high-water was unchanged at 1,687,961,600 bytes during replay. CI and local host
timings are separate measurements, not a controlled cross-device comparison.

The subsequent evidence-only commit changes this README and its sanitized
screenshot, not tested source code. Git's interactive HTTPS credentials were
unavailable; publication used the authenticated GitHub connector. Every uploaded
blob and complete tree was checked against the local Git object SHA before a
non-force, expected-head branch update. Local milestone commits were retained on
separate local branches; neither integration history nor unrelated worktrees
were rewritten. Review the [focused branch](https://github.com/kevin7898/Can-bus-Projects/tree/codex/obd-workflow-reliability).

## Storage and rollback

No stored trips are discarded, no reset is introduced, and existing schema-1/2
recording archives continue decoding. New contract metadata is optional. The
active journal is a private additive sidecar; completed trips retain the existing
archive/transfer path. Originals, hashes, recording/vehicle/fill UUIDs, receipts,
annotations, settings and credentials are not rewritten by this migration.
Derived policy versions invalidate analysis caches independently of original
bytes. Before downgrading to software unaware of the sidecar, finish the active
recording and back up the entire existing state/receipt/journal directory; an
older app cannot recover unfinalized sidecar-only samples. No deployment or
physical recording interruption was performed.

## Remaining Jetta / MX+ acceptance

1. Safely parked: record build and firmware privately; cold connect, disconnect,
   retry, then onboarding after targeted/enhanced polling. Check VIN identity
   without publishing it; preserve exact controller fingerprint checks.
2. Compare equal-duration standard-only, +DSG and +engine runs. Capture per-PID
   attempts/outcomes, latency, achieved cadence, max gaps and window occupancy.
   Confirm the six-second engine quiet period and restoration; restore normal
   configuration after testing. Do not promise 2 Hz from a delay setting.
3. At least 20 minutes mixed driving, unattended or passenger-operated: verify
   engine/DSG recovery, GPS loss versus OBD loss, ignition off/on, manual retry
   inside 120 seconds, app switch and phone lock. Check stable recording UUID.
4. Compare phone/Mac samples, exact originals/hashes, distances, measured fuel,
   coverage and gaps. Do not confuse purchased fuel or GPS speed with OBD fuel
   and engine-speed coverage.
5. Profile the real large drive with Time Profiler, SwiftUI and Core Animation;
   measure stalls, cursor p95 and peak memory. Exercise Finish, background
   checkpoints and storage pressure. Simulator timings do not close this item.
6. Parked fuel form: permitted/denied/offline lookup, edit-before-result, clear,
   refresh and historical fill. Compare any future verified odometer definition
   against the cluster at multiple readings/increments before enabling it.
7. Capture fresh/stale/unavailable states in light/dark. Keep VINs, adapter IDs,
   credentials, addresses and routes out of committed/exported acceptance data.
