#!/usr/bin/env python3
"""Run the iOS queue test against a real native Mac service with synthetic data only.

Usage: validate_ios_mac_queue.py MAC_BINARY XCTESTRUN SIMULATOR_UDID
Build the iOS test runner first with Xcode build-for-testing.
"""
import os
from pathlib import Path
import plistlib
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request

binary, run_path = [Path(value).resolve() for value in sys.argv[1:3]]
device = sys.argv[3]
token = "synthetic-ios-transfer-test-token"
with tempfile.TemporaryDirectory(prefix="canconnect-simulator-mac-") as directory:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    address = f"http://127.0.0.1:{port}"
    server = subprocess.Popen([str(binary), "--headless", "--library", directory, "--port", str(port)], env=dict(os.environ, CAN_CONNECT_TEST_TOKEN=token), stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    temporary_run = None
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
        configuration = plistlib.loads(run_path.read_bytes())
        if "TestConfigurations" in configuration:
            targets = [target for test_configuration in configuration["TestConfigurations"] for target in test_configuration["TestTargets"]]
        else:
            targets = [value for value in configuration.values() if isinstance(value, dict) and "TestBundlePath" in value]
        if not targets:
            raise RuntimeError("No test targets found in the Xcode run configuration")
        for target in targets:
            target.setdefault("EnvironmentVariables", {})["CAN_CONNECT_MAC_TEST_URL"] = address
        # __TESTROOT__ is relative to this file, so preserve the original run-file directory.
        with tempfile.NamedTemporaryFile(prefix="CANConnect-MacFixture-", suffix=".xctestrun", dir=run_path.parent, delete=False) as handle:
            temporary_run = Path(handle.name)
            handle.write(plistlib.dumps(configuration))
        subprocess.run(["xcodebuild", "test-without-building", "-xctestrun", str(temporary_run), "-destination", f"platform=iOS Simulator,id={device}", "-only-testing:CANConnectTests/TransferTests/testNativeMacServerQueueWhenLoopbackIntegrationEnabled"], check=True, timeout=180)
    finally:
        if temporary_run:
            temporary_run.unlink(missing_ok=True)
        server.terminate()
        try:
            server.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait()
