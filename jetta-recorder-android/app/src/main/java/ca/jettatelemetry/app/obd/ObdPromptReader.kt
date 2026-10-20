package ca.jettatelemetry.app.obd

import java.io.IOException
import java.io.InputStream
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withTimeout

class ObdRequestTimeoutException(
    val command: String,
    val timeoutMillis: Long,
    val partialReply: String,
    cause: TimeoutCancellationException
) : IOException(
    "Command $command timed out after $timeoutMillis ms waiting for adapter prompt '>'. " +
        "Partial reply: ${partialReply.ifBlank { "(no bytes received)" }}",
    cause
)

/** Retain the bytes seen before a deadline; never turn caller cancellation into an adapter fault. */
internal suspend fun readObdPrompt(reader: InputStream, command: String, timeoutMillis: Long): String {
    val response = StringBuilder()
    try {
        return withTimeout(timeoutMillis) {
            while (true) {
                currentCoroutineContext().ensureActive()
                if (reader.available() == 0) {
                    delay(4)
                    continue
                }
                val byte = reader.read()
                check(byte >= 0) { "Adapter disconnected while reading $command" }
                if (byte.toChar() == '>') break
                response.append(byte.toChar())
            }
            response.toString().trim()
        }
    } catch (failure: TimeoutCancellationException) {
        currentCoroutineContext().ensureActive()
        throw ObdRequestTimeoutException(command, timeoutMillis, response.toString(), failure)
    }
}
