import type { Layout, Layouts } from "react-grid-layout";
export type Quality = "simulated" | "unsupported" | "verified";
export interface SignalValue {
  value: number | null;
  unit: string;
  quality: Quality;
}
export interface TelemetryEnvelope {
  vehicleId: string;
  recordedAt: string;
  ingestedAt: string;
  state: "live" | "parked" | "offline" | "delayed";
  signals: Record<string, SignalValue>;
}
export type Coord = [number, number];
export interface Road {
  id: string;
  name: string;
  points: Coord[];
}
// Hand-authored, approximate road corridors around Nanaimo. No personal GPS traces.
export const roads: Road[] = [
  {
    id: "hwy19",
    name: "Nanaimo Parkway",
    points: [
      [49.142, -123.979],
      [49.159, -123.995],
      [49.178, -124.012],
      [49.199, -124.028],
      [49.222, -124.044],
      [49.244, -124.06],
    ],
  },
  {
    id: "bowen",
    name: "Bowen Road",
    points: [
      [49.166, -123.952],
      [49.177, -123.97],
      [49.187, -123.985],
      [49.198, -124.005],
      [49.207, -124.026],
    ],
  },
  {
    id: "island",
    name: "Island Highway",
    points: [
      [49.163, -123.939],
      [49.18, -123.948],
      [49.198, -123.957],
      [49.215, -123.976],
      [49.235, -124.008],
      [49.251, -124.038],
    ],
  },
  {
    id: "jingle",
    name: "Jingle Pot Road",
    points: [
      [49.16, -123.978],
      [49.169, -123.994],
      [49.181, -124.02],
      [49.197, -124.039],
    ],
  },
  {
    id: "hammond",
    name: "Hammond Bay Road",
    points: [
      [49.199, -123.957],
      [49.211, -123.944],
      [49.23, -123.95],
      [49.246, -123.97],
      [49.252, -123.997],
      [49.251, -124.038],
    ],
  },
  {
    id: "north",
    name: "Mostar Road",
    points: [
      [49.222, -124.044],
      [49.225, -124.028],
      [49.235, -124.008],
    ],
  },
  {
    id: "departure",
    name: "Departure Bay Road",
    points: [
      [49.187, -123.949],
      [49.198, -123.937],
      [49.21, -123.944],
    ],
  },
];
export interface Trip {
  id: string;
  date: string;
  ingestedAt: string;
  title: string;
  distance: number;
  minutes: number;
  economy: number;
  roadIds: string[];
  route: Coord[];
}
export const trips: Trip[] = Array.from({ length: 46 }, (_, i) => {
  const roadIds =
    i % 5 === 0
      ? ["bowen", "jingle"]
      : i % 3 === 0
        ? ["island", "hammond"]
        : ["hwy19", "north"];
  return {
    id: `trip-${i}`,
    date: new Date(
      Date.UTC(2026, 9, 22 - Math.floor(i / 2), i % 2 ? 7 : 17, 12),
    ).toISOString(),
    ingestedAt: new Date(
      Date.UTC(2026, 9, 22 - Math.floor(i / 2), i % 2 ? 9 : 18, 24),
    ).toISOString(),
    title:
      i % 3 === 0
        ? "Departure Bay → North Nanaimo"
        : i % 5 === 0
          ? "Bowen Road → Jingle Pot"
          : "South Nanaimo → Woodgrove",
    distance: +(18.4 + ((i * 7.31) % 63)).toFixed(1),
    minutes: 22 + (i % 39),
    economy: +(4.7 + ((i * 0.23) % 1.8)).toFixed(1),
    roadIds,
    route: roads.find((r) => r.id === roadIds[0])!.points,
  };
});
export function corridorStats(roadId: string, source: Trip[]) {
  const matches = [
    ...new Map(
      source.filter((t) => t.roadIds.includes(roadId)).map((t) => [t.id, t]),
    ).values(),
  ];
  return {
    count: matches.length,
    lastVisit: matches
      .map((t) => t.date)
      .sort()
      .at(-1),
    trips: matches,
  };
}
export function filterTrips(days: string, source = trips) {
  return source.filter(
    (t) =>
      days === "all" ||
      Date.parse(t.date) >=
        Date.parse("2026-10-23T00:00:00Z") - Number(days) * 86400000,
  );
}
export const snapshot: TelemetryEnvelope = {
  vehicleId: "jetta-2014",
  recordedAt: trips[0].date,
  ingestedAt: trips[0].ingestedAt,
  state: "parked",
  signals: {
    coolant: { value: 89, unit: "°C", quality: "simulated" },
    soot: { value: 12.4, unit: "g", quality: "simulated" },
    oil: { value: null, unit: "°C", quality: "unsupported" },
  },
};
export type Kind =
  | "heatmap"
  | "location"
  | "routes"
  | "geography"
  | "distance"
  | "trips"
  | "duration"
  | "speed"
  | "idle"
  | "economy"
  | "consumption"
  | "fuel"
  | "range"
  | "fillups"
  | "cost"
  | "rpm"
  | "coolant"
  | "oil"
  | "boost"
  | "intake"
  | "load"
  | "dpf"
  | "regen"
  | "sinceRegen"
  | "exhaust"
  | "pressure"
  | "faults"
  | "warnings"
  | "battery"
  | "maintenance"
  | "chart"
  | "overlay"
  | "gauge"
  | "histogram"
  | "statistics"
  | "connection"
  | "cellular"
  | "wifi"
  | "storage"
  | "can"
  | "quality"
  | "activity";
