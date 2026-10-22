import { useMemo, useState } from 'react'
import {
  Activity, ArrowDownToLine, BatteryCharging, CarFront, ChevronRight, CircleGauge,
  Cloud, Database, Fuel, Gauge, History, House, Menu, Navigation, Settings,
  ShieldCheck, Signal, Thermometer, UploadCloud, Wifi, X,
} from 'lucide-react'
import { chartData, trips, uploads, type Trip } from './model'

type Page = 'overview' | 'trips' | 'vehicle' | 'sync'

const navItems: { id: Page; label: string; icon: typeof House }[] = [
  { id: 'overview', label: 'Overview', icon: House },
  { id: 'trips', label: 'Trips', icon: Navigation },
  { id: 'vehicle', label: 'Vehicle', icon: CarFront },
  { id: 'sync', label: 'Data sync', icon: UploadCloud },
]

function Sparkline({ values = chartData }: { values?: number[] }) {
  const points = values.map((v, i) => `${(i / (values.length - 1)) * 100},${42 - (v - 4.6) * 22}`).join(' ')
  return <svg className="sparkline" viewBox="0 0 100 46" preserveAspectRatio="none" aria-label="Fuel consumption trend"><path d={`M ${points} L 100 46 L 0 46 Z`} /><polyline points={points} /></svg>
}

function SyncPill() {
  return <div className="sync-pill"><span className="pulse" /> <Signal size={14} /> LTE <span className="muted">· 3 bars</span></div>
}

function Sidebar({ page, setPage, open, onClose }: { page: Page; setPage: (p: Page) => void; open: boolean; onClose: () => void }) {
  return <aside className={`sidebar ${open ? 'open' : ''}`}>
    <button className="mobile-close" onClick={onClose} aria-label="Close menu"><X /></button>
    <div className="brand"><div className="brand-mark"><span>JT</span></div><div><strong>JETTA</strong><small>TELEMETRY</small></div></div>
    <nav>{navItems.map(({ id, label, icon: Icon }) => <button key={id} className={page === id ? 'active' : ''} onClick={() => { setPage(id); onClose() }}><Icon size={19} />{label}{id === 'sync' && <span className="nav-badge">1</span>}</button>)}</nav>
    <div className="sidebar-bottom">
      <div className="car-mini"><CarFront size={22} /><div><strong>2014 Jetta TDI</strong><small>CJAA · PPY</small></div><span className="status-dot" /></div>
      <button className="settings-row"><Settings size={18} />Settings</button>
    </div>
  </aside>
}

function Metric({ label, value, unit, icon: Icon, accent }: { label: string; value: string; unit: string; icon: typeof Gauge; accent?: boolean }) {
  return <div className={`metric ${accent ? 'accent' : ''}`}><div className="metric-label"><Icon size={16} />{label}</div><div><strong>{value}</strong><span>{unit}</span></div></div>
}

function RouteMap({ trip, large = false }: { trip: Trip; large?: boolean }) {
  return <div className={`route-map ${large ? 'large' : ''}`}>
    <div className="map-road r1" /><div className="map-road r2" /><div className="map-road r3" />
    <svg viewBox="0 0 276 116" preserveAspectRatio="none" role="img" aria-label={`Route from ${trip.origin} to ${trip.destination}`}>
      <path className="route-shadow" d={trip.route} /><path className="route-line" d={trip.route} />
      <circle className="route-start" cx="18" cy={trip.id === 't2' ? '24' : trip.id === 't3' ? '86' : '91'} r="5" />
      <circle className="route-end" cx="258" cy={trip.id === 't2' ? '96' : trip.id === 't3' ? '17' : '20'} r="6" />
    </svg>
    <span className="map-label ml1">RIVER RD</span><span className="map-label ml2">HWY 7</span>
  </div>
}

