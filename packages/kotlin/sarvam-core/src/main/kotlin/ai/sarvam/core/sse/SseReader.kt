package ai.sarvam.core.sse

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import java.nio.charset.StandardCharsets

public object SseReader {

    public fun parse(byteFlow: Flow<ByteArray>): Flow<SseEvent> = flow {
        val buffer = StringBuilder()
        var currentId: String? = null
        var currentEvent: String? = null
        val currentData = mutableListOf<String>()
        var currentRetry: Long? = null

        fun dispatchEvent(): SseEvent? {
            if (currentData.isEmpty() && currentEvent == null && currentId == null && currentRetry == null) {
                return null
            }
            val event = SseEvent(
                id = currentId,
                event = currentEvent,
                data = currentData.joinToString("\n"),
                retry = currentRetry
            )
            currentEvent = null
            currentData.clear()
            currentRetry = null
            return event
        }

        byteFlow.collect { chunk ->
            buffer.append(String(chunk, StandardCharsets.UTF_8))

            while (true) {
                val newlineIndex = buffer.indexOf('\n')
                if (newlineIndex == -1) break

                var line = buffer.substring(0, newlineIndex)
                buffer.delete(0, newlineIndex + 1)

                if (line.endsWith('\r')) {
                    line = line.substring(0, line.length - 1)
                }

                if (line.isEmpty()) {
                    val event = dispatchEvent()
                    if (event != null) {
                        emit(event)
                    }
                } else if (line.startsWith(":")) {
                    // Comment, ignore
                } else {
                    val colonIndex = line.indexOf(':')
                    val field: String
                    val value: String
                    if (colonIndex == -1) {
                        field = line
                        value = ""
                    } else {
                        field = line.substring(0, colonIndex)
                        value = if (colonIndex + 1 < line.length && line[colonIndex + 1] == ' ') {
                            line.substring(colonIndex + 2)
                        } else {
                            line.substring(colonIndex + 1)
                        }
                    }

                    when (field) {
                        "event" -> currentEvent = value
                        "data" -> currentData.add(value)
                        "id" -> currentId = value
                        "retry" -> currentRetry = value.toLongOrNull()
                    }
                }
            }
        }

        // Flush any trailing event
        val finalEvent = dispatchEvent()
        if (finalEvent != null) {
            emit(finalEvent)
        }
    }
}
