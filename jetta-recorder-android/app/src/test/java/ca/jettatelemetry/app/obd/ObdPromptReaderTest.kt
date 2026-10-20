package ca.jettatelemetry.app.obd

import java.io.ByteArrayInputStream
import java.io.InputStream
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class ObdPromptReaderTest {
    @Test
    fun returnsOnlyTheReplyBeforeThePrompt() = runBlocking {
        val input = ByteArrayInputStream("\r41 0C 1A F8\r>next".toByteArray())
        assertEquals("41 0C 1A F8", readObdPrompt(input, "010C", 1_000))
        assertEquals('n'.code, input.read())
    }

    @Test
    fun timeoutRetainsCommandAndExactPartialReply() = runBlocking {
        val input = ByteArrayInputStream("SEARCHING...\r".toByteArray())
        try {
            readObdPrompt(input, "010C", 200)
            fail("Expected missing-prompt timeout")
        } catch (failure: ObdRequestTimeoutException) {
            assertEquals("010C", failure.command)
            assertEquals(200L, failure.timeoutMillis)
            assertEquals("SEARCHING...\r", failure.partialReply)
            assertTrue(failure.message!!.contains("010C"))
            assertTrue(failure.message!!.contains("SEARCHING..."))
        }
    }

    @Test
    fun timeoutDistinguishesNoBytesFromPartialData() = runBlocking {
        try {
            readObdPrompt(ByteArrayInputStream(byteArrayOf()), "0133", 200)
            fail("Expected no-response timeout")
        } catch (failure: ObdRequestTimeoutException) {
            assertEquals("", failure.partialReply)
            assertTrue(failure.message!!.contains("no bytes received"))
        }
    }

    @Test
    fun parentDeadlineIsNotReportedAsAnAdapterTimeout() = runBlocking {
        try {
            withTimeout(200) {
                readObdPrompt(ByteArrayInputStream(byteArrayOf()), "010C", 5_000)
            }
            fail("Expected caller cancellation")
        } catch (failure: TimeoutCancellationException) {
            assertTrue(failure.message!!.contains("200"))
        }
    }

    @Test
    fun endOfStreamIsReportedAsDisconnection() = runBlocking {
        val input = object : InputStream() {
            override fun available() = 1
            override fun read() = -1
        }
        try {
            readObdPrompt(input, "010D", 1_000)
            fail("Expected disconnection")
        } catch (failure: IllegalStateException) {
            assertEquals("Adapter disconnected while reading 010D", failure.message)
        }
    }
}
