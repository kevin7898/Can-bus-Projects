"""Catch a packaging success that omits Kotlin activity classes (a startup failure)."""
import sys
import zipfile

required = [
    "Lca/jettatelemetry/app/pocket/PocketRecorderActivity;",
    "Lca/jettatelemetry/app/pocket/PocketRecorderService;",
    "Lca/jettatelemetry/app/pocket/PocketUploadWorker;",
    "Lca/jettatelemetry/app/pocket/ObservedJettaProfile;",
    "Lca/jettatelemetry/app/obd/ObdLinkTransport;",
]
with zipfile.ZipFile(sys.argv[1]) as apk:
    dex = [apk.read(name) for name in apk.namelist() if name.endswith(".dex")]
    for name in required:
        assert any(name.encode() in data for data in dex), f"Missing runtime class: {name}"
print(f"APK runtime-class verification passed: {len(required)} classes")
