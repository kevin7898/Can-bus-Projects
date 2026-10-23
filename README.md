# CAN bus projects

Experiments and applications built around CAN/OBD vehicle data.

## Projects

### [Jetta Recorder Android](jetta-recorder-android/)

An Android-first, local-first driving recorder for the Volkswagen Jetta, initially targeting a OnePlus 6T and OBDLink MX+.

The first hardware milestone establishes a real ELM327/STN connection, records standard OBD-II telemetry, captures raw CAN observations, and exports evidence for decoder development.

> Privacy: raw captures, GPS traces, VINs, and personal vehicle logs are intentionally excluded from this public repository.

### [CAN / CONNECT iOS companion](can-connect-ios/)

Native SwiftUI iPhone companion using the approved paged CAN / CONNECT design. Open `can-connect-ios/CANConnect.xcodeproj` in Xcode to run the sample dashboard, record iPhone GPS trips, import/export recordings, and keep a fuel log. CAN recorder transport and Mac mini backup are not yet configured.
