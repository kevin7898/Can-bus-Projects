# Device build 33 — DSG mileage and cluster fuel discovery

2026-10-26. Extends the build-32 parked diagnostic tool. The existing rebuilt recording engine remains the normal launch default.

More -> OBD scanner -> Check VW odometer & fuel now includes:
- Cluster 229A fuel-volume candidate, separately labelled in litres and unverified.
- Targeted DSG calibration check, followed only for 02E300062B9430 by one TP2.0/KWP read of measuring block 109. Assembled bytes remain raw; no unreviewed mileage formula is applied.
- Existing VIN/stationary checks, exclusive ownership, cancellation cleanup, and local reports.

No high-resolution total odometer or trip-meter decoder is claimed. Sources and limits are recorded in ODOMETER-DISCOVERY.md. User data backed up to `/tmp/driveline-before-odometer33` before installation.

Validation: 25 unit tests and one simulator scanner-settings UI test passed. Signed device build and in-place installation succeeded. Normal launch with no arguments succeeded; build 33 and exact process 16789 / executable were independently verified using devicectl. Real-car block 109 and fuel readings remain pending. Private logs: `/tmp/driveline-odometer33-finaltests.log`, `/tmp/driveline-odometer-device33-final.log`.
