#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

required = [
    "settings.gradle.kts",
    "build.gradle.kts",
    "app/build.gradle.kts",
    "app/src/main/AndroidManifest.xml",
    "app/src/main/java/ca/jettatelemetry/app/MainActivity.kt",
    "app/src/main/java/ca/jettatelemetry/app/obd/ObdLinkTransport.kt",
    "app/src/main/java/ca/jettatelemetry/app/obd/Elm327Client.kt",
    "app/src/main/java/ca/jettatelemetry/app/obd/Mode01Decoder.kt",
    "app/src/main/java/ca/jettatelemetry/app/obd/RawCanParser.kt",
    "app/src/main/java/ca/jettatelemetry/app/obd/JettaDiagnosticDiscovery.kt",
    "app/src/main/java/ca/jettatelemetry/app/recording/WebCanCsv.kt",
    "app/src/main/java/ca/jettatelemetry/app/recording/DiagnosticDiscoveryCsv.kt",
    "app/src/main/java/ca/jettatelemetry/app/data/ObdRepository.kt",
    "app/src/main/java/ca/jettatelemetry/app/ui/JettaRecorderScreen.kt",
]
for relative in required:
    assert (ROOT / relative).is_file(), f"missing {relative}"

manifest = (ROOT / "app/src/main/AndroidManifest.xml").read_text()
assert "android.permission.BLUETOOTH_CONNECT" in manifest
assert 'android:screenOrientation="unspecified"' in manifest

transport = (ROOT / "app/src/main/java/ca/jettatelemetry/app/obd/ObdLinkTransport.kt").read_text()
assert "00001101-0000-1000-8000-00805F9B34FB" in transport
assert "createRfcommSocketToServiceRecord" in transport

decoder = (ROOT / "app/src/main/java/ca/jettatelemetry/app/obd/Mode01Decoder.kt").read_text()
for pid in ("0C", "0D", "05", "0B", "33"):
    assert f'"{pid}"' in decoder, f"missing PID {pid} decoder"

repository = (ROOT / "app/src/main/java/ca/jettatelemetry/app/data/ObdRepository.kt").read_text()
assert "gaugeBoostKpa" in repository
assert re.search(r'query\("010C"', repository)
assert re.search(r'query\("010D"', repository)
assert "startRawCanProbe" in repository
assert "startDiagnosticDiscovery" in repository
assert "readDataByIdentifier" in repository
assert "STCMM0" in (ROOT / "app/src/main/java/ca/jettatelemetry/app/obd/Elm327Client.kt").read_text()
assert "STP 31" in (ROOT / "app/src/main/java/ca/jettatelemetry/app/obd/Elm327Client.kt").read_text()

workflow = (ROOT.parent / ".github/workflows/android-debug.yml").read_text()
assert "assembleDebug" in workflow
assert "upload-artifact" in workflow

discovery = (ROOT / "app/src/main/java/ca/jettatelemetry/app/obd/JettaDiagnosticDiscovery.kt").read_text()
assert "service 0x22" in discovery.lower()
assert "OBDb/Volkswagen-Jetta" in discovery
assert 'const val REQUEST_HEADER = "7E0"' in discovery

print(f"static checkpoint OK: {len(required)} required files, Bluetooth SPP, raw CAN and read-only UDS discovery")

