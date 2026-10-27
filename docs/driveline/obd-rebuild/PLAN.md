# DriveLine OBD Rebuild — Detailed Codex Implementation Plan

Date: 26 October 2026

## 1. Decision and scope

Rebuild the OBD acquisition, session coordination, recording and analysis internals within the existing DriveLine iOS app. Preserve the current UI as the design contract. Reuse reviewed protocol code where it passes independent tests. Build the replacement alongside the existing engine and migrate through an internal development switch, with exactly one engine owning an adapter at any time.

This is an implementation handoff, not a claim that a rebuild has been performed or that current repository code has been independently re-audited. It synthesizes the supplied `DriveLine iOS OBD Audit(1).md`, `DriveLine OBD Rebuild Plan.md`, and `DriveLine OBD Rebuild Plan 2.md`, plus the decisions in this conversation. The latest plan supplies reported capture statistics; their underlying recordings were not attached here and must be verified during implementation.

### Desired outcome

- Reliable automatic and manual recording using the existing screens.
- Correct per-ECU decoding, vehicle identity checks and capability discovery.
- Adaptive grouped polling with measured rates and bounded enhanced-read interruptions.
- Recoverable recordings with predictable memory and disk costs.
- Fuel, distance and economy computed over explicitly defined coverage intervals.
- Existing Mac transfer compatibility during the first rollout.
- The same visual layout, navigation, cards, typography, colors and interactions the user already loves.

### Explicit exclusions

Do not redesign the UI, implement the future CAN hardware recorder, port Android, implement new odometer decoding, rebuild station lookup, add coding/clearing/adaptation functions, or undertake a general Mac importer rewrite. Preserve existing odometer and fuel-prefill behavior and supply it through the compatibility layer where applicable. New acquisition must not silently remove existing non-OBD features.

The user previously accepted losing old drive data if necessary. That is not a reason to delete it during this rebuild: retain the legacy reader or archive data separately where inexpensive. Avoid an elaborate conversion project; any destructive reset must be an explicit user action. Keep fuel records and vehicle settings intact.

## 2. Start here: establish the actual repository state

The audit identifies `kevin7898/Can-bus-Projects`, branch `codex/obd-workflow-reliability`, commit `7a7eedd`, and says `main` had no iOS code at audit time. These are historical pointers, not guaranteed current state.

1. Read repository `AGENTS.md` and relevant local instructions.
2. Inspect working-tree changes, branches, HEAD, package manifests, Xcode schemes, iOS deployment target and CI configuration. Preserve unrelated work.
3. Locate the latest complete iOS implementation using branch history and actual files. Do not base the rebuild on an empty or older main branch.
4. Create an isolated working branch/worktree from the verified baseline. Suggested branch: `codex/driveline-obd-rebuild`.
5. Record baseline SHA, build commands, available simulators/devices, existing test results and known failures in `docs/driveline/obd-rebuild/BASELINE.md`.
6. Inventory the current transport, parser, scheduler, recorder, metrics, app-state and transfer boundaries before changing them.
7. Capture deterministic UI screenshots and navigation behavior with fixed demo data on the supported iPhone configuration, including iPhone 17 Pro Max where available. Check light/dark appearance and relevant Dynamic Type sizes.

Potential starting files from the audit: `MXPlusTransport`, `VehicleIdentification`, `ScannerRecorder`, `OBDPollScheduler`, `ScannerReadings`, `ELMResponses`, `VWMeasuringBlocks`, `VWDiagnostics`, `Jetta2014Profile`, `AppStore`, `DriveLineMetrics`, and `DriveLineAcquisitionPolicy`. Resolve actual paths; do not assume these names still describe the implementation.

**Baseline gate:** repository and app are identified, build/test limitations are recorded, UI reference captures exist or are explicitly pending, and no unrelated changes were lost.

## 3. Non-negotiable contracts

