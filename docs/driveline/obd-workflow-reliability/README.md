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
| Initial timestamp/transport milestone iPhone unit suite | 151 executed, 150 passed, 1 hardware skip |
| Shared after distance repair | 42 passed |
| Mac after distance repair | 34 passed |
| Shared after availability/checkpoint milestone | 43 passed, 0 failures |
| Mac after availability/checkpoint milestone | 34 passed, 0 failures |
| iPhone after availability/checkpoint milestone | 155 executed, 154 passed, 1 hardware skip |

Commands: `swift test --package-path shared/DriveLineShared`,
`swift test --package-path mac-app`, and
`xcodebuild test -project can-connect-ios/CANConnect.xcodeproj -scheme CANConnect -destination 'platform=iOS Simulator,id=C975E238-AE3A-4B13-9FE8-477B69F94928' -parallel-testing-enabled NO -only-testing:CANConnectTests -derivedDataPath /tmp/DriveLineOBDReliabilityBuild CODE_SIGNING_ALLOWED=NO`.

Intermediate regressions were fixed before the milestone: Xcode source lists
needed regeneration, discovery expectations needed the protocol-neutral
baseline, slow-temperature coverage expectations needed availability semantics,
and journal recovery needed to recognize automatically started drafts not yet
present in the main state file. These are not counted as passing runs.

## Preservation

Existing schema 1/2 archives remain decodable. Coverage metadata is additive and
optional. No raw recording bytes, transfer payloads/hashes, stable IDs, controller
fingerprints, diagnostic allowlists or six-second engine quiet interval changed.
Fixtures contain synthetic values and no personal VINs, routes or credentials.

Further integrated results, measurements and acceptance status follow in later
milestones; this document does not claim complete physical qualification.
