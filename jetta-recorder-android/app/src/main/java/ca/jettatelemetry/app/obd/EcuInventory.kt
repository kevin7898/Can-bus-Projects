package ca.jettatelemetry.app.obd

import java.util.Locale

/** Bounded, read-only standard OBD inventory on the already-verified engine route. */
internal suspend fun collectEcuInventory(
    control: ObdReply,
    request: suspend (String, Long) -> ObdReply,
    onExchange: (String, ObdReply) -> Unit
) {
    var bitmap = Mode01Decoder.dataBytes(control.body, "00", 4)
    // Bit 0 advertises the next supported-PID page. Never infer support from NO DATA.
    for (base in 0x20..0xE0 step 0x20) {
        if (bitmap == null || (bitmap.last() and 1) == 0) break
        val pid = String.format(Locale.ROOT, "%02X", base)
        val reply = request("01$pid", 4_000).also { onExchange("01$pid", it) }
        bitmap = Mode01Decoder.dataBytes(reply.body, pid, 4)
    }
    // Keep the raw replies, including multiline CALID/name replies and NO DATA.
    // These are identification reads, not a diagnostic-session or ECU-state change.
    for (command in listOf("0900", "0904", "090A")) {
        request(command, 4_000).also { onExchange(command, it) }
    }
}