| Contract | Implementation requirement |
| --- | --- |
| UI preservation | Existing views consume a compatibility presentation model. Changes to data binding are allowed; unsolicited layout/navigation changes are not. |
| One adapter owner | One coordinator and one serialized command executor per physical adapter, including setup commands, keep-alives and enhanced sessions. |
| Read-only diagnostics | Typed request builders allow only reviewed services, PIDs, groups and controller targets. Preserve exact reviewed KWP groups, not a blanket `21 xx` permission. |
| No invented measurements | Missing is not zero; last-known display values retain their timestamps and stale status; estimates have explicit provenance. |
| Vehicle identity | A mismatched VIN blocks attaching data to the selected vehicle. Never silently switch vehicles or mix their recordings. |
| No VIN in telemetry logs | Redact before persistence, diagnostics, crash breadcrumbs and export, including malformed and partial identity replies. |
| Reproducible results | Version parser/profile/analysis policies and retain enough sanitized source data and events to reproduce supported metrics. |
| Honest completion | Simulator and replay success never imply real-car, accessory or background-lifecycle success. |

Preserve the existing vehicle-onboarding contract. Before changing VIN storage, inspect whether onboarding currently displays or persists VIN. Distinguish explicitly retained user vehicle metadata from forbidden raw VIN telemetry logging. Any migration to hashed-only identity must preserve required onboarding behavior or document the conflict before changing it. New logs must never persist VIN bytes.

## 4. Evidence and performance baseline

The revised source plan reports:

| Capture | Reported result | Required verification |
| --- | --- | --- |
| Pocket Recorder grouped drive, ~99 minutes | RPM/speed/fuel ~1 Hz each, maximum gap ~1.2 s, 100% OK, ~50 ms per grouped exchange | Recompute from valid decoded readings and monotonic receipt times; identify all excluded intervals. |
| Pocket Recorder single-PID drive | ~52 ms/exchange; RPM 1.7 Hz, speed 2.9 Hz | Verify per-PID denominator and sample counts. |
| iOS scanner with count hint | ~24 ms/exchange; RPM 3.6 Hz | Verify command/reply pairing and adapter configuration. |
| iOS scanner without hint | ~51 ms/exchange; RPM 2.5 Hz | Verify comparable conditions. |
| Jetta PID `5E` | Valid fuel replies reported on every request | Confirm payload length, scaling, ECU provenance and support bitmap behavior. |

Do not treat a successful prompt or `OK` exchange as a valid sample. Separate transport success, parse success and per-PID completeness. Do not describe adapter transaction time as physical CAN bus utilization: measure **adapter occupancy** as time spent executing commands divided by elapsed time. True CAN bus load requires separate instrumentation.

Reference groups from the revised plan are candidates for the Jetta profile:

- Drive: `0D 0C 5E 70`.
- Exhaust: `78 7A`.
- Load: `04 10`.
- Slow group: `05 46 33 42`, initially every 5 seconds.
- DPF: `8B`, initially every 5 seconds.

Verify support and response lengths for every PID. Do not label the entire slow group as temperature data. Do not impose these groups on generic vehicles or require optional PID `70` to succeed for core speed/RPM/fuel polling to work.

## 5. Architecture and dependency boundaries

Use one shared Swift package with cohesive targets if it fits the repository. Seven architectural responsibilities do not require seven separately maintained packages. Pure decoding and analysis must build without UIKit, SwiftUI, ExternalAccessory or Network dependencies.

| Component | Owns | May depend on |
| --- | --- | --- |
| Core types | IDs, timestamps, units, outcomes, capability and freshness types | Foundation and minimal shared utilities |
| Protocol | ELM parsing, per-ECU reassembly, PID tables, typed request validation | Core types |
| Transport | Ordered byte exchange, framing through prompt, timeout/close | Core types; platform framework in platform targets |
| Session/coordinator | Discovery, identity, adapter configuration, exclusive enhanced windows | Protocol, Transport, Core types |
| Scheduler | Due work, grouping, hints, backoff, budget decisions | Core types and capability records; injected clock |
| Recording | Append log, durability, recovery, session events | Core types and storage utilities |
| Analysis | Streaming accumulators and replay analysis | Core types, Protocol for raw replay |
| Presentation bridge | Existing app-facing models and throttled updates | Coordinator and analysis outputs |

Dependencies form an acyclic graph; do not enforce an artificial rule that each component can call only the immediately preceding layer. Recording is an observer of acquisition, not a layer through which every parser call must travel.

Suggested package name: `DriveLineTelemetryCore`. Adapt names to the existing repository and avoid duplicate metrics implementations. The iOS application composition root constructs platform transports and injects them into the coordinator. A future Mac raw-log importer uses the same analysis package.

### Core data contracts

Define concrete, Codable, Sendable value types where appropriate:

