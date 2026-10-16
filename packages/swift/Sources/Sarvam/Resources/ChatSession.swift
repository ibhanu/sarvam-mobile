import Foundation

/// Stateful actor managing conversational multi-turn chat sessions with session affinity.
public actor ChatSession {
    public nonisolated let affinityId: String
    private let chatResource: ChatResource

    public init(chatResource: ChatResource, affinityId: String = UUID().uuidString) {
        self.chatResource = chatResource
        self.affinityId = affinityId
    }

    /// Unary Chat completions with session affinity.
    public func completions(
        _ request: ChatCompletionRequest,
        options: RequestOptions? = nil
    ) async throws -> ChatCompletionResponse {
        var opts = options ?? RequestOptions()
        opts.headers["x-session-affinity"] = affinityId
        return try await chatResource.completions(request, options: opts)
    }

    /// Streaming Chat completions with session affinity.
    public func completionsStream(
        _ request: ChatCompletionRequest,
        options: RequestOptions? = nil
    ) -> AsyncThrowingStream<ChatCompletionChunk, Error> {
        var opts = options ?? RequestOptions()
        opts.headers["x-session-affinity"] = affinityId
        return chatResource.completionsStream(request, options: opts)
    }

    /// Unary Chat completions V2 with session affinity.
    public func completionsV2(
        _ request: ChatCompletionRequest,
        options: RequestOptions? = nil
    ) async throws -> ChatCompletionResponse {
        var opts = options ?? RequestOptions()
        opts.headers["x-session-affinity"] = affinityId
        return try await chatResource.completionsV2(request, options: opts)
    }

    /// Streaming Chat completions V2 with session affinity.
    public func completionsV2Stream(
        _ request: ChatCompletionRequest,
        options: RequestOptions? = nil
    ) -> AsyncThrowingStream<ChatCompletionChunk, Error> {
        var opts = options ?? RequestOptions()
        opts.headers["x-session-affinity"] = affinityId
        return chatResource.completionsV2Stream(request, options: opts)
    }
}
