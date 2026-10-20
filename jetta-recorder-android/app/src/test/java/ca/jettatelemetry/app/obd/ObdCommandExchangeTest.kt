package ca.jettatelemetry.app.obd

import java.io.InputStream
import java.io.OutputStream
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class ObdCommandExchangeTest {
    @Test
    fun timeoutInvalidatesTheSessionAndRetainsItsPartialReply() = runBlocking {
        var invalidated = false
        try {
            exchangeObdCommand(
                ByteArrayInputStream("SEARCHING...".toByteArray()), ByteArrayOutputStream(), "0100", 100
            ) { invalidated = true }
            fail("Expected a bounded request timeout")
        } catch (failure: ObdRequestTimeoutException) {
            assertTrue(invalidated)
            assertEquals("0100", failure.command)
            assertEquals("SEARCHING...", failure.partialReply)
        }
    }

    @Test
    fun alreadyCancelledCallerDoesNotTransmit() = runBlocking {
        val output = ByteArrayOutputStream()
        val job = async {
            kotlinx.coroutines.currentCoroutineContext()[kotlinx.coroutines.Job]!!.cancel()
            exchangeObdCommand(ByteArrayInputStream("OK>".toByteArray()), output, "ATE0", 100)
        }
        try {
            job.await()
            fail("Expected caller cancellation")
        } catch (_: CancellationException) {
            assertEquals(0, output.size())
        }
    }

    @Test
    fun writeFailureInvalidatesWithoutMaskingTheOriginalFailure() = runBlocking {
        val failure = java.io.IOException("Disconnected during write")
        var invalidated = false
        val output = object : OutputStream() {
            override fun write(value: Int) { throw failure }
        }
        try {
            exchangeObdCommand(ByteArrayInputStream(byteArrayOf()), output, "ATE0", 100) {
                invalidated = true
            }
            fail("Expected write failure")
        } catch (caught: java.io.IOException) {
            assertTrue(invalidated)
            assertEquals(failure.message, caught.message)
            // Coroutine stack recovery may copy IOException, retaining the original cause.
            assertTrue(caught === failure || caught.cause === failure)
        }
    }

    @Test
    fun cancelledRequestStillExpiresAndInvalidatesIfItsPromptNeverArrives() = runBlocking {
        val sent = CompletableDeferred<Unit>()
        var invalidated = false
        val writer = object : ByteArrayOutputStream() {
            override fun write(value: ByteArray) {
                super.write(value)
                sent.complete(Unit)
            }
        }
        val poll = async {
            exchangeObdCommand(ByteArrayInputStream(byteArrayOf()), writer, "010B", 100) {
                invalidated = true
            }
        }
        sent.await()
        poll.cancel()
        withTimeout(1_000) { poll.join() }
        assertTrue(poll.isCancelled)
        assertTrue(invalidated)
    }

    @Test
    fun cancelledPollMustConsumeItsReplyBeforeDiscoveryCanSendACommand() = runBlocking {
        val bytes = ArrayDeque<Byte>()
        val reader = object : InputStream() {
            override fun available() = bytes.size
            override fun read() = if (bytes.isEmpty()) -1 else bytes.removeFirst().toInt() and 255
        }
        val pollSent = CompletableDeferred<Unit>()
        val setupSent = CompletableDeferred<Unit>()
        val writer = object : OutputStream() {
            override fun write(value: Int) = error("Expected complete command write")
            override fun write(value: ByteArray) {
                when (value.toString(Charsets.US_ASCII).trim()) {
                    "010B" -> pollSent.complete(Unit)
                    "ATE0" -> {
                        setupSent.complete(Unit)
                        bytes.addAll("OK\r>".toByteArray().toList())
                    }
                    else -> error("Unexpected command")
                }
            }
        }
        val mutex = Mutex()
        val poll = async {
            mutex.withLock { exchangeObdCommand(reader, writer, "010B", 1_000) }
        }
        pollSent.await()
        poll.cancel()
        val discovery = async {
            mutex.withLock { exchangeObdCommand(reader, writer, "ATE0", 1_000) }
        }
        try {
            delay(50)
            assertFalse("ATE0 was transmitted before the cancelled poll's prompt", setupSent.isCompleted)
            // The unsupported MAP query completes after its coroutine was cancelled.
            bytes.addAll("NO DATA\r>".toByteArray().toList())
            poll.join()
            assertTrue(poll.isCancelled)
            assertEquals("OK", discovery.await().body)
            assertEquals(0, reader.available())
        } finally {
            bytes.addAll("\r>".toByteArray().toList())
            poll.cancel()
            discovery.cancel()
        }
    }
}
