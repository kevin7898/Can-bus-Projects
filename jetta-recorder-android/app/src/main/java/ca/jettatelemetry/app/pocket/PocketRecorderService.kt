package ca.jettatelemetry.app.pocket

import android.Manifest
import android.app.*
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.*
import ca.jettatelemetry.app.obd.ObdLinkTransport
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

object PocketState {
    data class Reading(val value: Double, val unit: String, val elapsedMs: Long)
    val readings = ConcurrentHashMap<String, Reading>()
    @Volatile var status = "Stopped"
    @Volatile var upload = "No ingestion endpoint configured"
    @Volatile var recording = false
    @Volatile var gps = "GPS not started"
    @Volatile var rates: PocketRates? = null
    @Volatile var pollMode = ""
}

class PocketRecorderService : Service(), LocationListener {
    private val running = AtomicBoolean(false)
    private lateinit var transport: ObdLinkTransport
    private lateinit var store: PocketStore
    private var gps: LocationManager? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var notificationText = "Connecting to recorder"

    override fun onCreate() {
        super.onCreate(); transport = ObdLinkTransport(this); store = PocketStore(this)
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel("pocket", "Vehicle recording", NotificationManager.IMPORTANCE_LOW))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "stop") { if (!running.getAndSet(false)) stopSelf(); transport.closeImmediately(); return START_NOT_STICKY }
        if (!running.compareAndSet(false, true)) return START_NOT_STICKY
        val address = intent?.getStringExtra("address")
        if (address.isNullOrBlank()) { running.set(false); stopSelf(); return START_NOT_STICKY }
        val hasGps = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (Build.VERSION.SDK_INT >= 29) startForeground(71, notification(),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE or (if (hasGps) ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION else 0))
        else startForeground(71, notification())
        if (hasGps) startGps() else PocketState.gps = "GPS permission not granted; OBD recording still available"
        wakeLock = getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "can-connect:recording").apply { acquire() }
        Thread({ record(address) }, "pocket-recorder").start()
        return START_NOT_STICKY
    }

    private fun record(address: String) = runBlocking {
        val failures = mutableMapOf<String, Int>()
        try {
            while (running.get()) {
                try {
                    PocketState.status = "Connecting…"; transport.connect(address)
                    val init = listOf("ATZ", "ATE0", "ATL0", "ATS0", "ATH1", "ATD0", "ATSP6", "ATAT1", "ATCAF1", "ATCFC1", "ATSH7DF", "ATCRA7E8")
                    for (command in init) {
                        if (!running.get()) break
                        val reply = transport.request(command, if (command == "ATZ") 6_000 else 2_500)
                        check(!reply.body.contains("?")) { "Adapter rejected $command" }
                    }
                    if (!running.get()) break
                    val probe = transport.request("0100", 5_000)
                    check(EngineIsoTp.messages(probe.body).any { it.take(2) == listOf(0x41, 0) }) { "No engine OBD response" }
                    store.begin(); PocketState.recording = true; PocketState.readings.clear()
                    PocketState.status = "Recording · engine ECU 7E8"; updateNotification(PocketState.status)
                    val optimized = getSharedPreferences("pocket", MODE_PRIVATE).getBoolean("optimize", true)
                    val polling = PocketPolling(optimized)
                    val due = mutableMapOf<String, Long>()
                    val rates = PocketRates(SystemClock.elapsedRealtime()); PocketState.rates = rates
                    var consecutiveEmpty = 0
                    while (running.get()) {
                        val tasks = polling.tasks()
                        val poll = tasks.minBy { due[it.id] ?: 0L }
                        val wait = (due[poll.id] ?: 0L) - SystemClock.elapsedRealtime()
                        if (wait > 0) { delay(minOf(wait, 50)); continue }
                        val started = SystemClock.elapsedRealtime()
                        val command = polling.command(poll)
                        val reply = transport.request(command, 2_500)
                        val now = SystemClock.elapsedRealtime()
                        val decodedByPid = ObservedJettaProfile.decodeMany(poll.pids, reply.body)
                        val decoded = decodedByPid.values.flatten()
                        // Publish each actual reply before writing the local log.
                        decoded.forEach { PocketState.readings[it.id] = PocketState.Reading(it.value, it.unit, now) }
                        polling.observe(poll, reply.body, decodedByPid.keys)
                        rates.add(now, decodedByPid.size, reply.latencyMillis)
                        PocketState.pollMode = if (optimized) "Grouped reads · ${polling.fallbackGroups} compatibility fallbacks" else "Individual reads · compatibility mode"
                        store.append(JSONObject().put("type", "obd").put("recordedAt", Instant.now().toString())
                            .put("elapsedMs", now).put("pids", JSONArray(poll.pids)).put("command", command)
                            .put("ecu", "7E8").put("raw", reply.body).put("latencyMs", reply.latencyMillis)
                            .put("signals", JSONArray(decoded.map { JSONObject()
                                .put("id", it.id).put("value", it.value).put("unit", it.unit) })))
                        if (decoded.isEmpty()) {
                            failures[poll.id] = (failures[poll.id] ?: 0) + 1
                            due[poll.id] = now + minOf(300_000, 30_000L * failures.getValue(poll.id))
                            consecutiveEmpty++
                        } else {
                            failures[poll.id] = 0
                            // Period runs from request start, rather than adding an extra
                            // period after every completed reply. No catch-up bursts.
                            due[poll.id] = maxOf(now, started + poll.periodMs)
                            consecutiveEmpty = 0
                        }
                        check(consecutiveEmpty < 8) { "Repeated missing replies; reconnecting" }
                    }

                } catch (failure: Exception) {
                    PocketState.status = if (running.get()) "Disconnected: ${failure.message}; retrying" else "Stopped"
                    updateNotification(PocketState.status)
                } finally {
                    PocketState.recording = false
                    runCatching { store.finish() }.onFailure { PocketState.status = "Storage error: ${it.message}"; running.set(false) }
                    transport.closeImmediately()
                }
                runCatching { PocketUploadWorker.enqueue(this@PocketRecorderService) }
                    .onFailure { PocketState.upload = "Queue error: ${it.message}" }
                if (running.get()) repeat(30) { if (running.get()) delay(1_000) }
            }
        } finally {
            running.set(false); PocketState.recording = false
            if (!PocketState.status.startsWith("Storage error")) PocketState.status = "Stopped · recordings retained"
            Handler(Looper.getMainLooper()).post { gps?.removeUpdates(this@PocketRecorderService); stopForeground(STOP_FOREGROUND_REMOVE); stopSelf() }
        }
    }

    @android.annotation.SuppressLint("MissingPermission")
    private fun startGps() {
        gps = getSystemService(LocationManager::class.java)
        runCatching {
            gps?.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1_000, 0f, this)
            PocketState.gps = "Waiting for GPS fix"
        }.onFailure { PocketState.gps = "GPS unavailable: ${it.message}" }
    }
    override fun onLocationChanged(location: Location) {
        PocketState.gps = "GPS ±${location.accuracy.toInt()} m"
        store.append(JSONObject().put("type", "gps").put("recordedAt", Instant.ofEpochMilli(location.time).toString())
            .put("elapsedNanos", location.elapsedRealtimeNanos).put("latitude", location.latitude)
            .put("longitude", location.longitude).put("accuracyM", location.accuracy)
            .put("speedMps", if (location.hasSpeed()) location.speed else JSONObject.NULL)
            .put("altitudeM", if (location.hasAltitude()) location.altitude else JSONObject.NULL))
    }
    override fun onProviderEnabled(provider: String) { PocketState.gps = "Waiting for GPS fix" }
    override fun onProviderDisabled(provider: String) { PocketState.gps = "GPS disabled" }
    @Deprecated("Legacy Android callback") override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
    override fun onBind(intent: Intent?) = null
    override fun onDestroy() { running.set(false); transport.closeImmediately(); gps?.removeUpdates(this); wakeLock?.let { if (it.isHeld) it.release() }; super.onDestroy() }

    private fun notification(): Notification {
        val stop = PendingIntent.getService(this, 0, Intent(this, PocketRecorderService::class.java).setAction("stop"), PendingIntent.FLAG_IMMUTABLE)
        val open = PendingIntent.getActivity(this, 1, Intent(this, PocketRecorderActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, "pocket").setSmallIcon(android.R.drawable.ic_menu_compass)
            .setContentTitle("CAN / CONNECT Recorder").setContentText(notificationText).setContentIntent(open)
            .setOngoing(true).addAction(Notification.Action.Builder(null, "Stop", stop).build()).build()
    }
    private fun updateNotification(text: String) {
        notificationText = text
        getSystemService(NotificationManager::class.java).notify(71, notification())
    }
}
