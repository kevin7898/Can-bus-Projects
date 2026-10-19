package ca.jettatelemetry.app.obd

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RawCanParserTest {
    @Test
    fun parsesElevenBitFrameWithDlc() {
        val frame = requireNotNull(RawCanParser.parse("123 8 01 02 A0 FF 00 10 20 30", 1234.5))
        assertEquals(0x123, frame.arbitrationId)
        assertFalse(frame.isExtendedId)
        assertArrayEquals(byteArrayOf(0x01, 0x02, 0xA0.toByte(), 0xFF.toByte(), 0, 0x10, 0x20, 0x30), frame.data)
        assertEquals("123", frame.displayId)
    }

    @Test
    fun parsesExtendedFrameAndRejectsStatusText() {
        val frame = requireNotNull(RawCanParser.parse("18DAF110 3 41 0C FF", 12.0))
        assertTrue(frame.isExtendedId)
        assertEquals("18DAF110", frame.displayId)
        assertNull(RawCanParser.parse("STOPPED", 12.0))
        assertNull(RawCanParser.parse("NO DATA", 12.0))
    }
}
