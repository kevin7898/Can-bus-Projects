package ca.jettatelemetry.app.obd

object Mode01Decoder {
    fun rpm(reply: String): Double? {
        val bytes = dataBytes(reply, "0C", 2) ?: return null
        return ((bytes[0] shl 8) + bytes[1]) / 4.0
    }

    fun speedKmh(reply: String): Double? = dataBytes(reply, "0D", 1)?.first()?.toDouble()

    fun coolantC(reply: String): Double? = dataBytes(reply, "05", 1)?.first()?.minus(40.0)

    fun mapKpa(reply: String): Double? = dataBytes(reply, "0B", 1)?.first()?.toDouble()

    fun barometricKpa(reply: String): Double? = dataBytes(reply, "33", 1)?.first()?.toDouble()

    internal fun dataBytes(reply: String, pid: String, count: Int): List<Int>? {
        val compact = reply
            .uppercase()
            .replace("SEARCHING...", "")
            .replace(Regex("[^0-9A-F]"), "")
        val marker = "41${pid.uppercase()}"
        val markerIndex = compact.indexOf(marker)
        if (markerIndex < 0) return null
        val dataStart = markerIndex + marker.length
        val dataEnd = dataStart + count * 2
        if (compact.length < dataEnd) return null
        return (dataStart until dataEnd step 2).map { index ->
            compact.substring(index, index + 2).toIntOrNull(16) ?: return null
        }
    }
}