- `Exchange`: ID, session ID, sequence, typed request metadata, redacted reply, start/end monotonic time, wall time, outcome and transport generation.
- `Reading`: key, numeric value, unit, source ECU, observation time, exchange ID, parser version and validity/provenance.
- `VehicleCapabilities`: protocol/addressing type, candidate/selected ECU, supported PIDs, grouping support, adapter features, profile/fingerprint match; no raw VIN.
- `AcquisitionEvent`: connected, identity verified, disconnect, interrupted, enhanced window start/end, configuration restored, recording resumed, storage failure.
- `LiveSnapshot`: bounded latest-reading map, freshness, trip state, running metrics and compact rate summary.
- `MetricResult`: value or nil, units, source, policy version, covered duration, relevant denominator and missing/partial reason.

Use monotonic time within a process/session for durations. Give each new process a clock epoch identifier; monotonic values from before and after a restart cannot be subtracted blindly. Persist wall-clock mapping for display and cross-epoch ordering. Clock changes must not create negative duration or duplicate integration.

## 6. Transport and lifecycle design

The transport moves bytes and ends an exchange at a complete prompt. Content validation belongs to the session/request layer. Support fragmented bytes, multiple lines, echo, short writes and unexpected stream closure. Bound reply size and total command deadline.

An actor alone does not guarantee one command in flight because actor methods can re-enter across `await`. Use an explicit executor/queue and ownership token. All command paths must use it. Give each stream generation a unique identifier; callbacks from old generations cannot complete a new request.

- Cancellation: either drain to the prompt under a bounded deadline, or close and invalidate the stream. Never wait indefinitely.
- Timeout: fail the active request once, invalidate outstanding configuration/hints and close the broken stream. Prevent late bytes from satisfying the next command.
- Healthy session: retain it across ordinary UI changes; do not churn ExternalAccessory sessions for every polling operation.
- Actual disconnect/error: close the unusable session and create a fresh one during controlled recovery. “Long-lived session” does not mean reusing a closed stream.
- Wi-Fi and MX+: share the same exchange contract, with separate platform implementations and capability detection.
- Injection: provide a fake clock, scripted transport and timed replay transport for deterministic tests.

Suggested coordinator states: idle, connecting, discovering, validatingIdentity, ready, recording, recovering, stopping, failed. Specify allowed transitions and cancellation behavior in tests. No independent UI button should bypass this coordinator.

## 7. Protocol, discovery and identity

### Parser and request builder

Port and independently test the reviewed per-header ISO-TP reassembler and scaling code. Preserve ECU identity through every stage. Reject bad sequence numbers, invalid lengths, unsupported ambiguity and truncated payloads. Decode grouped responses by known PID layouts; do not scan unknown bytes for something that looks like the next PID.

Unknown or unsupported grouped layouts cause explicit classification and a smaller group/single-PID fallback. Duplicate identical readings may be deduplicated; conflicting readings require an explicit source rule, not first-response selection.

Maintain explicit request and configuration allowlists. Enhanced reads must retain the audited profile/fingerprint gates, reviewed groups 19/108/114 where applicable, and reviewed session transition commands. Adapter configuration commands also go through typed builders; raw arbitrary commands are not a production escape hatch.

### Discovery sequence

1. Open transport and establish prompt synchronization.
2. Apply the verified minimal adapter initialization, declaring expected response type for each command.
3. Enable headers when supported and discover protocol/addressing before assuming 11-bit CAN IDs.
4. Issue standard capability discovery and retain every responding ECU separately.
5. Rank candidate engine ECUs using profile evidence, required signal support and coherent responses. “Most PIDs” is only a heuristic. Never globally hardcode `7E8`/`7E0`.
6. Select and verify the appropriate request/response addressing and filter configuration for the detected protocol. For unsupported addressing modes, fail clearly rather than issuing incorrect CAN setup commands.
7. Reassemble VIN candidates per ECU, validate the full candidate and preserve the guard against conflicting valid identities. Do not require every ECU to provide VIN if a validated identity is available from another appropriate responder.
8. Compare normalized live identity in memory to the selected vehicle identity. Preserve the current mismatch/no-VIN policy; define onboarding and explicit retry paths without automatic reassignment.
9. Walk supported-PID pages using continuation bits and bounded retry rules. Check claimed support against real response behavior.
10. Read calibration identifiers only as needed and gate enhanced operations on the reviewed exact matches.
11. Restore/verify standard configuration before allowing the scheduler to run.

