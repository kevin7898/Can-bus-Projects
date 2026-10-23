package ca.jettatelemetry.app.pocket

import java.util.ArrayDeque

data class PollTask(val id: String, val pids: List<String>, val periodMs: Long)

/** Fixed groups keep the driving signals sampled together and make learned frame
 * counts repeatable. An incomplete group falls back to independent requests.
 */
class PocketPolling(private val optimized: Boolean) {
    val groups = listOf(
        PollTask("drive", listOf("0D", "0C", "5E", "70"), 1_000),
        PollTask("temperatures", listOf("05", "46", "33", "42"), 5_000),
        PollTask("exhaust", listOf("78", "7A"), 1_000),
        PollTask("dpf", listOf("8B"), 5_000),
        PollTask("load", listOf("04", "10"), 1_000)
    )
    private val split = mutableSetOf<String>()
    private val counts = mutableMapOf<String, Pair<Int, Int>>()
    private val disabledHints = mutableSetOf<String>()
    val fallbackGroups: Int get() = split.size

    fun tasks(): List<PollTask> = groups.flatMap { group ->
        if (!optimized || group.id in split) group.pids.map { PollTask("${group.id}-$it", listOf(it), group.periodMs) }
        else listOf(group)
    }

    fun command(task: PollTask): String {
        val count = counts[task.id]
        val hint = if (optimized && task.id !in disabledHints && count != null && count.second >= 3) count.first.toString(16).uppercase() else ""
        return "01" + task.pids.joinToString("") + hint
    }

    fun observe(task: PollTask, reply: String, returned: Set<String>) {
        val complete = task.pids.all { it in returned }
        val frames = reply.uppercase().split('\r', '\n').count { raw ->
            val line = raw.replace(" ", "").trim()
            line.matches(Regex("7E8[0-2][0-9A-F](?:[0-9A-F]{2}){1,7}"))
        }
        if (!complete) {
            counts.remove(task.id); disabledHints += task.id
            if (task.pids.size > 1) split += task.id
            return
        }
        if (frames !in 1..15) return
        val previous = counts[task.id]
        counts[task.id] = frames to if (previous?.first == frames) previous.second + 1 else 1
    }
}

/** Rolling acquisition measurements; these are observed values, not target rates. */
class PocketRates(private val startedMs: Long) {
    data class Snapshot(val requestsPerSecond: Double, val pidsPerSecond: Double, val averageReplyMs: Double)
    private data class Sample(val at: Long, val pids: Int, val latency: Long)
    private val samples = ArrayDeque<Sample>()
    @Synchronized fun add(now: Long, pids: Int, latency: Long) { samples.addLast(Sample(now, pids, latency)); trim(now) }
    private fun trim(now: Long) { while (samples.isNotEmpty() && samples.first.at <= now - 5_000) samples.removeFirst() }
    @Synchronized fun snapshot(now: Long): Snapshot {
        trim(now)
        val seconds = (now - maxOf(startedMs, now - 5_000)).coerceAtLeast(1) / 1000.0
        return Snapshot(samples.size / seconds, samples.sumOf { it.pids } / seconds,
            if (samples.isEmpty()) 0.0 else samples.sumOf { it.latency }.toDouble() / samples.size)
    }
}