function Overview({ openTrip }: { openTrip: (t: Trip) => void }) {
  return <>
    <section className="hero-grid">
      <div className="vehicle-card card">
        <div className="eyebrow"><span className="live-dot" /> VEHICLE ONLINE</div>
        <div className="vehicle-head"><div><h1>Parked at home</h1><p>Last updated 12 seconds ago</p></div><div className="signal-badge"><Signal size={17} /> LTE</div></div>
        <div className="vehicle-visual"><div className="car-silhouette"><CarFront /></div><div className="range-ring"><strong>624</strong><span>km range</span></div></div>
        <div className="status-strip"><span><ShieldCheck size={17} /> No warnings</span><span><BatteryCharging size={17} /> 14.2 V</span><span><Database size={17} /> Recording</span></div>
      </div>
      <div className="today-card card">
        <div className="card-title"><div><span className="kicker">TODAY</span><h2>24.8 km</h2></div><span className="score">91 <small>drive score</small></span></div>
        <div className="chart-value"><strong>5.2</strong><span>L/100 km average</span></div><Sparkline />
        <div className="chart-axis"><span>Start</span><span>Now</span></div>
      </div>
    </section>
    <section className="metrics-grid">
      <Metric label="Fuel level" value="63" unit="%" icon={Fuel} accent />
      <Metric label="Coolant" value="89" unit="°C" icon={Thermometer} />
      <Metric label="Oil temp" value="94" unit="°C" icon={Thermometer} />
      <Metric label="Boost" value="0.0" unit="bar" icon={Gauge} />
    </section>
    <section className="section-head"><div><span className="kicker">RECENT ACTIVITY</span><h2>Your latest drives</h2></div><button className="text-button">View all <ChevronRight size={17} /></button></section>
    <div className="trip-row-grid">{trips.slice(0, 2).map(t => <button className="trip-card card" key={t.id} onClick={() => openTrip(t)}><RouteMap trip={t} /><div className="trip-content"><div className="trip-title"><strong>{t.origin} <span>→</span> {t.destination}</strong><small>{t.day}, {t.time}</small></div><div className="trip-stats"><span><b>{t.distanceKm}</b> km</span><span><b>{t.economy}</b> L/100</span><span><b>{t.duration}</b></span></div></div></button>)}</div>
  </>
}

function TripsPage({ openTrip }: { openTrip: (t: Trip) => void }) {
  return <><section className="page-intro"><span className="kicker">DRIVE HISTORY</span><h1>Trips</h1><p>Every drive, automatically recorded and ready to explore.</p></section><div className="trips-list">{trips.map(t => <button className="trip-list-item card" key={t.id} onClick={() => openTrip(t)}><RouteMap trip={t} /><div className="trip-list-main"><div><span className="date-label">{t.date} · {t.time}</span><h3>{t.origin} <span>→</span> {t.destination}</h3></div><div className="trip-list-stats"><span><b>{t.distanceKm}</b> km</span><span><b>{t.duration}</b> duration</span><span><b>{t.economy}</b> L/100 km</span><span><b>{t.score}</b> score</span></div></div><div className={`cloud-state ${t.uploaded ? '' : 'pending'}`}>{t.uploaded ? <Cloud size={18} /> : <Wifi size={18} />}<small>{t.uploaded ? 'Synced' : 'Wi‑Fi queued'}</small></div><ChevronRight /></button>)}</div></>
}

function VehiclePage() {
  return <><section className="page-intro"><span className="kicker">VEHICLE HEALTH</span><h1>2014 Jetta TDI</h1><p>Live and learned state from the normalized vehicle feed.</p></section>
    <div className="health-grid">
      <div className="card health-main"><div className="vehicle-visual"><div className="car-silhouette big"><CarFront /></div></div><div className="health-ok"><ShieldCheck /><div><strong>Everything looks good</strong><span>No active warnings or stale safety data</span></div></div></div>
      <div className="card dpf-card"><div className="metric-label"><Activity size={17} /> DPF STATUS</div><div className="soot-gauge"><div style={{ width: '38%' }} /><span>38%</span></div><h3>Normal loading</h3><p>12.4 g calculated soot · last regeneration 286 km ago</p><div className="sub-metrics"><span><b>241°C</b> inlet</span><span><b>228°C</b> outlet</span></div></div>
      <div className="card sensor-card"><h3>Drivetrain</h3><div><span>Coolant</span><b>89 °C</b></div><div><span>Oil</span><b>94 °C</b></div><div><span>Transmission</span><b>76 °C</b></div><div><span>Battery</span><b>14.2 V</b></div></div>
      <div className="card sensor-card"><h3>Fuel & range</h3><div><span>Tank level</span><b>63%</b></div><div><span>Estimated range</span><b>624 km</b></div><div><span>Trip average</span><b>5.2 L/100</b></div><div><span>Lifetime average</span><b>5.6 L/100</b></div></div>
    </div></>
}

