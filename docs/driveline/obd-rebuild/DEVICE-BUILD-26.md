# On-car development build 26

Installed 2026-10-26 on the connected physical iPhone 17 Pro Max.

- DriveLine 1.0.0 (26), bundle `com.canconnect.companion`.
- Debug build with `SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG DRIVELINE_OBD_REBUILD`; compiler invocation verified both flags. The default is rebuilt acquisition even after ordinary Home Screen relaunches. Explicit engine injection remains available to tests. Release behavior is unchanged.
- Signed device build succeeded with Xcode 27.2. Both app and Live Activity extension use build 26.
- In-place install succeeded. Device application inventory independently confirmed build 26.
- Launch with no arguments succeeded; returned PID 15841 and its exact installed executable were independently matched in the device process inventory.
- No data reset performed. No replay or UI-testing arguments used.
- Build log: `/tmp/driveline-car-build26.log`; app: `/tmp/DriveLineOBDCarTest26/Build/Products/Debug-iphoneos/CANConnect.app`.
- Optional enhanced reads and response timing hints remain disabled. Actual MX+, vehicle, GPS, background, ignition and road acceptance are pending; see HARDWARE-CHECKLIST.md.

Reproduce from this checkout with automatic signing and the connected device destination:

```sh
xcodebuild -project can-connect-ios/CANConnect.xcodeproj -scheme CANConnect \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/DriveLineOBDCarTest26 -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=BYEVD8567N CURRENT_PROJECT_VERSION=26 \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG DRIVELINE_OBD_REBUILD' build
```
