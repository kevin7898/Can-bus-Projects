# Native Mac build handoff

Build the CAN / CONNECT native macOS app from the approved v1.0 design in this directory. Read `DESIGN_LOCK.md`, then open `preview.html` and use `source.html` as the inspectable reference. Preserve the design; implement the missing behavior behind it.

## Suggested implementation structure

Use a native SwiftUI application, with AppKit where required for desktop window behavior, file access, commands, and background lifecycle. Treat this as an implementation direction, not a selected deployment target or dependency version. Confirm the installed Xcode / macOS toolchain before creating the project.

| Prototype area | Native responsibility |
| --- | --- |
| Sidebar and vehicle picker | Application navigation and selected vehicle state |
| Overview and Customize | Persistent widget layout, per-widget settings, period filters |
| Your roads and inspector | Recorded-GPS history, corridor selection, saved map state |
| Trips | Queryable trip history, source-aware statistics, aligned chart and map playback |
| Compare | Two independent recording selections with shared geographic view state |
| Signals | Source-aware signal catalog, independent card settings, correct units and availability |
| Garage | Vehicle identity, manual setup, scanner-assisted discovery and user review |
| Imports | Format detection, vehicle matching, durable queue, duplicate detection and receipts |
| Server | Ingestion, processing, companion connectivity, retention, backup and service health |

Keep view code separate from vehicle identity, recordings, signals, import jobs, sync receipts, and server/service lifecycle. Hardware support belongs behind adapters rather than in Jetta-specific views. Preserve diagnostic capabilities separately from passive raw CAN capabilities.

## First implementation milestone

1. Create an Xcode macOS application in `mac-app/` alongside this design directory, using the repository's then-current structure and instructions.
2. Reproduce the approved shell and all seven workspaces with a clearly labeled demo repository. Keep missing values blank.
3. Persist vehicle selection, widget settings/layout, and map state locally. Keep fixture data separate from production storage.
4. Implement real local recording import and an idempotent processing queue before advertising an operational server connection.
5. Add the Mac ingestion service and companion API; distinguish “copied,” “accepted,” and “processed” in receipts. Closing the window must not unexpectedly stop a configured background service.
6. Integrate iOS first. Keep the same vehicle, recording, signal, and receipt contracts usable by Android and the future dual-CAN recorder.
7. Replace simulated actions one at a time, with explicit operational / offline / historical / demo states.

For mapping, choose an appropriate native provider for the recorded-history use case; this screen is not a turn-by-turn navigation product. Do not convert the municipal preview geometry into a fixed production basemap. Keep the user's navigation preferences separate from this telemetry visualization.

## Acceptance checks

- Faithful layout on 1920×1080 and larger displays, and usable window resizing on the user's MacBook Air.
- No clipped controls, overlapping labels, or horizontal application overflow.
- Independent vehicle histories and widget instances; settings survive relaunch.
- GPS-only drives never acquire invented fuel, RPM, engine-temperature, or raw-CAN values.
- Comparison selections affect their respective recordings, while zoom and center stay linked.
- Playback, charts, and map positions use actual aligned recording timestamps.
- Scanner identity is reviewed before saving; unsupported details remain unset.
- Imports survive interruption, avoid duplication, and keep original data and source provenance.
- Server pause, background operation, retention, and acknowledgements reflect actual service state.
- Keyboard navigation, accessible control names, focus handling, and readable contrast work in native controls.

## Existing validation and limits

The approved prototype was exercised in Chromium at 1920, 1440, 1024, 768, 390, and 320 px widths across all seven workspaces, with no horizontal page overflow or JavaScript errors observed. Interactions checked included period selection, summary configuration, zoom, vehicle onboarding, GPS-only blank readings, playback, comparison selection, signal selection, ingestion pause, and demo queue processing. These checks validate the prototype only. No native build, performance test, real scanner session, server integration, or production import has been completed by this package.
