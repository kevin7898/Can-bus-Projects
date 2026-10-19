package ca.jettatelemetry.app.recording

import ca.jettatelemetry.app.model.RawCanFrame
import java.io.StringWriter
import org.junit.Assert.assertEquals
import org.junit.Test

class WebCanCsvTest {
    @Test
    fun writesWebCanCompatibleRow() {
        val output = StringWriter()
        WebCanCsv.writeHeader(output)
        WebCanCsv.writeFrame(output, RawCanFrame(1234.5, 0x123, false, byteArrayOf(0x01, 0xA0.toByte()), ""))

        assertEquals(
            WebCanCsv.HEADER + "\n1234.500000;0;123;0;2;2;0;0;0;0;0;01A0\n",
            output.toString()
        )
    }
}