Separate AT informational response validation from AT configuration validation. Complete at prompt first; then validate expected `OK`, textual information or typed data. A valid `ATRV`-style response must not wait for an `OK` that will never arrive.

## 8. Adaptive polling and enhanced reads

### Standard polling

Begin with capabilities and conservative single/grouped probes. For the Jetta, test the reference groups, initially at 1 Hz for fast groups and 5 seconds for slow work. Keep core speed/RPM/fuel independently schedulable if an optional group member fails.

Use due times and priorities with an injected clock. Prioritize core signals and avoid catch-up bursts after a stall. Track rolling achieved rates, p50/p95 latency, p95/max gaps, valid sample counts and failure categories per signal. Report windows explicitly, e.g. 10-second and 60-second windows.

Raise the drive group to 2 Hz and then 3 Hz only when measured latency and queue delay support it, core completeness remains acceptable, and adapter occupancy stays below an initial 60% soft target. Use hysteresis and cooldown to avoid oscillation. Occupancy is a tuning signal; core deadline misses override it.

### Learned response-count hints

Treat hints as adapter/protocol/ECU/group/configuration-specific optimizations. Confirm the exact supported syntax against the adapter implementation during coding; the source plan's `010D0C5E703` is an example, not a universal encoding rule.

After at least three complete, consistent unhinted replies, a supported adapter may use the learned response count. Never derive it from already truncated replies. Drop the hint on missing PIDs, changed frame count, malformed response, timeout, reconnect, ECU change or relevant configuration change. Run periodic unhinted validation. Bound retries and split persistently incomplete groups into individual supported requests. Keep every exchange serialized through completion.

### Enhanced VW windows

Start with bounded open/read/close/restore transactions, DSG no more often than every 30 seconds and engine enhanced work no more often than every 60 seconds. Preserve the reviewed six-second engine quiet interval until its meaning and necessity are established from code and captures.

Reserve an initial 10% long-window adapter-time budget for enhanced work, including setup, keep-alives and restoration. Also enforce an interruption budget: a low average percentage does not make a multi-second core polling stall acceptable.

Enhanced reads cannot interleave standard polling while incompatible adapter routing/session configuration is active. The coordinator holds an exclusive configuration lease, records the window, executes it, validates every restore reply, and releases standard polling only after success. Failed restoration triggers recovery, not continued reads under uncertain configuration.

Persistent enhanced channels/keep-alives are a later optimization requiring replay and hardware evidence that core polling remains correct. They are not required for the initial rebuild. Defer optional enhanced work when core deadlines cannot be protected, and expose the reason in diagnostics.

## 9. Recording, privacy and recovery

Use a bounded, append-only writer off the main actor. The full trip sample array must not sit in a published UI property. Keep live accumulation incremental, with memory bounded by active signals and documented queues; replay the durable log for detailed analysis.

### Log format v1

Specify byte order, schema and limits before implementation. Recommended frame: 4-byte unsigned body length, 1-byte record type, versioned encoded body, and a per-frame CRC32 covering type+body. Define maximum frame size and reject larger lengths before allocation. A file header includes magic/version, recording ID, non-sensitive vehicle ID, source/app/policy versions and clock epoch metadata.

Records include redacted exchanges, acquisition events, optional GPS observations when already part of trip recording, and clock mappings. GPS-derived distance is reproducible only if its source observations and filtering policy are retained. Exclude GPS from public replay fixtures; preserve existing user-facing trip recording behavior.

On finish: flush and sync the log, compute SHA-256, atomically write a finalize marker containing ID, byte length, record count and hash, then update the trip index. Make finalization and indexing idempotent across crashes. Cached index data is rebuildable.

Recovery validates frames sequentially, retaining the valid prefix and recording the damaged/truncated tail. Preserve evidence before any repair. An incomplete file is recoverable, not automatically a completed trip. A finalized log is immutable; re-analysis writes separate versioned cache data.

### Durability definition

Distinguish received, queued, appended and durably acknowledged records. A disk queue acknowledgment is not durable persistence. Start with a bounded sync interval, such as one second, plus sync at important lifecycle events. Document the resulting maximum unsynced-loss window. Tests require every **durably acknowledged** frame to survive; do not promise that every adapter reply survives abrupt power loss.

If the writer falls behind, apply bounded backpressure or reduce optional polling. Disk-full/permission errors produce an explicit recording error and recovery path; never display successful recording while silently dropping data.

