package ca.jettatelemetry.app.obd

import java.io.IOException
import java.io.InputStream
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class ObdProtocolHandshakeTest {
    @Test
    fun waitsForVehicleReplyBeyondTheLiveDeadlineBeforeAskingForProtocol() = runBlocking {
        val bytes = ArrayDeque<Byte>("SEARCHING...\r".toByteArray().toList())
        val input = object : InputStream() {
            override fun available() = bytes.size
            override fun read() = if (bytes.isEmpty()) -1 else bytes.removeFirst().toInt() and 255
        }
        val commands = mutableListOf<String>()
        val exchanges = mutableListOf<String>()
        val response = launch {
            delay(2_800)
            // Protocol detection must still own the channel during the old 2.5 s deadline.
            assertEquals(listOf("0100"), commands)
            assertTrue(exchanges.isEmpty())
            bytes.addAll("41 00 BE 3F A8 13\r>".toByteArray().toList())
        }
        val protocol = establishObdProtocol({ command, deadline ->
            commands += command
            if (command == "0100") {
                ObdReply(command, readObdPrompt(input, command, deadline), 2_800)
            } else {
                ObdReply(command, "AUTO, ISO 15765-4 (CAN 11/500)", 10)
            }
        }) { command, _ -> exchanges += command }
        response.join()
        assertEquals(listOf("0100", "ATDP"), commands)
        assertEquals(commands, exchanges)
        assertTrue(protocol.body.contains("CAN 11/500"))
    }

    @Test
    fun rejectsAdapterErrorsAndIncompleteEcuRepliesBeforeDeclaringAProtocol() = runBlocking {
        for (body in listOf("SEARCHING...\rUNABLE TO CONNECT", "NO DATA", "?", "", "4100BE3F")) {
            val commands = mutableListOf<String>()
            val logged = mutableListOf<ObdReply>()
            try {
                establishObdProtocol({ command, _ ->
                    commands += command
                    ObdReply(command, body, 10)
                }) { _, reply -> logged += reply }
                fail("Expected vehicle handshake to reject '$body'")
            } catch (failure: IOException) {
                assertTrue(failure.message!!.contains("0100 returned"))
                assertEquals(listOf("0100"), commands)
                assertEquals(body, logged.single().body)
            }
        }
    }

    @Test
    fun cancellationDuringSearchDoesNotSendAnotherCommand() = runBlocking {
        val started = CompletableDeferred<Unit>()
        val commands = mutableListOf<String>()
        val search = async {
            establishObdProtocol({ command, _ ->
                commands += command
                started.complete(Unit)
                CompletableDeferred<ObdReply>().await()
            }) { _, _ -> fail("Cancelled request must not be logged as a completed exchange") }
        }
        started.await()
        assertFalse(search.isCompleted)
        search.cancelAndJoin()
        assertEquals(listOf("0100"), commands)
    }
}
