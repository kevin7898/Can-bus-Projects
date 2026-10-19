package ca.jettatelemetry.app.recording

import ca.jettatelemetry.app.model.DiagnosticProbeResult
import ca.jettatelemetry.app.obd.JettaDiagnosticDiscovery
import java.io.Writer

object DiagnosticDiscoveryCsv {
    fun write(writer: Writer, results: List<DiagnosticProbeResult>) {
        writer.appendLine("source,probe_id,category,name,request_header,response_header,service,did,status,latency_ms,payload_hex,decoded_value,unit,note,raw_reply")
        results.forEach { result ->
            val fields = listOf(
                JettaDiagnosticDiscovery.SOURCE_NAME,
                result.id,
                result.category,
                result.name,
                JettaDiagnosticDiscovery.REQUEST_HEADER,
                JettaDiagnosticDiscovery.RESPONSE_HEADER,
                "22",
                result.did,
                result.status.name,
                result.latencyMillis?.toString().orEmpty(),
                result.payloadHex.orEmpty(),
                result.decodedValue?.toString().orEmpty(),
                result.unit.orEmpty(),
                result.note.orEmpty(),
                result.rawReply
            )
            writer.appendLine(fields.joinToString(",", transform = ::escape))
        }
    }

    private fun escape(value: String): String = "\"${value.replace("\"", "\"\"")}\""
}
