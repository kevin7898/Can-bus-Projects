# CAN / CONNECT — iOS companion

Native SwiftUI iPhone app in the approved graphite/blue design, with five fixed tabs, pages within tabs, independent reading cards, and a fixed recording control. Open **CANConnect.xcodeproj**, select **CANConnect**, and Run in Xcode. Minimum iOS: 17.0; no package dependencies. Choose a development team for installation on a physical phone.

## Use your vehicle

First launch opens vehicle setup. Enter details manually, explicitly look up a VIN using NHTSA, or read VIN/protocol/supported PIDs through a Wi-Fi ELM327 adapter, then review and save. VIN lookup sends the VIN to NHTSA only after your action. Manual setup works offline. Scanner setup remembers its address and port. The vehicle menu manages separate profiles, trips, fuel entries and dashboard preferences. Switching profiles is blocked during recording; a scanner connection is cleared when switching vehicles.

The sample dashboard is opt-in during onboarding. Sample feeds and trips remain labelled; they are excluded from Mac transfers. Real profiles initially use iPhone GPS and show unavailable vehicle values until actual readings are available.

## Record

- **iPhone GPS:** choose it in Live and start recording. Location permission is requested when needed. Accepted GPS points retain their timestamps, accuracy and optional speed. Poor fixes, jumps and stationary jitter are filtered; distance excludes gaps over 30 seconds. GPS recording can continue with the location indicator while the phone is locked. GPS does not supply engine/fuel values.
- **Wi-Fi scanner:** join the adapter Wi-Fi, enable ignition, choose a real vehicle, then Connect → CAN recorder. Enter the adapter's local address/port and confirm the vehicle. The selected VIN must match the scanner VIN when both are present. Without a VIN, check the selected vehicle yourself. Continuous standard Mode 01 polling uses only PIDs confirmed by that connection. Supported readings include speed, RPM, coolant, MAP, barometric pressure, fuel rate/level, ambient temperature, voltage, intake temperature, oil temperature and engine load. The locked cards retain their independent selections. Unsupported, conflicting and stale readings are unavailable; gauge boost requires measured MAP and barometric pressure, and instantaneous L/100 km requires measured fuel rate and speed.
- Scanner recordings keep **each individual response**, its command, decoded values and receipt timestamp. No previous readings are filled into later samples. Distance integrates measured vehicle speed over intervals of at most 10 seconds. Fuel totals require at least 80% measured fuel-rate time coverage; economy additionally requires 80% speed coverage and more than 0.1 km. Gaps are excluded. Fuel totals are unavailable when the adapter/vehicle lacks fuel rate.
- **Keep the app visible for Wi-Fi OBD recording.** The screen stays awake during recording. Backgrounding saves the current recording and disconnects the scanner; this build does not claim background Wi-Fi acquisition. GPS is a separate source and is not simultaneously recorded with OBD in this version.
- Finish saves atomically. Checkpoints are saved about every five seconds; a terminated app recovers the last saved draft exactly once. Failed saves leave the active draft available for retry. A scanner recording stops at 100,000 responses so a new recording can be started.

Trips include route maps when recorded, scanner response counts and saved readings, JSON import/export, and deletion. Queued originals cannot be deleted before processing acknowledgment. Vehicle pages show actual saved readings from the latest drive. The fuel log supports full/partial fills and tank-to-tank economy independently of OBD-derived drive totals.

## Transfer to your private Mac

Use the native Mac app's API v1 on `feature/mac-native-app`. Start its Server and explicitly enable local-network access on the Mac. This iOS work does not change your Mac's network configuration. A loopback-only Mac listener cannot be reached by a physical iPhone.

1. Connect the phone to a network that can reach the Mac (often your home Wi-Fi after leaving the adapter Wi-Fi).
2. In Connect, open Mac mini M4 / Server setup. Enter its private URL, e.g. `http://mac-mini.local:8765`, and the pairing token copied from the Mac. **Pair & test server** verifies the API and saves the token in Keychain, separately from application state and exports. HTTP uses an unencrypted trusted LAN; HTTPS is supported when configured on the server.
3. Open Transfers → **Send / check recordings**. Real recordings with measured points/responses are queued durably and sent. Sample recordings are excluded. The phone creates a missing Mac vehicle profile or matches an existing ID/VIN without overwriting its details.
4. A stored/queued Mac receipt means **awaiting processing**. The phone verifies SHA-256, byte count, vehicle and receipt identity, and marks completion only when the Mac reports a processed trip. Use the transfer queue to retry/check. A failed Mac import must be retried in the Mac app, then checked on the phone.

Transfers run while the app is open, on explicit action; no background uploader is claimed. Retries use frozen identical payload bytes, which the Mac deduplicates by content hash. Pending items retain their destination when server setup changes. Originals stay on the phone after success. Wi-Fi policy disables cellular access for full recordings; cellular is allowed only when Wi-Fi-only is off and cellular is enabled. Separate summary uploads are unavailable. Public hosts, embedded URL credentials, arbitrary paths and redirects are rejected. No cloud, tunnel, VPN or public server is configured.

## Validation

Product → Test (⌘U), or from the repository root:

```sh
xcodebuild test -parallel-testing-enabled NO \
  -project can-connect-ios/CANConnect.xcodeproj -scheme CANConnect \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' CODE_SIGNING_ALLOWED=NO
```

Choose an installed simulator. The suite covers decoder formulas and ambiguity, real loopback TCP prompt framing, VIN mismatches, freshness/disconnect, vehicle isolation, source semantics, recording checkpoints/recovery, fuel coverage, archive/persistence, transfer queue retention, private endpoint rules, HTTP failures, vehicle matching and receipt integrity. Native UI smoke tests exercise onboarding, navigation, sample recording and scanner recording through a loopback TCP fixture. **All scanner fixture data is synthetic; passing these tests is not vehicle acceptance.**

The GitHub Actions iOS workflow builds/tests the project and retains the result bundle and screenshots. Optional `scripts/make_project.py` regenerates project references after adding source files; opening/building the checked-in project needs no generation step.

To test the same production transfer-client sources against the actual native Mac server using a temporary synthetic library:

```sh
python3 can-connect-ios/scripts/validate_mac_transfer.py /path/to/CANConnect.app/Contents/MacOS/CANConnect
```

For an iOS simulator check through the actual app's URLSession/ATS policy, pairing Keychain, durable queue, processing receipt and relaunch state, run `scripts/validate_ios_mac_queue.py MAC_BINARY XCTESTRUN SIMULATOR_UDID`. Use the `.xctestrun` generated by a normally signed Xcode build-for-testing (simulator ad-hoc signing works with `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`). Unsigned simulator builds can run the ordinary suite but cannot save pairing tokens to Keychain. The helper starts a temporary loopback-only Mac service and injects the synthetic endpoint into a temporary test-run configuration; it never uses your personal library or token. The native-Mac test is skipped by ordinary CI runs.

See [HARDWARE_VERIFICATION.md](HARDWARE_VERIFICATION.md) for outstanding acceptance checks and [INTEGRATION.md](INTEGRATION.md) for contracts. Bluetooth/MFi adapters, raw CAN, manufacturer-specific DPF/diagnostics, simultaneous GPS+OBD recording, automatic background transfer, charging/kWh logging and distribution signing remain unimplemented.

Personal data stays in the app's Application Support directory; uninstalling removes it. Export/transfer before uninstalling. No personal VINs, captures or pairing credentials belong in Git. Map attribution: City of Nanaimo open data (bundled illustrative map) and Apple Maps (recorded route maps).
