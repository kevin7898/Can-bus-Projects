package ca.jettatelemetry.app.obd

import ca.jettatelemetry.app.model.DiagnosticProbeStatus
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class StandardObdDiscoveryTest {
    private fun decode(pid: String, body: String) = StandardObdDiscovery.decode(
        StandardObdDiscovery.probes.single { it.did == pid }, ObdReply("01$pid", body, 1_020)
    )

    @Test fun fuelRateUsesStandardScalingAndPreservesEvidence() {
        val result = decode("5E", "41 5E 00 14")
        assertEquals(DiagnosticProbeStatus.SUPPORTED, result.status)
        assertEquals(1.0, result.decodedValue!!, 0.001)
        assertEquals("L/h", result.unit)
        assertEquals("41 5E 00 14", result.rawReply)
        assertEquals("0014", result.payloadHex)
        assertEquals("01", result.service)
    }

    @Test fun multilineBoostHonorsIndependentActualAndCommandedAvailability() {
        // Synthetic ELM-format response, not a captured vehicle reading.
        val result = decode("70", "00C\r0:417012FFFF0C\r1:80FFFF19000000")
        assertEquals(DiagnosticProbeStatus.SUPPORTED, result.status)
        assertEquals("A actual: 100.00 kPa; B actual: 200.00 kPa", result.note)
        assertEquals("12FFFF0C80FFFF190000", result.payloadHex)
        assertNull(result.decodedValue) // Neither commanded pressure nor a fabricated MAP.
    }

    @Test fun exhaustTemperaturesUseSupportBitsAndDoNotRenameSensorsAsDpfInlet() {
        val result = decode("78", "00B\r0:4178050D48FF\r1:FF0000FFFF")
        assertEquals("EGT 1: 300.00 °C; EGT 3: -40.00 °C", result.note)
        assertFalse(result.note!!.contains("DPF inlet"))
        assertFalse(result.note.contains("EGT 2"))
    }

    @Test fun dpfPressureDecodesSignedDeltaAndUnsignedInletAndOutlet() {
        val result = decode("7A", "009\r0:417A07FF9C27\r1:1026AC")
        assertEquals("Differential: -1.00 kPa; Inlet: 100.00 kPa; Outlet: 99.00 kPa", result.note)
    }

    @Test fun regenerationSeparatesStatusTriggerAndAverageIntervals() {
        val result = decode("8B", "009\r0:418B73038000\r1:3C01F4")
        assertEquals("DPF regeneration: in progress; Type: active; Regeneration trigger: 50.20 %; Average interval: 60.00 min; Average distance: 500.00 km", result.note)
        assertFalse(result.note!!.contains("soot"))
        assertFalse(result.note.contains("since"))
    }

    @Test fun absentAvailabilityBitsNeverBecomeZeroReadings() {
        for (pid in listOf("70", "78", "7A", "8B")) {
            val count = StandardObdDiscovery.probes.single { it.did == pid }.byteLength
            val result = decode(pid, "41$pid" + "00".repeat(count))
            assertEquals(DiagnosticProbeStatus.SUPPORTED, result.status)
            assertNull(result.decodedValue)
            assertEquals("No decoded sensor fields marked available", result.note)
        }
    }

    @Test fun noDataNegativeMalformedAndIncompleteRepliesAreDistinct() {
        assertEquals(DiagnosticProbeStatus.NO_DATA, decode("70", "NO DATA").status)
        assertEquals(DiagnosticProbeStatus.NEGATIVE_RESPONSE, decode("70", "7F0112").status)
        for (body in listOf("?", "4170020C80", "00C\r0:4170020C8000", "00C\r0:41700200000C\r2:80000000000000")) {
            val result = decode("70", body)
            assertEquals(body, DiagnosticProbeStatus.ERROR, result.status)
            assertNull(result.decodedValue)
        }
    }

    @Test fun unadvertisedStandardPidIsSkippedWithoutTransmission() = runBlocking {
        val result = readDiagnosticProbe(StandardObdDiscovery.probes.first(), emptySet()) {
            fail("Unadvertised PID must not be sent")
            error("Unexpected request")
        }
        assertEquals(DiagnosticProbeStatus.NOT_ADVERTISED, result.status)
        assertEquals("", result.rawReply)
    }

    @Test fun advertisedStandardRequestsAndExistingCandidatesShareReadOnlyPath() = runBlocking {
        val commands = mutableListOf<String>()
        val definitions = StandardObdDiscovery.probes + JettaDiagnosticDiscovery.probes
        for (definition in definitions) {
            val result = readDiagnosticProbe(definition, setOf(0x5E, 0x70, 0x78, 0x7A, 0x8B)) {
                commands += it
                ObdReply(it, "NO DATA", 1_000)
            }
            assertEquals(DiagnosticProbeStatus.NO_DATA, result.status)
        }
        assertEquals(listOf("015E", "0170", "0178", "017A", "018B") + JettaDiagnosticDiscovery.probes.map { it.command }, commands)
        assertEquals(16, JettaDiagnosticDiscovery.probes.size)
    }
}
