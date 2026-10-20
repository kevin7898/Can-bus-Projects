package ca.jettatelemetry.app.obd

import ca.jettatelemetry.app.model.DiagnosticProbeResult
import ca.jettatelemetry.app.model.DiagnosticProbeStatus
import java.util.Locale

/** Read-only Mode 01 definitions adapted from OBDb/SAEJ1979 (CC BY-SA 4.0).
 * Revision 06690177d2d5e11dbf82566297128d673b5a03a7; see THIRD_PARTY_NOTICES.md.
 * Support bits inside each reply gate every field, independently of PID support.
 */
object StandardObdDiscovery {
    const val SOURCE_NAME = "OBDb/SAEJ1979 @ 06690177"
    val probes = listOf(
        DiagnosticProbeDefinition("obd_fuel_rate", "Standard fuel rate", "5E", "Economy", 2, unit = "L/h", service = "01"),
        DiagnosticProbeDefinition("obd_boost", "Standard boost pressures", "70", "Engine", 10, service = "01"),
        DiagnosticProbeDefinition("obd_egt", "Standard EGT bank 1", "78", "DPF", 9, service = "01"),
        DiagnosticProbeDefinition("obd_dpf_pressure", "Standard DPF pressures", "7A", "DPF", 7, service = "01"),
        DiagnosticProbeDefinition("obd_regeneration", "Standard regeneration", "8B", "DPF", 7, service = "01")
    )

    fun decode(definition: DiagnosticProbeDefinition, reply: ObdReply): DiagnosticProbeResult {
        val bytes = ElmObdPayload.read(reply.body, "41${definition.did}")
        val negative = ElmObdPayload.read(reply.body, "7F01")?.firstOrNull()
        val status = when {
            reply.body.contains("NO DATA", true) || reply.body.contains("UNABLE TO CONNECT", true) -> DiagnosticProbeStatus.NO_DATA
            negative != null -> DiagnosticProbeStatus.NEGATIVE_RESPONSE
            bytes == null || bytes.size < definition.byteLength -> DiagnosticProbeStatus.ERROR
            else -> DiagnosticProbeStatus.SUPPORTED
        }
        val fields = mutableListOf<String>()
        var scalar: Double? = null
        if (status == DiagnosticProbeStatus.SUPPORTED) {
            val data = requireNotNull(bytes)
            fun u16(offset: Int) = (data[offset] shl 8) or data[offset + 1]
            fun available(mask: Int) = data[0] and mask != 0
            fun value(label: String, number: Double, unit: String) {
                fields += String.format(Locale.ROOT, "%s: %.2f %s", label, number, unit)
            }
            when (definition.did) {
                "5E" -> { scalar = u16(0) / 20.0 }
                "70" -> {
                    if (available(0x01)) value("A commanded", u16(1) / 32.0, "kPa")
                    if (available(0x02)) value("A actual", u16(3) / 32.0, "kPa")
                    if (available(0x08)) value("B commanded", u16(5) / 32.0, "kPa")
                    if (available(0x10)) value("B actual", u16(7) / 32.0, "kPa")
                }
                "78" -> for (sensor in 0..3) {
                    if (available(1 shl sensor)) value("EGT ${sensor + 1}", u16(1 + sensor * 2) / 10.0 - 40, "°C")
                }
                "7A" -> {
                    val delta = u16(1).let { if (it >= 0x8000) it - 0x10000 else it }
                    if (available(0x01)) value("Differential", delta / 100.0, "kPa")
                    if (available(0x02)) value("Inlet", u16(3) / 100.0, "kPa")
                    if (available(0x04)) value("Outlet", u16(5) / 100.0, "kPa")
                }
                "8B" -> {
                    if (available(0x01)) fields += "DPF regeneration: ${if (data[1] and 1 != 0) "in progress" else "inactive"}"
                    if (available(0x02)) fields += "Type: ${if (data[1] and 2 != 0) "active" else "passive"}"
                    if (available(0x10)) value("Regeneration trigger", data[2] * 100.0 / 255, "%")
                    if (available(0x20)) value("Average interval", u16(3).toDouble(), "min")
                    if (available(0x40)) value("Average distance", u16(5).toDouble(), "km")
                }
            }
        }
        return DiagnosticProbeResult(
            id = definition.id, name = definition.name, did = definition.did,
            category = definition.category, service = "01", status = status,
            rawReply = reply.body, latencyMillis = reply.latencyMillis,
            payloadHex = bytes?.joinToString("") { "%02X".format(Locale.ROOT, it) },
            decodedValue = scalar, unit = definition.unit,
            note = when (status) {
                DiagnosticProbeStatus.SUPPORTED -> fields.joinToString("; ").ifEmpty {
                    if (scalar == null) "No decoded sensor fields marked available" else "Standard Mode 01"
                }
                DiagnosticProbeStatus.NEGATIVE_RESPONSE -> "OBD negative response 0x%02X".format(Locale.ROOT, negative)
                DiagnosticProbeStatus.ERROR -> "Missing or incomplete Mode 01 payload"
                else -> null
            }
        )
    }
}
