# MX+ discovery fix — development build 27

## Evidence and cause

On 2026-10-26, the physical iPhone build 26 reported ambiguous ECU identity/capability data. Private telemetry logs were copied locally to `/tmp/driveline-car26-telemetry`; no identity data or complete device logs were committed. Fourteen sessions ended after capability discovery and protocol identification, before the VIN request. The non-identifying Mode 01 reply consistently contained two ECUs:

```
7E8 06 41 00 98 19 20 13
7E9 06 41 00 98 18 00 01
```

Both advertised RPM, speed and coolant, so the old core-PID score tied. The detailed Jetta-profile exception did not apply to the saved profile. Selection never reached VIN validation.

## Change

Among equally ranked RPM-capable candidates, select an ECU only if its advertised support is a strict superset of every other tied candidate. This resolves the captured reply to 7E8 without relying on optional vehicle engine/transmission metadata or address order. Equal and incomparable maps remain blocked. The previous profile-specific address-order exception was removed. VIN validation and per-ECU routing remain mandatory and unchanged. A non-identifying selected-ECU event is now persisted before VIN discovery.

The Record screen now shows Connecting scanner / Scanner not ready instead of Ready to record while the scanner source is disconnected. Start is disabled until the selected vehicle is connected; GPS-only recording and Finish remain available through their existing flows.

## Validation

- 24 iOS unit/contract tests passed, including captured-reply discovery through synthetic VIN, routing and RPM polling; reverse-address selection; equal/incomparable rejection; VIN mismatch blocking; and disconnected preflight messaging.
- The simulator UI replay test passed through the existing Record screen and save flow.
- Two shared protocol tests passed for conflicting VIN rejection and per-ECU capabilities.
- Signed device build 27 succeeded with DEBUG and DRIVELINE_OBD_REBUILD compilation flags; rebuilt acquisition remains the default on Home Screen launches.
- Installed in place and launched with no special arguments. Device inventory confirms build 27; launched PID/executable checked independently.
- This regression uses the actual non-identifying capability response, with synthetic subsequent VIN/measurement replies. Successful on-car connection and driving acceptance still require a retry with the MX+.

Build and test logs are `/tmp/driveline-car-build27.log`, `/tmp/driveline-car27-tests.log`, `/tmp/driveline-car27-shared.log`, and `/tmp/driveline-car27-ui.log`. The signed app is `/tmp/DriveLineOBDCarTest27/Build/Products/Debug-iphoneos/CANConnect.app`.
