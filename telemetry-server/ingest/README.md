# Pocket recording receiver

A small self-hosted Python 3.12+ ingestion endpoint, separate from the frontend and recorder. Stores exact NDJSON files and SQLite metadata with distinct recorded/ingested timestamps. It does not yet connect the dashboard's sample-data provider to real recordings.

Run tests:

```sh
python -m unittest discover -s telemetry-server/ingest -v
```

Set a private, randomly generated `CANC_UPLOAD_TOKEN` of at least 32 characters in your service environment, then run:

```sh
CANC_DATA_DIR=/path/to/private/recordings python telemetry-server/ingest/receiver.py
```

Defaults to loopback `127.0.0.1:8787`. Place it behind your HTTPS reverse proxy and enter `https://YOUR_HOST/ingest` plus the same bearer token in Pocket Recorder. `/health` reports readiness without exposing records. Do not enter the static dashboard URL: it has no ingestion handler.

Only authenticated POST `/ingest` accepts recordings. Bodies are limited to 64 MiB; exact SHA-256 acknowledgements, atomic file persistence, SQLite commits and duplicate IDs protect retry behavior. Original per-row timestamps are retained. Conflicting IDs, corrupted payloads and incomplete final rows are rejected; the phone retains its originals.

No records or credentials are included in this repository. Store recordings outside Git, protect the data directory and back it up. This is a prototype receiver, not a multi-user or publicly hardened telemetry service. Android Bluetooth/GPS and end-to-end HTTPS delivery require separate device acceptance tests.
