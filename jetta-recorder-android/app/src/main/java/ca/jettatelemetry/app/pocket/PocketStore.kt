package ca.jettatelemetry.app.pocket

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URI
import java.security.MessageDigest
import java.time.Instant
import java.util.UUID

/** Append-only private recordings. Upload receipts never delete the original file. */
class PocketStore(context: Context) {
    val directory = File(context.filesDir, "pocket-recordings").apply { mkdirs() }
    private var file: File? = null
    private var writer: java.io.BufferedWriter? = null

    @Synchronized fun begin() {
        check(writer == null)
        // A process killed mid-trip leaves .active files. Preserve them for later ingestion.
        directory.listFiles()?.filter { it.name.endsWith(".active") }?.forEach {
            check(it.renameTo(File(directory, it.name.removeSuffix(".active") + ".jsonl"))) { "Cannot recover recording" }
        }
        file = File(directory, "${Instant.now().epochSecond}-${UUID.randomUUID()}.active")
        writer = file!!.bufferedWriter()
        append(JSONObject().put("type", "session_start").put("schemaVersion", 1)
            .put("vehicleId", "jetta-2014").put("source", "pocket-obd").put("recordedAt", Instant.now().toString()))
    }

    @Synchronized fun append(row: JSONObject) {
        writer?.apply { write(row.toString()); newLine(); flush() }
    }

    @Synchronized fun finish() {
        writer?.close(); writer = null
        file?.let { check(it.renameTo(File(directory, it.name.removeSuffix(".active") + ".jsonl"))) { "Cannot finalize recording" } }
        file = null
    }

    fun completed(): List<File> = directory.listFiles()?.filter { it.extension == "jsonl" }?.sortedBy { it.name }.orEmpty()
    fun pending(): List<File> = completed().filter { !File(directory, it.name + ".uploaded").exists() }

    companion object {
        private val uploadLock = Any()
        fun sha256(file: File): String {
            val digest = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input -> val buffer = ByteArray(65536); while (true) { val n = input.read(buffer); if (n < 0) break; digest.update(buffer, 0, n) } }
            return digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
        }
        /** The endpoint must acknowledge the digest in JSON. A login/HTML 200 cannot discard queued data. */
        fun upload(context: Context, report: (String) -> Unit) = synchronized(uploadLock) {
            val preferences = context.getSharedPreferences("pocket", Context.MODE_PRIVATE)
            val endpoint = preferences.getString("endpoint", "").orEmpty().trim()
            val token = preferences.getString("token", "").orEmpty().trim()
            if (endpoint.isBlank()) { report("Uploads paused: configure an HTTPS ingestion endpoint"); return@synchronized }
            val uri = URI(endpoint)
            require(uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.userInfo == null && uri.fragment == null) { "Use an HTTPS ingestion URL" }
            require(token.isNotBlank()) { "Set your ingestion bearer token" }
            val store = PocketStore(context)
            for (file in store.pending()) {
                val checksum = sha256(file)
                val connection = uri.toURL().openConnection() as HttpURLConnection
                try {
                    connection.requestMethod = "POST"; connection.doOutput = true
                    connection.instanceFollowRedirects = false
                    connection.connectTimeout = 15_000; connection.readTimeout = 30_000
                    connection.setRequestProperty("Content-Type", "application/x-ndjson")
                    connection.setRequestProperty("Authorization", "Bearer $token")
                    connection.setRequestProperty("X-Recording-Id", file.name)
                    connection.setRequestProperty("X-Content-SHA256", checksum)
                    connection.setFixedLengthStreamingMode(file.length())
                    connection.outputStream.use { output -> file.inputStream().use { it.copyTo(output) } }
                    check(connection.responseCode in 200..299) { "Upload HTTP ${connection.responseCode}; file retained" }
                    val body = connection.inputStream.use { input ->
                        val buffer = ByteArray(8192); var used = 0
                        while (used < buffer.size) { val count = input.read(buffer, used, buffer.size - used); if (count < 0) break; used += count }
                        String(buffer, 0, used, Charsets.UTF_8)
                    }
                    check(JSONObject(body).optString("sha256") == checksum) { "Missing server acknowledgement; file retained" }
                    File(store.directory, file.name + ".uploaded").writeText(checksum)
                    report("Uploaded ${file.name}")
                } finally { connection.disconnect() }
            }
            report("Upload queue complete; originals retained")
        }
    }
}
