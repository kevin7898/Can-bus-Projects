package ca.jettatelemetry.app.obd

import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class UdsDiscoverySetupTest {
    @Test
    fun verifiesRouteWithAControlAndDoesNotIssueCandidateRequests() = runBlocking {
        val commands = mutableListOf<String>()
        val logged = mutableListOf<String>()
        prepareUdsDiscovery({ command, _ ->
            commands += command
            val body = if (command == "0100") "410098192013" else "$command\rOK"
            ObdReply(command, body, 120)
        }) { command, _ -> logged += command }
        assertEquals(commands, logged)
        assertEquals("0100", commands.last())
        assertTrue(commands.indexOf("ATSH7E0") < commands.indexOf("0100"))
        assertTrue(commands.indexOf("ATCRA7E8") < commands.indexOf("0100"))
        assertTrue(commands.indexOf("ATAT0") < commands.indexOf("STPTO 1000"))
        assertTrue(commands.none { it.startsWith("22") })
    }

    @Test
    fun stopsOnRejectedSetupAndRetainsItsReply() = runBlocking {
        val commands = mutableListOf<String>()
        val logged = mutableListOf<ObdReply>()
        try {
            prepareUdsDiscovery({ command, _ ->
                commands += command
                ObdReply(command, if (command == "ATCRA7E8") "?" else "OK", 10)
            }) { _, reply -> logged += reply }
            fail("Expected rejected receive-filter setup")
        } catch (failure: IOException) {
            assertTrue(failure.message!!.contains("ATCRA7E8"))
            assertEquals("?", logged.last().body)
            assertEquals("ATCRA7E8", commands.last())
            assertTrue("0100" !in commands)
        }
    }

    @Test
    fun distinguishesUnverifiedRouteFromUnsupportedCandidates() = runBlocking {
        for (body in listOf("NO DATA", "41009819", "UNABLE TO CONNECT")) {
            val logged = mutableListOf<ObdReply>()
            try {
                prepareUdsDiscovery({ command, _ ->
                    ObdReply(command, if (command == "0100") body else "OK", 115)
                }) { _, reply -> logged += reply }
                fail("Expected invalid control response")
            } catch (failure: IOException) {
                assertTrue(failure.message!!.contains("Sensor identifiers were not tested"))
                assertEquals(body, logged.last().body)
            }
        }
    }

    @Test
    fun callerCancellationIsNotConvertedToSetupFailure() = runBlocking {
        val cancelled = CancellationException("caller stopped discovery")
        try {
            prepareUdsDiscovery({ _, _ -> throw cancelled }) { _, _ -> fail("No completed reply") }
            fail("Expected cancellation")
        } catch (failure: CancellationException) {
            assertTrue(cancelled === failure)
        }
    }
}
