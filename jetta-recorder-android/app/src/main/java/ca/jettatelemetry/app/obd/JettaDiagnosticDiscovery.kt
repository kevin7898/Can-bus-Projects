package ca.jettatelemetry.app.obd

import ca.jettatelemetry.app.model.DiagnosticProbeStatus
import kotlin.math.pow

/**
 * A deliberately small, read-only discovery pack for the user's 2014 Jetta TDI.
 *
 * Candidate identifiers and scaling are derived from the OBDb Volkswagen-Jetta
 * signal set (CC BY-SA 4.0):
 * https://github.com/OBDb/Volkswagen-Jetta
 * Snapshot reviewed: 15e6acad6c58c118b479b8a4cd8a96909a8553d4.
 *
 * OBDb currently marks these definitions as debug candidates. A successful
 * response is therefore evidence of ECU support, not proof that the engineering
 * unit is correct. Each signal must be validated on the car before dashboard use.
 * Every generated diagnostic request uses read-only UDS service 0x22.
 */
data class DiagnosticProbeDefinition(
    val id: String,
    val name: String,
    val did: String,
    val category: String,
    val byteLength: Int,
    val signed: Boolean = false,
    val multiplier: Double = 1.0,
    val divisor: Double = 1.0,
    val offset: Double = 0.0,
    val unit: String? = null,
    val note: String? = null,
    val service: String = "22"
) {
    val command: String get() = "$service$did"
}

object JettaDiagnosticDiscovery {
    const val REQUEST_HEADER = "7E0"
    const val RESPONSE_HEADER = "7E8"
    const val SOURCE_NAME = "OBDb/Volkswagen-Jetta @ 15e6acad"

    val probes = listOf(
        DiagnosticProbeDefinition("boost_actual", "Boost pressure (absolute)", "1057", "Engine", 2, divisor = 1000.0, unit = "bar"),
        DiagnosticProbeDefinition("oil_temp_2", "Engine oil temperature", "179C", "Engine", 2, divisor = 10.0, offset = -273.1, unit = "°C"),
        DiagnosticProbeDefinition("fuel_flow", "Fuel flow rate", "111A", "Economy", 2, signed = true, divisor = 100.0, unit = "candidate L/h", note = "Unit requires on-car validation"),
        DiagnosticProbeDefinition("dpf_in_temp", "DPF inlet temperature", "11B2", "DPF", 2, divisor = 10.0, offset = -273.1, unit = "°C"),
        DiagnosticProbeDefinition("dpf_out_temp", "DPF outlet temperature", "10F9", "DPF", 2, divisor = 10.0, offset = -273.1, unit = "°C"),
        DiagnosticProbeDefinition("dpf_exhaust_temp", "DPF exhaust temperature", "44F8", "DPF", 2, signed = true, divisor = 10.0, offset = -273.1, unit = "°C"),
        DiagnosticProbeDefinition("dpf_diff_pressure", "DPF differential pressure", "2084", "DPF", 1, multiplier = 20.0, unit = "candidate pressure", note = "Engineering unit requires validation"),
        DiagnosticProbeDefinition("dpf_diff_offset", "DPF pressure offset", "10F1", "DPF", 2, signed = true, unit = "raw", note = "Engineering unit requires validation"),
        DiagnosticProbeDefinition("dpf_distance", "Distance since regeneration", "1ABA", "DPF", 2, divisor = 10.0, unit = "km"),
        DiagnosticProbeDefinition("dpf_time", "Time since regeneration", "2089", "DPF", 2, multiplier = 19531.0, divisor = 10_000_000.0, unit = "h"),
        DiagnosticProbeDefinition("dpf_fuel", "Fuel used since regeneration", "20D8", "DPF", 2, divisor = 100.0, unit = "L"),
        DiagnosticProbeDefinition("dpf_soot_measured", "DPF soot mass measured", "208C", "DPF", 2, signed = true, divisor = 100.0, unit = "candidate mass", note = "Engineering unit requires validation"),
        DiagnosticProbeDefinition("dpf_soot_calculated", "DPF soot mass calculated", "2609", "DPF", 2, signed = true, divisor = 100.0, unit = "candidate mass", note = "Engineering unit requires validation"),
        DiagnosticProbeDefinition("dpf_oil_ash", "DPF oil ash residue", "208A", "DPF", 4, multiplier = 0.0000003052, unit = "candidate mass", note = "Engineering unit requires validation"),
        DiagnosticProbeDefinition("dpf_regen_time", "DPF regeneration counter", "39F9", "DPF", 2, multiplier = 16.0, divisor = 25.0, unit = "s"),
        DiagnosticProbeDefinition("service_regen", "Service regeneration status", "115C", "DPF", 1, unit = "state")
    )
}

data class ParsedDiagnosticReply(
    val status: DiagnosticProbeStatus,
    val payloadHex: String? = null,
    val negativeResponseCode: String? = null
)

object UdsReadDataDecoder {
    fun parse(rawReply: String, did: String): ParsedDiagnosticReply {
        val upper = rawReply.uppercase()
        if (upper.contains("NO DATA") || upper.contains("UNABLE TO CONNECT")) {
            return ParsedDiagnosticReply(DiagnosticProbeStatus.NO_DATA)
        }

        val hexLines = upper.lineSequence()
            .map(String::trim)
            .filter(String::isNotBlank)
            .filterNot { it.startsWith("SEARCHING") || it.startsWith("BUS INIT") }
            .map { it.replace(Regex("[^0-9A-F]"), "") }
            .filter(String::isNotBlank)
            .toList()

        val marker = "62${did.uppercase()}"
        hexLines.forEach { line ->
            val markerIndex = line.indexOf(marker)
            if (markerIndex >= 0) {
                val payload = line.substring(markerIndex + marker.length)
                return ParsedDiagnosticReply(
                    status = DiagnosticProbeStatus.SUPPORTED,
                    payloadHex = payload.takeIf(String::isNotBlank)
                )
            }
        }

        hexLines.forEach { line ->
            val negativeIndex = line.indexOf("7F22")
            if (negativeIndex >= 0) {
                val codeStart = negativeIndex + 4
                return ParsedDiagnosticReply(
                    status = DiagnosticProbeStatus.NEGATIVE_RESPONSE,
                    negativeResponseCode = line.drop(codeStart).take(2).takeIf { it.length == 2 }
                )
            }
        }

        return ParsedDiagnosticReply(DiagnosticProbeStatus.ERROR)
    }

    fun decode(payloadHex: String?, definition: DiagnosticProbeDefinition): Double? {
        if (payloadHex == null || payloadHex.length < definition.byteLength * 2) return null
        val rawHex = payloadHex.take(definition.byteLength * 2)
        val unsigned = rawHex.toLongOrNull(16) ?: return null
        val raw = if (definition.signed) {
            val bits = definition.byteLength * 8
            val signBit = 2.0.pow(bits - 1).toLong()
            val fullRange = 2.0.pow(bits).toLong()
            if (unsigned >= signBit) unsigned - fullRange else unsigned
        } else {
            unsigned
        }
        return raw * definition.multiplier / definition.divisor + definition.offset
    }
}
