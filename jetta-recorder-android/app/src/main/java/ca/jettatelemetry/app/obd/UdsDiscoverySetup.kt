package ca.jettatelemetry.app.obd

import java.io.IOException

/** Verify the diagnostic route independently of the unvalidated service 22 candidates. */
internal suspend fun prepareUdsDiscovery(
    request: suspend (String, Long) -> ObdReply,
    onExchange: (String, ObdReply) -> Unit
): ObdReply {
    // The Android deadline does not extend the adapter's own response window.
    // Disable adaptive shortening for this run; initialize() restores normal polling settings.
    val commands = listOf(
        "ATE0", "ATL0", "ATS0", "ATH0", "ATCAF1", "ATSH7E0", "ATCRA7E8",
        "ATAT0", "STPTO 1000"
    )
    for (command in commands) {
        val reply = request(command, 5_000).also { onExchange(command, it) }
        val lines = reply.body.lineSequence().map(String::trim)
            .filter(String::isNotBlank)
            .filterNot { it.replace(" ", "").equals(command.replace(" ", ""), true) }
            .toList()
        if (lines != listOf("OK")) {
            throw IOException("Discovery setup rejected $command: ${reply.body.ifBlank { "(empty reply)" }}")
        }
    }

    val control = request("0100", 4_000).also { onExchange("0100", it) }
    if (Mode01Decoder.dataBytes(control.body, "00", 4) == null) {
        throw IOException(
            "Engine route 7E0/7E8 did not return a valid 0100 reply: ${control.body.ifBlank { "(empty reply)" }}. " +
                "Sensor identifiers were not tested."
        )
    }
    return control
}
