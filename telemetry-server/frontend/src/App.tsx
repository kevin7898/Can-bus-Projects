import { useEffect, useRef, useState } from "react";
import { Responsive, type Layout, type Layouts } from "react-grid-layout";
import {
  Activity,
  ArrowDownToLine,
  CarFront,
  ChartNoAxesCombined,
  Check,
  ChevronDown,
  ChevronRight,
  CircleGauge,
  Copy,
  Database,
  Fuel,
  Grip,
  LayoutDashboard,
  Menu,
  Navigation,
  Plus,
  Radio,
  Search,
  Settings2,
  ShieldCheck,
  SlidersHorizontal,
  Trash2,
  Wifi,
  X,
} from "lucide-react";
import {
  definition,
  registry,
  localRepository,
  appendWidget,
  deleteWidget,
  snapshot,
  trips,
  defaultMap,
  filterTrips,
  type Dashboard,
  type Kind,
  type Widget,
} from "./model";
import MapWidget from "./MapWidget";
import Chart from "./Chart";
const pages = [
  ["Overview", LayoutDashboard],
  ["Trips", Navigation],
  ["Telemetry", ChartNoAxesCombined],
  ["Diagnostics", ShieldCheck],
  ["CAN Explorer", Radio],
  ["Vehicles", CarFront],
] as const;
function copy<T>(v: T): T {
  return structuredClone(v);
}
function Metric({ widget }: { widget: Widget }) {
  const d = definition(widget.kind);
  const selected = filterTrips(widget.settings.period || "all");
  const distance = selected.reduce((s, t) => s + t.distance, 0);
  const economy =
    selected.reduce((s, t) => s + t.distance * t.economy, 0) / distance;
  let value = d.value;
  if (widget.kind === "distance")
    value = distance.toLocaleString("en-CA", { maximumFractionDigits: 1 });
  if (widget.kind === "trips") value = String(selected.length);
  if (widget.kind === "economy") value = economy.toFixed(1);
  if (widget.kind === "duration")
    value = (selected.reduce((s, t) => s + t.minutes, 0) / 60).toFixed(1);
  return (
    <div className="metric-content">
      <div className="metric-number">
        {value}
        <span>{d.unit}</span>
      </div>
      {widget.kind === "economy" && (
        <div className="delta">
          ↘ 0.3 <span>vs. previous period · sample</span>
        </div>
      )}
      {widget.kind === "fuel" && (
        <div className="progress">
          <i style={{ width: "63%" }} />
        </div>
      )}
      {widget.kind === "gauge" && (
        <div className="progress">
          <i style={{ width: "74%" }} />
        </div>
      )}
      <p>
        {widget.kind === "distance" || widget.kind === "trips"
          ? `${selected.length} sample trips · selected period`
          : d.note}
      </p>
      <span className={`quality ${d.unsupported ? "unsupported" : ""}`}>
        {d.unsupported ? "UNSUPPORTED" : "SIMULATED"}
      </span>
    </div>
  );
}
function WidgetContent({
  widget,
  onChange,
}: {
  widget: Widget;
  onChange: (settings: Widget["settings"]) => void;
}) {
  const { kind, settings } = widget;
  if (["heatmap", "location", "routes"].includes(kind))
    return (
      <MapWidget
        prefs={settings.map}
        mode={kind as "heatmap" | "location" | "routes"}
        onChange={(map) => onChange({ ...settings, map })}
      />
    );
  if (["consumption", "chart", "overlay", "histogram"].includes(kind))
    return (
      <div className="chart-widget">
        <div className="chart-controls">
          <span>
            <b>{settings.signal === "coolant" ? "87.3" : "5.3"}</b>{" "}
            {settings.signal === "coolant" ? "°C" : "L/100 km"}{" "}
            <small>SIMULATED</small>
          </span>
          <select
            aria-label="Chart signal"
            value={settings.signal || "economy"}
            onChange={(e) => onChange({ ...settings, signal: e.target.value })}
          >
            <option value="economy">Fuel economy</option>
            <option value="coolant">Coolant</option>
          </select>
          <select
            aria-label="Chart period"
            value={settings.period || "30"}
            onChange={(e) => onChange({ ...settings, period: e.target.value })}
          >
            <option value="30">30 days</option>
            <option value="7">7 days</option>
          </select>
        </div>
        <Chart
          signal={settings.signal}
          period={settings.period}
          histogram={kind === "histogram"}
          overlay={kind === "overlay"}
        />
        <div className="chart-foot">
          <i />{" "}
          {settings.signal === "coolant"
            ? "Coolant temperature"
            : "Fuel consumption"}
          {kind === "overlay" && (
            <span className="amber"> / Engine load (normalized)</span>
          )}
        </div>
      </div>
    );
  if (kind === "dpf")
    return (
      <div className="dpf-content">
        <div className="dpf-value">
          <strong>
            12.4 <small>g</small>
          </strong>
          <span className="pill">NORMAL · SAMPLE</span>
        </div>
        <div className="muted">Estimated soot mass</div>
        <div className="progress">
          <i style={{ width: "52%" }} />
        </div>
        <div className="scale">
          <span>0 g</span>
          <span>24 g · sample threshold</span>
        </div>
        <div className="data-row">
          <span>Since regeneration</span>
          <b>
            284 <small>km</small>
          </b>
        </div>
        <div className="data-row">
          <span>Last regeneration</span>
          <b>Oct 19</b>
        </div>
        <div className="quality">UNVERIFIED SIGNALS · SIMULATED</div>
      </div>
    );
  if (kind === "activity")
    return (
      <div className="activity-list">
        {trips.slice(0, 3).map((t, i) => (
          <div className="activity-item" key={t.id}>
            <span className="event-icon">
              {i === 2 ? <Wifi size={14} /> : <Navigation size={14} />}
            </span>
            <div>
              <strong>{i === 2 ? "Wi-Fi bulk upload" : t.title}</strong>
              <p>
                {i === 2
                  ? "Raw CAN capture · 248 MB"
                  : `${t.distance} km · ${t.economy} L/100 km`}
              </p>
              <small>
                Recorded{" "}
                {new Date(t.date).toLocaleTimeString([], {
                  hour: "2-digit",
                  minute: "2-digit",
                })}{" "}
                · ingested{" "}
                {new Date(t.ingestedAt).toLocaleTimeString([], {
                  hour: "2-digit",
                  minute: "2-digit",
                })}
              </small>
            </div>
          </div>
        ))}
        <span className="quality">SIMULATED ACTIVITY</span>
      </div>
    );
  return <Metric widget={widget} />;
}
function TripWorkspace() {
  const [selected, setSelected] = useState(trips[0]);
  const [progress, setProgress] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [prefs, setPrefs] = useState({ ...defaultMap, zoom: 12 });
  const [query, setQuery] = useState("");
  useEffect(() => {
    if (!playing) return;
    const timer = setInterval(
      () =>
        setProgress((v) => {
          if (v >= 100) {
            setPlaying(false);
            return 100;
          }
          return v + 1;
        }),
      150,
    );
    return () => clearInterval(timer);
  }, [playing]);
  return (
    <div className="trip-workspace">
      <section className="panel trip-list">
        <div className="panel-header">
          Trip history <span className="muted">46 recordings</span>
        </div>
        <label className="search">
          <Search size={15} />
          <input
            aria-label="Search trips"
            placeholder="Search trips…"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </label>
        {trips
          .filter((t) => t.title.toLowerCase().includes(query.toLowerCase()))
          .map((t) => (
            <button
              className={`trip-item ${selected.id === t.id ? "active" : ""}`}
              key={t.id}
              onClick={() => {
                setSelected(t);
                setProgress(0);
                setPlaying(false);
              }}
            >
              <small>
                {new Date(t.date).toLocaleDateString("en-CA", {
                  month: "short",
                  day: "numeric",
                })}{" "}
                ·{" "}
                {new Date(t.date).toLocaleTimeString([], {
                  hour: "2-digit",
                  minute: "2-digit",
                })}
              </small>
              <strong>{t.title}</strong>
              <span>
                {t.distance} km <b>·</b> {t.minutes} min <b>·</b> {t.economy}{" "}
                L/100 km
              </span>
            </button>
          ))}
      </section>
      <section className="trip-detail">
        <div className="panel">
          <div className="panel-header">
            {selected.title}
            <span className="quality">SAMPLE GPS</span>
          </div>
          <div className="trip-map">
            <MapWidget
              prefs={prefs}
              onChange={setPrefs}
              route={selected.route}
              progress={progress}
            />
          </div>
          <div className="replay">
            <button
              onClick={() => {
                if (progress >= 100) setProgress(0);
                setPlaying(!playing);
              }}
            >
              {playing ? "Pause" : "Play"} replay
            </button>
            <input
              aria-label="Trip timeline"
              type="range"
              min="0"
              max="100"
              value={progress}
              onChange={(e) => setProgress(+e.target.value)}
            />
            <code>
              {Math.round((selected.minutes * progress) / 100)} /{" "}
              {selected.minutes} min
            </code>
          </div>
          <div className="event-markers">
            <button onClick={() => setProgress(0)}>● Ignition on</button>
            <button onClick={() => setProgress(50)}>◆ Sample stop</button>
            <button onClick={() => setProgress(100)}>■ Parked</button>
          </div>
        </div>
        <div className="panel trip-chart">
          <div className="panel-header">
            Synchronized signals{" "}
            <span className="muted">Illustrative sample waveform</span>
          </div>
          <Chart progress={progress} overlay />
          <p className="muted">
            Recorded {selected.date} · Ingested {selected.ingestedAt}
          </p>
        </div>
      </section>
    </div>
  );
}
function Workspace({ page }: { page: string }) {
  const [signal, setSignal] = useState("economy");
  const [query, setQuery] = useState("");
  if (page === "Trips") return <TripWorkspace />;
  if (page === "Telemetry")
    return (
      <div className="panel workspace-panel">
        <div className="panel-header">
          Historical signals
          <select
            aria-label="Historical signal"
            value={signal}
            onChange={(e) => setSignal(e.target.value)}
          >
            <option value="economy">Fuel economy</option>
            <option value="coolant">Coolant temperature</option>
          </select>
        </div>
        <Chart signal={signal} overlay />
        <p className="muted">
          Simulated historical series. Decoder and API integration pending.
        </p>
      </div>
    );
  if (page === "CAN Explorer")
    return (
      <div className="panel workspace-panel">
        <div className="panel-header">
          Raw CAN traffic{" "}
          <span className="quality">SIMULATED · NO LIVE BUS</span>
        </div>
        <label className="search">
          <Search size={14} />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Filter CAN ID…"
            aria-label="Filter CAN ID"
          />
        </label>
        <table>
          <thead>
            <tr>
              <th>CAN ID</th>
              <th>DLC</th>
              <th>Payload (hex)</th>
              <th>Rate</th>
              <th>Definition</th>
            </tr>
          </thead>
          <tbody>
            {["0x280", "0x288", "0x380", "0x480", "0x5A0", "0x5C0"]
              .filter((id) => id.toLowerCase().includes(query.toLowerCase()))
              .map((id, i) => (
                <tr key={id}>
                  <td>
                    <code>{id}</code>
                  </td>
                  <td>8</td>
                  <td>
                    <code>00 {i}4 00 A0 00 FF 00 00</code>
                  </td>
                  <td>{20 + i * 5} Hz</td>
                  <td className="muted">Undecoded sample</td>
                </tr>
              ))}
          </tbody>
        </table>
        <p className="muted">
          Illustrative frames only. These payloads are not verified Volkswagen
          signal definitions.
        </p>
      </div>
    );
  if (page === "Vehicles")
    return (
      <div className="vehicle-workspace panel">
        <CarFront size={40} />
        <h2>2014 Volkswagen Jetta TDI</h2>
        <p>CJAA · Primary vehicle · Sample profile</p>
        <div className="data-row">
          <span>Recorder</span>
          <b>Not connected</b>
        </div>
        <div className="data-row">
          <span>Vehicle state</span>
          <b>Parked · last known</b>
        </div>
        <div className="data-row">
          <span>Cellular policy</span>
          <b>Summaries & downsampled signals</b>
        </div>
        <div className="data-row">
          <span>Bulk data policy</span>
          <b>Trusted Wi-Fi upload</b>
        </div>
        <div className="data-row">
          <span>Oil temperature</span>
          <b>Unsupported / unverified</b>
        </div>
        <p className="muted">
          Recorder settings require a future backend. This frontend does not
          configure vehicle hardware.
        </p>
      </div>
    );
  return (
    <div className="diagnostic-workspace">
      {(
        [
          "dpf",
          "faults",
          "battery",
          "sinceRegen",
          "pressure",
          "exhaust",
        ] as Kind[]
      ).map((kind, i) => (
        <section className="panel" key={kind}>
          <div className="panel-header">{definition(kind).title}</div>
          <WidgetContent
            widget={{ id: `diag${i}`, kind, settings: {} }}
            onChange={() => {}}
          />
        </section>
      ))}
    </div>
  );
}
export default function App() {
  const [saved, setSaved] = useState<Dashboard>(() => localRepository.load());
  const [draft, setDraft] = useState<Dashboard | null>(null);
  const dashboard = draft || saved;
  const editing = !!draft;
  const [page, setPage] = useState("Overview");
  const [library, setLibrary] = useState(false);
  const [query, setQuery] = useState("");
  const [group, setGroup] = useState("All");
  const [menu, setMenu] = useState(false);
  const [notice, setNotice] = useState("");
  const [settingsId, setSettingsId] = useState<string | null>(null);
  const container = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(1000);
  const [breakpoint, setBreakpoint] = useState("lg");
  useEffect(() => {
    if (!container.current) return;
    const observer = new ResizeObserver(([entry]) =>
      setWidth(Math.floor(entry.contentRect.width)),
    );
    observer.observe(container.current);
    return () => observer.disconnect();
  }, [page]);
  useEffect(() => {
    if (!notice) return;
    const t = setTimeout(() => setNotice(""), 4500);
    return () => clearTimeout(t);
  }, [notice]);
  function persist(next: Dashboard) {
    try {
      localRepository.save(next);
      setSaved(next);
      return true;
    } catch {
      setNotice("Unable to save. Browser storage is full or unavailable.");
      return false;
    }
  }
  function changeSettings(id: string, settings: Widget["settings"]) {
    const update = (d: Dashboard) => ({
      ...d,
      widgets: d.widgets.map((w) => (w.id === id ? { ...w, settings } : w)),
    });
    if (draft) setDraft(update(draft));
    else persist(update(saved));
  }
  function add(kind: Kind, source?: Widget) {
    if (!draft) return;
    const id = crypto.randomUUID();
    setDraft(appendWidget(draft, kind, id, source));
    setNotice(
      source ? "Widget duplicated with independent settings" : "Widget added",
    );
  }
  function remove(id: string) {
    if (!draft) return;
    setDraft(deleteWidget(draft, id));
  }
  function onLayout(_: Layout[], layouts: Layouts) {
    if (draft) setDraft((d) => (d ? { ...d, layouts } : d));
  }
  const settingsWidget = dashboard.widgets.find((w) => w.id === settingsId);
  return (
    <div className="app">
      <aside className={`sidebar ${menu ? "open" : ""}`}>
        <a
          className="brand"
          href="#"
          onClick={(e) => {
            e.preventDefault();
            setPage("Overview");
          }}
        >
          <div className="brand-symbol">
            <Activity size={21} />
          </div>
          <div>
            CAN <em>/</em> CONNECT<small>VEHICLE INTELLIGENCE</small>
          </div>
        </a>
        <div className="workspace-label">WORKSPACE</div>
        <nav>
          {pages.map(([label, Icon]) => (
            <button
              key={label}
              className={page === label ? "active" : ""}
              onClick={() => {
                if (editing && label !== "Overview") {
                  setNotice(
                    "Save or cancel your layout before changing workspace",
                  );
                  return;
                }
                setPage(label);
                setMenu(false);
              }}
            >
              <Icon size={17} />
              {label}
              {label === "CAN Explorer" && <span className="nav-tag">DEV</span>}
            </button>
          ))}
        </nav>
        <div className="sidebar-bottom">
          <div className="system-state">
            <span className="status-dot" /> SAMPLE ENVIRONMENT
          </div>
          <div className="vehicle-mini">
            <CarFront size={22} />
            <div>
              <b>Jetta TDI</b>
              <small>2014 · CJAA</small>
            </div>
            <ChevronDown size={14} />
          </div>
          <small className="version">
            CAN / CONNECT <span>v0.1.0</span>
          </small>
        </div>
      </aside>
      {menu && (
        <button
          className="menu-backdrop"
          aria-label="Close navigation"
          onClick={() => setMenu(false)}
        />
      )}
      <div className="main-shell">
        <header className="topbar">
          <div className="breadcrumb">
            <button
              className="mobile-menu"
              aria-label="Open navigation"
              onClick={() => setMenu(!menu)}
            >
              <Menu size={18} />
            </button>
            <span>Workspace</span>
            <ChevronRight size={13} />
            <b>{page}</b>
          </div>
          <div className="topbar-right">
            <span>
              <span className="status-dot amber-dot" /> Parked · last known
            </span>
            <span className="sample-tag">SIMULATED DATA</span>
            <div className="avatar">KS</div>
          </div>
        </header>
        <main>
          <div className="page-heading">
            <div>
              <div className="eyebrow">
                2014 VOLKSWAGEN JETTA TDI <span>/</span> PERSONAL TELEMETRY
              </div>
              <h1>
                {page}
                <span className="heading-dot">.</span>
              </h1>
              <p>
                {page === "Overview"
                  ? "Every drive. Every signal. One connected view."
                  : page === "Trips"
                    ? "Recorded journeys, replay and synchronized vehicle signals."
                    : "Your vehicle data, organized for investigation."}
              </p>
            </div>
            <div className="heading-actions">
              {page === "Overview" &&
                (editing ? (
                  <>
                    <button onClick={() => setLibrary(true)}>
                      <Plus size={14} /> Add widget
                    </button>
                    <button
                      onClick={() => {
                        setDraft(null);
                        setLibrary(false);
                        setSettingsId(null);
                        setNotice("Changes discarded");
                      }}
                    >
                      Cancel
                    </button>
                    <button
                      className="primary"
                      onClick={() => {
                        if (persist(draft!)) {
                          setDraft(null);
                          setLibrary(false);
                          setSettingsId(null);
                          setNotice("Dashboard layout saved");
                        }
                      }}
                    >
                      <Check size={14} /> Save layout
                    </button>
                  </>
                ) : (
                  <>
                    <span className="period-label">
                      October 2026 <ChevronDown size={13} />
                    </span>
                    <button onClick={() => setDraft(copy(saved))}>
                      <SlidersHorizontal size={14} /> Customize
                    </button>
                  </>
                ))}
            </div>
          </div>
          <div className="vehicle-strip">
            <span>
              <CarFront size={16} />
              <b>Jetta TDI</b>
              <span className="muted">CJAA / 2014</span>
            </span>
            <span>
              <i className="status-dot amber-dot" /> Recorder offline
            </span>
            <span>
              Recorded{" "}
              <b>
                {new Date(snapshot.recordedAt).toLocaleTimeString([], {
                  hour: "2-digit",
                  minute: "2-digit",
                })}
              </b>
            </span>
            <span>
              Ingested{" "}
              <b>
                {new Date(snapshot.ingestedAt).toLocaleTimeString([], {
                  hour: "2-digit",
                  minute: "2-digit",
                })}
              </b>
            </span>
            <span className="strip-end">
              <Database size={13} /> Local demo dataset
            </span>
          </div>
          {editing && (
            <div className="edit-banner">
              <Grip size={16} />
              <span>
                <b>Customize dashboard</b> · Drag headers to move. Resize from
                any edge or corner. Controls remain interactive.
              </span>
              <span className="muted">12-column grid · {breakpoint}</span>
            </div>
          )}
          {page === "Overview" ? (
            <div
              className={`dashboard ${editing ? "editing" : ""}`}
              ref={container}
            >
              <Responsive
                width={width}
                layouts={dashboard.layouts}
                breakpoints={{ lg: 1000, md: 700, sm: 480, xs: 0 }}
                cols={{ lg: 12, md: 8, sm: 6, xs: 4 }}
                rowHeight={28}
                margin={[12, 12]}
                containerPadding={[0, 0]}
                isDraggable={editing}
                isResizable={editing}
                draggableHandle=".widget-header"
                draggableCancel="button,select,input,.widget-tools"
                resizeHandles={["s", "w", "e", "n", "sw", "nw", "se", "ne"]}
                compactType="vertical"
                preventCollision={false}
                onLayoutChange={onLayout}
                onBreakpointChange={setBreakpoint}
              >
                {dashboard.widgets.map((w) => (
                  <section
                    key={w.id}
                    className={`widget kind-${w.kind}`}
                    data-widget-id={w.id}
                    aria-label={`${definition(w.kind).title} widget`}
                  >
                    <header
                      className="widget-header"
                      title={w.settings.title || definition(w.kind).title}
                    >
                      <div>
                        {editing && <Grip size={13} />}
                        <span>
                          {w.settings.title || definition(w.kind).title}
                        </span>
                        {["heatmap", "dpf", "activity"].includes(w.kind) && (
                          <span className="widget-subtag">
                            {w.kind === "heatmap"
                              ? "GPS"
                              : w.kind === "dpf"
                                ? "TDI"
                                : "LOG"}
                          </span>
                        )}
                      </div>
                      <div className="widget-tools">
                        {editing && (
                          <>
                            <button
                              title="Duplicate widget"
                              aria-label={`Duplicate ${definition(w.kind).title}`}
                              onClick={() => add(w.kind, w)}
                            >
                              <Copy size={12} />
                            </button>
                            <button
                              title="Remove widget"
                              aria-label={`Remove ${definition(w.kind).title}`}
                              onClick={() => remove(w.id)}
                            >
                              <Trash2 size={12} />
                            </button>
                          </>
                        )}
                        <button
                          title="Widget settings"
                          aria-label={`Settings ${definition(w.kind).title}`}
                          onClick={() => setSettingsId(w.id)}
                        >
                          <Settings2 size={12} />
                        </button>
                      </div>
                    </header>
                    <div className="widget-body">
                      <WidgetContent
                        widget={w}
                        onChange={(settings) => changeSettings(w.id, settings)}
                      />
                    </div>
                  </section>
                ))}
              </Responsive>
              {!dashboard.widgets.length && (
                <div className="empty-state">
                  <LayoutDashboard size={28} />
                  <h2>Your dashboard, your way</h2>
                  <p>Add your first widget from the library.</p>
                  <button onClick={() => setLibrary(true)}>
                    Open widget library
                  </button>
                </div>
              )}
            </div>
          ) : (
            <Workspace page={page} />
          )}
          <footer>
            <span>
              <i className="status-dot" /> All displayed vehicle values are
              simulated. Unverified signals are labeled.
            </span>
            <span>
              Recorded time is the source of truth <ArrowDownToLine size={12} />
            </span>
          </footer>
        </main>
      </div>
      {library && (
        <div className="modal-backdrop" onClick={() => setLibrary(false)}>
          <section
            className="library"
            role="dialog"
            aria-modal="true"
            aria-label="Widget library"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="drawer-heading">
              <div>
                <span className="eyebrow">BUILD YOUR WORKSPACE</span>
                <h2>
                  Widget library <span>{registry.length}</span>
                </h2>
              </div>
              <button
                aria-label="Close widget library"
                onClick={() => setLibrary(false)}
              >
                <X size={18} />
              </button>
            </div>
            <label className="search">
              <Search size={16} />
              <input
                autoFocus
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Search widgets, signals, systems…"
                aria-label="Search widget library"
              />
            </label>
            <div className="categories">
              {["All", ...new Set(registry.map((d) => d.group))].map((g) => (
                <button
                  key={g}
                  onClick={() => setGroup(g)}
                  className={group === g ? "selected" : ""}
                >
                  {g}
                </button>
              ))}
            </div>
            <div className="catalog">
              {registry
                .filter(
                  (d) =>
                    (group === "All" || d.group === group) &&
                    `${d.title} ${d.group} ${d.note}`
                      .toLowerCase()
                      .includes(query.toLowerCase()),
                )
                .map((d) => (
                  <button
                    className="catalog-item"
                    key={d.kind}
                    onClick={() => add(d.kind)}
                  >
                    <span className="catalog-icon">
                      {d.group === "Maps" ? (
                        <Navigation size={18} />
                      ) : d.group === "Fuel" ? (
                        <Fuel size={18} />
                      ) : (
                        <CircleGauge size={18} />
                      )}
                    </span>
                    <div>
                      <b>{d.title}</b>
                      <p>{d.note}</p>
                      <small>
                        {d.group.toUpperCase()} · {d.w} × {d.h}{" "}
                        {d.unsupported ? "· UNSUPPORTED" : ""}
                      </small>
                    </div>
                    <Plus size={16} />
                  </button>
                ))}
            </div>
            <div className="drawer-footer">
              Add as many instances as you need. Each keeps its own settings.
            </div>
          </section>
        </div>
      )}
      {settingsWidget && (
        <div className="modal-backdrop" onClick={() => setSettingsId(null)}>
          <section
            className="settings-dialog"
            role="dialog"
            aria-modal="true"
            aria-label="Widget settings"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="drawer-heading">
              <h2>Widget settings</h2>
              <button
                aria-label="Close widget settings"
                onClick={() => setSettingsId(null)}
              >
                <X size={18} />
              </button>
            </div>
            <label>
              Display title
              <input
                aria-label="Widget title"
                value={settingsWidget.settings.title || ""}
                placeholder={definition(settingsWidget.kind).title}
                onChange={(e) =>
                  changeSettings(settingsWidget.id, {
                    ...settingsWidget.settings,
                    title: e.target.value,
                  })
                }
              />
            </label>
            <label>
              Statistics period
              <select
                aria-label="Widget statistics period"
                value={settingsWidget.settings.period || "all"}
                onChange={(e) =>
                  changeSettings(settingsWidget.id, {
                    ...settingsWidget.settings,
                    period: e.target.value,
                  })
                }
              >
                <option value="all">All sample history</option>
                <option value="7">Last 7 days</option>
                <option value="14">Last 14 days</option>
              </select>
            </label>
            <p className="muted">
              Period affects driving totals. Map and chart controls are inside
              the widget.{" "}
              {editing
                ? "Changes are part of your layout draft."
                : "Changes save automatically in this browser."}
            </p>
            <button className="primary" onClick={() => setSettingsId(null)}>
              Done
            </button>
          </section>
        </div>
      )}
      {notice && (
        <div className="toast" role="status">
          {notice}
          <button
            aria-label="Dismiss notification"
            onClick={() => setNotice("")}
          >
            <X size={14} />
          </button>
        </div>
      )}
    </div>
  );
}
