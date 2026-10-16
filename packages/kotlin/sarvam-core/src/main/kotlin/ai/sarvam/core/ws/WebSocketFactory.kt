package ai.sarvam.core.ws

public interface WebSocketFactory {
    public suspend fun connect(
        url: String,
        headers: Map<String, String> = emptyMap(),
        subprotocols: List<String> = emptyList()
    ): WebSocketSession
}
