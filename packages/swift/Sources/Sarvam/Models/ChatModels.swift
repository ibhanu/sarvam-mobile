import Foundation

public struct ChatMessage: Codable, Sendable, Equatable {
    public var role: String
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct ChatCompletionRequest: Codable, Sendable, Equatable {
    public var model: ChatModel
    public var messages: [ChatMessage]
    public var stream: Bool?
    public var temperature: Double?
    public var maxTokens: Int?
    public var topP: Double?

    public init(
        model: ChatModel,
        messages: [ChatMessage],
        stream: Bool? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        topP: Double? = nil
    ) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case temperature
        case maxTokens = "max_tokens"
        case topP = "top_p"
    }
}

public struct ChatDelta: Codable, Sendable, Equatable {
    public let role: String?
    public let content: String?

    public init(role: String? = nil, content: String? = nil) {
        self.role = role
        self.content = content
    }
}

public struct ChatChoice: Codable, Sendable, Equatable {
    public let index: Int?
    public let message: ChatMessage?
    public let delta: ChatDelta?
    public let finishReason: String?

    public init(
        index: Int? = nil,
        message: ChatMessage? = nil,
        delta: ChatDelta? = nil,
        finishReason: String? = nil
    ) {
        self.index = index
        self.message = message
        self.delta = delta
        self.finishReason = finishReason
    }

    enum CodingKeys: String, CodingKey {
        case index
        case message
        case delta
        case finishReason = "finish_reason"
    }
}

public struct ChatUsage: Codable, Sendable, Equatable {
    public let promptTokens: Int?
    public let completionTokens: Int?
    public let totalTokens: Int?

    public init(promptTokens: Int? = nil, completionTokens: Int? = nil, totalTokens: Int? = nil) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

public struct ChatCompletionResponse: Codable, Sendable, Equatable {
    public let id: String?
    public let choices: [ChatChoice]
    public let usage: ChatUsage?

    public init(id: String? = nil, choices: [ChatChoice] = [], usage: ChatUsage? = nil) {
        self.id = id
        self.choices = choices
        self.usage = usage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.choices = (try container.decodeIfPresent([ChatChoice].self, forKey: .choices)) ?? []
        self.usage = try container.decodeIfPresent(ChatUsage.self, forKey: .usage)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case choices
        case usage
    }
}

/// Streaming chunk emitted by Chat completions SSE.
public struct ChatCompletionChunk: Codable, Sendable, Equatable {
    public let id: String?
    public let choices: [ChatChoice]
    public let usage: ChatUsage?

    public init(id: String? = nil, choices: [ChatChoice] = [], usage: ChatUsage? = nil) {
        self.id = id
        self.choices = choices
        self.usage = usage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.choices = (try container.decodeIfPresent([ChatChoice].self, forKey: .choices)) ?? []
        self.usage = try container.decodeIfPresent(ChatUsage.self, forKey: .usage)
    }

    /// Convenience accessor for content delta of the first choice.
    /// Safely returns `nil` when `choices` is empty (e.g. on final usage chunks).
    public var firstDeltaContent: String? {
        choices.first?.delta?.content
    }

    enum CodingKeys: String, CodingKey {
        case id
        case choices
        case usage
    }
}

public struct ChatModelInfo: Codable, Sendable, Equatable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

public struct ChatModelListResponse: Codable, Sendable, Equatable {
    public let models: [ChatModelInfo]

    public init(models: [ChatModelInfo]) {
        self.models = models
    }
}
