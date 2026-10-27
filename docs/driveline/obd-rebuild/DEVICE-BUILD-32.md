# Device build 32 — bounded VW odometer probe

2026-10-26. Existing app updated in place, rebuilt acquisition engine enabled by `DEBUG DRIVELINE_OBD_REBUILD` for normal Home Screen launches.

## Behavior

More -> OBD scanner -> Check VW odometer runs the fixed candidate set documented in [ODOMETER-DISCOVERY.md](ODOMETER-DISCOVERY.md). Saved VIN and stationary-speed checks precede manufacturer reads. Normal acquisition is stopped and awaited; recording and reconnect are blocked during the probe. Results remain unverified, local, and separate from trip samples and fuel prefill. Cluster extended session is explicitly restored to default, including cancellation cleanup. No TP2.0 odometer block is guessed.

## Validation

- 15 existing TelemetryRebuildTests passed.
- 7 VWOdometerProbeTests passed: exact response/ECU/scaling, conflicts and invalid data, session routing/restore, moving vehicle and wrong VIN, negative response, cancellation, failed restore, and concurrent recording/profile/connection exclusion.
- Simulator UI test testMXPlusSetupUsesPairedAccessoriesWithoutNetworkFields passed, including reaching the new probe and rejecting a missing adapter without manufacturing results.
- Signed physical-device build succeeded; build 32 installed on the paired iPhone in place.
- Existing application-support data backed up privately to `/tmp/driveline-before-odometer32` before installation.
- Initial launch was blocked by iOS because the iPhone was locked. After the user unlocked it, normal launch with no arguments succeeded; process 16684 and its exact installed CANConnect.app/CANConnect executable were independently confirmed in the device process list. Evidence: `/tmp/driveline-launch32-unlocked.json`, `/tmp/driveline-processes32.json`.
- Physical odometer requests, dashboard comparison, actual resolution and cross-drive consistency remain unverified.

Private build/test logs: `/tmp/driveline-odometer-tests.log`, `/tmp/driveline-odometer-ownership.log`, `/tmp/driveline-odometer-ui.log`, `/tmp/driveline-odometer-device32.log`, `/tmp/driveline-install32.log`, `/tmp/driveline-launch32.json`.
