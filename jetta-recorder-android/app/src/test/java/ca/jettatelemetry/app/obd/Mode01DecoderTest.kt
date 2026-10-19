package ca.jettatelemetry.app.obd

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class Mode01DecoderTest {
    @Test fun decodesRpmWithEchoAndSpacing() {
        val reply = "010C\rSEARCHING...\r41 0C 1A F8\r"
        assertEquals(1_726.0, Mode01Decoder.rpm(reply)!!, 0.001)
    }

    @Test fun decodesSpeedCoolantAndPressures() {
        assertEquals(88.0, Mode01Decoder.speedKmh("41 0D 58")!!, 0.001)
        assertEquals(90.0, Mode01Decoder.coolantC("41 05 82")!!, 0.001)
        assertEquals(100.0, Mode01Decoder.mapKpa("41 0B 64")!!, 0.001)
        assertEquals(98.0, Mode01Decoder.barometricKpa("41 33 62")!!, 0.001)
    }

    @Test fun returnsNullForNoDataAndTruncatedFrames() {
        assertNull(Mode01Decoder.rpm("NO DATA"))
        assertNull(Mode01Decoder.rpm("41 0C 1A"))
    }
}

