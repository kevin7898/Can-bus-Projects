import { useEffect, useRef, useState } from "react";
import L from "leaflet";
import { Maximize2, Minimize2, Layers, Columns2 } from "lucide-react";
import {
  roads,
  trips,
  corridorStats,
  filterTrips,
  defaultMap,
  type MapPrefs,
  type Coord,
} from "./model";
interface Props {
  prefs?: MapPrefs;
  onChange: (p: MapPrefs) => void;
  mode?: "heatmap" | "location" | "routes";
  route?: Coord[];
  progress?: number;
}
export default function MapWidget({
  prefs = defaultMap,
  onChange,
  mode = "heatmap",
  route,
  progress = 100,
}: Props) {
  const [expanded, setExpanded] = useState(false);
  const [settings, setSettings] = useState(false);
  const [tileError, setTileError] = useState(false);
  const maps = useRef<L.Map[]>([]);
  const hosts = useRef<(HTMLDivElement | null)[]>([]);
  const layers = useRef<L.LayerGroup[]>([]);
  const prefsRef = useRef(prefs);
  prefsRef.current = prefs;
  const onChangeRef = useRef(onChange);
  onChangeRef.current = onChange;
  const update = (patch: Partial<MapPrefs>) => onChange({ ...prefs, ...patch });
  useEffect(() => {
    let syncing = false;
    const list = [0, ...(prefs.compare ? [1] : [])];
    list.forEach((i) => {
      const m = L.map(hosts.current[i]!, {
        center: prefsRef.current.center,
        zoom: prefsRef.current.zoom,
        zoomControl: true,
        attributionControl: true,
      });
      maps.current[i] = m;
      L.tileLayer(
        "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png",
        { attribution: "&copy; OpenStreetMap &copy; CARTO", maxZoom: 19 },
      )
        .on("tileerror", () => setTileError(true))
        .addTo(m);
      // A small offline vector reference preserves geographic context if basemap tiles cannot load.
      roads.forEach((r) =>
        L.polyline(r.points, {
          color: "#34404e",
          weight: 2,
          opacity: 0.7,
          interactive: false,
        }).addTo(m),
      );
      layers.current[i] = L.layerGroup().addTo(m);
      m.on("move", () => {
        if (syncing) return;
        syncing = true;
        maps.current.forEach((other) => {
          if (other !== m)
            other.setView(m.getCenter(), m.getZoom(), { animate: false });
        });
        syncing = false;
      });
      m.on("moveend zoomend", () => {
        const c = m.getCenter(),
          p = prefsRef.current;
        if (
          Math.abs(c.lat - p.center[0]) > 0.000001 ||
          Math.abs(c.lng - p.center[1]) > 0.000001 ||
          m.getZoom() !== p.zoom
        )
          onChangeRef.current({
            ...p,
            center: [c.lat, c.lng],
            zoom: m.getZoom(),
          });
      });
    });
    const observers = hosts.current.filter(Boolean).map((h) => {
      const o = new ResizeObserver(() =>
        maps.current.forEach((m) => m.invalidateSize()),
      );
      o.observe(h!);
      return o;
    });
    return () => {
      observers.forEach((o) => o.disconnect());
      maps.current.forEach((m) => m.remove());
      maps.current = [];
      layers.current = [];
    };
  }, [prefs.compare]);
  useEffect(() => {
    maps.current.forEach((m) => {
      const c = m.getCenter();
      if (
        Math.abs(c.lat - prefs.center[0]) > 0.000001 ||
        Math.abs(c.lng - prefs.center[1]) > 0.000001 ||
        m.getZoom() !== prefs.zoom
      )
        m.setView(prefs.center, prefs.zoom, { animate: false });
    });
  }, [prefs.center, prefs.zoom]);
  useEffect(() => {
    layers.current.forEach((layer, i) => {
      layer.clearLayers();
      const selected = filterTrips(i === 1 ? prefs.compareDays : prefs.days);
      if (route) {
        L.polyline(route, { color: "#4cafff", weight: 4 }).addTo(layer);
        const index = Math.min(
          route.length - 1,
          Math.floor((progress / 100) * (route.length - 1)),
        );
        L.circleMarker(route[index], {
          radius: 7,
          color: "#fff",
          fillColor: "#4cafff",
          fillOpacity: 1,
        }).addTo(layer);
        return;
      }
      roads.forEach((r) => {
        const stats = corridorStats(r.id, selected);
        if (!stats.count && !prefs.unexplored) return;
        const color =
          stats.count > 20
            ? "#88d8ff"
            : stats.count > 8
              ? "#389dff"
              : stats.count
                ? "#2865a7"
                : "#a49470";
        if (stats.count)
          L.polyline(r.points, {
            color,
            weight: 16,
            opacity: prefs.opacity * 0.12,
            interactive: false,
          }).addTo(layer);
        L.polyline(r.points, {
          color,
          weight: stats.count ? 3 + stats.count / 12 : 2,
          opacity: prefs.opacity,
          dashArray: stats.count ? undefined : "4 7",
        })
          .bindPopup(
            `<strong>${r.name}</strong><br>${stats.count} distinct sample trips<br>Last visit: ${stats.lastVisit ? new Date(stats.lastVisit).toLocaleDateString() : "Never in sample"}<br><small>Approximate sample corridor</small>`,
          )
          .addTo(layer);
      });
      if (mode === "location")
        L.circleMarker(trips[0].route.at(-1)!, {
          radius: 8,
          color: "#fff",
          fillColor: "#409eff",
          fillOpacity: 1,
        })
          .bindPopup("Last known position · simulated · parked")
          .addTo(layer);
    });
  }, [
    prefs.days,
    prefs.compareDays,
    prefs.opacity,
    prefs.unexplored,
    prefs.compare,
    mode,
    route,
    progress,
  ]);
  useEffect(() => {
    maps.current.forEach((m) => m.invalidateSize());
  }, [expanded]);
  useEffect(() => {
    if (!expanded) return;
    const old = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const close = (e: KeyboardEvent) => {
      if (e.key === "Escape") setExpanded(false);
    };
    window.addEventListener("keydown", close);
    return () => {
      document.body.style.overflow = old;
      window.removeEventListener("keydown", close);
    };
  }, [expanded]);
  return (
    <div
      className={`map-widget ${expanded ? "expanded-map" : ""}`}
      role={expanded ? "dialog" : undefined}
      aria-modal={expanded || undefined}
      aria-label={expanded ? "Expanded driving map" : undefined}
    >
      <div className="map-toolbar">
        <select
          aria-label="Map date range"
          value={prefs.days}
          onChange={(e) => update({ days: e.target.value })}
        >
          <option value="all">All recorded history</option>
          <option value="7">Last 7 days</option>
          <option value="14">Last 14 days</option>
        </select>
        <div className="map-buttons">
          <button
            title="Map preferences"
            aria-label="Map preferences"
            onClick={() => setSettings(!settings)}
          >
            <Layers size={14} />
          </button>
          <button
            title="Compare periods"
            aria-label="Compare map periods"
            className={prefs.compare ? "selected" : ""}
            onClick={() => update({ compare: !prefs.compare })}
          >
            <Columns2 size={14} />
          </button>
          <button
            title={expanded ? "Close expanded map" : "Expand map"}
            aria-label={expanded ? "Close expanded map" : "Expand map"}
            onClick={() => setExpanded(!expanded)}
          >
            {expanded ? <Minimize2 size={14} /> : <Maximize2 size={14} />}
          </button>
        </div>
      </div>
      {settings && (
        <div className="map-settings">
          <label>
            Intensity{" "}
            <input
              aria-label="Heatmap intensity"
              type="range"
              min="0.1"
              max="1"
              step="0.1"
              value={prefs.opacity}
              onChange={(e) => update({ opacity: +e.target.value })}
            />
          </label>
          <label>
            Zoom{" "}
            <select
              aria-label="Map zoom"
              value={prefs.zoom}
              onChange={(e) => update({ zoom: +e.target.value })}
            >
              {Array.from({ length: 18 }, (_, i) => (
                <option key={i} value={i + 2}>
                  {i + 2}
                </option>
              ))}
            </select>
          </label>
          <label>
            <input
              type="checkbox"
              checked={prefs.unexplored}
              onChange={(e) => update({ unexplored: e.target.checked })}
            />{" "}
            Undriven sample corridors
          </label>
          <small>Coverage limited to the sample network.</small>
        </div>
      )}
      <div className={`map-canvases ${prefs.compare ? "comparison" : ""}`}>
        <div className="map-panel">
          <div
            ref={(el) => {
              hosts.current[0] = el;
            }}
            className="leaflet-host"
          />
          <span className="map-caption">
            {prefs.days === "all" ? "All history" : `Last ${prefs.days} days`} ·
            SAMPLE GPS
          </span>
        </div>
        {prefs.compare && (
          <div className="map-panel">
            <div
              ref={(el) => {
                hosts.current[1] = el;
              }}
              className="leaflet-host"
            />
            <select
              className="compare-period"
              aria-label="Comparison date range"
              value={prefs.compareDays}
              onChange={(e) => update({ compareDays: e.target.value })}
            >
              <option value="7">Last 7 days</option>
              <option value="14">Last 14 days</option>
              <option value="all">All history</option>
            </select>
          </div>
        )}
      </div>
      <div className="map-legend">
        <span>
          <i /> Low frequency
        </span>
        <span className="gradient" />
        <span>High</span>
        <span className="legend-note">
          {tileError
            ? "Basemap unavailable · offline corridors shown"
            : "Nanaimo, BC · approximate sample corridors"}
        </span>
      </div>
    </div>
  );
}
