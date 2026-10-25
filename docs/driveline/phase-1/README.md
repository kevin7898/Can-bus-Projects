# DriveLine Phase 1 shared-contract evidence

Validated on 25 October 2026 on branch `codex/driveline-drive-ledger`, starting
from Phase 0 commit `cf3ec1bc99d5e4e5b0d7007d620c6335e99ab3f4`.

## Migrations and compatibility

- `DriveLineArchive` schema version 2 is the canonical Mac/iPhone recording,
  vehicle, fill, receipt-metadata, coverage, and provenance contract.
- Version-1 recording archives still decode through an in-memory adapter.
  Stable `recordingID` and `vehicleID` values and fractional timestamps are
  retained; original uploaded bytes remain in the Mac `Originals` store.
- Mac `LibraryState` advances from schema 1 to schema 2 by adding
  `fuelEntries`. Loading a schema-1 library does not rewrite its file. It is
  written as schema 2 only on a later ordinary save.
- Existing iPhone state remains decodable because new fill and receipt fields
  have migration defaults. Version-1 iPhone trip archives remain importable.
- No telemetry database migration is part of Phase 1.

## Shared correctness policy

- GPS distance uses validated points, a 30-second gap boundary, a 300 km/h
  plausibility limit, and a 5 m movement threshold. Recorded summary distance
  is retained only when raw GPS or speed integration cannot calculate it.
- Signal integration uses a 10-second gap boundary. Fuel rate must cover at
  least 80% of the recording before trip fuel is derived.
- Coverage counts valid observations independently of sign or vehicle motion,
  without bridging GPS or signal gaps.
- The latest observation is selected independently for every signal across
  recordings. Sample recordings are excluded by default.
- Gauge boost uses `boostAbsoluteKpa` (or MAP) and an independently observed
  barometric value no more than 75 seconds apart; the absolute-pressure sample
  itself must be no more than 10 seconds old.
- Purchased `litresPurchased` and measured `tripFuelLitres` are separate
  contract fields. `dpfRegenTrigger` is a normalized 0–100 trigger indicator,
  never physical filter fullness.

## Sanitized golden agreement

Both app adapters consume `shared/DriveLineShared/Tests/DriveLineSharedTests/Fixtures/golden-v2.json`.
The fixture contains synthetic GPS, OBD, fill, and receipt metadata only.

Expected and observed on both platforms:

- duration: 20 seconds
- GPS distance: approximately 0.20015 km
- trip fuel: 0.02000 L
- economy: approximately 9.9925 L/100 km
- fuel-rate coverage: 100%
- provenance: synthetic GPS plus synthetic OBD
- asynchronous gauge boost: 35 kPa

The migration fixture contains no personal recordings, locations, VINs, or
credentials. Sample data is marked explicitly and tests prove that it cannot
enter real distance, latest-signal, or tank-to-tank totals.

## Local validation

- Shared contract package: 5 passed, 0 failed.
- Mac Swift package: 22 passed, 0 failed.
- Mac Xcode Debug build: passed.
- Mac isolated API integration: passed schema-2 mixed GPS/OBD/fill transfer,
  receipt metadata, stable identities, authentication, exact-original storage,
  content-hash deduplication, same-ID conflict rejection, and retrieval.
- iPhone unit/UI suite: 110 passed, 0 failed, 3 skipped (113 total) on an
  iPhone 18 Pro / iOS 27.2 simulator.

The non-failing Mac Swift run still reports the Phase 0 `pkg-config` / sqlite3
metadata warning; SQLite tests pass. Physical iPhone, OBDLink MX+, Jetta,
Bluetooth/reconnect, Live Activity presentation, background GPS, and real-drive
acceptance remain hardware checks. Phase 2 UI redesign has not started.
