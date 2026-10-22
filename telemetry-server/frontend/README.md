# CAN / CONNECT

Standalone React + TypeScript + Vite frontend for a self-hosted automotive telemetry platform. Dedicated to the 2014 Jetta TDI first; independent of the Android recorder, CAN decoder and future cluster.

## Run

Use Node 24 or later.

```sh
npm ci
npm run dev
npm test
npm run build
```

`dist/` is the production application. Serve it with any static HTTP server, or use Docker:

```sh
docker build -t can-connect .
docker run --rm -p 8080:80 can-connect
```

Open http://localhost:8080. No build or account service is required at runtime. The Sites deployment is private; this source can be hosted independently.

## Implemented

- Overview landing page; six distinct workspaces with functional navigation.
- react-grid-layout 12-column desktop grid, responsive 8/6/4-column layouts, header dragging, edge/corner resizing, live placement and collision compaction in Customize mode.
- Normal mode locks layout but leaves controls interactive.
- Searchable, category-filtered registry of 42 widget types; add, remove and duplicate without instance limits; nested settings cloned per duplicate.
- Transactional Customize drafts: Save persists layouts and settings; Cancel discards them. Normal widget settings save immediately. All responsive layouts share widget identities but have independent positions.
- Local persistence behind `DashboardRepository` for a future server adapter. Key: `can-connect.dashboard.v1`. A browser refresh retains saved layout and map settings.
- Leaflet pan/zoom, CARTO dark tiles, sample road frequency layers, corridor popups, remembered center/zoom/date range/intensity/layers, expanded view, and two synchronized maps with independent date filters.
- Optional undriven roads are limited to the hand-authored sample network; they do not imply complete OpenStreetMap coverage.
- Trip list search, route selection, play/pause, timeline scrubbing, sample event markers and a signal cursor synchronized to replay progress.
- Historical signal selector, diagnostic sample widgets, CAN ID filtering and read-only vehicle policy summary.
- Explicit simulated/unsupported labels and separate recorded/ingested timestamps. Last known parked readings are not presented as live.

## Data and limits

All values are synthetic. `src/model.ts` contains 46 sample trips and approximate Nanaimo road corridors. These are not personal location traces. Distinct trip IDs are counted per corridor; repeated GPS samples cannot increase a corridor's count. Real road-segment map matching is a future backend concern. Trip routes use sparse approximate coordinates; chart waveforms are illustrative, not physically derived from the route.

No recorder, live CAN feed, decoder, authentication service, telemetry ingestion API, real DPF thresholds or server database is implemented here. Vehicle settings are descriptive, not hardware controls. Unknown oil-temperature availability is marked unsupported. The normalized envelope distinguishes vehicle recording time, ingestion time, live/parked/offline/delayed state and signal quality; a future backend must order records by recording time.

Basemap tiles require Internet access to CARTO; attribution is shown in each map. If tiles fail, the app identifies that and retains its offline vector corridor reference. Fonts use Google Fonts with system fallbacks.

The frontend never sends CAN commands. Local browser settings contain demo layouts/preferences only. Runtime vehicle data should come from a normalized API, not raw CAN traffic embedded in the UI.

## Verification

`npm test` verifies corridor deduplication, delayed-upload date filtering, independent duplicated settings, draft isolation/removal, and local persistence roundtrips. `npm run build` performs TypeScript checking and the optimized production build.

Browser interaction and visual QA could not be completed in the development environment: its browser security policy blocked access to the managed preview. Drag/resize/touch behavior, responsive rendering and third-party map tile loading therefore remain unverified in a browser. Implemented behavior should not be confused with a passing browser interaction test.

## Next work

1. Complete browser interaction QA on desktop, iPad and iPhone.
2. Replace the demo repository/data providers with versioned vehicle APIs and server persistence.
3. Ingest GPS with recorded/ingested timestamps; map-match actual segments; derive real distinct-trip corridor statistics.
4. Add timestamped replay samples and real synchronized time-series rather than sample waveforms.
5. Add decoder definitions and evidence-based VW signal support.
