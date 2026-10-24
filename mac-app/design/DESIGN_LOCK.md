# CAN / CONNECT Mac — locked design v1.0

Approved by Kevin on October 23, 2026: “I like it. Lock it, github it so I can mac app it later.”

This is the approved visual and interaction baseline for the future native macOS app. Preserve its composition, navigation, information density, and dark graphite / Volkswagen-blue palette. Further visual redesign requires Kevin's direction; production wiring, accessibility improvements, and faithful native control adaptations may proceed without redesigning the app.

## Approved composition

- A desktop window designed for a widescreen monitor, with a persistent left sidebar and vehicle switcher.
- Overview opens with a large driving-history map, four compact summary readings, recent drives, and a right-hand inspector containing the vehicle snapshot, data health, and recent activity.
- The desktop layout uses available width; smaller previews reflow rather than clip. The mobile reflow is preview compatibility, not the iOS design.
- Workspace navigation: Overview, Trips, Compare, Signals, Garage. Infrastructure navigation: Imports, Server.
- A persistent footer distinguishes service state, devices, and data provenance.
- Multiple vehicles are first-class. Jetta TDI, F-150 XLT, and CB500X ABS are illustrative profiles, not hardcoded application limits.

## Approved interactions

- Overview period selection: 7 days, 30 days, all time.
- Map zoom, recenter, expand / restore, road layer toggle, panning, and road corridor inspection.
- Trip selection opens its map, statistics, speed chart, and playback scrubber. GPS-only recordings leave vehicle-dependent values blank.
- Compare shows two drive selections side by side with shared map zoom and center.
- Signals has independently selectable readings; duplicate signals are allowed. Boost is displayed relative to atmospheric pressure.
- Garage supports vehicle switching and an add-vehicle flow with simulated scanner detection, review, and manual entry.
- Imports presents recording intake, transfer policy, and a queue; Server presents services, devices, storage, retention, and background behavior.
- Customize mode exposes summary reorder / selection and map placement without making normal dashboard interactions an editing operation.

## Production requirements retained from the broader platform design

These are requirements for the eventual app; the prototype only demonstrates part of them.

- Persist per-vehicle map center, zoom, layers, periods, and dashboard layout across launches.
- Complete the snap-grid widget system: drag, resize, add, remove, independent configurations, and saved layouts. Prototype editing is limited and session-only.
- Keep source, freshness, and availability explicit. Never substitute sample values for unavailable hardware signals.
- Preserve original recordings, timestamps, source identity, and unit definitions. Distinguish GPS, diagnostic polling, and raw CAN.
- Support iOS companions first, with Android companion / recorder compatibility in the data contract.
- Prefer Wi-Fi for large raw recordings; retain local copies until the server acknowledges receipt.
- Keep background ingestion independent of whether the app window is open. Raw CAN rolling retention target: 5,000 km; preserve derived summaries.

## Prototype boundary

The preview is a visual reference with illustrative data. It is not an Xcode project, native app, connected server, diagnostic client, or real import engine. Vehicle detection, server controls, transfer state, log processing, and playback are simulated. File selection records names and sizes only; it does not upload or parse logs. Changes exist only in the preview session.

The municipal road geometry is real; highlighted driving history and telemetry are illustrative and must not be treated as actual recorded personal trips. No VINs, credentials, or vehicle captures are included.
