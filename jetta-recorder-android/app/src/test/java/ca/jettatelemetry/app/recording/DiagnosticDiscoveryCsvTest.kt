package ca.jettatelemetry.app.recording

import ca.jettatelemetry.app.model.DiagnosticProbeResult
import ca.jettatelemetry.app.model.DiagnosticProbeStatus
import ca.jettatelemetry.app.model.DiagnosticSetupExchange
import java.io.StringWriter
import org.junit.Assert.assertTrue
import org.junit.Test

class DiagnosticDiscoveryCsvTest {
    @Test
    fun standardResultsExportTheCorrectServiceSourceAndDecodedFields() {
        val writer = StringWriter()
        DiagnosticDiscoveryCsv.write(writer, listOf(DiagnosticProbeResult(
            "obd_dpf_pressure", "Standard DPF pressures", "7A", "DPF",
            status = DiagnosticProbeStatus.SUPPORTED,
            rawReply = "009\r0:417A01FF9C00\r1:000000",
            note = "Differential: -1.00 kPa", service = "01"
        )))
        val csv = writer.toString()
        assertTrue(csv.contains("\"OBDb/SAEJ1979 @ 06690177\""))
        assertTrue(csv.contains("\"7E8\",\"01\",\"7A\""))
        assertTrue(csv.contains("\"probe\",\"017A\""))
        assertTrue(csv.contains("Differential: -1.00 kPa"))
        assertTrue(!csv.contains("227A"))
    }
    @Test
    fun exportIncludesControlEvidenceVersionAndTheUnmodifiedProbeReply() {
        val writer = StringWriter()
        DiagnosticDiscoveryCsv.write(
            writer,
            listOf(DiagnosticProbeResult("boost", "Boost", "1057", "Engine",
                status = DiagnosticProbeStatus.NO_DATA, rawReply = "NO DATA", latencyMillis = 117)),
            listOf(DiagnosticSetupExchange("0100", "410098192013", 1_000)),
            appVersion = "test-version"
        )
        val csv = writer.toString()
        assertTrue(csv.lineSequence().first().endsWith("raw_reply,record_type,command,app_version,run_error"))
        assertTrue(csv.contains("\"410098192013\",\"setup\",\"0100\",\"test-version\",\"\""))
        assertTrue(csv.contains("\"NO_DATA\",\"117\""))
        assertTrue(csv.contains("\"NO DATA\",\"probe\",\"221057\",\"test-version\",\"\""))
    }

    @Test
    fun failedSetupExportPreservesMultilineReplyAndCancelledCandidates() {
        val writer = StringWriter()
        DiagnosticDiscoveryCsv.write(
            writer,
            listOf(DiagnosticProbeResult("boost", "Boost", "1057", "Engine",
                status = DiagnosticProbeStatus.CANCELLED)),
            listOf(DiagnosticSetupExchange("0100", "SEARCHING...\r\nNO DATA", 1_000)),
            runError = "Route check returned \"NO DATA\""
        )
        val csv = writer.toString()
        assertTrue(csv.contains("\"SEARCHING...\r\nNO DATA\""))
        assertTrue(csv.contains("\"Route check returned \"\"NO DATA\"\"\""))
        assertTrue(csv.contains("\"CANCELLED\""))
        assertTrue(!csv.contains("\"SUPPORTED\""))
    }
}
