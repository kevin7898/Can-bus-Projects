# Pocket Recorder 0.4.0

A prototype standalone Android recorder for a 2014 Jetta TDI and paired classic-Bluetooth OBDLink MX+. No Car Scanner installation, licensing changes or private PID database is needed. The native launcher avoids the earlier Compose startup path.

## Use

1. Pair the MX+ in Android Bluetooth settings. Close Car Scanner and other apps using the same adapter.
2. Open Jetta Recorder. Grant Bluetooth permission. Grant precise location for GPS; notifications are recommended. Approximate-only location currently leaves GPS disabled.
3. Refresh the paired list, choose the MX+, and tap Connect & record while parked.
4. A foreground notification remains visible. Recording and GPS continue with the screen off. A partial wake lock is held until Stop. The service reconnects while recording is enabled; it does not yet auto-start at ignition or stop itself after parking.
5. Stop to finalize the current file. Export completed recordings as ZIP through Android's file picker, or configure uploads.

The current transport supports Bluetooth Classic SPP, not BLE. Older iCarPro/iOS sessions in the source log do not imply that every adapter supports SPP. GPS and actual vehicle behavior require device testing.

## Data

App-private `files/pocket-recordings/` holds append-only NDJSON files. `.active` denotes a current recording; completed and interrupted/recovered recordings use `.jsonl`. Every OBD entry retains its command, raw reply, decoded signals, reading receipt time (`recordedAt`), monotonic time and latency. GPS entries retain location-fix time, accuracy and coordinates. There is no VIN collection.

The server must add `ingestedAt` separately and index samples by their original `recordedAt`. Upload acknowledgements never remove phone originals. Interrupted sessions can lack a final row; a truncated last line must be reported during ingestion, not silently joined to another sample.

Observed reads: 010D speed, 010C RPM, 015E fuel rate, 0105 coolant, 0146 ambient, 0133 barometric pressure, 0170 boost control, 0178 EGT sensors, 017A DPF differential pressure, 018B aftertreatment status, 0142 ECU voltage, 0104 load and 0110 MAF. Only ECU 7E8 is decoded. ISO-TP sequence order and expected lengths are checked; incomplete messages and responses from other ECUs are rejected.

The earlier MAP PID 010B is not advertised in the trace's engine support bitmap. The first build therefore uses supported extended standard PID 0170 instead of assuming that MAP/UDS candidates work. Manufacturer-specific engine 22xxxx probes frequently returned NO DATA in the supplied trace.

DPF normalized regeneration trigger (%) is explicitly distinct from soot mass and the unverified Car Scanner “DPF Soot Level” calculation. Some captured 018B replies encode 100% trigger. No soot percentage or grams are invented. All EGT sensors keep their own identities rather than assuming sensor 1 is the DPF inlet. Standard formulas and field support bits follow the diagnostic-device manufacturer's reference: https://www.dashlogic.com/docs/technical/obdii_pids

Requested polling periods are targets, not measured throughput. Failed signals back off; all requests share one serialized adapter stream. Displayed gauge boost and instantaneous economy require fresh component readings; at rest, fuel use stays in L/h.

## Upload contract

The existing hosted CAN / CONNECT static dashboard is NOT an ingestion endpoint. Leave the URL blank for local recording/export, or enter the HTTPS URL of a compatible receiver and its bearer token. Use the supplied self-hosted receiver under `telemetry-server/ingest/` behind an HTTPS reverse proxy.

WorkManager queues completed recordings with exponential retries. Select “unmetered networks only” to restrict bulk transfers; otherwise any connected network can be used. WorkManager scheduling is subject to Android and OnePlus power management; it does not promise real-time upload.

Each request is POST with:

- `Content-Type: application/x-ndjson`
- `Authorization: Bearer <configured token>`
- `X-Recording-Id: <filename>`
- `X-Content-SHA256: <digest of exact body>`

A successful receiver must durably accept the file and return a 2xx JSON response `{"sha256":"<same digest>"}`. Duplicate content should return that same acknowledgement. Redirects, login pages, mismatched digests and errors leave the file queued. Credentials remain in app-private preferences; backups are disabled. No secrets or personal logs belong in Git.

## Validation and limits

JVM decoder tests cover observed non-identifying byte examples, engine/transmission separation, multi-frame ordering/truncation, signed pressure, per-field support masks and distinct DPF trigger naming. CI builds the APK and checks that the Kotlin launcher, service, uploader and decoder actually exist in DEX. The previous Gradle configuration omitted the Kotlin Android plugin; a successful package build alone was therefore not sufficient evidence of runnable Kotlin activities.

Compilation and replay tests cannot establish Bluetooth, GPS, background survival, rate accuracy or upload delivery on the real OnePlus/Jetta. Those are explicit on-device acceptance checks. The original uploaded log is not committed; it contains identifiers and historical diagnostic details.
