# Physical MX+ locked-phone drive — build 28

The user reported driving with the phone locked and switching ignition off before ending recording. A read-only copy of app data was retrieved on 2026-10-26 to `/tmp/driveline-long-drive28-evidence`; private analysis is `/tmp/driveline-long28-analysis.txt`. These originals remain outside Git. No coordinates or private identifiers are included here.

## Recorded result

- Latest finished recording: 13:15:04–13:18:13 America/Vancouver (188.70 seconds), 0.94722 km selected from GPS, 1,385 scanner samples and 111 GPS points; no unfinished draft.
- Acquisition selected 7E8 and verified the VIN before this trip. All saved samples were from 7E8. No reconnect appeared within the acquisition session. Lock timing is user-reported; the diagnostic log does not timestamp phone lock/unlock, so this is evidence of continuity in a user-reported locked-phone run rather than an independently timed lock-duration measurement.
- RPM, speed and fuel each had 269 observations. Rates over valid observation spans were 1.624, 1.627 and 1.627 Hz. All 269 requests per core PID up to the last valid sample produced decoded observations; no privacy-redacted/invalid core replies occurred in that window. Whole-trip availability includes the ignition-off tail and must not be described as 100%.
- Maximum internal gaps: RPM 1.165 seconds, speed 1.319 seconds, fuel 1.174 seconds. One speed interval exceeded the 1.2-second reference target. At offsets 40.782–42.101 seconds, a non-preemptible exhaust-temperature request (0178) took 0.532 seconds amid other scheduled reads. There was no dropped reply or reconnect. This run therefore does not pass the strict maximum-gap target, despite continuous valid acquisition.
- GPS median interval was 1 second and p95 2 seconds. The largest interval was 16 seconds near the beginning (offsets 1.32–17.32); all later intervals were at most approximately 5 seconds. Median reported horizontal accuracy was 2.01 metres. The final GPS point preceded Finish by 28.38 seconds. The 5-metre distance filter makes endpoint gaps insufficient evidence of background failure.
- Last valid OBD sample preceded Finish by 22.25 seconds, consistent with the user-confirmed ignition-off-before-Finish sequence. Sanitized non-decodable replies cannot identify the exact vehicle/adapter error. Matched fuel/distance coverage was 158.96 / 188.70 seconds (84.24%), explicitly partial.

## Save integrity

Trip-log CRCs, final SHA256, byte length and record count all match (465,638 bytes; 1,534 records). The trip log is indexed; its 1,385 sample records exactly equal the saved trip's samples. Acquisition-log CRCs, SHA256, length and count also match (700,065 bytes; 1,497 records). No post-finalization metadata was appended: build 28's late-checkpoint fix passed this physical save check.

No source changes or reinstall were needed for this inspection. The test supports successful acquisition, GPS capture and finalization in this bounded locked-phone run. It does not establish extended-duration memory stability, 20-minute locked operation, repeated ignition/reconnection reliability, or fuel calibration. The single 1.319-second speed gap remains a measured scheduling limitation to track against longer drives.
