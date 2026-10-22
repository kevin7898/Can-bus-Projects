# Jetta Telemetry Dashboard

A web-first, local-first telemetry experience for the 2014 Volkswagen Jetta TDI (CJAA/PPY). This UI prototype is deliberately separated from CAN acquisition so it can consume the same normalized vehicle data from the Android recorder, a dedicated telemetry box, or a future cluster computer.

## Run locally

```bash
npm install
npm run dev
```

Production build:

```bash
npm run build
```

## Cellular-first data policy

The prototype models a telemetry box with onboard LTE/5G and opportunistic Wi-Fi:

- live trip summaries, warnings, positions, and downsampled telemetry can stream over cellular;
- raw CAN captures and other bundles above the configured threshold remain encrypted locally;
- oversized bundles automatically resume in chunks when trusted Wi-Fi is available;
- vehicle instruments never depend on upload success, cloud reachability, storage processing, or navigation;
- missing or stale source data must be represented explicitly by the future API rather than silently displaying the last value.

The first UI uses simulated data. No mock value should be treated as a verified CAN signal or scaling definition.

## Initial screens

- **Overview** — current vehicle state, range, fuel and recent drives
- **Trips** — drive history and trip detail
- **Vehicle** — TDI health, temperatures and DPF state
- **Data sync** — cellular/Wi-Fi queue, local storage and transfer policy

## Intended service boundary

The browser should eventually subscribe to a normalized API rather than raw CAN frames. A representative envelope is:

```json
{
  "vehicleId": "jetta-2014",
  "capturedAt": "2026-10-22T07:42:12Z",
  "source": "drive-can",
  "signals": {
    "vehicle.speed": { "value": 0, "unit": "km/h", "quality": "fresh" },
    "fuel.level": { "value": 63, "unit": "%", "quality": "candidate" },
    "engine.coolantTemp": { "value": 89, "unit": "°C", "quality": "fresh" }
  }
}
```

This boundary lets the telemetry box and future cluster share decoded state without coupling either UI to Volkswagen frame IDs.
