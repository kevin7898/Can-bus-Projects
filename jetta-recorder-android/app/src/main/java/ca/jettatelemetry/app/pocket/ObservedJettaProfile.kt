package ca.jettatelemetry.app.pocket

/** Standard J1979 reads observed in the supplied Car Scanner trace, not copied app code.
 * Formula reference: https://www.dashlogic.com/docs/technical/obdii_pids
 * Presence in a historical reply is evidence of support, not on-device acceptance testing.
 */
data class PocketSignal(val id: String, val value: Double, val unit: String)
data class PocketPoll(val pid: String, val periodMs: Long)

object ObservedJettaProfile {
    val polls = listOf(
        PocketPoll("0D", 250), PocketPoll("0C", 500), PocketPoll("5E", 500),
        PocketPoll("70", 750), PocketPoll("05", 5_000), PocketPoll("46", 10_000),
        PocketPoll("33", 30_000), PocketPoll("78", 2_000), PocketPoll("7A", 5_000),
        PocketPoll("8B", 10_000), PocketPoll("42", 10_000), PocketPoll("04", 2_000),
        PocketPoll("10", 2_000)
    )

    fun decode(pid: String, reply: String): List<PocketSignal> {
        val payload = EngineIsoTp.messages(reply).lastOrNull {
            it.size >= 2 && it[0] == 0x41 && it[1] == pid.toInt(16)
        } ?: return emptyList()
        val d = payload.drop(2)
        val result = mutableListOf<PocketSignal>()
        fun add(id: String, unit: String, value: Double) { if (value.isFinite()) result += PocketSignal(id, value, unit) }
        fun u16(i: Int) = d[i] * 256 + d[i + 1]
        when (pid) {
            "0D" -> if (d.size >= 1) add("speed", "km/h", d[0].toDouble())
            "0C" -> if (d.size >= 2) add("rpm", "rpm", u16(0) / 4.0)
            "05" -> if (d.size >= 1) add("coolant", "°C", d[0] - 40.0)
            "46" -> if (d.size >= 1) add("ambient", "°C", d[0] - 40.0)
            "33" -> if (d.size >= 1) add("baro", "kPa", d[0].toDouble())
            "5E" -> if (d.size >= 2) add("fuel_rate", "L/h", u16(0) / 20.0)
            "42" -> if (d.size >= 2) add("ecu_voltage", "V", u16(0) / 1000.0)
            "04" -> if (d.size >= 1) add("load", "%", d[0] / 2.55)
            "10" -> if (d.size >= 2) add("maf", "g/s", u16(0) / 100.0)
            "70" -> if (d.size >= 10) {
                if (d[0] and 1 != 0) add("boost_commanded_absolute", "kPa", u16(1) / 32.0)
                if (d[0] and 2 != 0) add("boost_absolute", "kPa", u16(3) / 32.0)
            }
            "78" -> if (d.size >= 9) {
                for (i in 0..3) if (d[0] and (1 shl i) != 0) add("egt_${i + 1}", "°C", u16(1 + i * 2) / 10.0 - 40)
            }
            "7A" -> if (d.size >= 7 && d[0] and 1 != 0) {
                val raw = u16(1); val signed = if (raw >= 32768) raw - 65536 else raw
                add("dpf_delta_pressure", "kPa", signed / 100.0)
            }
            "8B" -> if (d.size >= 7) {
                if (d[0] and 1 != 0) add("dpf_regen_active", "boolean", (d[1] and 1).toDouble())
                if (d[0] and 2 != 0) add("dpf_regen_type_active", "boolean", ((d[1] shr 1) and 1).toDouble())
                // This standardized trigger is NOT a verified Car Scanner soot-mass/soot-% mapping.
                if (d[0] and 16 != 0) add("dpf_regen_trigger", "%", d[2] / 2.55)
                if (d[0] and 32 != 0) add("dpf_average_regen_time", "min", u16(3).toDouble())
                if (d[0] and 64 != 0) add("dpf_average_regen_distance", "km", u16(5).toDouble())
            }
        }
        return result
    }
}

/** Reassemble only the engine ECU's ISO-TP messages. Never concatenate headers,
 * padding, different ECU replies, or incomplete/out-of-order consecutive frames.
 * Requires ATH1 + ATS0 + ATD0 (no additional DLC column).
 */
object EngineIsoTp {
    fun messages(reply: String): List<List<Int>> {
        val result = mutableListOf<List<Int>>()
        var pending: MutableList<Int>? = null
        var required = 0
        var sequence = 1
        for (raw in reply.uppercase().split('\r', '\n', '>')) {
            val line = raw.replace(" ", "").trim()
            if (!line.startsWith("7E8")) continue
            val hex = line.drop(3)
            if (hex.length < 2 || hex.length % 2 != 0 || !hex.all { it in "0123456789ABCDEF" }) continue
            val frame = hex.chunked(2).map { it.toInt(16) }
            when (frame[0] shr 4) {
                0 -> {
                    pending = null
                    val count = frame[0] and 15
                    if (count in 1..7 && frame.size >= count + 1) result += frame.drop(1).take(count)
                }
                1 -> {
                    pending = null
                    if (frame.size < 3) continue
                    required = ((frame[0] and 15) shl 8) + frame[1]
                    if (required !in 8..4095) continue
                    pending = frame.drop(2).toMutableList(); sequence = 1
                }
                2 -> {
                    val current = pending ?: continue
                    if (frame[0] and 15 != sequence) { pending = null; continue }
                    current.addAll(frame.drop(1)); sequence = (sequence + 1) and 15
                    if (current.size >= required) { result += current.take(required); pending = null }
                }
            }
        }
        return result
    }
}
