# Recording format and next integration points

`TripArchive` is a JSON envelope with `schemaVersion: 1` and a `trips` array. Dates use ISO 8601 UTC strings (whole seconds). Export from the app to obtain a complete example. Import is limited to 20 MB / 500 trips, with up to 100,000 route points per trip, and rejects invalid coordinates, negative metrics, duplicate IDs within an archive and unsupported versions. Already stored IDs are skipped.

```json
{
  "schemaVersion": 1,
  "trips": [{
    "id": "AC28048E-A5F1-4EFA-A727-54FD194DFA00",
    "name": "Example imported recording",
    "startedAt": "2026-10-23T08:00:00Z",
    "duration": 600,
    "distanceKM": 5.2,
    "source": "imported",
    "isSample": true,
    "economy": 5.4,
    "fuelLitres": 0.2808,
    "route": []
  }]
}
```

`source` is `phoneGPS`, `imported`, or `demo`. Each route point has `latitude`, `longitude`, `timestamp`, `accuracy` (metres) and optional `speed` (m/s). `economy` and `fuelLitres` may be absent/null. Missing signals remain unavailable. Do not infer vehicle fuel consumption from GPS speed alone.

## Code boundaries

- `Core/Models.swift`: portable values, JSON contract, recording acceptance and fuel calculations.
- `Services/GPSRecorder.swift`: explicit Core Location session and permission lifecycle.
- `Services/LocalStore.swift`: atomic Application Support state; format version guard.
- `Services/AppStore.swift`: recording state, persisted preferences, import deduplication.
- `Views/`: locked UI and native maps. Card settings use stable per-instance keys such as `drive.0` and `economy.3`.

## CAN recorder and Mac mini

Before adding a real transport, agree on the device protocol, authentication, signal units, timestamps and freshness semantics. Feed live readings only while a source is connected; clear stale values after disconnect. Keep recorded snapshots separate from live values.

A future upload queue must persist each item and retain originals until the server acknowledges durable storage. The first native version does not simulate that acknowledgment. The transfer switches are stored preferences for that implementation.

Raw Android CAN/OBD captures require their own parser and decoder. The current raw `WebCanCsv` export is not the JSON trip archive and is not accepted by this importer.

## Bundled sample map sources

- https://nanmap.nanaimo.ca/arcgis/rest/services/NanMap/Lines/MapServer/4
- https://nanmap.nanaimo.ca/arcgis/rest/services/NanMap/Basemap/MapServer/3
- https://nanmap.nanaimo.ca/arcgis/rest/services/NanMap/Basemap/MapServer/5

The bundled map is clipped to the Nanaimo sample area. Personal GPS routes use native MapKit, which can display routes elsewhere. Sample road highlights illustrate coverage; the illustrative sample trip polyline is not a claim of a measured journey.

## Vehicle identity and storage v2

State schema v2 adds `vehicles`, `selectedVehicleID`, and `onboardingCompleted`. `Trip`, `FuelEntry`, and `RecordingDraft` carry optional `vehicleID`. The migration assigns v1 history to one explicit legacy/sample profile; recovery preserves the draft's vehicle ID. Existing records are not assumed to belong to a particular real Jetta.

The additive archive v1 envelope may now include `vehicles`. Export supplies profiles for its trips; import maps foreign IDs to a local profile with the same VIN or ID, creates other profiles as needed, and never overwrites an existing profile from imported suggestions. Missing vehicle IDs in old archives bind to the selected vehicle. An unknown vehicle ID without its profile is rejected instead of guessed. Recordings cannot change vehicles while active.

`VehicleIdentification.swift` implements explicit local-network TCP ELM327 identification, prompt buffering/timeouts, formatted ISO/J1850 VIN parsing, supported-PID bitmaps, and NHTSA vPIC lookup. It reads only identification/capability commands. It does not provide live CAN transport, infer manufacturer DPF PIDs, or assume every scanner is accessible through Core Bluetooth.

The setup workflow separates scanner facts from VIN-decoder suggestions and manual fields. Odometer, tank capacity and missing identity fields remain unknown until entered or provided by a compatible source. Decoder lookup is optional, user-initiated, and uses an ephemeral session. Scanner addresses are restricted to private/link-local IPv4 addresses and `.local` hostnames; the app does not sweep the network.

Sources:
- NHTSA vPIC flat VIN API: https://vpic.nhtsa.dot.gov/api/
- ELM327L command and Mode 09 examples: https://www.elmelectronics.com/wp-content/uploads/2016/07/ELM327L_Data_Sheet.pdf
- Apple local network privacy: https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
