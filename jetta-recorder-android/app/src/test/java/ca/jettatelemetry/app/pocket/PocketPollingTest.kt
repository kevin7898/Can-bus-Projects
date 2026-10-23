package ca.jettatelemetry.app.pocket

import org.junit.Assert.*
import org.junit.Test

class PocketPollingTest {
    private val combined = "7E81009410C1C980D4E\r7E8215E009300000000"

    @Test fun `driving and exhaust target one fresh read per second`() {
        val polling = PocketPolling(true)
        assertEquals(1_000L, polling.groups.single { it.id == "drive" }.periodMs)
        assertEquals(1_000L, polling.groups.single { it.id == "exhaust" }.periodMs)
        assertTrue(polling.tasks().all { it.periodMs >= 1_000L })
    }

    @Test fun `combined response decodes PID boundaries after one service byte`() {
        val decoded = ObservedJettaProfile.decodeMany(listOf("0C", "0D", "5E"), combined)
        assertEquals(setOf("0C", "0D", "5E"), decoded.keys)
        assertEquals(1830.0, decoded.getValue("0C").single().value, 0.001)
        assertEquals(78.0, decoded.getValue("0D").single().value, 0.001)
        assertEquals(7.35, decoded.getValue("5E").single().value, 0.001)
        val separate = ObservedJettaProfile.decodeMany(listOf("0C", "0D"), "7E804410C1C98\r7E803410D4E")
        assertEquals(setOf("0C", "0D"), separate.keys)
    }

    @Test fun `unknown and truncated fields do not become guessed readings`() {
        assertTrue(ObservedJettaProfile.decodeMany(listOf("0C"), "7E80341050C").isEmpty())
        assertTrue(ObservedJettaProfile.decodeMany(listOf("0C"), "7E805413C0C1C98").isEmpty())
        assertTrue(ObservedJettaProfile.decodeMany(listOf("0C"), "7E803410C1C").isEmpty())
    }

    @Test fun `response count is learned only after three complete consistent replies`() {
        val polling = PocketPolling(true)
        val task = PollTask("example", listOf("0C", "0D", "5E"), 1_000)
        repeat(2) { polling.observe(task, combined, task.pids.toSet()) }
        assertEquals("010C0D5E", polling.command(task))
        polling.observe(task, combined, task.pids.toSet())
        assertEquals("010C0D5E2", polling.command(task))
        polling.observe(task, "NO DATA", emptySet())
        assertEquals("010C0D5E", polling.command(task))
        repeat(4) { polling.observe(task, combined, task.pids.toSet()) }
        assertEquals("010C0D5E", polling.command(task))
    }

    @Test fun `incomplete group falls back without dropping its remaining sensors`() {
        val polling = PocketPolling(true)
        val drive = polling.tasks().single { it.id == "drive" }
        polling.observe(drive, "7E803410D4E", setOf("0D"))
        val fallback = polling.tasks().filter { it.id.startsWith("drive-") }
        assertEquals(drive.pids.toSet(), fallback.flatMap { it.pids }.toSet())
        assertTrue(fallback.all { it.pids.size == 1 && it.periodMs == 1_000L })
        assertEquals(1, polling.fallbackGroups)
        assertFalse(polling.tasks().any { it.id == "drive" })
    }

    @Test fun `compatibility mode never batches or adds count hints`() {
        val polling = PocketPolling(false)
        assertTrue(polling.tasks().all { it.pids.size == 1 })
        val task = polling.tasks().first()
        repeat(4) { polling.observe(task, "7E803410D4E", task.pids.toSet()) }
        assertEquals("01" + task.pids.single(), polling.command(task))
    }

    @Test fun `measured rates count actual decoded replies over elapsed window`() {
        val rates = PocketRates(0)
        rates.add(1_000, 4, 100); rates.add(2_000, 0, 300)
        val first = rates.snapshot(2_000)
        assertEquals(1.0, first.requestsPerSecond, 0.001)
        assertEquals(2.0, first.pidsPerSecond, 0.001)
        assertEquals(200.0, first.averageReplyMs, 0.001)
        val expired = rates.snapshot(7_000)
        assertEquals(0.0, expired.pidsPerSecond, 0.001)
        assertEquals(0.0, expired.requestsPerSecond, 0.001)
    }
}
