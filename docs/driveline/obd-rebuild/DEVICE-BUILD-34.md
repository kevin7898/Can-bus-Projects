# Build 34 — periodic cluster readings and rolling range

Development build, rebuilt engine enabled on ordinary launches. Existing recordings and settings retained; private pre-install backup is outside Git.

## Behaviour

- For a VIN-verified 2014 VW Jetta on protocol 6, verify cluster part 5C6920853A / software 0809 before reading 22229A and 222203. Exact response ECU, identifier, length and agreement are required.
- First cluster window after 15 seconds; subsequent windows 60 seconds after completion. Default session only, no 1003, no TP2.0/DSG polling. Single engine task owns every exchange and restores flow-control mode and primary ECU routing before resuming standard requests.
- Failed/unsupported decoding, fingerprint mismatch, or a window longer than 3 seconds disables subsequent cluster windows until reconnect. Transport/configuration failures disconnect instead of reusing uncertain routing. Actual physical overhead remains to be measured.
- Fuel volume uses the captured two-byte 229A interpretation, raw / 8 litres. Coarse odometer uses the captured two-byte 2203 candidate, raw * 10 km. The latter is explicitly experimental, does not provide fractional odometer precision, and never fills a trusted odometer field.
- Both observations are timestamped and saved with raw reviewed replies, headers, exchange ID and monotonic epoch. They expire for display after 90 seconds, or immediately on disconnect. Aggregate cluster timing is included in scanner diagnostics and window timing is recorded in the local telemetry log.
- Range uses the latest 500 **matched OBD kilometres** for the selected real vehicle, including saved recordings and the current recording. Fuel-rate and speed intervals are intersected before integration; idling fuel is retained. Samples more than 10 seconds apart, source/clock changes and acquisition interruptions break continuity. GPS-only and sample trips do not contribute.
- Uses distance-weighted litres/100 km, not an average of trip averages. The oldest approximately one-kilometre bin is fractionally trimmed at the 500 km boundary. At least 1 matched kilometre and positive measured fuel use are needed. Under 500 km, the UI shows the actual evidence distance and a learning label. More data is not a promise of accurate future consumption.
- Range before reserve = max(0, fresh cluster litres - reserve litres) / rolling L/100 km * 100. Default reserve 5 L, adjustable 0–50 L in 0.5 L steps and persisted per vehicle. Reserve remains a user-selected buffer; tank sender volume and calculated range remain estimates.
- Fuel/range card is on Fuel and the active recording page. Live recording map removed; GPS acquisition, saved routes and drive-history maps retained.

## Validation

- Signed device build succeeded. Installed bundle version 34; ordinary launch verified against the exact executable and process ID (16839) returned by devicectl.
- 33 distinct targeted iOS unit tests passed across FuelRangeTests, TelemetryRebuildTests and VWOdometerProbeTests. Includes captured cluster responses, fingerprint rejection, primary routing restoration, single command owner, rolling-window clipping, idle fuel, missing intervals, source/epoch mismatch, privacy and backwards-compatible reserve persistence.
- Shared package: 60 tests passed, including existing two-hour simulated telemetry benchmark.
- Two targeted UI flows passed: Today starts recording / Fuel fill-up navigation; rebuilt replay shows no live map, adjusts reserve from 5.0 to 5.5 L, keeps Finish reachable, and saves. The replay test was updated to scroll to telemetry; its reserve check exposed and fixed an inherited parent accessibility identifier.

## Car acceptance still needed

With the MX+ connected, compare fuel volume against the known dashboard/gauge context and log the first cluster window plus two subsequent windows. Compare standard PID rate/gap diagnostics before, during and after those windows, including while the phone is locked. Confirm any coarse odometer step against the dashboard over sufficient distance; do not infer fractional total mileage from the resettable trip meter. After a fill-up, compare sender change against purchased litres, allowing for gauge/sender behaviour. Check range and reserve adjustment with a fresh fuel reading.