### Sanitization

Redact identity-bearing requests before any disk-backed raw reply handling. Include partial, malformed, echoed, fragmented and headerless identity responses. Apply an explicit policy to calibration identifiers and adapter serials; safe diagnostics retain status and profile-match results rather than sensitive raw identifiers. Test logs, crash context, exports and debug output, not only the export sanitizer.

Corpus sanitization must examine nested fields, SQLite tables and metadata; simply deleting `gps` and `trip_place` lines is insufficient proof of privacy. Store sanitized fixtures, manifest and hashes. VIN parser tests use documented synthetic identities, never the user's VIN.

## 10. Trip lifecycle and analysis policy

### Trip lifecycle

Preserve current user expectations for automatic/manual start, stop and short-stop merging. Use a stable recording ID and explicit event ordering. Initial policy may retain the existing RPM >= 400 start condition, but confirm its behavior for generic vehicles; do not generalize it to hybrids/EVs without an explicit policy.

Buffer a small bounded pre-roll of sanitized observations before automatic start. At start, assign a recording ID and write the chosen pre-roll consistently. A temporary disconnect must not finalize immediately. Use a configurable initial 120-second reconnect grace period, requiring identity revalidation before appending vehicle data. Keep one trip ID during a valid same-vehicle resume while recording the gap. Manual stop finalizes once and must not immediately auto-restart without the documented state reset.

Ignition-off evidence, silence and disconnected transport are different events. Do not invent zero RPM when communication stops. Test stop/start races, two concurrent stop requests and app relaunch with an unfinished log.

### Shared metric algorithm

Implement analysis with recording, before first road acceptance. Use the same incremental policy for live summaries and finalized replay results; rounding belongs at display/export boundaries.

1. Validate and order samples per signal, ECU and clock epoch; deduplicate exchange/sample identity.
2. Build valid speed and fuel-rate segments between adjacent valid observations. Convert units explicitly: km/h times seconds divided by 3600 gives km; L/h times seconds divided by 3600 gives litres.
3. Begin with a configurable maximum interpolation gap of 10 seconds, inherited from the plan. Validate this policy; it is not proof that a 10-second outage is accurate.
4. Never bridge a vehicle change, transport-loss boundary, invalid clock epoch, or explicitly invalid acquisition state. A short, successfully restored planned window may be treated like a normal sampling gap when the policy allows it. Record the interpolation and its coverage implications.
5. Compute overlap of valid fuel and selected-distance intervals. Clip and integrate each piece over the exact same overlap using deterministic linear interpolation/trapezoidal integration.
6. Economy in L/100 km = 100 * overlap fuel litres / overlap distance km. Return nil with an explicit reason when overlap distance is zero or below a documented numerical threshold.
7. Preserve idle fuel: speed zero with valid fuel is covered time and contributes fuel. Do not discard idle intervals merely because their distance is zero.
8. Report observed trip duration, individually covered durations, matched duration and missing reasons separately. Partial-interval economy is labeled partial; do not present it as whole-trip economy without an explicit coverage policy.
9. Retain an initial 80% coverage threshold for qualifying trip totals if that matches existing policy, but keep measured covered totals available and clearly partial. Define denominator and qualifying policy in tests.
10. Choose distance source explicitly. Do not add OBD and GPS distances or silently substitute one halfway through a matched interval. If source switching is supported, record disjoint source intervals and provenance.

Test the audit's offset-start defect directly: trip start 0.3 seconds before first fuel reading and trip end after the final reading must still yield correct matched-interval economy, with honest incomplete coverage. Weekly economy is weighted by summed compatible fuel and distance, not an arithmetic mean of individual trip economy values. Do not mix fill-up economy with OBD interval economy under one unlabeled number.

## 11. Preserve the UI through a presentation bridge

Define a facade matching existing view-model needs. It exposes connection state, vehicle identity outcome, latest readings, freshness, trip lifecycle and analysis summaries. Views must not know which acquisition engine is selected.

- Publish ordinary telemetry snapshots at most four times per second initially.
- Deliver critical connection/storage/identity error transitions promptly without waiting for a routine telemetry tick.
- Keep raw capture cadence independent of render cadence.
- Assign freshness thresholds per signal relative to expected cadence, not one global timeout.
- Preserve stable card and list identities, map camera state, current tab/page, scroll position and navigation during updates.
- Keep existing last-known odometer provenance/time for fuel prefill; do not substitute integrated trip distance for a scanned odometer.
- Put detailed new rate diagnostics behind an existing diagnostics/debug route where possible. Do not redesign the dashboard to expose implementation internals.

