package ai.sarvam

import ai.sarvam.core.sse.SseReader
import kotlinx.coroutines.flow.asFlow
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test
import java.nio.charset.StandardCharsets

class SseReaderTest {

    @Test
    fun `parses standard SSE events and skips comments`() = runTest {
        val payload = """
            : this is a comment
            event: add
            data: 7331
            id: 1

            event: remove
            data: 42
            id: 2

        """.trimIndent()

        val byteFlow = listOf(payload.toByteArray(StandardCharsets.UTF_8)).asFlow()
        val events = SseReader.parse(byteFlow).toList()

        assertEquals(2, events.size)
        assertEquals("add", events[0].event)
        assertEquals("7331", events[0].data)
        assertEquals("1", events[0].id)

        assertEquals("remove", events[1].event)
        assertEquals("42", events[1].data)
        assertEquals("2", events[1].id)
    }

    @Test
    fun `parses chunks split across arbitrary byte boundaries`() = runTest {
        val chunk1 = "data: {\"id\":\"chatcmpl-1\",\"choices\":[{\"in".toByteArray()
        val chunk2 = "dex\":0,\"delta\":{\"content\":\"Hello\"}}]}\n\ndata: [DONE]\n\n".toByteArray()

        val byteFlow = listOf(chunk1, chunk2).asFlow()
        val events = SseReader.parse(byteFlow).toList()

        assertEquals(2, events.size)
        assertEquals("{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"}}]}", events[0].data)
        assertEquals("[DONE]", events[1].data)
    }

    @Test
    fun `joins multi-line data with newline`() = runTest {
        val payload = "data: line 1\ndata: line 2\n\n"
        val byteFlow = listOf(payload.toByteArray()).asFlow()
        val events = SseReader.parse(byteFlow).toList()

        assertEquals(1, events.size)
        assertEquals("line 1\nline 2", events[0].data)
    }

    @Test
    fun `handles CRLF line endings`() = runTest {
        val payload = "data: foo\r\n\r\ndata: bar\r\n\r\n"
        val byteFlow = listOf(payload.toByteArray()).asFlow()
        val events = SseReader.parse(byteFlow).toList()

        assertEquals(2, events.size)
        assertEquals("foo", events[0].data)
        assertEquals("bar", events[1].data)
    }
}
