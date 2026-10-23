# CAN / CONNECT — iOS companion

A native SwiftUI iPhone app ported from Kevin's locked CAN / CONNECT design. Open the checked-in Xcode project directly; there are no package dependencies or project generators to install.

## Open and run

1. Clone or download this branch, then open **`can-connect-ios/CANConnect.xcodeproj`** in Xcode 16 or newer.
2. Select the **CANConnect** scheme and an iPhone simulator, then press **Run** (⌘R).
3. To run on your iPhone, select your Apple development team under **Signing & Capabilities**, choose your phone, and Run. Use a unique bundle identifier if Xcode asks.

Minimum iOS version: **17.0**. Portrait iPhone layout. The sample dashboard works immediately in the simulator. GPS needs location permission and movement (or a simulated route in Xcode).

## Working features

- Five fixed bottom tabs: Overview, Trips, Live, Vehicle and Connect.
- Horizontal pages inside tabs, with labelled page controls; no long dashboard scroll.
- Live Drive, Engine and Economy pages; the recording button stays anchored.
- Independent signal selection for each card, with duplicates allowed and choices saved.
- Sample CAN recording that creates a saved sample trip.
- Real iPhone GPS recording: route, distance, current speed and duration. Location is requested only after you tap Start GPS recording. Active recordings can continue with the phone locked using the visible iOS location indicator.
- GPS accuracy, stale fixes, stationary jitter and implausible jumps are filtered. Gaps over 30 seconds do not invent distance.
- Trip filters, screen-sized pagination, detail maps, deletion, JSON import and export. Reimporting the same IDs does not duplicate trips.
- Fuel log with full and partial fills, validation, history and tank-to-tank economy between full fills. Demo entries are excluded from real calculations.
- Reorderable Overview summary cards, local preferences and sample-history removal.
- Atomic on-device storage. An interrupted recording is recovered on the next launch using the last saved checkpoint.
- Bundled offline Nanaimo road geometry for the approved overview design; native Apple Maps for recorded routes.

## Connection status

The CAN feed is explicitly a **sample feed**. GPS-only drives have no engine or fuel values. The Vehicle snapshot is explicitly sample recorded data. Bluetooth CAN transport and the Mac mini server API are not implemented in this first native port; Connect shows them as not configured, and transfer preferences are saved without claiming uploads occurred.

The existing Android recorder exports raw CAN CSV for decoder development. This iOS build imports the versioned CAN Connect **JSON** format described in `INTEGRATION.md`; it does not yet decode those raw CSV captures.

## Tests

Use **Product → Test** (⌘U). The project includes six unit tests for GPS validation, recording source semantics, partial-fill economy, archive validation, persistence, and independent signal settings, plus a UI smoke test that navigates tabs and pages and records a sample drive.

The repository's `iOS companion` GitHub Actions workflow builds and tests on a macOS iPhone simulator and saves the Xcode results bundle. Test launch data is isolated from normal app data.

Command line on a Mac:

```sh
xcodebuild test -project CANConnect.xcodeproj -scheme CANConnect \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

Choose an installed simulator name if yours differs. The optional `scripts/make_project.py` regenerates the checked-in project deterministically after adding source files; ordinary users do not need it.

## Design baseline and data

Visual baseline v1.0, approved October 23, 2026: dark graphite, VW blue, compact metrics, phone-sized pages and fixed navigation. This port keeps that direction. Native permission prompts, file pickers and forms use iOS conventions.

Sample trip names and Nanaimo road coverage are illustrative; they are not personal GPS recordings. No VIN, credentials or personal vehicle captures are included. Real records remain in the app's Application Support directory until you export or delete them. Removing the app removes its local data. Export recordings before uninstalling if you want to keep them. Server backup is not active.

Map attribution: City of Nanaimo open data (road, water and park geometry) and Apple Maps (expanded/native route maps). See `INTEGRATION.md` for source endpoints.