Use fixed replay scenarios to compare baseline and rebuilt screens. Only explicitly necessary missing/stale/error-state text may change; document any visual difference.

## 12. Mac compatibility and migration

Initial release keeps the current transfer endpoint and existing trip envelope readable. Build an export adapter from new canonical analysis into the old schema. Do not mislabel raw exchanges as legacy samples or lose coverage metadata silently; document any legacy representation limit.

Add raw-log transfer later as an optional, versioned capability. Receiver negotiation must establish support before sending the new payload. The Mac verifies hash/length, imports idempotently and runs the shared analysis package when that capability is implemented. A successful file hash proves transfer integrity; separate golden tests prove analysis equivalence.

Do not claim phone/Mac metric parity merely because the endpoint is unchanged. Mark shared raw-log analysis as a separate rollout milestone if the Mac cannot yet consume it. This resolves the source plan's contradiction between unchanged transfer format and new raw-log ingestion.

The engine selector is an internal development setting. Switching requires stopping/releasing the current engine, closing or transferring ownership through the coordinator, and confirming no recording is active. Automatic fallback must not mix two engines' samples in one recording. Keep a documented rollback procedure and legacy reader until acceptance.

## 13. Implementation phases and deliverables

### Phase 0 — Baseline, evidence and UI contract

Perform Section 2. Add the source documents, a decision record and a checklist mapping all nine audit findings. Locate available raw recordings and recompute their statistics. Assemble sanitized fixtures with manifest fields: fixture ID, source, capture scenario, adapter/firmware when known, addressing/protocol, redactions, expected behavior, capture vs synthetic status, hash and evidence limitations.

Missing hardware captures do not block pure software development. Track them as pending; never fabricate them or mark hardware gates passed.

**Deliverables:** baseline report, fixture manifest, UI references, implementation status, resolved module map.

**Gate:** baseline reproducible within available environment; evidence classified; no unsupported claim of a verified 99-minute result.

### Phase 1 — Core contracts, parser and replay harness

Create shared types, typed command validation, injected clocks, scripted transport and parser tests. Port reviewed decoding/reassembly. Add grouped parsing and per-ECU VIN handling. Keep all platform APIs out of pure targets.

**Tests:** single/grouped payloads, known independent scaling vectors, multiple ECUs, conflicting values, reordered/broken/truncated frames, echoes/noise, variable lengths, unsupported PID in a group, redaction and forbidden-request rejection.

**Gate:** independent expected values pass; available captured values match or differences are investigated; all rejected input has a reason and bounded resource use.

### Phase 2 — Durable recording, analysis and early UI bridge

Implement framed logging, recovery, streaming accumulators, interval intersection and the presentation facade using replay. Wire a development replay mode into existing screens without redesign. Implement finalization/index ordering and legacy export mapping early enough to expose compatibility problems.

**Tests:** offset-start economy, idle fuel, zero-distance economy, disjoint coverage, gap boundaries, duplicate samples, clock jumps, source changes, weighted weekly totals, corrupted/truncated frames, interrupted finalization, disk failures, deterministic replay and UI snapshots.

**Gate:** same log and policy yield the same metrics; recovered data is an exact valid prefix; UI reference comparison passes or precise differences are documented.

### Phase 3 — Platform transport, discovery and session ownership

Implement MX+ and Wi-Fi adapters behind the tested transport contract. Add coordinator transitions, response validation, identity verification and generic ECU selection. Use generation tokens and serialize configuration/restoration.

**Tests:** fragmented reads, short writes, concurrent callers, cancellation before/during/after reply, late prompts, double callbacks, timeout then reconnect, multi-ECU discovery and VIN mismatch/no-VIN states.

**Desk gate:** all scripted fault scenarios pass and no duplicate owner/request occurs.

**Hardware gate, pending until run:** 10 cold/warm connect-disconnect cycles without resetting Bluetooth, stable identity discovery, no stale bytes assigned to new commands.

### Phase 4 — Adaptive standard polling and integrated replay

