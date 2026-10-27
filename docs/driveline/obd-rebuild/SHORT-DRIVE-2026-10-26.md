# Physical MX+ short-drive evidence — build 27

User-reported drive, inspected from a read-only device-container copy on 2026-10-26. Private originals and analysis remain outside Git under `/tmp/driveline-short-drive27-evidence` and `/tmp/driveline-short27-analysis.txt`. No route coordinates, VIN, vehicle ID or trip ID are included here.

## Observations

- Latest scanner trip: 13:05:34–13:08:58 America/Vancouver, 203.91 seconds, 0.14395 km from measured OBD speed integration, 1,625 persisted scanner samples and 21 GPS points. No unfinished draft remained.
- Acquisition selected 7E8 and logged identityVerified. Every persisted sample retained response ECU 7E8. No reconnect event appeared during the trip.
- RPM / speed / fuel rate each had 320 samples, averaging 1.675 / 1.682 / 1.677 Hz over their valid observation spans. Maximum internal gaps were 1.075 / 1.080 / 1.069 seconds; none exceeded the 1.2-second core reference target. These rates exclude the no-valid-data tail and are not whole-trip availability figures.
- Vehicle movement was observed roughly 148–188 seconds into the recording, with a maximum OBD speed of 22 km/h. The user confirmed the first approximately 2.5 minutes were stationary and ignition was switched off before Finish.
- GPS had a 151-second initial inter-point gap; movement began near its end. The app uses a 5-metre distance filter. This stationary interval is not evidence of a GPS failure, nor does this short test establish background GPS acceptance.
- Valid scanner observations ended approximately 13 seconds before Finish. Subsequent replies were privacy-redacted as non-decodable; their exact error text cannot be recovered from the sanitized log. The user-confirmed ignition-off timing is consistent with this tail; it is not counted as valid coverage.
- Matched economy coverage was 189.62 / 203.91 seconds (92.99%). About 0.0515 L was recorded. The short distance and extended idle time make fuel-economy accuracy assessment inappropriate.

## Save integrity finding and fix

All frames in both copied logs passed CRC validation. The saved trip's 1,625 samples exactly matched its append-only log. Acquisition-log final SHA256, length and frame count matched. The trip log had one additional 263-byte metadata checkpoint after the finalized prefix: the final marker matched the prefix exactly (530,034 bytes / 1,690 frames), but not the resulting complete file (530,297 bytes / 1,691 frames). The trip was indexed and its samples were intact. Original evidence was left unchanged.

A checkpoint could run while Finish was saving or be queued after finalization. Build 28 suppresses AppStore checkpoints while finishing and makes superseded buffer checkpoints harmless before admission and again on the serialized writer queue. This protects final bytes, final metadata and checksum. No existing trip data is rewritten.

Validation: 24 iOS tests passed (15 rebuild/storage, nine AppStore), including a new regression that a late checkpoint cannot change final log bytes, marker, metadata or samples. Signed device build 28 succeeded with the rebuilt engine enabled by default. Installed in place on the physical iPhone; device inventory confirmed build 28 and its launched PID/executable was independently verified.

This is a successful bounded physical connection/identity/acquisition/save test with a discovered finalization bookkeeping bug. Long drives, repeated connection/ignition cycles, locked-phone behavior, sustained memory usage and fuel accuracy remain separate acceptance work.
