package ca.jettatelemetry.app.obd

import java.io.InputStream
import java.io.OutputStream
import java.nio.charset.StandardCharsets
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

/** Caller holds the transport request mutex for this entire exchange. */
internal suspend fun exchangeObdCommand(
    reader: InputStream,
    writer: OutputStream,
    command: String,
    timeoutMillis: Long,
    onUnrecoverableFailure: () -> Unit = {}
): ObdReply {
    currentCoroutineContext().ensureActive()
    // A coroutine can stop polling, but bytes already sent to the adapter cannot
    // be cancelled. Keep owning the channel until this reply's prompt arrives.
    // readObdPrompt still enforces the request's bounded timeout in this context.
    val reply = try {
        withContext(NonCancellable) {
            try {
                val started = System.nanoTime()
                writer.write((command.trim() + "\r").toByteArray(StandardCharsets.US_ASCII))
                writer.flush()
                val body = readObdPrompt(reader, command.trim(), timeoutMillis)
                ObdReply(command.trim(), body, (System.nanoTime() - started) / 1_000_000)
            } catch (failure: Throwable) {
                // Without a consumed prompt, a later reply cannot be assigned safely.
                runCatching(onUnrecoverableFailure)
                throw failure
            }
        }
    } catch (failure: Throwable) {
        // A caller that cancelled while waiting still observes cancellation,
        // including when the bounded drain failed and invalidated the session.
        currentCoroutineContext().ensureActive()
        throw failure
    }
    // Preserve caller cancellation after the stream is synchronized. A cancelled
    // poll must not update telemetry or send its next command.
    currentCoroutineContext().ensureActive()
    return reply
}
