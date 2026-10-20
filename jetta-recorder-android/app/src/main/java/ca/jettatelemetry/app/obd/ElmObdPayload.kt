package ca.jettatelemetry.app.obd

/** Payloads with ATH0/ATCAF1: ordinary hex replies or ELM length + numbered lines.
 * Number labels are framing, never data. Never concatenate separate ECU replies.
 */
internal object ElmObdPayload {
    fun read(reply: String, marker: String): List<Int>? {
        val lines = reply.uppercase().lineSequence().map(String::trim)
            .filter(String::isNotBlank).toList()
        for ((index, line) in lines.withIndex()) {
            if (line.startsWith("0:")) {
                val length = lines.getOrNull(index - 1)?.takeIf {
                    it.matches(Regex("[0-9A-F]{3}"))
                }?.toInt(16) ?: continue
                val assembled = StringBuilder()
                var frame = 0
                for (numbered in lines.drop(index)) {
                    val match = Regex("([0-9A-F]):\\s*([0-9A-F ]+)").matchEntire(numbered) ?: break
                    if (match.groupValues[1].toInt(16) != frame % 16) return null
                    val chunk = match.groupValues[2].replace(" ", "")
                    if (chunk.isEmpty() || chunk.length % 2 != 0) return null
                    assembled.append(chunk)
                    frame++
                    if (assembled.length >= length * 2) break
                }
                if (assembled.length < length * 2) return null
                val message = assembled.take(length * 2).toString()
                if (message.startsWith(marker)) return bytes(message.drop(marker.length))
            } else {
                val compact = line.replace(" ", "")
                if (compact.startsWith(marker) && compact.matches(Regex("[0-9A-F]+"))) {
                    return bytes(compact.drop(marker.length))
                }
            }
        }
        return null
    }

    private fun bytes(hex: String): List<Int>? =
        if (hex.length % 2 != 0) null else hex.chunked(2).map { it.toInt(16) }
}
