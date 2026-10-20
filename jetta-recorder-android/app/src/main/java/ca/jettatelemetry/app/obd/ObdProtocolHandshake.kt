package ca.jettatelemetry.app.obd

import java.io.IOException

/** ATSP0 only selects auto mode; the first vehicle request actually searches the bus. */
internal suspend fun establishObdProtocol(
    request: suspend (String, Long) -> ObdReply,
    onExchange: (String, ObdReply) -> Unit
): ObdReply {
    // Protocol search is a startup operation, separate from the 2.5 s live-query deadline.
    val supported = request("0100", 60_000).also { onExchange("0100", it) }
    if (Mode01Decoder.dataBytes(supported.body, "00", 4) == null) {
        throw IOException("Vehicle protocol detection failed: 0100 returned ${supported.body.ifBlank { "(empty reply)" }}")
    }
    // Ask only after a real ECU reply, so this describes the selected protocol, not just AUTO.
    return request("ATDP", 2_500).also { onExchange("ATDP", it) }
}
