## Build 40 — second cluster discovery batch

Installed and launched. Batch 2 defaults to 2210–221F and 22A0–22AF; Batch 1 remains selectable. All 12 probe tests passed. See [DEVICE-BUILD-40.md](DEVICE-BUILD-40.md). Await parked before/after-drive reports without another trip reset.

## Build 39 — bounded cluster trip discovery

Installed and launched (PID 17157). Separate parked snapshot scan of 32 hypothesized cluster identifiers in two sessions; raw responses only, no trip decoder or decimal odometer claim. All 11 probe tests passed. See [DEVICE-BUILD-39.md](DEVICE-BUILD-39.md). Await paired dashboard photos and reports before/after driving.

## Build 38 — display units and slow ambient polling

Pressure defaults to psi with independent saved distance, temperature, volume and economy preferences. See [DEVICE-BUILD-38.md](DEVICE-BUILD-38.md). Installed after the user confirmed recording finished; launch PID 17147 verified. Ambient temperature reads on connection then every five minutes. Coarse odometer remains unchanged pending a decoded trip counter.

# DriveLine OBD rebuild status — 26 October 2026

Latest automation policy: [Build 37](DEVICE-BUILD-37.md) starts on valid live ECU data including zero RPM, keeps recording through engine stops, and uses a ten-second grace after confirmed Bluetooth loss. This supersedes build 36 before installation.

Latest recording follow-up: [Build 36](DEVICE-BUILD-36.md) prevents ignition-only manual recordings from auto-stopping before an engine-running observation. The physical capture shows acquisition continued after the short recordings ended.

Latest connection follow-up: [Build 35](DEVICE-BUILD-35.md) exposes startup errors that previously collapsed into the generic acquisition/storage message. Physical recovery is still pending.

Previous development-device follow-up: [Build 34](DEVICE-BUILD-34.md) adds fingerprint-gated default-session cluster reads, an experimental coarse odometer, fuel volume, rolling 500 km reserve range and removes the recording-page map. See the build-specific report for current installation and test evidence; the original rebuild acceptance snapshot below is historical.

Branch: `codex/driveline-obd-rebuild`. Baseline: `7a7eedd`. Xcode 27.2 (27B48), iOS 27.2 simulator, minimum deployment target iOS 17. Existing unrelated checkout/build outputs are unchanged. No merge, push, public distribution or physical installation.

## Implemented

- Shared Foundation telemetry types, typed Mode 01/configuration requests, per-ECU ISO-TP parsing including 29-bit parser vectors, strict grouped layouts, identity conflict checks, source-specific capability pages and redaction before persistence.
- Development engine behind the existing ScannerRecorder facade. Use `--obd-rebuild` in a Debug Run scheme. Exactly one acquisition task; explicit in-flight guard; process-wide adapter lease also covers onboarding. Generation checks and bounded transport deadlines prevent reuse of failed streams. Generic 11-bit engine selection uses required-signal evidence and rejects unresolved ties; unsupported routing fails explicitly.
- Conservative groups, completion-based due times, optional-member fallback, bounded backoff and adaptive 1/2/3 Hz. Diagnostic exports expose 10/60-second valid-sample rates, p50/p95 latency and gaps including current outages. Hints have tested learning/invalidation state but production hint transmission remains disabled pending verified adapter-specific support.
- Append-only CRC-framed local exchange and trip logs, independent raw GPS records, bounded producer queue, one-second-on-append sync plus lifecycle/checkpoint sync, SHA-256 finalize markers, valid-prefix recovery, retry of admitted frames after a simulated torn disk-full write. Legacy archive materialization happens once at Finish off the main actor. The live draft retains at most 256 samples and 4096 route-preview points; running integrals retain one previous value per signal.
- Matched fuel/distance interval analysis with offset starts/ends, idle fuel, source separation, interruptions, overlap denominators, explicit partial coverage and weighted weekly economy. The legacy Mac payload keeps its endpoint/schema; partial economy is omitted from the older unlabeled field while explicit matched metadata remains available.
- Existing UI, navigation and controls remain. Critical state/errors publish immediately; ordinary replacement telemetry is coalesced. `--ui-testing --obd-replay` opens a synthetic, isolated existing Record screen and exercises recording/save. No replay mode accesses a real adapter.

## Validation

