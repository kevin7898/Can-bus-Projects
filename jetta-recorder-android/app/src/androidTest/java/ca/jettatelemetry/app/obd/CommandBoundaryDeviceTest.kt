package ca.jettatelemetry.app.obd

import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Exercises the production exchange on Android/Dispatchers.IO; never uses the car or telemetry UI. */
class CommandBoundaryDeviceTest {
    @Test
    fun cancelledPollCannotDonateItsReplyToDiscovery() = runBlocking {
        val bytes = ConcurrentLinkedQueue<Int>()
        fun enqueue(text: String) = text.toByteArray().forEach { bytes.add(it.toInt() and 255) }
        val reader = object : InputStream() {
            override fun available() = bytes.size
            override fun read() = bytes.poll() ?: -1
        }
        val pollSent = CompletableDeferred<Unit>()
        val setupQueued = CompletableDeferred<Unit>()
        val setupSent = AtomicBoolean(false)
        val invalidated = AtomicBoolean(false)
        val writer = object : OutputStream() {
            override fun write(value: Int) = error("Expected a complete command")
            override fun write(value: ByteArray) {
                when (value.toString(Charsets.US_ASCII).trim()) {
                    "010B" -> pollSent.complete(Unit)
                    "ATE0" -> {
                        setupSent.set(true)
                        enqueue("OK\r>")
                    }
                    else -> error("Unexpected command")
                }
            }
        }
        val mutex = Mutex()
        val poll = async(Dispatchers.IO) {
            mutex.withLock {
                exchangeObdCommand(reader, writer, "010B", 5_000) { invalidated.set(true) }
            }
        }
        withTimeout(5_000) { pollSent.await() }
        poll.cancel()
        val setup = async(Dispatchers.IO) {
            setupQueued.complete(Unit)
            mutex.withLock {
                exchangeObdCommand(reader, writer, "ATE0", 5_000) { invalidated.set(true) }
            }
        }
        try {
            withTimeout(5_000) { setupQueued.await() }
            delay(100)
            assertFalse("Discovery transmitted before the old poll's prompt", setupSent.get())
            enqueue("NO DATA\r>")
            withTimeout(5_000) { poll.join() }
            val reply = withTimeout(5_000) { setup.await() }
            assertTrue(poll.isCancelled)
            assertEquals("OK", reply.body)
            assertEquals(0, bytes.size)
            assertFalse(invalidated.get())
        } finally {
            enqueue("\r>")
            poll.cancel()
            setup.cancel()
        }
    }

    @Test
    fun missingPromptAfterCancellationStillInvalidatesWithinTheDeadline() = runBlocking {
        val sent = CompletableDeferred<Unit>()
        val invalidated = AtomicBoolean(false)
        val reader = object : InputStream() {
            override fun available() = 0
            override fun read() = -1
        }
        val writer = object : OutputStream() {
            override fun write(value: Int) = error("Expected a complete command")
            override fun write(value: ByteArray) { sent.complete(Unit) }
        }
        val poll = async(Dispatchers.IO) {
            exchangeObdCommand(reader, writer, "010B", 300) { invalidated.set(true) }
        }
        withTimeout(5_000) { sent.await() }
        poll.cancel()
        withTimeout(5_000) { poll.join() }
        assertTrue(poll.isCancelled)
        assertTrue(invalidated.get())
    }
}
