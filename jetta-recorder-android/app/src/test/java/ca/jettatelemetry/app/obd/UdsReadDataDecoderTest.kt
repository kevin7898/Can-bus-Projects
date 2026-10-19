package ca.jettatelemetry.app.obd

import ca.jettatelemetry.app.model.DiagnosticProbeStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class UdsReadDataDecoderTest {
    @Test
    fun parsesPositiveReadDataReply() {
        val parsed = UdsReadDataDecoder.parse("62 10 57 03 F5", "1057")

        assertEquals(DiagnosticProbeStatus.SUPPORTED, parsed.status)
        assertEquals("03F5", parsed.payloadHex)
    }

    @Test
    fun findsPayloadWhenCanHeaderIsPresent() {
        val parsed = UdsReadDataDecoder.parse("7E8 05 62 17 9C 0B B9", "179C")

        assertEquals(DiagnosticProbeStatus.SUPPORTED, parsed.status)
        assertEquals("0BB9", parsed.payloadHex)
    }

    @Test
    fun parsesNegativeResponseCode() {
        val parsed = UdsReadDataDecoder.parse("7F 22 31", "208A")

        assertEquals(DiagnosticProbeStatus.NEGATIVE_RESPONSE, parsed.status)
        assertEquals("31", parsed.negativeResponseCode)
    }

    @Test
    fun reportsNoData() {
        val parsed = UdsReadDataDecoder.parse("SEARCHING...\rNO DATA", "1057")

        assertEquals(DiagnosticProbeStatus.NO_DATA, parsed.status)
        assertNull(parsed.payloadHex)
    }

    @Test
    fun decodesTemperatureScaling() {
        val definition = DiagnosticProbeDefinition(
            id = "oil",
            name = "Oil",
            did = "179C",
            category = "Engine",
            byteLength = 2,
            divisor = 10.0,
            offset = -273.1,
            unit = "°C"
        )

        assertEquals(26.9, UdsReadDataDecoder.decode("0BB8", definition)!!, 0.0001)
    }

    @Test
    fun decodesSignedBigEndianValue() {
        val definition = DiagnosticProbeDefinition(
            id = "signed",
            name = "Signed",
            did = "0000",
            category = "Test",
            byteLength = 2,
            signed = true,
            divisor = 100.0
        )

        assertEquals(-1.0, UdsReadDataDecoder.decode("FF9C", definition)!!, 0.0001)
    }
}
