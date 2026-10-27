# Build 37 — automatic recording while the vehicle supplies data

This supersedes the pending build-36 running-engine transition policy at the user's request. Build 36 was tested but not installed. The user requested recording whenever ignition is on, including with the engine stopped, and finalization on Bluetooth loss.

## Policy

- After existing vehicle identity validation, the first valid decoded Mode 01 observation starts a real scanner recording automatically, including zero RPM. Adapter pairing/availability alone and invalid or missing data cannot start a trip.
- Zero RPM does not stop an active recording, including after the engine has run. Manual Finish remains available and does not immediately restart on continuing readings.
- Confirmed MX+ accessory availability loss shortens the persisted reconnect deadline to ten seconds, stops the stale scanner session, checkpoints the draft, and leaves GPS provisional during that grace period. A reconnected valid response clears the deadline and continues the same recording. At expiry, save exactly once with the end bounded by the last actual ECU observation; do not append a subsequent walk to the saved route.
- Missing ECU responses while Bluetooth remains connected retain the existing 120-second recovery policy. Failed retries never extend that deadline.
- This detects an awake/responding vehicle, not a verified key/ignition bit. A vehicle may answer briefly after the key is turned off. Background execution still depends on iOS accessory/location scheduling; persisted deadlines are checked when execution resumes.

## Validation

18 scanner lifecycle tests passed, including zero-RPM automatic start, engine running then stopped without auto-finish, explicit Finish suppression, confirmed Bluetooth-loss ten-second expiry, restart on subsequent zero-RPM data, original temporary acquisition recovery, identity rejection and gap persistence. A simulator UI test verifies automatic ignition-only recording survives Home Screen departure/return and can be finished explicitly. Signed device build 37 succeeded with the rebuilt engine enabled.

Private pre-install copies and device launch verification are outside Git. No physical on-car acceptance of the revised Bluetooth-loss policy is claimed from simulator tests.

Installation completed; ordinary launch verified against exact running executable and process 17033. Full private pre-install copy completed at `/tmp/driveline-before37`.
