import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from receiver import RecordingStore, validate


def recording():
    return (json.dumps({"type": "session_start", "schemaVersion": 1, "vehicleId": "test", "recordedAt": "2026-10-01T12:00:00Z"}) + "\n" +
            json.dumps({"type": "obd", "recordedAt": "2026-10-01T12:00:01Z", "pid": "0D", "signals": []}) + "\n").encode()


class ReceiverTests(unittest.TestCase):
    def test_exact_bytes_retained_and_delayed_ingestion_kept_separate(self):
        with tempfile.TemporaryDirectory() as folder:
            store = RecordingStore(folder); data = recording(); digest = hashlib.sha256(data).hexdigest()
            ack = store.accept("test.jsonl", data, digest)
            self.assertEqual(ack["sha256"], digest)
            self.assertEqual((Path(folder) / (digest + ".jsonl")).read_bytes(), data)
            with store.connection() as db:
                start, end, ingested = db.execute("SELECT recorded_from,recorded_to,ingested_at FROM recordings").fetchone()
            self.assertTrue(start.startswith("2026-10-01T12:00:00"))
            self.assertTrue(end.startswith("2026-10-01T12:00:01"))
            self.assertEqual(ingested, ack["ingestedAt"])

    def test_duplicate_is_acknowledged_without_another_database_row(self):
        with tempfile.TemporaryDirectory() as folder:
            store = RecordingStore(folder); data = recording(); digest = hashlib.sha256(data).hexdigest()
            store.accept("test.jsonl", data, digest)
            self.assertTrue(store.accept("test.jsonl", data, digest)["duplicate"])
            with store.connection() as db:
                self.assertEqual(db.execute("SELECT COUNT(*) FROM recordings").fetchone()[0], 1)

    def test_conflicting_id_does_not_overwrite_original(self):
        with tempfile.TemporaryDirectory() as folder:
            store = RecordingStore(folder); data = recording(); digest = hashlib.sha256(data).hexdigest()
            store.accept("test.jsonl", data, digest)
            changed = data.replace(b'"0D"', b'"0C"')
            with self.assertRaises(FileExistsError):
                store.accept("test.jsonl", changed, hashlib.sha256(changed).hexdigest())
            self.assertEqual((Path(folder) / (digest + ".jsonl")).read_bytes(), data)

    def test_bad_checksum_truncation_and_path_traversal_are_rejected(self):
        data = recording(); digest = hashlib.sha256(data).hexdigest()
        for name, body, checksum in [("test.jsonl", data, "0" * 64), ("test.jsonl", data[:-1], hashlib.sha256(data[:-1]).hexdigest()), ("../test.jsonl", data, digest)]:
            with self.assertRaises(ValueError):
                validate(name, body, checksum)

    def test_timestamp_requires_timezone(self):
        data = recording().replace(b"12:00:01Z", b"12:00:01")
        with self.assertRaises(ValueError):
            validate("test.jsonl", data, hashlib.sha256(data).hexdigest())


if __name__ == "__main__":
    unittest.main()