export interface Definition {
  kind: Kind;
  title: string;
  group: string;
  unit?: string;
  value?: string;
  note: string;
  w: number;
  h: number;
  minW: number;
  minH: number;
  unsupported?: boolean;
}
const metric = (
  kind: Kind,
  title: string,
  group: string,
  value: string,
  unit: string,
  note: string,
  unsupported = false,
): Definition => ({
  kind,
  title,
  group,
  value,
  unit,
  note,
  w: 3,
  h: 3,
  minW: 2,
  minH: 3,
  unsupported,
});
export const registry: Definition[] = [
  {
    kind: "heatmap",
    title: "Driving heatmap",
    group: "Maps",
    note: "Distinct trips per road corridor",
    w: 8,
    h: 9,
    minW: 4,
    minH: 7,
  },
  {
    kind: "location",
    title: "Vehicle location",
    group: "Maps",
    note: "Last recorded position",
    w: 6,
    h: 7,
    minW: 4,
    minH: 7,
  },
  {
    kind: "routes",
    title: "Recent routes",
    group: "Maps",
    note: "Recorded GPS route overlay",
    w: 6,
    h: 7,
    minW: 4,
    minH: 7,
  },
  metric(
    "geography",
    "Geographic coverage",
    "Maps",
    "6",
    "corridors",
    "Sample Nanaimo road network",
  ),
  metric(
    "distance",
    "Distance driven",
    "Driving",
    "2,042.6",
    "km",
    "46 trips · October 2026",
  ),
  metric(
    "trips",
    "Recorded trips",
    "Driving",
    "46",
    "trips",
    "All sample recordings",
  ),
  metric("duration", "Driving time", "Driving", "28.4", "h", "October 2026"),
  metric(
    "speed",
    "Average speed",
    "Driving",
    "48.2",
    "km/h",
    "Moving time only",
  ),
  metric("idle", "Idle time", "Driving", "1.8", "h", "6.3% of engine runtime"),
  metric(
    "economy",
    "Fuel economy",
    "Fuel",
    "5.3",
    "L/100 km",
    "Distance-weighted average",
  ),
  {
    kind: "consumption",
    title: "Consumption trend",
    group: "Fuel",
    note: "Trip-weighted fuel consumption",
    w: 6,
    h: 6,
    minW: 3,
    minH: 5,
  },
  metric("fuel", "Fuel level", "Fuel", "63", "%", "Last known · 34.7 L"),
  metric(
    "range",
    "Estimated range",
    "Fuel",
    "654",
    "km",
    "Based on recent fuel economy",
  ),
  metric(
    "fillups",
    "Last fill-up",
    "Fuel",
    "47.2",
    "L",
    "Oct 17 · simulated receipt",
  ),
  metric(
    "cost",
    "Fuel cost",
    "Fuel",
    "0.092",
    "$/km",
    "At $1.74/L · sample price",
  ),
  metric("rpm", "Engine speed", "Engine", "0", "rpm", "Parked · last known"),
  metric("coolant", "Coolant", "Engine", "89", "°C", "At end of last drive"),
  metric(
    "oil",
    "Oil temperature",
    "Engine",
    "—",
    "°C",
    "Signal availability unverified",
    true,
  ),
  metric(
    "boost",
    "Boost pressure",
    "Engine",
    "0.0",
    "bar",
    "Gauge pressure · parked",
  ),
  metric("intake", "Intake air", "Engine", "22", "°C", "At end of last drive"),
  metric("load", "Engine load", "Engine", "0", "%", "Parked · last known"),
  {
    kind: "dpf",
    title: "DPF status",
    group: "DPF",
    note: "Unverified signals · simulated values",
    w: 4,
    h: 6,
    minW: 3,
    minH: 6,
  },
  metric(
    "regen",
    "Regenerations",
    "DPF",
    "7",
    "events",
    "October · simulated detection",
  ),
  metric(
    "sinceRegen",
    "Since regeneration",
    "DPF",
    "284",
    "km",
    "Last event · Oct 19",
  ),
  metric(
    "exhaust",
    "Exhaust temperature",
    "DPF",
    "181",
    "°C",
    "At end of last drive",
  ),
  metric(
    "pressure",
    "Differential pressure",
    "DPF",
    "8",
    "mbar",
    "At end of last drive",
  ),
  metric(
    "faults",
    "Faults",
    "Diagnostics",
    "0",
    "active",
    "Simulated · no diagnostic scan",
  ),
  metric(
    "warnings",
    "Warning history",
    "Diagnostics",
    "2",
    "events",
    "Both cleared · sample events",
  ),
  metric(
    "battery",
    "Battery voltage",
    "Diagnostics",
    "12.6",
    "V",
    "Parked · last known",
  ),
  metric(
    "maintenance",
    "Next maintenance",
    "Diagnostics",
    "3,100",
    "km",
    "User-defined service interval",
  ),
  ...(["chart", "overlay", "histogram"] as Kind[]).map((kind) => ({
    kind,
    title:
      kind === "chart"
        ? "Signal history"
        : kind === "overlay"
          ? "Multi-signal overlay"
          : "Speed distribution",
    group: "Telemetry",
    note: "Simulated time-series",
    w: 6,
    h: 6,
    minW: 3,
    minH: 5,
  })),
  metric(
    "gauge",
    "Coolant gauge",
    "Telemetry",
    "89",
    "°C",
    "At end of last drive",
  ),
  metric(
    "statistics",
    "Signal statistics",
    "Telemetry",
    "87.3",
    "°C mean",
    "Coolant · min 16 / max 94",
  ),
  metric(
    "connection",
    "Recorder connection",
    "System",
    "OFFLINE",
    "",
    "Sample recorder disconnected",
  ),
  metric(
    "cellular",
    "Cellular sync",
    "System",
    "24.8",
    "MB",
    "Summaries uploaded · simulated",
  ),
  metric(
    "wifi",
    "Wi-Fi upload queue",
    "System",
    "1.2",
    "GB",
    "Raw captures awaiting trusted Wi-Fi",
  ),
  metric(
    "storage",
    "Recorder storage",
    "System",
    "18.4",
    "GB",
    "Of 64 GB · simulated",
  ),
  metric(
    "can",
    "CAN traffic",
    "System",
    "1,284",
    "frames/s",
    "Historical · simulated",
  ),
  metric(
    "quality",
    "Data quality",
    "System",
    "98.7",
    "%",
    "Valid samples · simulated",
  ),
  {
    kind: "activity",
    title: "Recent activity",
    group: "System",
    note: "Recorded time / ingestion time",
    w: 4,
    h: 7,
    minW: 3,
    minH: 7,
  },
];
export const definition = (kind: Kind) =>
  registry.find((d) => d.kind === kind)!;
