package ca.jettatelemetry.app.recording

import ca.jettatelemetry.app.model.RawCanFrame
import java.io.Writer

/** webCAN-compatible CSV consumed directly by the CSS Electronics analysis scripts. */
object WebCanCsv {
    const val HEADER = "TimestampEpoch;BusChannel;ID;IDE;DLC;DataLength;Dir;EDL;BRS;ESI;RTR;DataBytes"

    fun writeHeader(writer: Writer) {
        writer.appendLine(HEADER)
    }

    fun writeFrame(writer: Writer, frame: RawCanFrame) {
        val bytes = frame.data.joinToString("") { "%02X".format(it.toInt() and 0xFF) }
        writer.append("%.6f".format(java.util.Locale.US, frame.timestampEpochSeconds)).append(';')
            .append("0;")
            .append(frame.displayId).append(';')
            .append(if (frame.isExtendedId) "1;" else "0;")
            .append(frame.data.size.toString()).append(';')
            .append(frame.data.size.toString()).append(';')
            .append("0;0;0;0;0;")
            .append(bytes)
            .append('\n')
    }
}
