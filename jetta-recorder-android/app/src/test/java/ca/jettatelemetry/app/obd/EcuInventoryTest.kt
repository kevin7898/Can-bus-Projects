package ca.jettatelemetry.app.obd

import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class EcuInventoryTest {
    private fun control(body: String) = ObdReply("0100", body, 1_018)

    @Test
    fun capturedJettaSupportPagesAdvertiseStandardAlternativesButNotGenericMap() = runBlocking {
        val capturedPages = mapOf(
            "0120" to "41209801A011", "0140" to "4140C4D2800D",
            "0160" to "4160EAA9A343", "0180" to "4180C0A00000"
        )
        val supported = collectEcuInventory(control("410098192013"), { command, _ ->
            ObdReply(command, capturedPages[command] ?: "NO DATA", 1_000)
        }) { _, _ -> }
        assertTrue(supported.containsAll(setOf(0x5E, 0x70, 0x78, 0x7A, 0x8B)))
        assertTrue(0x0B !in supported)
        assertTrue(0x5C !in supported)
        assertTrue(0x8C !in supported)
    }

    @Test
    fun followsOnlyAdvertisedSupportedPidPages() = runBlocking {
        val commands = mutableListOf<String>()
        val logged = mutableListOf<String>()
        collectEcuInventory(control("410098192013"), { command, _ ->
            commands += command
            ObdReply(command, when (command) {
                "0120" -> "41 20 80 00 00 01"
                "0140" -> "414000000000"
                else -> "NO DATA"
            }, 1_000)
        }) { command, _ -> logged += command }
        assertEquals(listOf("0120", "0140", "0900", "0904", "090A"), commands)
        assertEquals(commands, logged)
    }

    @Test
    fun noContinuationBitSkipsFurtherMode01Pages() = runBlocking {
        val commands = mutableListOf<String>()
        collectEcuInventory(control("410098192012"), { command, _ ->
            commands += command
            ObdReply(command, "NO DATA", 1_000)
        }) { _, _ -> }
        assertEquals(listOf("0900", "0904", "090A"), commands)
    }

    @Test
    fun missingPageDataStopsThePageWalkButRetainsIdentificationReads() = runBlocking {
        for (body in listOf("NO DATA", "41208000", "?")) {
            val commands = mutableListOf<String>()
            collectEcuInventory(control("410098192013"), { command, _ ->
                commands += command
                ObdReply(command, body, 1_000)
            }) { _, _ -> }
            assertEquals(listOf("0120", "0900", "0904", "090A"), commands)
        }
    }

    @Test
    fun pageWalkIsBoundedEvenIfEveryPageAdvertisesAnother() = runBlocking {
        val commands = mutableListOf<String>()
        collectEcuInventory(control("410000000001"), { command, _ ->
            commands += command
            ObdReply(command, "41${command.takeLast(2)}00000001", 1_000)
        }) { _, _ -> }
        assertEquals(listOf("0120", "0140", "0160", "0180", "01A0", "01C0", "01E0",
            "0900", "0904", "090A"), commands)
    }

    @Test
    fun multilineAndNoDataIdentificationRepliesAreRetainedVerbatim() = runBlocking {
        val calid = "013\r0: 49 04 01 30 33 4C\r1: 39 30 36 30 31 39 4A\r2: 4A 00 00 00 00 00 00"
        val replies = mutableMapOf<String, String>()
        collectEcuInventory(control("410000000000"), { command, _ ->
            ObdReply(command, if (command == "0904") calid else "NO DATA", 1_000)
        }) { command, reply -> replies[command] = reply.body }
        assertEquals(calid, replies["0904"])
        assertEquals("NO DATA", replies["090A"])
    }

    @Test
    fun cancellationAndTransportFailureStopWithoutSendingFurtherQueries() = runBlocking {
        for (failure in listOf(CancellationException("Stopped"), IOException("Connection lost"))) {
            val commands = mutableListOf<String>()
            try {
                collectEcuInventory(control("410000000000"), { command, _ ->
                    commands += command
                    throw failure
                }) { _, _ -> fail("An unfinished exchange must not be recorded as completed") }
                fail("Expected transport failure or cancellation")
            } catch (caught: Exception) {
                assertTrue(caught === failure)
                assertEquals(listOf("0900"), commands)
            }
        }
    }
}
