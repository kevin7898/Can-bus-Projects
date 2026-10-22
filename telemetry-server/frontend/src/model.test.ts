import { test } from "node:test";
import assert from "node:assert/strict";
import {
  initialDashboard,
  appendWidget,
  deleteWidget,
  corridorStats,
  filterTrips,
  trips,
  localRepository,
  defaultMap,
} from "./model";
test("road frequency counts a trip once even if input is duplicated", () => {
  const t = trips[0];
  const road = t.roadIds[0];
  const expected = corridorStats(road, trips);
  assert.deepEqual(corridorStats(road, [...trips, t, t]), expected);
  assert.equal(
    expected.count,
    trips.filter((v) => v.roadIds.includes(road)).length,
  );
  assert.equal(corridorStats("unknown", trips).count, 0);
});
test("historical filters use recording time, independent of late ingestion", () => {
  const late = {
    ...trips[0],
    date: "2026-10-01T00:00:00Z",
    ingestedAt: "2026-10-22T18:00:00Z",
  };
  assert.equal(filterTrips("7", [late]).length, 0);
  assert.equal(filterTrips("all", [late]).length, 1);
  assert.ok(filterTrips("7").length < filterTrips("14").length);
});
test("duplicate has independent nested map settings and is placed after occupied rows", () => {
  const d = initialDashboard();
  d.widgets[0].settings.map = structuredClone(defaultMap);
  const next = appendWidget(d, "heatmap", "duplicate", d.widgets[0]);
  const duplicate = next.widgets.at(-1)!;
  duplicate.settings.map!.center[0] = 0;
  duplicate.settings.map!.zoom = 18;
  assert.equal(d.widgets[0].settings.map!.zoom, 12);
  assert.notEqual(d.widgets[0].settings.map!.center[0], 0);
  assert.ok(
    next.layouts.lg.at(-1)!.y >=
      Math.max(...d.layouts.lg.map((l) => l.y + l.h)),
  );
  assert.equal(d.widgets.length, 9);
});
test("draft mutation and cancellation leave saved dashboard intact; removal cleans every layout", () => {
  const saved = initialDashboard();
  const before = JSON.stringify(saved);
  const draft = structuredClone(saved);
  draft.layouts.lg[0].x = 3;
  draft.widgets[0].settings.title = "Draft";
  const changed = deleteWidget(draft, draft.widgets[1].id);
  assert.equal(changed.widgets.length, 8);
  assert.ok(
    Object.values(changed.layouts).every(
      (layout) => !layout.some((l) => l.i === draft.widgets[1].id),
    ),
  );
  assert.equal(JSON.stringify(saved), before);
});
test("browser repository roundtrips layout, map preferences and per-instance settings", () => {
  const store = new Map<string, string>();
  Object.defineProperty(globalThis, "localStorage", {
    value: {
      getItem: (k: string) => store.get(k) || null,
      setItem: (k: string, v: string) => store.set(k, v),
    },
    configurable: true,
  });
  const d = initialDashboard();
  d.widgets[0].settings.map = {
    ...defaultMap,
    zoom: 14,
    compare: true,
    opacity: 0.4,
  };
  localRepository.save(d);
  assert.deepEqual(localRepository.load(), d);
  store.set("can-connect.dashboard.v1", "bad JSON");
  assert.deepEqual(localRepository.load(), initialDashboard());
});

test("malformed stored layouts recover to a usable default", () => {
  const broken = { ...initialDashboard(), layouts: { lg: "invalid" } };
  localStorage.setItem("can-connect.dashboard.v1", JSON.stringify(broken));
  assert.deepEqual(localRepository.load(), initialDashboard());
});