function SyncPage() {
  const [threshold, setThreshold] = useState(25)
  return <><section className="page-intro sync-intro"><div><span className="kicker">LOCAL-FIRST PIPELINE</span><h1>Data sync</h1><p>Small telemetry moves over cellular. Heavy captures wait for trusted Wi‑Fi.</p></div><div className="pipeline-status"><span className="pulse" /><strong>Recording locally</strong><small>Nothing blocks live instruments</small></div></section>
    <div className="sync-layout"><div className="queue card"><div className="card-heading"><div><span className="kicker">UPLOAD QUEUE</span><h2>3 data bundles</h2></div><span className="queue-total">197.1 MB</span></div>{uploads.map(item => <div className="upload-item" key={item.id}><div className={`upload-icon ${item.state}`} >{item.state === 'waiting-wifi' ? <Wifi /> : item.state === 'complete' ? <ShieldCheck /> : <UploadCloud />}</div><div className="upload-info"><div><strong>{item.label}</strong><span>{item.sizeMb} MB</span></div><p>{item.detail}</p><div className="progress"><div style={{ width: `${item.progress}%` }} /></div><small>{item.state === 'waiting-wifi' ? `Paused at ${item.progress}% · waiting for trusted Wi‑Fi` : item.state === 'complete' ? 'Safely stored in cloud' : `${item.progress}% · uploading over LTE`}</small></div></div>)}</div>
      <aside className="sync-settings"><div className="card rule-card"><div className="rule-icon"><ArrowDownToLine /></div><h3>Smart upload rule</h3><p>Bundles larger than your limit stay encrypted on the telemetry box until trusted Wi‑Fi is available.</p><label>Cellular size limit <output>{threshold} MB</output><input type="range" min="5" max="100" step="5" value={threshold} onChange={e => setThreshold(Number(e.target.value))} /></label><div className="rule-example"><Wifi size={18} /><span><strong>Raw CAN → Wi‑Fi</strong><small>Resumable 8 MB chunks</small></span></div><div className="rule-example"><Signal size={18} /><span><strong>Trips → cellular</strong><small>Summaries, events, positions</small></span></div></div><div className="card storage-card"><span>LOCAL STORAGE</span><strong>18.6 <small>/ 64 GB</small></strong><div className="progress"><div style={{ width: '29%' }} /></div><p>About 42 hours of full-rate capture available</p></div></aside>
    </div></>
}

function TripDetail({ trip, onClose }: { trip: Trip; onClose: () => void }) {
  return <div className="modal-backdrop" onClick={onClose}><article className="trip-detail" onClick={e => e.stopPropagation()}><button className="modal-close" onClick={onClose}><X /></button><RouteMap trip={trip} large /><div className="detail-body"><span className="kicker">{trip.date.toUpperCase()} · {trip.time}</span><h2>{trip.origin} <span>→</span> {trip.destination}</h2><div className="detail-metrics"><Metric label="Distance" value={String(trip.distanceKm)} unit="km" icon={Navigation} /><Metric label="Economy" value={String(trip.economy)} unit="L/100" icon={Fuel} accent /><Metric label="Maximum" value={String(trip.maxSpeed)} unit="km/h" icon={CircleGauge} /><Metric label="Drive score" value={String(trip.score)} unit="/ 100" icon={ShieldCheck} /></div><div className="detail-chart"><div><strong>Fuel consumption</strong><span>Average {trip.economy} L/100 km</span></div><Sparkline values={[5.1, 5.8, 5.3, 4.8, 6.1, 5.5, 5.0, 4.9, 5.4, trip.economy]} /></div></div></article></div>
}

export default function App() {
  const [page, setPage] = useState<Page>('overview')
  const [menuOpen, setMenuOpen] = useState(false)
  const [selectedTrip, setSelectedTrip] = useState<Trip | null>(null)
  const title = useMemo(() => navItems.find(n => n.id === page)?.label, [page])
  return <div className="app-shell">
    <Sidebar page={page} setPage={setPage} open={menuOpen} onClose={() => setMenuOpen(false)} />
    {menuOpen && <div className="menu-scrim" onClick={() => setMenuOpen(false)} />}
    <main><header><button className="menu-button" onClick={() => setMenuOpen(true)} aria-label="Open menu"><Menu /></button><div className="mobile-title">{title}</div><div className="header-right"><SyncPill /><div className="clock"><strong>07:42</strong><small>THU, OCT 22</small></div><button className="avatar" aria-label="User profile">K</button></div></header>
      <div className="content">{page === 'overview' && <Overview openTrip={setSelectedTrip} />}{page === 'trips' && <TripsPage openTrip={setSelectedTrip} />}{page === 'vehicle' && <VehiclePage />}{page === 'sync' && <SyncPage />}</div>
    </main>{selectedTrip && <TripDetail trip={selectedTrip} onClose={() => setSelectedTrip(null)} />}
  </div>
}
