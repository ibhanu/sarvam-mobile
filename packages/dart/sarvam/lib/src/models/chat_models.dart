/// Single message in a chat conversation.
class ChatMessage {
  final String role;
  final String content;

  const ChatMessage({
    required this.role,
    required this.content,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'role': role,
        'content': content,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: json['role'] as String? ?? 'user',
      content: json['content'] as String? ?? '',
    );
  }
}

/// Token usage statistics for a chat completion request.
class ChatUsage {
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;

  const ChatUsage({
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
  });

  factory ChatUsage.fromJson(Map<String, dynamic> json) {
    return ChatUsage(
      promptTokens: json['prompt_tokens'] as int?,
      completionTokens: json['completion_tokens'] as int?,
      totalTokens: json['total_tokens'] as int?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (promptTokens != null) 'prompt_tokens': promptTokens,
        if (completionTokens != null) 'completion_tokens': completionTokens,
        if (totalTokens != null) 'total_tokens': totalTokens,
      };
}

/// Delta token chunk emitted during streaming chat completions.
class ChatDelta {
  final String? role;
  final String? content;

  const ChatDelta({this.role, this.content});

  factory ChatDelta.fromJson(Map<String, dynamic> json) {
    return ChatDelta(
      role: json['role'] as String?,
      content: json['content'] as String?,
    );
  }
}

/// Choice alternative in a unary or streaming chat completion.
class ChatCompletionChoice {
  final int index;
  final ChatMessage? message;
  final ChatDelta? delta;
  final String? finishReason;

  const ChatCompletionChoice({
    required this.index,
    this.message,
    this.delta,
    this.finishReason,
  });

  factory ChatCompletionChoice.fromJson(Map<String, dynamic> json) {
    return ChatCompletionChoice(
      index: json['index'] as int? ?? 0,
      message: json['message'] != null
          ? ChatMessage.fromJson(json['message'] as Map<String, dynamic>)
          : null,
      delta: json['delta'] != null
          ? ChatDelta.fromJson(json['delta'] as Map<String, dynamic>)
          : null,
      finishReason: json['finish_reason'] as String?,
    );
  }
}

/// Unary response returned by [ChatResource.completions].
class ChatCompletionResponse {
  final String id;
  final List<ChatCompletionChoice> choices;
  final ChatUsage? usage;
  final String? model;
  final Map<String, dynamic> raw;

  const ChatCompletionResponse({
    required this.id,
    required this.choices,
    this.usage,
    this.model,
    this.raw = const <String, dynamic>{},
  });

  factory ChatCompletionResponse.fromJson(Map<String, dynamic> json) {
    final rawChoices = json['choices'] as List<dynamic>? ?? const [];
    return ChatCompletionResponse(
      id: json['id'] as String? ?? '',
      choices: rawChoices
          .map((e) => ChatCompletionChoice.fromJson(e as Map<String, dynamic>))
          .toList(),
      usage: json['usage'] != null
          ? ChatUsage.fromJson(json['usage'] as Map<String, dynamic>)
          : null,
      model: json['model'] as String?,
      raw: json,
    );
  }
}

/// Unary response returned by [ChatResource.completionsV2].
class ChatCompletionV2Response extends ChatCompletionResponse {
  const ChatCompletionV2Response({
    required super.id,
    required super.choices,
    super.usage,
    super.model,
    super.raw,
  });

  factory ChatCompletionV2Response.fromJson(Map<String, dynamic> json) {
    final base = ChatCompletionResponse.fromJson(json);
    return ChatCompletionV2Response(
      id: base.id,
      choices: base.choices,
      usage: base.usage,
      model: base.model,
      raw: json,
    );
  }
}

/// Streaming chunk emitted by [ChatResource.completionsStream] and [ChatResource.completionsV2Stream].
class ChatCompletionChunk {
  final String id;
  final List<ChatCompletionChoice> choices;
  final ChatUsage? usage;
  final String? model;
  final Map<String, dynamic> raw;

  const ChatCompletionChunk({
    required this.id,
    this.choices = const <ChatCompletionChoice>[],
    this.usage,
    this.model,
    this.raw = const <String, dynamic>{},
  });

  /// Convenience getter returning the delta content of the first choice,
  /// safely returning `null` if [choices] is empty (such as on terminal usage chunks).
  String? get firstDeltaContent {
    if (choices.isEmpty) return null;
    return choices.first.delta?.content;
  }

  factory ChatCompletionChunk.fromJson(Map<String, dynamic> json) {
    final rawChoices = json['choices'] as List<dynamic>? ?? const [];
    return ChatCompletionChunk(
      id: json['id'] as String? ?? '',
      choices: rawChoices
          .map((e) => ChatCompletionChoice.fromJson(e as Map<String, dynamic>))
          .toList(),
      usage: json['usage'] != null
          ? ChatUsage.fromJson(json['usage'] as Map<String, dynamic>)
          : null,
      model: json['model'] as String?,
      raw: json,
    );
  }
}

/// Request parameters for [ChatResource.completions].
class ChatCompletionRequest {
  final String model;
  final List<ChatMessage> messages;
  final bool? stream;
  final double? temperature;
  final int? maxTokens;

  const ChatCompletionRequest({
    required this.model,
    required this.messages,
    this.stream,
    this.temperature,
    this.maxTokens,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'model': model,
      'messages': messages.map((m) => m.toJson()).toList(),
    };
    if (stream != null) map['stream'] = stream;
    if (temperature != null) map['temperature'] = temperature;
    if (maxTokens != null) map['max_tokens'] = maxTokens;
    return map;
  }
}

/// Request parameters for [ChatResource.completionsV2].
class ChatCompletionV2Request {
  final String model;
  final List<ChatMessage> messages;
  final bool? stream;
  final double? temperature;
  final int? maxTokens;

  const ChatCompletionV2Request({
    required this.model,
    required this.messages,
    this.stream,
    this.temperature,
    this.maxTokens,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'model': model,
      'messages': messages.map((m) => m.toJson()).toList(),
    };
    if (stream != null) map['stream'] = stream;
    if (temperature != null) map['temperature'] = temperature;
    if (maxTokens != null) map['max_tokens'] = maxTokens;
    return map;
  }
}

/// Representation of an AI model returned by [ChatResource.listModels] and [ChatResource.getModel].
class ModelResponse {
  final String id;
  final Map<String, dynamic> raw;

  const ModelResponse({
    required this.id,
    this.raw = const <String, dynamic>{},
  });

  factory ModelResponse.fromJson(Map<String, dynamic> json) {
    return ModelResponse(
      id: json['id'] as String? ?? '',
      raw: json,
    );
  }
}

/// List of models returned by [ChatResource.listModels].
class ModelListResponse {
  final List<ModelResponse> models;
  final Map<String, dynamic> raw;

  const ModelListResponse({
    required this.models,
    this.raw = const <String, dynamic>{},
  });

  factory ModelListResponse.fromJson(Map<String, dynamic> json) {
    final rawModels = json['models'] as List<dynamic>? ?? const [];
    return ModelListResponse(
      models: rawModels
          .map((e) => ModelResponse.fromJson(e as Map<String, dynamic>))
          .toList(),
      raw: json,
    );
  }
}
