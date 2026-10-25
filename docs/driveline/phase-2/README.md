# DriveLine Phase 2 evidence

Phase 2 starts at pushed Phase 1 commit
`3750fa813127ac85e978dd42b10a9c40e636dc2a`. It establishes the Drive Ledger
semantic themes, persisted appearance selection, platform navigation shells and
shared state components. It does not implement Phase 3 content or change the
recording contract, telemetry calculations, lifecycle, or storage architecture.

## Theme and appearance

Both apps expose the same semantic roles: app and navigation backgrounds;
primary, raised and field surfaces; primary, secondary and tertiary text;
normal and selected borders; cobalt action/selection; healthy green;
fuel/queued/stale amber; recording/fault red; unavailable grey; and accessible
chart and route series. Compatibility aliases keep existing functional views on
the semantic palette while later phases progressively adopt the named roles.

`DriveLineAppearance` persists `System`, `Light`, or `Dark` under
`driveline.appearance`. `System` is the default. Each app resolves it once at its
scene/root boundary; production sheets and full-screen covers inherit that
choice. Explicit light and dark preview fixtures remain available.

Normal-size semantic text and action colours were checked against the app
background. Light ratios range from 4.57:1 to 16.07:1 and dark ratios from
5.23:1 to 17.61:1. Status components pair colour with a title and SF Symbol,
and availability values include text provenance rather than relying on colour.

## Navigation contracts

- Mac primary navigation is Today, Drives, Fuel, Signals and Garage. Compare is
  inside Drives. Imports and Server remain reachable in the persistent service
  strip and overflow menu; menu-bar and headless server entry points are
  unchanged.
- iPhone tabs are Today, Drives, Record, Garage and More. More retains
  connections, transfers, Mac pairing/queue, settings and vehicle data. Garage
  owns vehicle management. Recording deep links and the active-recording
  indicator select Record.

The shared package defines and tests the complete destination sets, secondary
capabilities and recording deep-link route independently of the SwiftUI shells.

## Shared components and fixtures

Mac and iPhone include `StatusPill`, `SourceBadge`, `FreshnessLabel`,
`AvailabilityValue`, `MetricTile`, `SectionCard`, `RecoveryBanner`, and
`EmptyStateCard`. Preview galleries cover healthy, stale, unavailable, queued
and recording states in both themes. Navigation previews cover both themes on
both platforms, and the settings fixture exposes the three-way appearance
picker.

## Local validation

Commands were run from the repository root unless a subshell is shown:

```sh
(cd shared/DriveLineShared && swift test)
(cd mac-app && swift test)
xcodebuild build -project mac-app/CANConnect.xcodeproj -scheme CANConnect \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/driveline-p2-mac-build-final CODE_SIGNING_ALLOWED=NO
python3 mac-app/scripts/api_integration.py \
  /tmp/driveline-p2-final-mac/Build/Products/Debug/CANConnect.app/Contents/MacOS/CANConnect
xcodebuild test -parallel-testing-enabled NO \
  -project can-connect-ios/CANConnect.xcodeproj -scheme CANConnect \
  -destination 'platform=iOS Simulator,name=DriveLine iPhone 17 Pro Max' \
  CODE_SIGNING_ALLOWED=NO
```

- Shared package: 11 passed, 0 failed.
- Mac Swift package: 22 passed, 0 failed. The existing non-failing
  `pkg-config` / sqlite3 metadata warning remains; SQLite tests pass.
- Mac Xcode Debug build: passed for the macOS destination.
- Mac isolated API integration: passed authentication, schema-2 mixed GPS/OBD
  and fill transfer, stable identities, exact-original storage, hash
  deduplication/conflict handling, receipt processing, trip retrieval and
  vehicle validation.
- iPhone 17 Pro Max / iOS 27.2 unit and UI suite: 112 passed, 0 failed,
  3 expected skips (115 total).
- iPhone SE (3rd generation) / iOS 27.2 at
  `accessibility-extra-extra-extra-large`: the primary-navigation and More route
  UI test passed, 1 passed and 0 failed.

The expected skips are the opt-in native-Mac loopback integration and the two
Live Activity presentation tests that require lock-screen/Dynamic Island
surfaces.

## Layout and accessibility checks

- Mac windows were inspected at a 1080 by 720 content minimum and a 1540 by
  1000 widescreen size. Primary destinations and the Imports/Server strip remain
  visible without clipped labels or controls.
- With Full Keyboard Access enabled for the isolated validation launch, Tab
  focus reached Today, Drives, Fuel, Signals, Garage, the vehicle picker,
  Imports, Server and the overflow menu. The temporary global preference was
  restored after the check.
- iPhone 17 Pro Max was checked in light and dark appearance. An iPhone SE
  (3rd generation) was checked at the largest Dynamic Type category; all five
  tab titles and Record controls remained reachable and unclipped.
- Light and dark screenshots were visually inspected for text, status icon,
  selection, border and control contrast. Native map tiles retain their own
  MapKit styling while surrounding DriveLine chrome follows the selected theme.

## Screenshots

- [Mac light, widescreen](screenshots/mac-navigation-light-widescreen.png)
- [Mac light, 1080 minimum](screenshots/mac-navigation-light-1080x720.png)
- [Mac dark, widescreen](screenshots/mac-navigation-dark-widescreen.png)
- [iPhone 17 Pro Max Today, light](screenshots/iphone-17-pro-max-today-light.png)
- [iPhone 17 Pro Max Record, light](screenshots/iphone-17-pro-max-record-light.png)
- [iPhone 17 Pro Max Today, dark](screenshots/iphone-17-pro-max-today-dark.png)
- [iPhone 17 Pro Max Record, dark](screenshots/iphone-17-pro-max-record-dark.png)
- [iPhone SE Record, largest Dynamic Type](screenshots/iphone-se-dynamic-type-record-light.png)

## Known limitations and remaining hardware validation

Screenshots use isolated sample libraries and simulator-only sample telemetry;
sample data stays labeled and excluded from real totals. Physical iPhone,
OBDLink MX+, Jetta, Bluetooth discovery/reconnect, background GPS, lock-screen
Live Activity, Dynamic Island, real Mac-to-iPhone LAN transfer and an on-road
recording still require hardware validation. Phase 3 destination content and
later information-density refinements are intentionally not included.
