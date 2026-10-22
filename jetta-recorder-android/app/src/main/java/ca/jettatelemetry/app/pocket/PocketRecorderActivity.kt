package ca.jettatelemetry.app.pocket

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.*
import android.text.InputType
import android.view.ViewGroup
import android.widget.*
import ca.jettatelemetry.app.obd.ObdLinkTransport
import java.io.File
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** A deliberately small platform-only screen: no Compose startup or chart dependencies. */
class PocketRecorderActivity : Activity() {
    private lateinit var devices: Spinner
    private lateinit var status: TextView
    private lateinit var values: TextView
    private lateinit var queue: TextView
    private lateinit var endpoint: EditText
    private lateinit var token: EditText
    private lateinit var unmetered: CheckBox
    private val handler = Handler(Looper.getMainLooper())
    private var addresses = emptyList<String>()
    private val refresh = object : Runnable { override fun run() { render(); handler.postDelayed(this, 1_000) } }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val content = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(18), dp(18), dp(18), dp(24)); setBackgroundColor(Color.rgb(12, 17, 24)) }
        fun label(text: String, size: Float = 13f) = TextView(this).apply { this.text = text; textSize = size; setTextColor(Color.rgb(176, 196, 216)); setPadding(0, dp(8), 0, dp(8)) }
        fun button(text: String, action: () -> Unit) = Button(this).apply { this.text = text; setOnClickListener { runCatching(action).onFailure { toast(it.message ?: "Operation failed") } } }
        content.addView(label("CAN / CONNECT", 24f)); content.addView(label("POCKET RECORDER · JETTA 2014\nObserved standard OBD requests · real data only"))
        status = label("Stopped", 16f); content.addView(status)
        content.addView(button("Grant Bluetooth / GPS permissions") { permissions() })
        devices = Spinner(this); content.addView(devices)
        content.addView(button("Refresh paired adapters") { loadDevices() })
        content.addView(button("Connect & record") {
            check(Build.VERSION.SDK_INT < 31 || checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED) { "Grant Bluetooth permission first" }
            val address = addresses.getOrNull(devices.selectedItemPosition) ?: error("Pair the OBDLink MX+ in Android settings, then refresh")
            saveSettings()
            startForegroundService(Intent(this, PocketRecorderService::class.java).putExtra("address", address))
        })
        content.addView(button("Stop recording") { startService(Intent(this, PocketRecorderService::class.java).setAction("stop")) })
        values = label("Waiting for vehicle data…", 14f).apply { typeface = android.graphics.Typeface.MONOSPACE }; content.addView(values)
        content.addView(label("DPF regeneration trigger is not verified soot %. Missing/stale values are never shown as current."))
        content.addView(label("UPLOAD DESTINATION", 16f))
        val preferences = getSharedPreferences("pocket", Context.MODE_PRIVATE)
        endpoint = EditText(this).apply { hint = "HTTPS ingestion URL (optional)"; inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI; setSingleLine(); setText(preferences.getString("endpoint", "")) }
        token = EditText(this).apply { hint = "Ingestion bearer token"; inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD; setSingleLine(); setText(preferences.getString("token", "")) }
        unmetered = CheckBox(this).apply { text = "Upload on unmetered networks only"; isChecked = preferences.getBoolean("unmetered", false) }
        content.addView(endpoint); content.addView(token); content.addView(unmetered)
        content.addView(button("Save upload settings & queue uploads") { saveSettings(); PocketUploadWorker.enqueue(this); toast("Settings saved; recordings stay on phone") })
        queue = label(""); content.addView(queue)
        content.addView(button("Export completed recordings (ZIP)") {
            startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
                .setType("application/zip").putExtra(Intent.EXTRA_TITLE, "can-connect-recordings.zip"), 91)
        })
        content.addView(label("Configure permissions and connect while parked. Recording continues in a foreground service with a notification. Uploads target only the endpoint you enter. No Car Scanner installation is required."))
        setContentView(ScrollView(this).apply { addView(content, ViewGroup.LayoutParams(-1, -2)) })
        loadDevices()
    }
    override fun onResume() { super.onResume(); handler.post(refresh) }
    override fun onPause() { handler.removeCallbacks(refresh); super.onPause() }
    private fun render() {
        status.text = PocketState.status + "\n" + PocketState.gps
        val names = linkedMapOf("speed" to "Speed", "rpm" to "RPM", "fuel_rate" to "Fuel rate", "coolant" to "Coolant", "ambient" to "Ambient", "boost_absolute" to "Boost absolute", "baro" to "Barometric", "egt_1" to "EGT bank1 sensor1", "dpf_delta_pressure" to "DPF delta pressure", "dpf_regen_active" to "DPF regen active", "dpf_regen_trigger" to "DPF regen trigger", "ecu_voltage" to "ECU voltage")
        val now = SystemClock.elapsedRealtime()
        val lines = names.map { (id, title) ->
            val reading = PocketState.readings[id]
            val stale = reading == null || !PocketState.recording || now - reading.elapsedMs > (if (id == "baro") 120_000 else 30_000)
            "$title: " + if (reading == null) "—" else String.format(Locale.US, "%.2f %s%s", reading.value, reading.unit, if (stale) " [last known]" else "")
        }.toMutableList()
        val boost = PocketState.readings["boost_absolute"]; val baro = PocketState.readings["baro"]
        if (PocketState.recording && boost != null && baro != null && now - boost.elapsedMs < 5_000 && now - baro.elapsedMs < 120_000) lines += String.format(Locale.US, "Gauge boost: %.2f psi", (boost.value - baro.value) * 0.1450377377)
        val speed = PocketState.readings["speed"]; val fuel = PocketState.readings["fuel_rate"]
        if (PocketState.recording && speed != null && fuel != null && now - speed.elapsedMs < 5_000 && now - fuel.elapsedMs < 5_000) lines += if (speed.value > 1) String.format(Locale.US, "Instant economy: %.2f L/100km", 100 * fuel.value / speed.value) else "Stationary: fuel rate in L/h"
        values.text = lines.joinToString("\n")
        val store = PocketStore(this); queue.text = "${store.completed().size} completed · ${store.pending().size} queued\n${PocketState.upload}"
    }
    private fun permissions() {
        val wanted = mutableListOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
        if (Build.VERSION.SDK_INT >= 31) wanted += Manifest.permission.BLUETOOTH_CONNECT
        if (Build.VERSION.SDK_INT >= 33) wanted += Manifest.permission.POST_NOTIFICATIONS
        requestPermissions(wanted.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }.toTypedArray(), 90)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) { super.onRequestPermissionsResult(requestCode, permissions, grantResults); loadDevices() }
    private fun loadDevices() {
        val paired = runCatching { ObdLinkTransport(this).bondedDevices() }.getOrDefault(emptyList())
        addresses = paired.map { it.address }
        devices.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, paired.map { "${it.name} · ${it.address}" }.ifEmpty { listOf("No paired adapters / permission required") })
    }
    private fun saveSettings() {
        getSharedPreferences("pocket", Context.MODE_PRIVATE).edit().putString("endpoint", endpoint.text.toString().trim())
            .putString("token", token.text.toString().trim()).putBoolean("unmetered", unmetered.isChecked).apply()
    }
    @Deprecated("Platform result callback") override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 91 || resultCode != RESULT_OK) return
        val uri = data?.data ?: return
        Thread {
            runCatching {
                val files = PocketStore(this).completed()
                check(files.isNotEmpty()) { "No completed recordings; stop the recorder first" }
                ZipOutputStream(contentResolver.openOutputStream(uri) ?: error("Cannot open destination")).use { zip ->
                    for (file: File in files) { zip.putNextEntry(ZipEntry(file.name)); file.inputStream().use { it.copyTo(zip) }; zip.closeEntry() }
                }
            }.onSuccess { runOnUiThread { toast("Recordings exported") } }.onFailure { runOnUiThread { toast(it.message ?: "Export failed") } }
        }.start()
    }
    private fun dp(value: Int) = (resources.displayMetrics.density * value).toInt()
    private fun toast(message: String) = Toast.makeText(this, message, Toast.LENGTH_LONG).show()
}
