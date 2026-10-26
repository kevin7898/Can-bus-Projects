# DriveLine known limitations

Applies to version 1.0.0 (25), Phase 9 automated candidate.

- Physical qualification is incomplete even though the preceding signed Debug app and Live Activity extension built, installed and launched successfully on the physical iPhone. The GPS-status and journey-selection correction has passed automated validation and signed-build verification but has not yet replaced the installed app, to avoid interrupting an active recording. Stationary GPS status, Jetta/scanner, background, Live Activity presentation, safe-route and LAN-transfer checks remain open.
- Actual 2014 Volkswagen Jetta TDI DSG onboarding, VIN review, OBDLink MX+, available Wi-Fi scanner, ignition/reconnect, safe-route recording and device-to-Mac LAN transfer remain unverified. No real VIN or private route was captured.
- Background execution, force-quit recovery, Live Activity, Dynamic Island, physical GPS/scanner loss/recovery, stationary-session status and OS scheduling must be checked on the signed corrected build.
- Simulator tests do not establish physical cold/warm launch-to-first-frame performance, battery impact, thermals, GPS accuracy, scanner timing or radio reliability.
- Mac window close/reopen, logout, disconnected volumes, pause/resume, VoiceOver, full keyboard access and resize still need hands-on qualification. Automated server start/conflict/shutdown/restart does pass.
- The current Mac project is ad-hoc/manual signed with hardened runtime and App Sandbox disabled. Developer ID distribution, validation and notarization are not qualified.
- The Release archive is unsigned. Development provisioning now works through an ephemeral local-team override, but App Store validation/export and distribution signing remain unqualified.
- A dedicated Instruments Allocations capture failed to attach. The bounded repeated-selection test and process peak are available, but long-duration physical app memory/leak qualification remains pending.
- Signal/chart downsampling is display-only at a default 2,400-point limit. It preserves original observations, gaps, isolated points, endpoints and extrema, but dense traces intentionally do not draw every stored point simultaneously.
- Distance alignment still requires sufficient recorded GPS evidence; OBD-only or sparse-GPS recordings remain elapsed-time-only with an explanation.
- Missing receipts remain metadata-only and visible as missing; DriveLine does not invent or silently remove receipt evidence.
- Unknown diagnostic identifiers remain raw/unsupported. DriveLine does not invent names, units or scaling.
- Mac SwiftPM may warn that `sqlite3.pc` is unavailable on hosts without pkg-config metadata; direct SQLite linkage and tests pass.
- No cloud VIN decoder, cloud telemetry service, public server exposure, TestFlight/App Store upload, notarized package, public release or final tag was created.
