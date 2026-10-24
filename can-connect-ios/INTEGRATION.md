# iOS data and connection contracts

## Phone state and trip archives

Local state schema v3 adds remembered scanner/server settings and a durable transfer queue to v2's vehicles, trips, fills, dashboard preferences and recovery draft. v1/v2 history migrates without loss. Scanner endpoint settings may be remembered on a vehicle after identification. Pairing tokens are stored only in Keychain, keyed by normalized server endpoint; they never appear in the state file or trip archive.

The JSON export envelope is still `schemaVersion: 1`, with `trips` and optional `vehicles`. Existing whole-second ISO-8601 dates remain accepted; exports include fractional seconds. Each trip has identity, vehicle ID, name, source, sample flag, start, duration, distance, optional fuel/economy and route. `source` is `phoneGPS`, `scanner`, `imported`, or `demo`. GPS route points carry latitude, longitude, timestamp, accuracy (metres), and optional speed (m/s). Scanner trips additionally carry optional `samples`:

```json
{
  "timestamp": "2026-10-23T12:00:00.125Z",
  "signals": {"rpm": 1726},
  "command": "010C",
  "reply": "41 0C 1A F8\r"
}
```

This is synthetic explanatory data. Each sample contains only the readings returned by that response. Receipt timestamps are phone wall-clock times; they are not ECU-generated timestamps. Local state and Mac wire payloads retain numeric timestamp precision. Export timestamps use ISO fractional-second precision. Do not interpret absent engine values as zero or copy earlier values into missing samples.

Imports enforce a 20 MB / 500 trip / 500 profile limit, at most 100,000 route points and 200,000 OBD responses per trip, finite valid measurements and known schema/source semantics. Duplicate trip IDs within one archive are rejected; existing IDs are skipped. Vehicles map by ID/VIN; unknown IDs without profiles are rejected. Legacy archives without vehicle IDs bind to the selected profile. GPS-only trips cannot claim fuel/economy. Sample trips remain labelled. Scanner raw responses and original telemetry survive local export/import; the phone does not decode Android raw CSV or proprietary CAN captures.

## ELM327 identification and Wi-Fi

`ELMIdentification` shares the same command sequence between Wi-Fi and MX+. `ELMWiFiSession` implements one TCP session with prompt buffering, per-command timeout, serial requests and explicit disconnect. Initialization sends `ATI`, `ATE0`, `ATL0`, `ATS1`, `ATH0`, `ATCAF1`, `ATSP0`, then Mode 09 VIN and supported standard PID pages, and reads `ATDP`. Required adapter settings must be acknowledged. No clearing faults, module coding, security access or bus monitoring is issued.

`ScannerRecorder` keeps the identified connection open and serially polls only recognized, confirmed Mode 01 PIDs. `OBDDecoder` handles speed, RPM, coolant, absolute MAP/barometer, fuel rate/level, ambient temperature, ECU voltage, intake/oil temperatures and engine load in canonical units. With headers disabled, conflicting ECU replies are deliberately unavailable because their source cannot be attributed. Multiple distinct VINs are rejected. Unsupported commands, timeout, transport loss and empty polling cycles stop live acquisition; disconnect clears readings. Live values expire after ten seconds. Real vehicle/scanner compatibility remains unverified.

Scanner endpoint validation accepts private/link-local IPv4 addresses, valid `.local` names and loopback for local protocol fixtures. There is no network sweep. VIN lookup is separate, explicit and ephemeral; it uses NHTSA vPIC suggestions for review, never inferred odometer/tank/DPF values.

## OBDLink MX+ Bluetooth

`ELMMXPlusSession` opens an Apple `EASession` only for an authenticated MX+ advertising `com.obdlink`. Name/model matching accepts MX+ / MX201 and excludes other OBDLink products. The setup sheet offers the native Bluetooth accessory picker, refresh and explicit selection. A privately remembered serial prevents replacing a chosen adapter with another one. `ScannerSettings.transport` is optional; legacy profiles default to Wi-Fi.

