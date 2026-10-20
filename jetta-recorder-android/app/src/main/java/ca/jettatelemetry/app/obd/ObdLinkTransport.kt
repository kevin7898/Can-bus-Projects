package ca.jettatelemetry.app.obd

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import ca.jettatelemetry.app.model.PairedObdDevice
import java.io.InputStream
import java.io.OutputStream
import java.nio.charset.StandardCharsets
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.atomic.AtomicBoolean

data class ObdReply(
    val command: String,
    val body: String,
    val latencyMillis: Long
)

class ObdLinkTransport(context: Context) {
    private val bluetoothManager = context.getSystemService(BluetoothManager::class.java)
    private val adapter: BluetoothAdapter?
        get() = bluetoothManager?.adapter

    private val requestMutex = Mutex()
    private var socket: BluetoothSocket? = null
    private var input: InputStream? = null
    private var output: OutputStream? = null
    private val monitoring = AtomicBoolean(false)

    @SuppressLint("MissingPermission")
    fun bondedDevices(): List<PairedObdDevice> =
        adapter?.bondedDevices
            ?.sortedWith(compareBy<BluetoothDevice>({ !looksLikeObdAdapter(it.name) }, { it.name ?: "" }))
            ?.map { PairedObdDevice(it.name ?: "Unnamed Bluetooth device", it.address) }
            .orEmpty()

    @SuppressLint("MissingPermission")
    suspend fun connect(address: String) = withContext(Dispatchers.IO) {
        disconnect()
        val bluetoothAdapter = requireNotNull(adapter) { "Bluetooth is not available on this phone" }
        check(bluetoothAdapter.isEnabled) { "Bluetooth is turned off" }
        val device = bluetoothAdapter.getRemoteDevice(address)
        bluetoothAdapter.cancelDiscovery()

        val candidate = device.createRfcommSocketToServiceRecord(SPP_UUID)
        try {
            candidate.connect()
            socket = candidate
            input = candidate.inputStream
            output = candidate.outputStream
            drainInput()
        } catch (failure: Throwable) {
            runCatching { candidate.close() }
            throw failure
        }
    }

    suspend fun request(command: String, timeoutMillis: Long = 2_500): ObdReply =
        requestMutex.withLock {
            withContext(Dispatchers.IO) {
                val writer = requireNotNull(output) { "Adapter is not connected" }
                val started = System.nanoTime()
                writer.write((command.trim() + "\r").toByteArray(StandardCharsets.US_ASCII))
                writer.flush()
                val reader = requireNotNull(input) { "Adapter input is not available" }
                val body = readObdPrompt(reader, command.trim(), timeoutMillis)
                ObdReply(command.trim(), body, (System.nanoTime() - started) / 1_000_000)
            }
        }

    /**
     * Enter the STN streaming monitor. This owns the request mutex until the
     * adapter prints its next command prompt. Call [stopMonitor] from another
     * coroutine to send the single-character escape required by STN firmware.
     */
    suspend fun monitor(command: String = "STM", onLine: (String) -> Unit) =
        requestMutex.withLock {
            withContext(Dispatchers.IO) {
                check(monitoring.compareAndSet(false, true)) { "Raw CAN monitor is already running" }
                try {
                    val writer = requireNotNull(output) { "Adapter is not connected" }
                    val reader = requireNotNull(input) { "Adapter input is not available" }
                    writer.write((command.trim() + "\r").toByteArray(StandardCharsets.US_ASCII))
                    writer.flush()

                    val line = StringBuilder()
                    while (true) {
                        if (reader.available() == 0) {
                            delay(2)
                            continue
                        }
                        val byte = reader.read()
                        check(byte >= 0) { "Adapter disconnected while monitoring" }
                        when (val character = byte.toChar()) {
                            '>' -> {
                                line.toString().trim().takeIf(String::isNotBlank)?.let(onLine)
                                break
                            }
                            '\r', '\n' -> {
                                line.toString().trim().takeIf(String::isNotBlank)?.let(onLine)
                                line.clear()
                            }
                            else -> line.append(character)
                        }
                    }
                } finally {
                    monitoring.set(false)
                }
            }
        }

    fun stopMonitor() {
        if (!monitoring.get()) return
        val writer = output ?: return
        // Any one character stops STM. CR is discarded and cannot accidentally
        // become the next command after the STOPPED prompt.
        runCatching {
            writer.write('\r'.code)
            writer.flush()
        }
    }

    suspend fun disconnect() = withContext(Dispatchers.IO) {
        closeImmediately()
    }

    fun closeImmediately() {
        monitoring.set(false)
        input = null
        output = null
        val oldSocket = socket
        socket = null
        runCatching { oldSocket?.close() }
    }

    private fun drainInput() {
        val reader = input ?: return
        while (reader.available() > 0) reader.read()
    }

    private fun looksLikeObdAdapter(name: String?): Boolean {
        val value = name?.uppercase().orEmpty()
        return value.contains("OBDLINK") || value.contains("MX+") || value.contains("STN") || value.contains("VLINK")
    }

    companion object {
        val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }
}