- Baseline shared suite: 44 tests passed. Baseline iOS test build passed. Baseline UI selection: 3 tests passed.
- Rebuilt shared suite: 59 tests passed, including the 60,000-exchange / two-hour log benchmark and a separate two-hour adaptive scheduler model. A finalization-retry regression was then added: 59 non-benchmark tests passed on the final sources; 60 distinct shared tests are verified across these runs.
- Mac SwiftPM core/import suite: 34 tests passed.
- iOS full suite: 175 tests executed with zero failures and one opt-in native-server integration test skipped in ordinary runs. Earlier regressions were fixed without dropping tests. A later 31-test storage/AppStore/rebuild selection passed, including a new no-resurrection-after-deletion test; its final synchronized-index version was rebuilt and passed again. The opt-in native-server test also passed separately (1 test), using an isolated loopback Mac library and an ad-hoc signed simulator build; processed receipt, original retention and queue relaunch were verified.
- Native UI selection: 5 tests passed (navigation, dark More, light/dark Garage/details, largest-accessibility onboarding, replacement replay record/save). Final replay recheck after the freshness correction also passed.
- Seven paired screenshots and comparison JSON are in `ui/`: five bodies match exactly; two vehicle-detail differences are explained by pre-existing random fixture UUIDs (including line wrapping). Screenshots were inspected. Intentional differences are partial-economy wording, long-route preview thinning, and correct render-time freshness.

Benchmark (host test runner; not an iPhone budget): 60,000 exchanges, 7,200 simulated seconds, 26,395,449 bytes, 6,669 syncs. First/last steady-window handler p95 0.440/0.311 ms; p50 0.295/0.291 ms. Resident memory observations 162,529,280/63,963,136 bytes: no positive growth in this run, but prior suite allocations/allocator reclamation affect these values. Replay 17.315 s; total benchmark 35.847 s. Do not treat host timings or the sample/GPS buffer tests as on-device profiling. UI update count and device-specific absolute budgets still need device profiling.

## Phase dispositions

| Phase | Disposition |
|---|---|
| 0 Baseline/evidence | Software baseline recorded; selected UI references captured; reported private capture rates pending (no matching Pocket/OBD raw captures located in Downloads). |
| 1 Protocol/replay | Software verified against independent synthetic vectors; real capture corpus pending. |
| 2 Recording/analysis/bridge | Software verified, including disk fault, prefix recovery, bounded live sample/map buffers, matched metrics and existing-screen replay. |
| 3 Platform/session | Existing real platform transports integrated and fault-tested; physical connection cycles pending. |
| 4 Adaptive standard polling | Software verified; hint optimization deliberately inactive pending verified adapter support. |
| 5 Standard-only hardware | Pending; do not enable as release default. |
| 6 Enhanced VW | Existing audited legacy implementation retained with restore validation; replacement defers optional windows because the six-second quiet period cannot meet the core-gap reference. No persistent enhanced channels. |
| 7 Compatibility/release | Legacy archive/queue and actual loopback Mac server test pass; hardware/field acceptance and default switch remain pending. Raw-log Mac ingestion is a separate unimplemented, negotiated rollout milestone. |

## All nine findings

1. Economy coverage defect: matched-interval policy + offset-start/idle/gap vectors.
2. Expensive enhanced windows: deferred in the replacement; existing reviewed code retained, no unmeasured promise of 1.2-second gaps with enhanced reads.
3. Generic RPM ambiguity: ECU provenance, required-signal selection and unresolved-tie rejection.
4. Mixed VIN frames: per-ECU reassembly, interleaved/conflicting/broken-sequence vectors; anonymous legacy formats retained separately.
5. Published trip copies: disk-spooled samples, bounded live preview and streaming integrals; final legacy materialization remains explicit.
6. Journal rewrite overhead: replacement uses framed append logs; legacy diagnostics remain bounded and are not used by replacement acquisition.
7. Identity leakage: pre-write identity/calibration/informational redaction; malformed identity and unexpected identity beside standard replies tested; onboarding VIN metadata remains explicit user metadata.
8. Non-OK AT hangs: prompt completion independent of content, echo-only synchronization retained; ATRV/rejected replies tested.
9. Restore API: removed dead restoreCANDefaults parameter; checked targeted-route restoration. Failed boundary/configuration causes disconnect/recovery.

## Remaining acceptance

Follow HARDWARE-CHECKLIST.md. Real MX+, Wi-Fi, second vehicle, phone lock, ignition, road rates, fill comparison and current physical Mac transfer have not been validated. No source captures were fabricated. Legacy acquisition remains the default until applicable gates pass. Unimplemented optional scope: raw-log Mac importer/negotiation, persistent enhanced channels and enabled response-count hints. Full all-screen/device/appearance UI matrix and device resource budgets are not claimed from the selected simulator captures.

Evidence logs/result bundles are local under `/tmp/driveline-rebuild-*` and `/tmp/driveline-obd-*`; committed reports and screenshots retain the useful summaries. Simulator-built app: `/tmp/driveline-obd-signed/Build/Products/Debug-iphonesimulator/CANConnect.app` (not installable on a physical iPhone).
