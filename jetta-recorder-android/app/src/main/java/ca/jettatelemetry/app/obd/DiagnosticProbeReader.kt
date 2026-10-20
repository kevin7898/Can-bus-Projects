package ca.jettatelemetry.app.obd

import ca.jettatelemetry.app.model.DiagnosticProbeResult
import ca.jettatelemetry.app.model.DiagnosticProbeStatus

/** Shares one serialized discovery path; unsupported standard PIDs send no request. */
internal suspend fun readDiagnosticProbe(
    definition: DiagnosticProbeDefinition,
    supportedPids: Set<Int>,
    request: suspend (String) -> ObdReply
): DiagnosticProbeResult {
    require(definition.service == "01" || definition.service == "22")
    if (definition.service == "01" && definition.did.toInt(16) !in supportedPids) {
        return DiagnosticProbeResult(
            id = definition.id, name = definition.name, did = definition.did,
            category = definition.category, service = definition.service,
            status = DiagnosticProbeStatus.NOT_ADVERTISED,
            note = "Not advertised by this ECU; request skipped"
        )
    }
    val reply = request(definition.command)
    if (definition.service == "01") return StandardObdDiscovery.decode(definition, reply)
    val parsed = UdsReadDataDecoder.parse(reply.body, definition.did)
    return DiagnosticProbeResult(
        id = definition.id, name = definition.name, did = definition.did,
        category = definition.category, service = definition.service,
        status = parsed.status, rawReply = reply.body, payloadHex = parsed.payloadHex,
        decodedValue = if (parsed.status == DiagnosticProbeStatus.SUPPORTED) {
            UdsReadDataDecoder.decode(parsed.payloadHex, definition)
        } else null,
        unit = definition.unit, latencyMillis = reply.latencyMillis,
        note = parsed.negativeResponseCode?.let { "UDS negative response 0x$it" } ?: definition.note
    )
}