Implement group negotiation, hint learning/invalidation, capability filtering, rates, priorities and bounded backoff. Keep enhanced work disabled. Reproduce the reference 1 Hz profile with a deterministic timed harness, then exercise adaptive 2/3 Hz behavior using latency models and supported fixtures.

A sequential captured trace alone cannot validate arbitrary scheduler decisions. Use command-matched scripted responses or a vehicle-response model with recorded latency/fault distributions. Keep exact trace reproduction as one regression mode, separate from adaptive-scheduler tests.

**Gate:** no starvation or catch-up bursts; missing optional PIDs cannot block core signals; reconnect resets hints; two-hour replay meets Section 14 resource criteria.

### Phase 5 — Standard-only hardware acceptance

Use the existing UI and new engine in a parked session first, then a passenger-operated 20-minute drive. Begin at 1 Hz, then test 2 and 3 Hz separately. Capture valid per-PID rates, completeness, gaps, occupancy and lifecycle events.

**Baseline gate:** in stable connected driving windows, RPM/speed/supported fuel achieve at least 1 Hz over the run with at least 99% per-PID valid replies; maximum gap <=1.2 seconds is the reference target. Report every exception and also publish whole-trip statistics including outages. Do not conceal reconnect gaps by only presenting stable-window numbers.

**Performance target:** 3 Hz for the drive group when measured hardware supports it. Failure to hit 3 Hz requires a documented bottleneck, not fabricated samples or an unbounded retry loop. A stable validated lower rate may be the release default.

**Lifecycle gate:** phone lock/app switch for at least five minutes, controlled link drop, ignition cycle and within-grace reconnect preserve honest trip continuity. Record OS/device/accessory versions and actual results.

### Phase 6 — Enhanced VW reads with core-rate protection

Add bounded DSG windows, then engine windows, one controller at a time. Compare standard-only, +DSG and +engine sessions. Include total setup/restore time in budgets. Validate fingerprint gates and restoration failures.

**Gate:** enhanced work stays within its measured average budget and separately documented interruption target. If the reference core gap cannot be maintained, default to deferring/disabling optional reads and report the tradeoff; do not relax the standard-only baseline invisibly. Persistent-channel optimization remains optional and separately tested.

### Phase 7 — Compatibility, field validation and release switch

Verify old-trip access, fuel-prefill continuity, transfer to the current Mac app, export identity and no duplicate imports. If optional raw transfer is implemented, verify byte integrity and cross-platform metric golden files. Compare fuel totals with full-to-full fill records across complete recording coverage; one pump fill is a sanity check, not a precise calibration truth. Use +/-5% as an initial investigation target only, and document fill variation, missing drives, idle fuel and partial coverage.

Run UI regression, fault suite and final long-run benchmark. Make the new engine default only after its applicable hardware gates pass. Remove legacy acquisition only after rollback is no longer needed; retain legacy archive reading as appropriate.

**Deliverables:** acceptance report, supported-feature matrix, outstanding hardware/vehicle limitations, rollback instructions and user-test checklist.

## 14. Validation matrix and benchmark definitions

| Area | Required evidence |
| --- | --- |
| All nine audit findings | Explicit test/fix or evidence-backed disposition for each finding |
| Parsing | Captured fixtures plus independent expected-value vectors |
| Identity | Interleaved multi-ECU VIN, conflicting identities, no VIN and reconnect mismatch |
| Ownership | Concurrent requests and repeated start/stop show exactly one active exchange |
| Metrics | Matched intervals, partial boundaries, idle fuel and policy-version determinism |
| Storage | Truncated body/header/CRC, disk full, kill/relaunch and interrupted finalize |
| Privacy | Synthetic identity patterns absent from every persisted/exported/logged surface |
| UI | Fixed-data screenshot/navigation comparison and freshness state checks |
| Hardware | Actual MX+/iPhone/car evidence; Wi-Fi tested separately or explicitly pending |
| Generic vehicle | Real second-vehicle test when available; synthetic 29-bit/multi-ECU fixtures do not substitute for it |

Long-run benchmark: simulate at least two hours and at least 60,000 exchanges, plus a higher-rate case matching the proposed grouped scheduler. Compare first and last steady five-minute windows after warm-up. Measure handler p50/p95, resident memory, UI update count, disk bytes, sync count, writer backlog and replay wall time. Set absolute device-specific budgets after baseline measurement; an initial relative target is no more than 20% p95 handler degradation and no sustained memory growth proportional to trip length. Investigate noisy measurements before drawing conclusions. Disk growth with recorded exchanges is expected; in-memory trip-array growth is not.

