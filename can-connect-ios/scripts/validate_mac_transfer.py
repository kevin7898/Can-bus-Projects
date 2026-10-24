#!/usr/bin/env python3
"""Exercise the production iOS HTTP client against a native Mac server binary, loopback only."""
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request

root = Path(__file__).resolve().parents[1]
binary = Path(sys.argv[1]).resolve()
# This is deliberately a public synthetic fixture credential, never the user's pairing token.
token = "synthetic-ios-transfer-test-token"
with tempfile.TemporaryDirectory(prefix="canconnect-ios-mac-test-") as folder:
    folder = Path(folder)
    probe = folder / "probe"
    sources = ["Core/Models.swift", "Core/VehicleProfile.swift", "Core/ScannerReadings.swift", "Services/VehicleIdentification.swift", "Services/MacServer.swift"]
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", *[str(root / "CANConnect" / p) for p in sources], str(root / "scripts/mac_transfer_probe.swift"), "-o", str(probe)], check=True)
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    address = f"http://127.0.0.1:{port}"
    env = dict(os.environ, CAN_CONNECT_TEST_TOKEN=token)
    server = subprocess.Popen([str(binary), "--headless", "--library", str(folder / "library"), "--port", str(port)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        for _ in range(80):
            if server.poll() is not None:
                raise RuntimeError(server.stderr.read().decode())
            try:
                request = urllib.request.Request(address + "/v1/health", headers={"Authorization": "Bearer " + token})
                with urllib.request.urlopen(request, timeout=2):
                    break
            except OSError:
                time.sleep(.1)
        else:
            raise RuntimeError("Mac fixture did not start")
        subprocess.run([str(probe), address], env=env, check=True, timeout=30)
        import json
        manifest = json.loads((folder / "library/library.json").read_text())
        assert len(manifest["receipts"]) == 2
        assert len(manifest["vehicles"]) == 1
        assert len(list((folder / "library/Originals").iterdir())) == 2
        print("Mac's isolated library contains one synthetic vehicle and exactly two preserved originals / receipts.")
    finally:
        server.terminate()
        try:
            server.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait()
