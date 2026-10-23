# Local companion API v1

Start the server in the app. Default: `http://127.0.0.1:8765`. All routes require `Authorization: Bearer <pairing-token>`. Use Server → Copy pairing token; the token is stored in Keychain. LAN access is optional and intended for trusted local networks; HTTPS and internet exposure are not configured.

| Method | Path | Result |
| --- | --- | --- |
| GET | `/v1/health` | Actual ingestion state and queued count |
| GET | `/v1/vehicles` | Vehicle profiles |
| POST | `/v1/vehicles` | Creates or updates a reviewed vehicle profile |
| POST | `/v1/recordings?vehicleID=<UUID>` | Copies and queues a canonical JSON recording |
| GET | `/v1/receipts/<UUID>` | Durable queue / processing status and trip IDs |
| GET | `/v1/trips?vehicleID=<UUID>` | Recording summaries; vehicle filter is optional |
| GET | `/v1/trips/<UUID>` | Canonical JSON telemetry for one recording |

Create a vehicle using all fields: `id` (UUID string), `name`, `year`, `make`, `model`, `vin`, and `notes`. Empty strings are valid for optional identity details. A non-empty VIN must have 17 valid VIN characters. The app never derives trim, engine, or drivetrain from an unverified identity.

Example recording shape, with deliberately synthetic coordinates:

```json
{
  "schemaVersion": 1,
  "vehicleID": "00000000-0000-0000-0000-000000000001",
  "name": "Example recording",
  "source": "iPhone GPS",
  "samples": [
    {"timestamp": "2026-10-23T12:00:00.125Z", "latitude": 49.1, "longitude": -123.9, "signals": {"speedKph": 60}},
    {"timestamp": "2026-10-23T12:00:01.125Z", "latitude": 49.1001, "longitude": -123.9, "signals": {"speedKph": 61}}
  ]
}
```

The vehicle ID must already exist in the library. The query parameter overrides the body vehicleID when present. Import assignment is always explicit. The endpoint validates the recording before copying it. It then returns **202 Accepted** with the receipt; that receipt does not yet mean the recording was processed. Poll until `status` is `processed`, then retain the returned trip IDs. If `failed`, keep the sender's original and surface the error. A byte-identical recording for the same vehicle reuses the existing receipt; an already processed duplicate returns 200.

`Content-Length` is required for POST bodies. Limit: 50 MB per recording and 16 KiB of HTTP headers. Chunked transfer is not implemented. File-picker import supports more formats than the network endpoint; network upload is canonical JSON only in this release. Raw CAN and proprietary diagnostic bytes should not be mislabeled as decoded vehicle signals.

This contract is shared by future iOS and Android companions; no client implementation is bundled in this Mac change. Integration validation uses an isolated temporary library and a synthetic test token supplied only via the test environment, with no production Keychain token exposure.
