"""Small authenticated NDJSON receiver. Bind locally behind an HTTPS proxy.

Stores exact recordings plus separate server ingestion metadata. No external dependencies.
"""
from __future__ import annotations
import hashlib
import hmac
import json
import os
import re
import sqlite3
import tempfile
from datetime import datetime, timezone
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

MAX_BYTES = 64 * 1024 * 1024


def validate(recording_id: str, data: bytes, checksum: str):
    if not re.fullmatch(r"[A-Za-z0-9_-][A-Za-z0-9._-]{0,180}\.jsonl", recording_id) or ".." in recording_id:
        raise ValueError("Invalid recording ID")
    if not data or len(data) > MAX_BYTES:
        raise ValueError("Recording is empty or too large")
    digest = hashlib.sha256(data).hexdigest()
    if not hmac.compare_digest(digest, checksum):
        raise ValueError("Checksum mismatch")
    if not data.endswith(b"\n"):
        raise ValueError("Incomplete final row; original retained on phone")
    times = []
    def invalid_constant(value):
        raise ValueError("Non-finite JSON number")
    for number, line in enumerate(data.splitlines(), 1):
        if len(line) > 1024 * 1024:
            raise ValueError("Row too large")
        row = json.loads(line, parse_constant=invalid_constant)
        if not isinstance(row, dict) or row.get("type") not in {"session_start", "obd", "gps"}:
            raise ValueError(f"Unknown row type at {number}")
        if number == 1 and (row.get("type") != "session_start" or row.get("schemaVersion") != 1):
            raise ValueError("Missing schema-1 session header")
        if not isinstance(row.get("recordedAt"), str):
            raise ValueError("Missing recording timestamp")
        timestamp = datetime.fromisoformat(row["recordedAt"].replace("Z", "+00:00"))
        if timestamp.tzinfo is None:
            raise ValueError("Timestamp requires a timezone")
        times.append(timestamp.astimezone(timezone.utc))
    if not times:
        raise ValueError("Empty recording")
    return digest, len(times), min(times).isoformat(), max(times).isoformat()


class RecordingStore:
    def __init__(self, directory):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)
        with self.connection() as db:
            db.execute("""CREATE TABLE IF NOT EXISTS recordings (
                recording_id TEXT PRIMARY KEY, sha256 TEXT NOT NULL, row_count INTEGER NOT NULL,
                recorded_from TEXT NOT NULL, recorded_to TEXT NOT NULL, ingested_at TEXT NOT NULL)""")

    @contextmanager
    def connection(self):
        db = sqlite3.connect(self.directory / "recordings.sqlite3", timeout=30)
        db.execute("PRAGMA synchronous=FULL")
        try:
            with db:
                yield db
        finally:
            db.close()

    def accept(self, recording_id, data, checksum):
        digest, count, start, end = validate(recording_id, data, checksum)
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            existing = db.execute("SELECT sha256 FROM recordings WHERE recording_id=?", (recording_id,)).fetchone()
            if existing:
                if existing[0] != digest:
                    raise FileExistsError("Recording ID already exists with different content")
                return {"sha256": digest, "duplicate": True}
            path = self.directory / (digest + ".jsonl")
            fd, temporary = tempfile.mkstemp(dir=self.directory, prefix="incoming-")
            try:
                with os.fdopen(fd, "wb") as output:
                    output.write(data)
                    output.flush()
                    os.fsync(output.fileno())
                os.replace(temporary, path)
                directory_fd = os.open(self.directory, os.O_RDONLY)
                try:
                    os.fsync(directory_fd)
                finally:
                    os.close(directory_fd)
            finally:
                Path(temporary).unlink(missing_ok=True)
            ingested = datetime.now(timezone.utc).isoformat()
            db.execute("INSERT INTO recordings VALUES (?,?,?,?,?,?)", (recording_id, digest, count, start, end, ingested))
            db.commit()
            return {"sha256": digest, "duplicate": False, "ingestedAt": ingested, "rows": count}


class Receiver(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    store: RecordingStore
    token: str

    def setup(self):
        super().setup()
        self.connection.settimeout(30)

    def log_message(self, *_):
        pass  # Do not put recording names, location data or tokens in access logs.

    def respond(self, status, payload):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(data)
        self.close_connection = True

    def do_GET(self):
        self.respond(200 if self.path == "/health" else 404,
                     {"status": "ready"} if self.path == "/health" else {"error": "Not found"})

    def do_POST(self):
        if self.path != "/ingest":
            self.respond(404, {"error": "Not found"}); return
        expected = ("Bearer " + self.token).encode()
        if not hmac.compare_digest(self.headers.get("Authorization", "").encode(), expected):
            self.respond(401, {"error": "Unauthorized"}); return
        if self.headers.get("Content-Type", "").split(";")[0] != "application/x-ndjson":
            self.respond(415, {"error": "Use application/x-ndjson"}); return
        if self.headers.get("Transfer-Encoding"):
            self.respond(400, {"error": "Content-Length required"}); return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= MAX_BYTES:
                self.respond(413, {"error": "Body must be 1..67108864 bytes"}); return
            data = self.rfile.read(length)
            if len(data) != length:
                raise ValueError("Truncated upload")
            result = self.store.accept(self.headers.get("X-Recording-Id", ""), data,
                                       self.headers.get("X-Content-SHA256", ""))
        except FileExistsError:
            self.respond(409, {"error": "Recording ID conflict"})
        except (ValueError, KeyError, TypeError, UnicodeError):
            self.respond(422, {"error": "Invalid, incomplete or mismatched recording"})
        except (OSError, sqlite3.Error):
            self.respond(503, {"error": "Storage unavailable; retry later"})
        else:
            self.respond(200, result)


def main():
    token = os.environ.get("CANC_UPLOAD_TOKEN", "")
    if len(token) < 32:
        raise SystemExit("Set CANC_UPLOAD_TOKEN to a private random token of at least 32 characters")
    Receiver.token = token
    Receiver.store = RecordingStore(os.environ.get("CANC_DATA_DIR", "./recordings"))
    server = ThreadingHTTPServer((os.environ.get("CANC_BIND", "127.0.0.1"), int(os.environ.get("CANC_PORT", "8787"))), Receiver)
    print("CAN / CONNECT receiver ready; use an HTTPS reverse proxy for Android uploads", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