Track the original findings explicitly:

1. Whole-trip economy coverage failure -> matched-interval analysis and offset-start fixture.
2. Expensive DSG windows -> measured budget, cadence and exclusive restoration.
3. Ambiguous generic RPM -> per-ECU discovery and selected-source decoding.
4. Mixed VIN frames -> per-ECU reassembly and identity fixtures.
5. Published trip-copy overhead -> bounded live snapshot plus measured long-run profile.
6. Journal rewrite overhead -> append-only log, bounded ring and batched flush.
7. Identity leakage -> pre-persistence redaction including malformed responses.
8. Non-OK AT hangs -> prompt completion and typed response validation.
9. Dead restore parameter/unchecked restore -> explicit configuration state and checked restoration, removing dead API after callers migrate.

## 15. Codex workflow and reporting requirements

Use small coherent commits by phase. Suggested documentation directory: `docs/driveline/obd-rebuild/` with `PLAN.md`, `BASELINE.md`, `DECISIONS.md`, `STATUS.md`, `HARDWARE-CHECKLIST.md` and fixture manifest. These are suggested deliverables, not evidence that files already exist.

For each phase, report: concrete changes; tests run and exact results; build environment; UI impact; evidence links/paths; remaining failures; hardware gates pending; next independent work. Mark statuses as not started, implemented, software verified, hardware verified or blocked. Avoid a single ambiguous “complete” label.

Continue independent desk work when a hardware gate is pending. Stop only the dependent live rollout/claim, not all development. Do not rewrite unrelated app features, silently erase test failures, weaken assertions to make tests pass, or claim device testing from replay.

Public release/distribution requirements for the accessory are outside this coding milestone and must be checked with current official sources if distribution is undertaken. Likewise, verify exact adapter hint syntax and platform lifecycle requirements against official documentation during implementation rather than treating this design document as protocol authority.

## 16. Initial prompt to paste into Codex

```text
Implement the attached DriveLine OBD Rebuild — Detailed Codex Implementation Plan in the existing iOS application.

Preserve the current UI: screens, navigation, layouts, typography, colors, map behavior and interactions are the fixed design contract. Rebuild the OBD internals behind a compatibility presentation layer. Reuse reviewed parser/decoder code only after independent tests. Use an internal engine selector and guarantee one adapter owner.

First read repository instructions, inspect branch history and the working tree, and identify the newest complete iOS baseline. The prior audit referenced codex/obd-workflow-reliability at 7a7eedd; verify rather than assuming it is still current. Preserve unrelated changes and use an isolated branch/worktree.

Execute Phase 0, then begin Phase 1. Verify the reported Pocket Recorder statistics from actual raw captures if present; label missing evidence and hardware gates pending. Continue independent software work without inventing hardware results. Implement recording, matched-interval economy and the early UI bridge before road acceptance. Keep existing Mac transfer compatible; new raw-log transfer requires explicit version negotiation.

Run appropriate tests and builds, keep small phase-based commits, and maintain docs/driveline/obd-rebuild/STATUS.md with implemented/software-verified/hardware-verified states. For each milestone report what changed, tests and results, UI differences, pending hardware checks and the next task. Do not merge or publish automatically.
```

## 17. Final completion checklist

- [ ] Current iOS baseline and UI references recorded.
- [ ] Reported capture statistics independently verified or clearly pending.
- [ ] Generic ECU selection and per-ECU VIN parsing verified.
- [ ] One command owner under concurrency, cancellation and reconnection.
- [ ] Grouping and hints negotiate/fall back without fabricated data.
- [ ] Core rates measured on hardware; enhanced interruptions separately bounded.
- [ ] Correct matched-interval metrics and honest partial coverage.
- [ ] Append log, bounded memory, crash recovery and disk-error behavior verified.
- [ ] Sensitive raw identifiers absent from telemetry/diagnostic persistence and exports.
- [ ] UI preserved through deterministic comparison.
- [ ] Existing fuel, odometer-prefill and trip/navigation behavior preserved.
- [ ] Mac compatibility and idempotent transfer verified.
- [ ] Phone-lock, ignition and disconnect scenarios actually tested or declared pending.
- [ ] Rollback available until new-engine hardware acceptance.
- [ ] All nine audit findings have documented dispositions.