`MXPlusStreams` schedules input/output on the main run loop; `ELMAccessoryChannel` handles partial writes, backpressure, fragmented prompts, serial requests, a 64 KB response bound, per-command timeout, cancellation and stream closure. The same identity, VIN safety and confirmed-PID polling pipeline feeds actual scanner recordings. Optional recording transport metadata survives drafts, archives and the Mac wire source label. Non-scanner recordings cannot claim scanner transport metadata. No Bluetooth session, manufacturer approval or hardware acceptance is inferred from stream fixtures. See MXPLUS.md.

## Native Mac API v1

The server implementation is on branch `feature/mac-native-app`, under `mac-app/`. The iOS branch consumes its contract without changing the Mac branch. LAN access remains an explicit runtime setting. Requests carry `Authorization: Bearer …`. Redirects are refused; local-network HTTP is enabled via `NSAllowsLocalNetworking`, and public endpoints/credentials in URLs are rejected by the client.

- `GET /v1/health`: validate schema 1, service `CAN CONNECT`, and ingestion running/paused.
- `GET /v1/vehicles`: match ID or normalized VIN; conflicting identity fails. No name-based guessing.
- `POST /v1/vehicles`: create a missing profile with the phone UUID and reviewed identity. Existing profiles are not overwritten.
- `POST /v1/recordings?vehicleID=…`: canonical envelope `{schemaVersion:1, recordingID, name, source, samples}`. Scanner samples carry numeric Unix timestamps and canonical `signals`; source command/reply remain in the original upload. GPS points carry actual coordinates, accuracy, and `gpsSpeedMps`, with no invented OBD speed/fuel signals. GPS speed metadata remains in the preserved original; the current Mac importer derives its route from coordinates and does not plot GPS speed as vehicle speed.
- `GET /v1/receipts/{id}`: verify receipt/vehicle identity, SHA-256, byte count and recognized processing status. Only `processed` with nonempty trip IDs completes a queue item. `queued`/`processing` remains awaiting acknowledgment; `failed` remains actionable.

The stable recording payload is frozen when enqueued and persisted with its destination and vehicle snapshot. Interrupted or ambiguous requests retry the identical bytes; Mac content-hash deduplication prevents duplicate imports. Server receipt IDs and resolved vehicle IDs are checkpointed. Changing server setup does not silently redirect existing queue entries. Deleting an unacknowledged queued recording is blocked. The current manual queue retains originals and completed payloads; no automatic retention deletion is implemented.

The Mac archives source bytes before its initial 202 receipt, then processes separately. An initial 202 is never called a completed backup. If processing fails, retry import in the Mac app, then check the existing receipt on the phone. Transfer errors and state-write failures preserve the local recording. The Mac import currently ignores unsupported signal names such as ambient temperature while preserving them in the archived original.

## Code boundaries

- `Core/Models.swift`, `VehicleProfile.swift`, `ScannerReadings.swift`: values, migrations, acceptance, standard decoding and source-aware derived totals.
- `Services/GPSRecorder.swift`: Core Location lifecycle.
- `Services/VehicleIdentification.swift`, `MXPlusTransport.swift`, `ScannerRecorder.swift`: TCP/MFi transports, reviewed identity and continuous acquisition.
- `Services/LocalStore.swift`, `AppStore.swift`: atomic state, recovery, vehicle isolation and orchestration.
- `Services/MacServer.swift`: Keychain, endpoint/API contract, stable payload and receipt validation.
- `Views/`: existing locked tab/page/card design, native connection/setup sheets.

References: [ELM327L data sheet](https://www.elmelectronics.com/wp-content/uploads/2016/07/ELM327L_Data_Sheet.pdf), [NHTSA vPIC API](https://vpic.nhtsa.dot.gov/api/), [Apple local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy), [Apple local networking ATS key](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking).

Bundled sample map sources: [roads](https://nanmap.nanaimo.ca/arcgis/rest/services/NanMap/Lines/MapServer/4), [water](https://nanmap.nanaimo.ca/arcgis/rest/services/NanMap/Basemap/MapServer/3), [parks](https://nanmap.nanaimo.ca/arcgis/rest/services/NanMap/Basemap/MapServer/5). Geometry is clipped to the Nanaimo sample area; illustrative highlights are not personal trip records. Real routes use native MapKit.
