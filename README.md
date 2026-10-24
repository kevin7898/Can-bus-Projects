# CAN bus projects

Experiments and applications built around CAN/OBD vehicle data.

## Projects

### [Jetta Recorder Android](jetta-recorder-android/)

An Android-first, local-first driving recorder for the Volkswagen Jetta, initially targeting a OnePlus 6T and OBDLink MX+.

The first hardware milestone establishes a real ELM327/STN connection, records standard OBD-II telemetry, captures raw CAN observations, and exports evidence for decoder development.

> Privacy: raw captures, GPS traces, VINs, and personal vehicle logs are intentionally excluded from this public repository.

### [CAN / CONNECT iOS companion](can-connect-ios/)

Native SwiftUI iPhone companion using the locked paged CAN / CONNECT design. Open `can-connect-ios/CANConnect.xcodeproj` in Xcode for vehicle onboarding, GPS and Wi-Fi ELM327 recording, fuel logging, import/export and verified transfers to the native Mac server. Hardware acceptance remains outstanding; see the iOS hardware checklist.

### [CAN / CONNECT Mac — locked design](mac-app/design/)

Approved widescreen Mac UI baseline, interactive preview, and native macOS implementation handoff. The design is locked; hardware, import, and server behavior in the preview uses illustrative data.
