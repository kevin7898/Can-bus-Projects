# iPhone test guide — build 7

CAN Connect 1.0.0 (6) is development-signed and installed over the existing app. Existing recordings, vehicle IDs and histories are preserved, with private backups outside Git. The locked dashboard composition and styling are unchanged.

The physical 2014 Jetta TDI DSG/MX+ tests supplied 13 standard PIDs and 20 available fields. RPM, actual boost, exhaust temperatures, airflow and DPF pressure/regeneration now use the Android Pocket Recorder's reviewed decoding. A new recording and the earlier extended recording reached the native Mac, with original bytes, hashes, timestamps, ECU identity and processed fields verified. See [JETTA_2014.md](JETTA_2014.md) and [MXPLUS.md](MXPLUS.md).

Build 7 stops acquisition on disconnect, drains any in-flight response through its prompt, and reuses the foreground MFi session. A teardown barrier after explicit cancel prevents the next request from racing the previous operation. The underlying session closes on app backgrounding or transport failure. Unit tests cover cancellation during both opening and a pending read, with direct replacement and explicit Disconnect. Repeated physical reconnect checks and any remaining limits are recorded in PR #7 and HARDWARE_VERIFICATION.md.

## First checks on the phone

1. Open **CAN Connect**. Keep the existing sample profile for previews, or use the header's vehicle menu → **Add a vehicle** for your real vehicle. Enter/review make and model, tap the keyboard’s Done key or scroll to dismiss it, then Save. The keyboard and setup screen should dismiss; verify the vehicle name and Vehicle tab. Switch profiles and confirm the separate histories.
2. **GPS:** Live → source menu → iPhone GPS → Start GPS recording. Allow location access when prompted and wait for a real fix. Finish and check the saved trip, its map and export. A short recording without a GPS fix has no measured route and is excluded from transfers. Test screen-lock recording separately with actual movement.
3. **Scanner:** this build supports Wi-Fi ELM327 TCP adapters. Join the adapter Wi-Fi, turn on ignition, select the real vehicle, then Connect → CAN recorder. Enter the adapter's documented address and port. Confirm the vehicle. Supported readings should appear in Live; unknown readings stay blank. Keep the app visible for scanner recording, then Finish. Build 7 also provides OBDLink MX+ Bluetooth through the connection selector; see MXPLUS.md. Other Bluetooth/MFi adapters remain unsupported.
4. **Mac transfer:** after recording, join a network that can reach your Mac. In the native Mac app's Server page, start the server and explicitly allow your private LAN. Pair from iPhone Connect using the Mac address and copied token. Never put the token in a GitHub issue or exported test report. Transfers → Send / check recordings queues measured real recordings; use Transfer queue → Retry / check receipts until the Mac reports processing completed. Verify the saved trip on the Mac and retain the iPhone original.
5. **Recovery:** relaunch the app and check saved history/vehicle selection. Test an unreachable server or scanner disconnect and verify that recordings remain available. Record any failure's visible message, source, app build and reproduction steps without sharing personal captures or credentials.

Moving-route GPS accuracy, trusted-scanner comparison, load/long-drive conditions and interruption recovery still require hardware acceptance. Short successful parked tests do not establish those results. Full checks are in [HARDWARE_VERIFICATION.md](HARDWARE_VERIFICATION.md).

## Rebuild or reinstall

Open `CANConnect.xcodeproj` in Xcode, select CANConnect and the connected iPhone, choose your development team in Signing & Capabilities, and Run. Keep bundle ID `com.canconnect.companion` to update this app. Do not uninstall it to resolve signing issues; uninstalling removes local history.

The development profile used for this installation expires October 30, 2026. If iOS stops allowing the development app to launch after expiry, rebuild/reinstall with a refreshed profile while preserving the app's data. Signed app bundles and private signing settings stay outside the repository; no TestFlight/App Store release is implied.