export interface Widget {
  id: string;
  kind: Kind;
  settings: {
    period?: string;
    signal?: string;
    title?: string;
    map?: MapPrefs;
  };
}
export interface MapPrefs {
  center: Coord;
  zoom: number;
  days: string;
  opacity: number;
  unexplored: boolean;
  compare: boolean;
  compareDays: string;
}
export const defaultMap: MapPrefs = {
  center: [49.202, -123.996],
  zoom: 12,
  days: "all",
  opacity: 0.8,
  unexplored: false,
  compare: false,
  compareDays: "7",
};
export interface Dashboard {
  version: 1;
  widgets: Widget[];
  layouts: Layouts;
}
const starter: [Kind, number, number, number, number][] = [
  ["heatmap", 0, 0, 8, 9],
  ["economy", 8, 0, 4, 3],
  ["dpf", 8, 3, 4, 6],
  ["distance", 0, 9, 3, 3],
  ["trips", 3, 9, 3, 3],
  ["range", 6, 9, 3, 3],
  ["battery", 9, 9, 3, 3],
  ["consumption", 0, 12, 8, 6],
  ["activity", 8, 12, 4, 7],
];
export function initialDashboard(): Dashboard {
  return {
    version: 1,
    widgets: starter.map(([kind], i) => ({
      id: `widget-${i}`,
      kind,
      settings: {},
    })),
    layouts: {
      lg: starter.map(([kind, x, y, w, h], i) => ({
        i: `widget-${i}`,
        x,
        y,
        w,
        h,
        minW: definition(kind).minW,
        minH: definition(kind).minH,
      })),
    },
  };
}
export interface DashboardRepository {
  load(): Dashboard;
  save(value: Dashboard): void;
}
export const localRepository: DashboardRepository = {
  load() {
    try {
      const v = JSON.parse(
        localStorage.getItem("can-connect.dashboard.v1") || "null",
      );
      if (validDashboard(v)) return v;
    } catch {}
    return initialDashboard();
  },
  save(v) {
    localStorage.setItem("can-connect.dashboard.v1", JSON.stringify(v));
  },
};
export function newLayout(id: string, kind: Kind, current: Layout[]): Layout {
  const d = definition(kind);
  return {
    i: id,
    x: 0,
    y: Math.max(0, ...current.map((l) => l.y + l.h)),
    w: d.w,
    h: d.h,
    minW: d.minW,
    minH: d.minH,
  };
}
export function appendWidget(
  dashboard: Dashboard,
  kind: Kind,
  id: string,
  source?: Widget,
): Dashboard {
  return {
    ...dashboard,
    widgets: [
      ...dashboard.widgets,
      { id, kind, settings: source ? structuredClone(source.settings) : {} },
    ],
    layouts: Object.fromEntries(
      Object.entries(dashboard.layouts).map(([bp, layout]) => [
        bp,
        [...layout, newLayout(id, kind, layout)],
      ]),
    ),
  };
}
export function deleteWidget(dashboard: Dashboard, id: string): Dashboard {
  return {
    ...dashboard,
    widgets: dashboard.widgets.filter((w) => w.id !== id),
    layouts: Object.fromEntries(
      Object.entries(dashboard.layouts).map(([bp, layout]) => [
        bp,
        layout.filter((l) => l.i !== id),
      ]),
    ),
  };
}

function validDashboard(value: unknown): value is Dashboard {
  if (!value || typeof value !== "object") return false;
  const d = value as Dashboard;
  if (
    d.version !== 1 ||
    !Array.isArray(d.widgets) ||
    !d.layouts ||
    !Array.isArray(d.layouts.lg)
  )
    return false;
  const ids = new Set(d.widgets.map((w) => w?.id));
  if (
    ids.size !== d.widgets.length ||
    d.widgets.some(
      (w) =>
        !w ||
        typeof w.id !== "string" ||
        !w.settings ||
        !registry.some((def) => def.kind === w.kind),
    )
  )
    return false;
  return Object.values(d.layouts).every(
    (layout) =>
      Array.isArray(layout) &&
      layout.every(
        (l) =>
          ids.has(l.i) &&
          ["x", "y", "w", "h"].every((k) =>
            Number.isFinite(l[k as "x" | "y" | "w" | "h"]),
          ) &&
          l.x >= 0 &&
          l.y >= 0 &&
          l.w > 0 &&
          l.h > 0,
      ),
  );
}
