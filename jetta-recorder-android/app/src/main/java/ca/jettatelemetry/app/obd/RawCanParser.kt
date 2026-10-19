package ca.jettatelemetry.app.obd

import ca.jettatelemetry.app.model.RawCanFrame

/** Parses the header + DLC format produced by an STN adapter with ATH1/ATD1/ATS1. */
object RawCanParser {
    private val hex = Regex("^[0-9A-Fa-f]+$")

    fun parse(line: String, timestampEpochSeconds: Double): RawCanFrame? {
        val clean = line.trim()
        if (clean.isBlank() || clean.equals("STOPPED", true) || clean == ">") return null

        val tokens = clean.split(Regex("\\s+")).filter(String::isNotBlank)
        if (tokens.size < 2 || tokens[0].length !in setOf(3, 8) || !tokens[0].matches(hex)) return null

        val id = tokens[0].toLongOrNull(16)?.takeIf { it in 0L..0x1FFFFFFFL }?.toInt() ?: return null
        val isExtended = tokens[0].length == 8

        // ATD1 prints DLC after the identifier. Fall back to a header+data line if a
        // firmware revision omits it despite the setting.
        val possibleDlc = tokens.getOrNull(1)?.toIntOrNull(16)
        val hasDlc = possibleDlc != null && possibleDlc in 0..8 && tokens.size >= possibleDlc + 2
        val dataTokens = if (hasDlc) tokens.drop(2).take(possibleDlc!!) else tokens.drop(1)
        if (dataTokens.size > 8 || dataTokens.any { it.length != 2 || !it.matches(hex) }) return null

        return RawCanFrame(
            timestampEpochSeconds = timestampEpochSeconds,
            arbitrationId = id,
            isExtendedId = isExtended,
            data = dataTokens.map { it.toInt(16).toByte() }.toByteArray(),
            sourceLine = clean
        )
    }
}
