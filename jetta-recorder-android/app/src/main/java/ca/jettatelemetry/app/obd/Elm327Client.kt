package ca.jettatelemetry.app.obd

data class ElmInitialization(
    val identity: String?,
    val firmware: String?,
    val protocol: String?
)

class Elm327Client(private val transport: ObdLinkTransport) {
    suspend fun initialize(onExchange: (command: String, reply: ObdReply) -> Unit): ElmInitialization {
        fun clean(reply: ObdReply) = sanitize(reply.command, reply.body)

        val reset = transport.request("ATZ", timeoutMillis = 6_000).also { onExchange("ATZ", it) }
        val commands = listOf("ATE0", "ATL0", "ATS0", "ATH0", "ATAT2", "ATSP0")
        for (command in commands) {
            transport.request(command).also { onExchange(command, it) }
        }

        val identityReply = runCatching { transport.request("STI") }.getOrNull()
        identityReply?.let { onExchange("STI", it) }
        val firmwareReply = runCatching { transport.request("STDI") }.getOrNull()
        firmwareReply?.let { onExchange("STDI", it) }
        val protocolReply = transport.request("ATDP").also { onExchange("ATDP", it) }

        return ElmInitialization(
            identity = identityReply?.let(::clean) ?: clean(reset),
            firmware = firmwareReply?.let(::clean),
            protocol = clean(protocolReply)
        )
    }

    suspend fun query(command: String): ObdReply = transport.request(command)

    suspend fun raw(command: String): ObdReply = transport.request(command, timeoutMillis = 5_000)

    suspend fun configureUdsDiscovery(onExchange: (command: String, reply: ObdReply) -> Unit) {
        // Keep ISO-TP formatting enabled so the adapter reassembles multi-frame
        // UDS responses. Only service 0x22 (read data by identifier) follows.
        listOf("ATE0", "ATL0", "ATS0", "ATH0", "ATCAF1", "ATSH7E0", "ATCRA7E8").forEach { command ->
            transport.request(command, timeoutMillis = 5_000).also { onExchange(command, it) }
        }
    }

    suspend fun readDataByIdentifier(did: String): ObdReply =
        transport.request("22${did.uppercase()}", timeoutMillis = 4_000)

    suspend fun configureRawCanMonitor(onExchange: (command: String, reply: ObdReply) -> Unit) {
        // STP31 = ISO 11898 raw CAN, 11-bit transmit IDs, 500 kbit/s, variable DLC.
        // STCMM0 is receive-only and emits no ACKs. The zero-mask pass filter
        // admits every 11-bit identifier while STM preserves raw frame boundaries.
        listOf(
            "STPC", "STP 31", "STPO", "ATH1", "ATS1", "ATD1",
            "STCMM0", "STFAC", "STFPC", "STFBC", "STFFCC", "STFPA 000,000"
        ).forEach { command ->
            transport.request(command, timeoutMillis = 5_000).also { onExchange(command, it) }
        }
    }

    suspend fun monitorRawCan(onLine: (String) -> Unit) = transport.monitor("STM", onLine)

    fun stopRawCanMonitor() = transport.stopMonitor()

    private fun sanitize(command: String, body: String): String = body
        .lineSequence()
        .map(String::trim)
        .filter(String::isNotBlank)
        .filterNot { it.equals(command, ignoreCase = true) }
        .joinToString(" ")
        .ifBlank { "No response" }
}

