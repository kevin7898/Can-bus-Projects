# Device build 39 — bounded cluster trip discovery

Adds Scan cluster for trip counter alongside the existing odometer/fuel probe. The scan checks DID 2200–220F and 2290–229F (32 identifiers) in default and, if accepted, extended sessions: at most 64 discovery reads. These are hypothesis-driven neighborhoods around known odometer/fuel identifiers, not documented trip-counter DIDs.

The probe verifies selected VIN, stationary speed, CAN protocol 6/A6, and exact cluster part 5C6920853A/software 0809 before discovery. It uses the existing exclusive transport ownership and blocks recording/reconnection during the operation. Fixed requests only; no coding, writes, resets or security access. Extended session is returned to default, including cancellation cleanup, then transport is disconnected. Manual reconnect is required afterwards.

Reports preserve raw replies, accepted payload bytes, response attribution, per-exchange timestamps and session labels. No bytes are decoded as trip distance or promoted to a trusted odometer. Existing reports remain on disk with unique IDs. Compare two parked snapshots with photographs of total odometer and trip before/after a short drive without resetting trip; a reset comparison is a later validation step after a candidate is identified.

Validation: all 11 VWOdometerProbeTests passed, including bounded request counts, fingerprint mismatch, raw payload attribution, no promotion, and cancellation restore. Signed Debug build with rebuilt engine succeeded. Full app data backup /tmp/driveline-before39 completed; no unfinished draft or unfinalized trip logs found. Build 39 installed and exact executable/PID 17157 verified. Physical discovery results remain pending.

Artifacts: /tmp/driveline-trip-probe39-tests.log, /tmp/driveline-build39.log, /tmp/driveline-install39.json, /tmp/driveline-launch39.json, /tmp/driveline-processes39.json.
