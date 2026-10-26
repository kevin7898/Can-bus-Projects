# DriveLine OBD reliability implementation plan

Prepared 26 October 2026. Assignment for Codex working in the native DriveLine checkout on Kevin’s Mac.

## Assignment

Implement the OBD workflow repair described below. Start by checking the current checkout against the audit baseline, then complete every software phase that can be implemented and verified without the vehicle. Do not stop after producing another plan, and do not require approval between routine phases. Keep hardware acceptance explicitly pending when the Jetta/MX+ is unavailable; continue independent software work.

Use the existing iOS application and shared phone/Mac contracts. Preserve the established UI, working adapter support, vehicle profiles, raw recordings and transfer identity. This is a focused reliability and performance repair, not a new app or a dashboard redesign.

Audit baseline:

- Repository: `kevin7898/Can-bus-Projects`.
- Branch reviewed: `codex/driveline-drive-ledger`.
- Commit reviewed: `9dfc043a2b733760c7cdf2650445ef7ac2953723`.
- [Source snapshot](https://github.com/kevin7898/Can-bus-Projects/tree/9dfc043a2b733760c7cdf2650445ef7ac2953723).
- [Full audit](https://chatgpt.com/library?file_id=libfile_1ccb52b52c708191a403fd6ab5c5085c&account_id=personal). The findings and reproduction cases are also included below, so this assignment does not require access to that link.
- Baseline iOS CI passed, but the audit did not run Xcode or perform a new vehicle test. Existing CI success is not acceptance of these repairs.

The real target is Kevin’s **2014 Jetta TDI DSG with OBDLink MX+**. The earlier request to make the sample Jetta a 2013 was for onboarding tests; do not change the real vehicle’s year to enable a code path. Keep generic vehicle support and Wi-Fi ELM behavior intact. Android is outside this implementation scope; shared contracts should remain extensible.

## Execution rules

1. Read applicable `AGENTS.md`, project guides, tests, hardware notes and the current diff. The audit is a baseline, not proof that the latest checkout still has each defect. Identify already-fixed findings and avoid reverting newer work.
2. Work from the current intended native-app branch, not an outdated `main`. Use an isolated worktree/branch such as `codex/obd-workflow-reliability` when appropriate. Preserve unrelated uncommitted work. Do not force-reset or discard changes.
3. Keep one adapter transaction owner. Do not parallelize requests across RPM, VIN, standard PIDs and VW sessions on the same ELM/MX+ channel.
4. Preserve exact controller fingerprint checks, ECU/source validation, diagnostic allowlists, prompt boundaries, cancellation barriers and restoration of ordinary OBD settings.
5. Retain the reviewed six-second engine quiet interval until an alternative has been independently validated on this controller. Do not insert standard polls into that quiet interval or an active TP 2.0 session.
6. Never fabricate samples, forward-fill raw recordings, turn missing data into zero, or relabel estimated mileage as scanned odometer. Do not globally widen speed/fuel integration gaps to improve coverage percentages.
7. Keep raw recording bytes and original transfer hashes immutable. Recalculate derived results separately and version the policy where necessary. Preserve stable trip/vehicle IDs and idempotent transfer/recovery behavior.
8. Keep private VINs, locations, adapter identifiers and actual diagnostic traces out of Git. Commit sanitized or synthetic fixtures with their provenance labelled.
9. No coding, adaptation, actuator tests, security access, DTC clearing, forced regeneration or broad DID sweeps. Retain the existing reviewed measurement-session behavior.
10. Commit coherent changes when repository rules permit. A reviewable branch/draft PR is an appropriate result if remote access is available; do not merge, release or deploy as part of this handoff.

## Finding map and implementation order

| Phase | Work | Audit finding | Exit condition |
|---|---|---|---|
| 0 | Establish current baseline and regression fixtures | All | Current files, existing fixes and runnable checks documented |
| 1 | Repair timestamps, live-state consistency and manual retry | F1, F3 | Old data never labelled Live; retry cannot shorten a trip |
| 2 | Fix distance and economy source selection | F2 | Partial GPS cannot override a more complete OBD drive |
| 3 | Normalize discovery and vehicle identity handling | F8 | Reused sessions cannot inherit the previous vehicle’s addressing |
| 4 | Add outcome telemetry, per-request cooldown and correct coverage | F5, F6; prepares F4 | Failed PIDs consume bounded budget; slow signals report honest coverage |
| 5 | Remove growing work and synchronous persistence from acquisition/UI | F7 | Bounded live updates; durable ordered writes; measured improvement |
| 6 | Budget standard and enhanced polling using measurements | F4 | Fair serialized polling, explicit intentional gaps and achieved-rate evidence |
| 7 | Add trustworthy odometer and station prefill | F9 | Complete software path; physical odometer validation clearly separated |
| 8 | Integrated acceptance and handback | All | Tests/builds, evidence, finding status and exact hardware checklist |

Phases are reviewable milestones, not automatic stopping points. Continue through all feasible work.

## Phase 0 — Establish the baseline

Inspect these paths first, adapting to any current refactor:

- `can-connect-ios/CANConnect/Services/ScannerRecorder.swift`
- `can-connect-ios/CANConnect/Services/VehicleIdentification.swift`
- `can-connect-ios/CANConnect/Services/MXPlusTransport.swift`
- `can-connect-ios/CANConnect/Services/VWMeasuringBlocks.swift`
- `can-connect-ios/CANConnect/Services/AppStore.swift`
- `can-connect-ios/CANConnect/Services/LocalStore.swift`
- `can-connect-ios/CANConnect/Core/ScannerReadings.swift`
- `can-connect-ios/CANConnect/Core/ELMResponses.swift`
- `can-connect-ios/CANConnect/Core/VWDiagnostics.swift`
- `can-connect-ios/CANConnect/Core/Jetta2014Profile.swift` — also contains the diagnostic journal at the audited commit.
- `can-connect-ios/CANConnect/Core/DriveLinePresentation.swift`
- `can-connect-ios/CANConnect/Core/Models.swift`
- `can-connect-ios/CANConnect/Views/SemanticComponents.swift`
- `can-connect-ios/CANConnect/Views/LiveView.swift`
- `can-connect-ios/CANConnect/Views/VehicleView.swift`
- `shared/DriveLineShared/Sources/DriveLineShared/DriveLineMetrics.swift`
- `can-connect-ios/CANConnectTests`, `can-connect-ios/CANConnectUITests`, shared tests and relevant Mac tests.
- `can-connect-ios/JETTA_2014.md`, `HARDWARE_VERIFICATION.md`, `MXPLUS.md`, existing CI workflows and performance fixtures.

Record the actual starting commit and a short F1–F9 status map. Reproduce the deterministic failures in the current code before changing their implementation. Reuse the injectable transport, clock and sample-time facilities already present. Prefer deterministic virtual-time tests to long sleeps.

Run the applicable baseline build/tests using the repository’s current scheme and supported simulator. Record pre-existing failures separately. Add low-overhead measurements for command latency, enhanced-session time, checkpoint time and main-thread stalls so later performance work has a comparison point. Do not make the new diagnostic instrumentation another synchronous disk writer.

## Phase 1 — Make displayed data and retry behavior truthful

### F1: True observation timestamps

At the baseline, `MetricTile` passes `Date()` to `AvailabilityValue` unless the state is unavailable. The presentation may mark a thirty-second-old RPM value stale while its child label says Live.

Implementation:

- Pass the actual observation timestamp, current evaluation time and applicable freshness policy through presentation and tile components. Make the timestamp explicit at telemetry call sites; do not provide a render-time default.
- Establish one small observation/state contract shared by live surfaces: signal ID, value/unit, observation time, source, vehicle/session identity, current acquisition outcome and optional last-known observation. Reuse current models where possible rather than introducing a parallel telemetry framework.
- Separate transport connection, request health and value freshness. A connected adapter is not proof of a fresh value.
- On a failed read, keep the last valid observation only as explicitly last-known data; do not let one screen silently call it live while another says unavailable. On disconnect/reconnect or vehicle change, old observations must not become fresh or cross identities.
- Stop rebuilding the authoritative live state from the entire successful-sample history. Phase 5 will optimize storage, but presentation semantics should be correct now.
- Evaluate derived boost/economy using compatible fresh inputs. A stale preferred boost source must not prevent a valid alternative from being considered without an explicit policy. Preserve source/timestamp provenance; never label a derived value newer than its inputs support.

Tests:

- Thirty-second-old RPM remains stale through repeated redraws and tab changes.
- Fresh success → NO DATA → recovery; success → disconnect → reconnect; vehicle A → vehicle B.
- Slow ash/soot uses its own validity window; RPM does not inherit that window.
- A future-dated reading is not automatically Live after a clock change.
- UI test inspects the rendered freshness label and accessible state, not just the presentation enum.

### F3: Retry without changing time

Replace `reconcileScannerConnection(at: Date().addingTimeInterval(61))` with an explicit action such as `retryScannerNow()`. It should bypass the connection backoff only, then reconcile using actual time. Retain checks for a valid vehicle, storage availability, pending teardown and an already-running connection attempt. A repeated tap must not create parallel opens or reset the trip’s loss deadline.

Use monotonic elapsed time for in-process scheduling where appropriate; preserve wall-clock timestamps for recorded evidence and a deliberate restart-recovery policy. Do not serialize a process-local monotonic instant as if it were portable across launches.

Tests: retry at 60 and 90 seconds within the 120-second grace retains the recording ID on success; repeated failures never extend the grace period; real expiry finishes once; manual Finish/Disconnect remains respected; wrong VIN cannot append samples.

Phase exit: F1 and F3 regression tests pass, and native UI labels agree with the underlying observation state.

## Phase 2 — Select defensible distance and economy

At the baseline, shared metrics use `gpsDistance ?? speedDistance`, even if GPS covers only a short segment. Live OBD distance updates also stop once `route` contains any point.

Implementation:

1. Produce separate GPS and OBD distance candidates with value, covered intervals, coverage fraction, source and quality. Retain the candidates for inspection.
2. Implement one deterministic shared selection policy for live accumulation, saved trips and Mac processing. Prefer the more complete valid source; use GPS as a tie-breaker only when its coverage is comparable. Define and test the comparability/adequacy thresholds in one place. Never choose a source merely because it is non-nil.
3. For the first repair, choose a single defensible source for the trip instead of introducing complex GPS/OBD segment fusion. If neither covers the trip adequately, show an explicitly partial observed distance. Do not extrapolate it into a complete drive.
4. A lone GPS fix must not freeze OBD distance. Invalid GPS jumps and missing GPS intervals must not erase valid OBD progress.
5. Calculate economy from compatible covered distance/fuel intervals, or suppress the whole-trip figure when the inputs cannot support it. Keep the current minimum fuel-coverage safeguard, but do not treat a threshold alone as permission to divide a partial fuel numerator by unrelated whole-trip distance. Label observed fuel versus complete/estimated totals honestly.
6. Reuse existing gap limits for integration and GPS plausibility checks. Version derived policy changes so stale cached results are invalidated and phone/Mac agree. Preserve originals, IDs and prior transfer hashes.

Tests: synthetic 20 km OBD trip with GPS covering 1 km; one GPS point; no GPS; full GPS; partial OBD with full GPS; both partial; overlapping sources; outliers; stationary periods; long fuel gap; different fuel/distance coverage intervals. Assert no double-counted distance, no invented total and phone/Mac parity.

Phase exit: the 20 km/1 km counterexample selects the defensible result and cannot produce whole-trip economy from the short GPS segment.

## Phase 3 — Make discovery independent of previous adapter state

At the baseline, Jetta polling/restoration selects `ATSH7E0` / `ATCRA7E8`, while onboarding identification requests `restoreCANDefaults:false` on a reused MX+ session.

Implementation:

- Define explicit adapter states: discovery, targeted standard reads, enhanced session, restoring and disconnected/error. Track whether configuration is known or invalidated.
- Before identification, establish a documented discovery baseline suitable for the selected/detected protocol and transport. Clear stale addressing/filter state without blindly imposing an 11-bit CAN recipe on a generic non-CAN vehicle. Verify adapter-command behavior against official documentation when adding or changing commands.
- Retain session reuse and teardown ordering. Do not fix this by repeatedly racing a close/reopen of the MFi channel.
- Rediscover VIN and support information after a vehicle/session change. Any capability cache must be keyed by verified vehicle/controller/definition context and invalidated correctly.
- Treat missing VIN separately from mismatched VIN. Keep mismatches blocked. For VIN-unavailable manual profiles, provide an explicit reviewed/manual identity state; do not silently mark the vehicle verified or auto-bind it to an unrelated prior scan.
- Keep controller identity separate from editable display fields. A year/model/transmission edit must not bypass enhanced-calibration checks or misrepresent a successful scan.

Tests: identify after targeted Jetta polling; identify after canceled enhanced cleanup; switch vehicles using the same adapter; generic Wi-Fi path; unknown protocol; missing/conflicting VIN; different ECUs supplying conflicting values. Assert the appropriate discovery configuration occurs before the VIN request.

Phase exit: discovery tests start from deliberately dirty adapter state and still produce properly scoped identity/capabilities.

## Phase 4 — Observe failures, bound retries and correct coverage

### Request outcomes and diagnostics

Give each logical request a result that distinguishes valid decoded response, NO DATA, explicit rejection, response pending, wrong source/service, malformed data, transport timeout/disconnect and cancellation. Preserve raw evidence privately where useful. Follow the selected protocol’s pending-response semantics; do not blindly resend or assign a late response to the next request.

Capture bounded counters per request/controller/session: attempts, successes, outcome counts, command latency, achieved sample rate, maximum observation gap, queued delay, cooldown state and time spent in enhanced sessions. Make a concise diagnostics export available through the existing diagnostic workflow; avoid filling normal dashboard screens with developer terminology. Redact identifying data before any repository fixture or public export.

### F5: Per-request cooldown

- Consecutive failed standard requests should enter bounded exponential cooldown. Treat NO DATA as potentially transient and use slower re-probes for explicit rejection. Choose named, testable defaults based on latency fixtures; a successful validated response clears escalation.
- Keep healthy requests running. One malformed PID must not force a full vehicle reconnect if the transport remains correctly framed.
- A transport timeout may make transaction ownership uncertain. Preserve the existing conservative reset/reconnect behavior unless verified prompt drain/resynchronization makes continuing safe. Never catch and ignore an unknown framing state.
- Centralize retry ownership so transport, request and controller retries cannot multiply one another into a retry storm.

### F6: Coverage semantics

Create a small shared signal/request policy registry containing expected cadence, display validity, integration gap policy, source/unit and definition/policy version. Group fields decoded from one reply under one request. Keep UI freshness and historical calculations tied to that policy.

Report separately:

- Actual observations and achieved cadence.
- Availability/freshness coverage appropriate to the signal’s intended schedule.
- Integration coverage for speed/fuel calculations, with strict gap handling.

For historical coverage, clip intervals to the recording bounds, avoid overlapping/double-counted intervals, and stop at known disconnect/invalidity boundaries. Unknown imported signals should get conservative defaults and explicit unknown cadence. Never add synthetic raw samples to represent a validity window.

Persist enough policy/version and discontinuity information for Mac and replay to reproduce the same result. Add optional metadata or a tested versioned migration if required; do not break import of existing archives.

Tests: healthy 30/60/68-second observations no longer report zero availability solely because intervals exceed ten seconds; missed cycles and disconnects reduce coverage; a long speed/fuel gap is still excluded from integration. Repeated NO DATA has bounded attempts while healthy RPM continues. Test late prompts, cancellation and recovery to a healthy request.

Phase exit: diagnostic metrics expose why a value is missing, and one failed request cannot consume an unbounded share of the normal budget.

## Phase 5 — Keep acquisition and UI work bounded

At the baseline, every exchange rewrites the diagnostic journal on the main actor, checkpoints encode/decode/write the entire state every five seconds, and live computations repeatedly traverse growing sample arrays.

Implementation:

1. Keep UI state publication and platform callbacks on their required actors. Move expensive serialization, journal writes and historical calculations to appropriate serial workers/actors. Do not move ExternalAccessory callbacks arbitrarily off their required execution context.
2. Maintain incremental latest-observation snapshots and distance/fuel accumulators. They must match the canonical shared policy, including gap boundaries and out-of-order input handling. Bound publication frequency without reducing raw acquisition/recording fidelity.
3. Separate active telemetry persistence from full-library metadata rewrites. Prefer a small append-oriented recording journal or chunk store behind the existing repository boundary; reuse suitable infrastructure already present. Define record framing, sequence/identity, recoverable tail handling and atomic finalization.
4. Preserve bounded recovery loss at least as good as the existing five-second checkpoint target. Flush on Finish and relevant lifecycle events; report durable save only after successful acknowledgement. Handle disk-full errors and write backlog explicitly.
5. Coalesce snapshots with generation/revision guards. Older asynchronous writes must never overwrite newer state, finalize the wrong vehicle/trip, or race transfer queue edits. Keep one owner of persistence ordering.
6. Make finalization/recovery idempotent: a crash during flush, archive creation or metadata insertion must recover to one recording with the same ID. The transfer path must not upload an unfinished archive.
7. Batch the bounded diagnostic journal independently of user telemetry. Preserve useful recovery/error events and make failures visible without a log-write loop.
8. Cache historical analysis by recording identity plus content/policy revision. Keep immutable source bytes and transfer hashes separate from recalculated summaries.

Tests: termination after acknowledged checkpoint; truncated final journal record; repeated recovery; Finish racing checkpoint; storage failure; out-of-order asynchronous completion; vehicle switch; transfer queue mutation; sample count/ordering/hash parity before and after the storage refactor. Test old-state migration without destructive reset.

Benchmark the existing representative corpus and a 30–60 minute synthetic replay. Compare main-thread stalls, checkpoint latency, acquisition latency and peak memory. Require bounded growth in per-sample/UI work and no lost acknowledged samples. Do not claim an on-device improvement without measurements from that device.

Phase exit: correctness tests pass and measured results show that growing history/disk work no longer blocks the acquisition/UI path in the same way.

## Phase 6 — Budget polling without breaking the VW protocol

Use Phase 4 diagnostics and Phase 5 measurements to adjust scheduling. Do not simply increase the number of timers or threads.

- Use one deadline/priority scheduler over grouped requests. Prioritize speed, RPM, fuel rate and boost when supported; prevent slow-request starvation with explicit deadlines/fairness.
- Treat requested cadence as a target. Initially preserve the existing standard intervals and validate achieved rates with measured adapter latency. Back off under load and recover gradually rather than promising 2 Hz from a 0.5-second delay.
- Model enhanced engine/DSG work as exclusive session reservations including quiet time, setup, read, teardown and restoration. Never interrupt a protocol exchange to service a fast PID.
- Record intentional quiet/session gaps as diagnostic context; do not create placeholder samples or misleading “continuous coverage.”
- Keep existing engine/DSG behavior available while measuring standard-only, +DSG and +engine modes through a debug/test configuration. Do not silently disable enhanced signals in the shipped default to improve a benchmark.
- Use bounded overload policy and explicit degradation. If hardware cannot meet all priorities, document the tradeoff and choose a conservative justified cadence; any significant default schedule change requires the hardware evidence listed below. Routine software work can finish with that change disabled or retaining the existing default until validated.
- Expose achieved rate/data age through diagnostics and concise status where relevant, not a proliferation of normal UI controls.

Tests: representative command latency, slow/no-data PID, delayed enhanced completion, controller cooldown, late response, cancellation during quiet/setup/read/restore and clock changes. Assert one transaction owner, fair healthy requests, verified restoration and no duplicate recording samples.

The reported RPM 27% versus speed 100% remains a hypothesis to investigate. Compare per-PID raw replies, source selection, accepted sample counts, timestamps and coverage policy before attributing it to shared quiet time.

Phase exit: repeatable performance evidence and correct scheduler behavior; actual Jetta cadence remains hardware-pending if no car is connected.

## Phase 7 — Implement trustworthy fuel-entry suggestions

### Odometer

The audited registry does not contain a functioning scanned-odometer source. A previously listed diagnostic candidate is not evidence that this Jetta supports it.

- Inspect the latest code and privately available captures for a validated source. Verify any newly adopted definition against primary/upstream evidence and the specific controller; record origin, version, units, layout and invalid-value handling.
- Implement a per-vehicle odometer observation with value, timestamp, controller/definition provenance and validation state. Exclude unverified controller counters from authoritative automatic prefill.
- Build and test the consumer/UI path even if no hardware-supported source is available yet. Keep candidate decoders replay-tested and disabled for authoritative use until physically validated; do not fake success to close this phase.
- Prefill a new fuel entry from the latest trusted observation for that vehicle, displaying its age. A stale trusted scan may be suggested as last-known mileage with review, not presented as a fresh scan. Allow manual correction and never overwrite user edits when a new scan arrives.
- Do not substitute profile starting mileage or GPS/OBD integrated distance under the “scanned odometer” label. Preserve any explicit manual/estimated source identity.
- Detect regressions, implausible jumps and controller resets before accepting a new authoritative value. Preserve original evidence for review.

### Station address

- Use a recent, sufficiently accurate permitted location fix to suggest an address when adding a fuel entry; prefer the contemporaneous stop/fill location over an old route endpoint.
- Reverse-geocode using a current supported platform API after checking the project’s deployment target and official documentation. Resolve a station name only when supported by location/search evidence; an address alone is not proof of a particular business.
- Keep station name and address distinct in the data model as needed. Persist user-confirmed values locally and through existing transfer contracts.
- Run lookup asynchronously with cancellation, throttling/caching and a timeout. Do not block saving or overwrite edited fields. Permission denial, offline use, ambiguous stations and historical entries must retain a manual path.

Tests: fresh/stale/absent/wrong-vehicle odometer; unverified source; user edits during scan/geocode completion; denied location; outdated fix; offline lookup; multiple nearby stations; historical entry; import/export parity.

Phase exit: complete suggestion UI and persistence path, with the precise supported/unsupported odometer source stated. Physical validation is the only permitted reason to leave authoritative scanning disabled.

## Phase 8 — Integrated acceptance

Run the repository’s applicable iOS unit/UI suites, shared-package tests and affected Mac tests. Build the native phone and Mac targets affected by contract changes. Discover actual schemes/destinations rather than copying an obsolete simulator command. Document exact commands, commit and outcomes.

Minimum regression matrix:

| Scenario | Required result |
|---|---|
| Redraw a stale tile | Original timestamp retained; no false Live label |
| Retry inside grace | Same trip ID; no premature expiry; one connection attempt |
| True grace expiry | One finalization; provisional post-loss route handled deliberately |
| Partial GPS, complete OBD | Defensible distance; no inflated economy from partial GPS |
| Healthy slow signal | Cadence-aware availability; no fabricated samples |
| One failing PID | Bounded retry cost; healthy requests continue |
| Enhanced session failure/cancel | Ordinary OBD restored or connection explicitly failed |
| Reused adapter during onboarding | Known discovery state; correct vehicle/controller attribution |
| Long recording with UI navigation | Bounded live work; preserved samples and durable recovery |
| Crash/storage error | No false saved state, duplicate trip or overwritten newer snapshot |
| Phone/Mac import and reprocessing | Same policy results; stable IDs and original hashes |
| Fuel form with unavailable scan/location | Honest manual fallback; no blocked save or overwritten edit |

### Physical Jetta and MX+ checklist

Perform available checks with Kevin’s actual hardware; otherwise leave these explicitly pending with exact instructions. Use parked checks first and a passenger-operated or unattended recording for moving checks.

1. Record app commit/build, adapter/firmware privately, protocol, calibration identity and location permission state. Preserve private raw evidence locally.
2. Cold connect, repeated disconnect/reconnect and onboarding after targeted polling. Confirm identity and supported readings.
3. Capture comparable timed runs with standard-only, standard+DSG and standard+DSG+engine configurations. Record per-PID achieved rates, max gaps, failures and session occupancy. Restore the intended normal configuration afterward.
4. Confirm engine ash/soot and DSG recovery over several cycles. Do not equate a successful parked response with calibrated sensor accuracy.
5. Exercise app switching and phone lock, then verify recording ID and timestamp continuity. Test ignition off/on and manual Retry inside the grace interval.
6. Exercise GPS loss while OBD continues and OBD loss while GPS continues; verify distance, coverage and trip boundaries.
7. Compare odometer against the cluster at more than one point, including increments, before enabling authoritative odometer prefill. If the source does not work, report that explicitly.
8. Review a longer drive on phone and Mac. Compare raw sample counts, IDs, originals/hashes, distance/fuel policy results, gaps, duplicate handling and UI responsiveness.

## Required final handback

Provide a concise result with:

- Branch, commit(s), reviewable diff/PR and changed components.
- F1–F9 table: fixed, already fixed, awaiting hardware validation, or blocked with a concrete reason.
- Regression tests/builds run and exact outcomes; distinguish local, CI, replay and physical evidence.
- Before/after polling and performance measurements, with configuration and dataset/device identified.
- Storage/contract migration behavior, original-data preservation and rollback considerations.
- Actual odometer source status and fuel/location fallback behavior.
- Remaining hardware checklist and any default scheduler changes held pending its results.

Do not mark hardware validation complete based on synthetic fixtures. Do not leave feasible software work unfinished merely because the car is absent.
