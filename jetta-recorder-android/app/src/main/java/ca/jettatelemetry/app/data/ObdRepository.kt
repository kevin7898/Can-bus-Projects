package ca.jettatelemetry.app.data

import android.content.Context
import android.net.Uri
import ca.jettatelemetry.app.model.ConnectionPhase
import ca.jettatelemetry.app.model.ConsoleEntry
import ca.jettatelemetry.app.model.DerivedSignals
import ca.jettatelemetry.app.model.LiveVehicleData
import ca.jettatelemetry.app.model.MainUiState
import ca.jettatelemetry.app.model.PairedObdDevice
import ca.jettatelemetry.app.model.RawCanProbeState
import ca.jettatelemetry.app.obd.Elm327Client
import ca.jettatelemetry.app.obd.Mode01Decoder
import ca.jettatelemetry.app.obd.ObdLinkTransport
import ca.jettatelemetry.app.obd.RawCanParser
import ca.jettatelemetry.app.recording.WebCanCsv
import java.io.BufferedWriter
import java.io.File
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class ObdRepository(context: Context) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val appContext = context.applicationContext
    private val transport = ObdLinkTransport(appContext)
    private val elm = Elm327Client(transport)
    private val entryIds = AtomicLong(0)
    private var pollingJob: Job? = null
    private var monitorJob: Job? = null
    private var rawCaptureFile: File? = null

    private val _state = MutableStateFlow(MainUiState())
    val state: StateFlow<MainUiState> = _state.asStateFlow()

    fun refreshBondedDevices() {
        runCatching { transport.bondedDevices() }
            .onSuccess { devices ->
                _state.update { current ->
                    current.copy(
                        devices = devices,
                        selectedAddress = current.selectedAddress
                            ?.takeIf { selected -> devices.any { it.address == selected } }
                            ?: devices.firstOrNull { looksLikeMxPlus(it) }?.address
                            ?: devices.firstOrNull()?.address,
                        errorMessage = null
                    )
                }
            }
            .onFailure { failure -> fail("Unable to read paired Bluetooth devices", failure) }
    }

    fun selectDevice(address: String) {
        _state.update { it.copy(selectedAddress = address) }
    }

    fun connect() {
        val selected = _state.value.selectedAddress
        if (selected == null) {
            fail("Pair the OBDLink MX+ in Android Bluetooth settings first")
            return
        }
        if (_state.value.connectionPhase == ConnectionPhase.CONNECTING ||
            _state.value.connectionPhase == ConnectionPhase.INITIALIZING
        ) return

        scope.launch {
            disconnectInternal(clearConsole = false)
            val device = _state.value.devices.firstOrNull { it.address == selected }
            _state.update {
                it.copy(
                    connectionPhase = ConnectionPhase.CONNECTING,
                    connectedDeviceName = device?.name,
                    errorMessage = null,
                    vehicleData = LiveVehicleData()
                )
            }
            system("Connecting to ${device?.name ?: selected}")
            try {
                transport.connect(selected)
                _state.update { it.copy(connectionPhase = ConnectionPhase.INITIALIZING) }
                system("Bluetooth connected; initializing ELM/STN interface")
                val initialization = elm.initialize(::logExchange)
                _state.update {
                    it.copy(
                        connectionPhase = ConnectionPhase.LIVE,
                        adapterIdentity = initialization.identity,
                        adapterFirmware = initialization.firmware,
                        isPolling = true
                    )
                }
                system("Live using ${initialization.protocol ?: "automatic protocol"}")
                startPolling()
            } catch (failure: Throwable) {
                runCatching { transport.disconnect() }
                fail("Connection failed", failure)
            }
        }
    }

    fun disconnect() {
        scope.launch { disconnectInternal(clearConsole = false) }
    }

    fun sendConsoleCommand(command: String) {
        val normalized = command.trim()
        if (normalized.isBlank()) return
        if (_state.value.connectionPhase != ConnectionPhase.LIVE) {
            fail("Connect to the adapter before sending a command")
            return
        }
        scope.launch {
            try {
                sent(normalized)
                val reply = elm.raw(normalized)
                received(reply.body.ifBlank { "(empty response)" })
            } catch (failure: Throwable) {
                system("Command failed: ${failure.message ?: failure::class.java.simpleName}")
            }
        }
    }

    fun clearConsole() {
        _state.update { it.copy(console = emptyList()) }
    }

    fun startRawCanProbe() {
        if (_state.value.connectionPhase != ConnectionPhase.LIVE || monitorJob?.isActive == true) return
        pollingJob?.cancel()
        pollingJob = null

        monitorJob = scope.launch {
            var writer: BufferedWriter? = null
            val ids = mutableSetOf<Int>()
            var frames = 0L
            var rejected = 0L
            var rateWindowFrames = 0L
            var rateWindowStarted = System.nanoTime()
            var lastUiUpdate = 0L
            val startedAtMillis = System.currentTimeMillis()
            try {
                system("Preparing silent raw CAN probe (11-bit / 500 kbit/s)")
                elm.configureRawCanMonitor(::logExchange)

                val file = File(appContext.cacheDir, "jetta-raw-can-latest.csv")
                writer = file.bufferedWriter()
                WebCanCsv.writeHeader(writer)
                rawCaptureFile = file
                _state.update {
                    it.copy(
                        isPolling = false,
                        rawCanProbe = RawCanProbeState(
                            isCapturing = true,
                            startedAtMillis = startedAtMillis
                        )
                    )
                }
                system("Raw CAN monitor started in receive-only mode")

                elm.monitorRawCan { line ->
                    if (line.equals("STM", true) || line.equals("STOPPED", true)) return@monitorRawCan
                    val nowMillis = System.currentTimeMillis()
                    val frame = RawCanParser.parse(line, nowMillis / 1000.0)
                    if (frame == null) {
                        rejected++
                        return@monitorRawCan
                    }
                    val activeWriter = writer ?: return@monitorRawCan
                    WebCanCsv.writeFrame(activeWriter, frame)
                    frames++
                    rateWindowFrames++
                    ids += frame.arbitrationId

                    val now = System.nanoTime()
                    if (now - lastUiUpdate >= 250_000_000L) {
                        val rateElapsed = (now - rateWindowStarted) / 1_000_000_000.0
                        val rate = if (rateElapsed > 0.0) rateWindowFrames / rateElapsed else 0.0
                        if (rateElapsed >= 2.0) {
                            rateWindowFrames = 0
                            rateWindowStarted = now
                        }
                        _state.update { current ->
                            current.copy(
                                rawCanProbe = current.rawCanProbe.copy(
                                    frameCount = frames,
                                    uniqueIdCount = ids.size,
                                    framesPerSecond = rate,
                                    elapsedMillis = nowMillis - startedAtMillis,
                                    recentFrames = (listOf(frame) + current.rawCanProbe.recentFrames).take(12),
                                    rejectedLineCount = rejected,
                                    captureFileAvailable = true
                                )
                            )
                        }
                        lastUiUpdate = now
                    }
                }
            } catch (failure: Throwable) {
                system("Raw CAN probe stopped: ${failure.message ?: failure::class.java.simpleName}")
            } finally {
                runCatching { writer?.flush() }
                runCatching { writer?.close() }
                _state.update { current ->
                    current.copy(
                        rawCanProbe = current.rawCanProbe.copy(
                            isCapturing = false,
                            frameCount = frames,
                            uniqueIdCount = ids.size,
                            elapsedMillis = System.currentTimeMillis() - startedAtMillis,
                            rejectedLineCount = rejected,
                            captureFileAvailable = rawCaptureFile?.isFile == true
                        )
                    )
                }

                if (_state.value.connectionPhase == ConnectionPhase.LIVE) {
                    runCatching {
                        system("Restoring diagnostic polling")
                        elm.initialize(::logExchange)
                        _state.update { it.copy(isPolling = true) }
                        startPolling()
                    }.onFailure { fail("Could not restore diagnostic polling", it) }
                }
            }
        }
    }

    fun stopRawCanProbe() {
        if (_state.value.rawCanProbe.isCapturing) {
            system("Stopping raw CAN monitor")
            elm.stopRawCanMonitor()
        }
    }

    fun exportRawCanProbe(destination: Uri) {
        val source = rawCaptureFile
        if (source == null || !source.isFile || _state.value.rawCanProbe.isCapturing) {
            system("Stop a completed raw CAN capture before exporting it")
            return
        }
        scope.launch {
            runCatching {
                val resolver = appContext.contentResolver
                requireNotNull(resolver.openOutputStream(destination, "wt")) {
                    "Unable to open export destination"
                }.use { output -> source.inputStream().use { input -> input.copyTo(output) } }
            }.onSuccess {
                _state.update { current ->
                    current.copy(rawCanProbe = current.rawCanProbe.copy(exportedFileName = destination.lastPathSegment))
                }
                system("Raw CAN CSV exported")
            }.onFailure { system("CSV export failed: ${it.message ?: it::class.java.simpleName}") }
        }
    }

    fun close() {
        pollingJob?.cancel()
        elm.stopRawCanMonitor()
        monitorJob?.cancel()
        transport.closeImmediately()
        scope.cancel()
    }

    private fun startPolling() {
        pollingJob?.cancel()
        pollingJob = scope.launch {
            var cycle = 0L
            var successCount = 0
            var rateWindowStarted = System.nanoTime()
            try {
                while (isActive) {
                    query("010C", Mode01Decoder::rpm) { data, value -> data.copy(rpm = value) }
                        .also { if (it) successCount++ }
                    query("010D", Mode01Decoder::speedKmh) { data, value -> data.copy(speedKmh = value) }
                        .also { if (it) successCount++ }
                    query("010B", Mode01Decoder::mapKpa) { data, value -> data.copy(mapAbsoluteKpa = value) }
                        .also { if (it) successCount++ }

                    if (cycle % 8L == 0L) {
                        query("0105", Mode01Decoder::coolantC) { data, value -> data.copy(coolantC = value) }
                            .also { if (it) successCount++ }
                    }
                    if (cycle % 16L == 0L) {
                        query("0133", Mode01Decoder::barometricKpa) { data, value -> data.copy(barometricAbsoluteKpa = value) }
                            .also { if (it) successCount++ }
                    }

                    val now = System.nanoTime()
                    val elapsedSeconds = (now - rateWindowStarted) / 1_000_000_000.0
                    if (elapsedSeconds >= 2.0) {
                        val rate = successCount / elapsedSeconds
                        _state.update { current ->
                            current.copy(vehicleData = current.vehicleData.copy(samplesPerSecond = rate))
                        }
                        successCount = 0
                        rateWindowStarted = now
                    }
                    cycle++
                    delay(8)
                }
            } catch (failure: Throwable) {
                if (isActive) {
                    fail("Live polling stopped", failure)
                    runCatching { transport.disconnect() }
                }
            }
        }
    }

    private suspend fun query(
        command: String,
        decode: (String) -> Double?,
        apply: (LiveVehicleData, Double) -> LiveVehicleData
    ): Boolean {
        val reply = elm.query(command)
        val value = decode(reply.body) ?: return false
        _state.update { current ->
            val withValue = apply(current.vehicleData, value)
            val withBoost = withValue.copy(
                boostGaugeKpa = DerivedSignals.gaugeBoostKpa(
                    withValue.mapAbsoluteKpa,
                    withValue.barometricAbsoluteKpa
                ),
                updatedElapsedNanos = System.nanoTime()
            )
            current.copy(vehicleData = withBoost)
        }
        return true
    }

    private suspend fun disconnectInternal(clearConsole: Boolean) {
        elm.stopRawCanMonitor()
        monitorJob?.join()
        monitorJob = null
        pollingJob?.cancel()
        pollingJob = null
        runCatching { transport.disconnect() }
        _state.update {
            it.copy(
                connectionPhase = ConnectionPhase.DISCONNECTED,
                isPolling = false,
                connectedDeviceName = null,
                adapterIdentity = null,
                adapterFirmware = null,
                vehicleData = LiveVehicleData(),
                rawCanProbe = it.rawCanProbe.copy(isCapturing = false),
                console = if (clearConsole) emptyList() else it.console
            )
        }
    }

    private fun logExchange(command: String, reply: ca.jettatelemetry.app.obd.ObdReply) {
        sent(command)
        received("${reply.body}  ·  ${reply.latencyMillis} ms")
    }

    private fun sent(text: String) = appendConsole(ConsoleEntry.Direction.SENT, text)
    private fun received(text: String) = appendConsole(ConsoleEntry.Direction.RECEIVED, text)
    private fun system(text: String) = appendConsole(ConsoleEntry.Direction.SYSTEM, text)

    private fun appendConsole(direction: ConsoleEntry.Direction, text: String) {
        val entry = ConsoleEntry(entryIds.incrementAndGet(), System.currentTimeMillis(), direction, text)
        _state.update { current -> current.copy(console = (current.console + entry).takeLast(250)) }
    }

    private fun fail(message: String, failure: Throwable? = null) {
        val detail = failure?.message?.takeIf(String::isNotBlank)
        val fullMessage = if (detail == null) message else "$message: $detail"
        system(fullMessage)
        _state.update {
            it.copy(
                connectionPhase = ConnectionPhase.FAILED,
                isPolling = false,
                errorMessage = fullMessage
            )
        }
    }

    private fun looksLikeMxPlus(device: PairedObdDevice): Boolean {
        val name = device.name.uppercase()
        return name.contains("OBDLINK") || name.contains("MX+")
    }
}

