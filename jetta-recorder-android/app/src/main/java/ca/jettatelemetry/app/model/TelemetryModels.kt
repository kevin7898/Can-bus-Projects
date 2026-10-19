package ca.jettatelemetry.app.model

enum class ConnectionPhase {
    DISCONNECTED,
    CONNECTING,
    INITIALIZING,
    LIVE,
    FAILED
}

data class PairedObdDevice(
    val name: String,
    val address: String
)

data class LiveVehicleData(
    val rpm: Double? = null,
    val speedKmh: Double? = null,
    val coolantC: Double? = null,
    val mapAbsoluteKpa: Double? = null,
    val barometricAbsoluteKpa: Double? = null,
    val boostGaugeKpa: Double? = null,
    val samplesPerSecond: Double = 0.0,
    val updatedElapsedNanos: Long? = null
)

data class RawCanFrame(
    val timestampEpochSeconds: Double,
    val arbitrationId: Int,
    val isExtendedId: Boolean,
    val data: ByteArray,
    val sourceLine: String
) {
    val displayId: String
        get() = if (isExtendedId) "%08X".format(arbitrationId) else "%03X".format(arbitrationId)

    val displayData: String
        get() = data.joinToString(" ") { "%02X".format(it.toInt() and 0xFF) }
}

data class RawCanProbeState(
    val isCapturing: Boolean = false,
    val frameCount: Long = 0,
    val uniqueIdCount: Int = 0,
    val framesPerSecond: Double = 0.0,
    val startedAtMillis: Long? = null,
    val elapsedMillis: Long = 0,
    val recentFrames: List<RawCanFrame> = emptyList(),
    val rejectedLineCount: Long = 0,
    val captureFileAvailable: Boolean = false,
    val exportedFileName: String? = null
)

data class ConsoleEntry(
    val id: Long,
    val timestampMillis: Long,
    val direction: Direction,
    val text: String
) {
    enum class Direction { SENT, RECEIVED, SYSTEM }
}

data class MainUiState(
    val connectionPhase: ConnectionPhase = ConnectionPhase.DISCONNECTED,
    val devices: List<PairedObdDevice> = emptyList(),
    val selectedAddress: String? = null,
    val connectedDeviceName: String? = null,
    val adapterIdentity: String? = null,
    val adapterFirmware: String? = null,
    val vehicleData: LiveVehicleData = LiveVehicleData(),
    val console: List<ConsoleEntry> = emptyList(),
    val errorMessage: String? = null,
    val isPolling: Boolean = false,
    val rawCanProbe: RawCanProbeState = RawCanProbeState()
)

object DerivedSignals {
    fun gaugeBoostKpa(mapAbsoluteKpa: Double?, barometricAbsoluteKpa: Double?): Double? {
        if (mapAbsoluteKpa == null || barometricAbsoluteKpa == null) return null
        return mapAbsoluteKpa - barometricAbsoluteKpa
    }

    fun kpaToPsi(kpa: Double?): Double? = kpa?.times(0.1450377377)
}

