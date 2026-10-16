import { ChatModel } from '../generated/sarvamSpecGenerated.js';
import { RequestOptions, ClientDispatcher } from './types.js';
import { HttpRequest, HttpResponse } from '../transport/http.js';
import { createHttpError } from '../errors.js';
import { parseSseStream } from '../streaming/sse.js';

export interface ChatMessage {
  role: 'system' | 'user' | 'assistant' | (string & {});
  content: string;
}

export interface ChatCompletionRequest {
  model: ChatModel | string;
  messages: ChatMessage[];
  temperature?: number;
  top_p?: number;
  max_tokens?: number;
  stop?: string | string[];
  stream?: boolean;
}

export interface ChatCompletionChoice {
  index: number;
  message?: ChatMessage;
  finish_reason?: string | null;
}

export interface ChatCompletionResponse {
  id: string;
  object?: string;
  created?: number;
  model?: string;
  choices: ChatCompletionChoice[];
  usage?: {
    prompt_tokens: number;
    completion_tokens: number;
    total_tokens: number;
  };
}

export interface ChatDelta {
  role?: string;
  content?: string;
}

export interface ChatCompletionChunkChoice {
  index: number;
  delta?: ChatDelta;
  finish_reason?: string | null;
}

export class ChatCompletionChunk {
  readonly id: string;
  readonly choices: ChatCompletionChunkChoice[];
  readonly usage?: {
    prompt_tokens: number;
    completion_tokens: number;
    total_tokens: number;
  };
  readonly model?: string;
  readonly created?: number;

  constructor(data: Record<string, unknown>) {
    this.id = (data['id'] as string) ?? '';
    this.choices = Array.isArray(data['choices'])
      ? (data['choices'] as ChatCompletionChunkChoice[])
      : [];
    this.usage = data['usage'] as any;
    this.model = data['model'] as string | undefined;
    this.created = data['created'] as number | undefined;
  }

  /**
   * Safely extracts the delta content of the first choice,
   * returning null if choices array is empty (e.g. On final usage chunk).
   */
  get firstDeltaContent(): string | null {
    if (!this.choices || this.choices.length === 0) {
      return null;
    }
    return this.choices[0]?.delta?.content ?? null;
  }
}

export interface ChatCompletionV2Request extends ChatCompletionRequest {
  session_affinity?: string;
}

export interface ChatModelInfo {
  id: string;
  created?: number;
  owned_by?: string;
}

export interface ChatModelsResponse {
  models: ChatModelInfo[];
}

export class ChatSession {
  private readonly chatResource: ChatResource;
  private sessionAffinity?: string;

  constructor(chatResource: ChatResource, initialAffinity?: string) {
    this.chatResource = chatResource;
    this.sessionAffinity = initialAffinity;
  }

  getSessionAffinity(): string | undefined {
    return this.sessionAffinity;
  }

  async completions(
    request: ChatCompletionV2Request,
    options?: RequestOptions
  ): Promise<ChatCompletionResponse> {
    const headers: Record<string, string> = { ...options?.headers };
    if (this.sessionAffinity && !headers['x-session-affinity']) {
      headers['x-session-affinity'] = this.sessionAffinity;
    }

    const res = await this.chatResource.completionsV2(request, {
      ...options,
      headers,
    });

    return res;
  }

  async completionsStream(
    request: ChatCompletionV2Request,
    options?: RequestOptions
  ): Promise<AsyncIterable<ChatCompletionChunk>> {
    const headers: Record<string, string> = { ...options?.headers };
    if (this.sessionAffinity && !headers['x-session-affinity']) {
      headers['x-session-affinity'] = this.sessionAffinity;
    }

    return this.chatResource.completionsV2Stream(request, {
      ...options,
      headers,
    });
  }
}

export class ChatResource {
  private readonly dispatcher: ClientDispatcher;

  constructor(dispatcher: ClientDispatcher) {
    this.dispatcher = dispatcher;
  }

  createSession(options?: { initialAffinity?: string }): ChatSession {
    return new ChatSession(this, options?.initialAffinity);
  }

  async completions(
    request: ChatCompletionRequest,
    options?: RequestOptions
  ): Promise<ChatCompletionResponse> {
    const url = `${this.dispatcher.getApiBaseUrl()}/v1/chat/completions`;
    const headers: Record<string, string> = {
      'content-type': 'application/json',
      ...options?.headers,
    };
    if (options?.idempotencyKey) {
      headers['idempotency-key'] = options.idempotencyKey;
    }

    const httpReq: HttpRequest = {
      method: 'POST',
      url,
      headers,
      body: JSON.stringify({ ...request, stream: false }),
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      operationKind: 'STATELESS_POST',
    };

    const res = await this.dispatcher.execute(httpReq);
    if (res.status >= 400) {
      const text = await res.text();
      throw await createHttpError(res.status, text, (n) => res.headers.get(n));
    }

    return (await res.json()) as ChatCompletionResponse;
  }

  async completionsStream(
    request: ChatCompletionRequest,
    options?: RequestOptions
  ): Promise<AsyncIterable<ChatCompletionChunk>> {
    const url = `${this.dispatcher.getApiBaseUrl()}/v1/chat/completions`;
    const headers: Record<string, string> = {
      'content-type': 'application/json',
      Accept: 'text/event-stream',
      ...options?.headers,
    };
    if (options?.idempotencyKey) {
      headers['idempotency-key'] = options.idempotencyKey;
    }

    const httpReq: HttpRequest = {
      method: 'POST',
      url,
      headers,
      body: JSON.stringify({ ...request, stream: true }),
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      operationKind: 'STATELESS_POST',
    };

    const res = await this.dispatcher.execute(httpReq);
    if (res.status >= 400) {
      const text = await res.text();
      throw await createHttpError(res.status, text, (n) => res.headers.get(n));
    }

    const stream = res.bodyStream();
    if (!stream) {
      throw new Error('Response stream not available');
    }

    return {
      async *[Symbol.asyncIterator]() {
        for await (const sseEvent of parseSseStream(stream, { signal: options?.signal })) {
          if (!sseEvent.data || sseEvent.data.trim() === '[DONE]') {
            return;
          }
          try {
            const json = JSON.parse(sseEvent.data) as Record<string, unknown>;
            yield new ChatCompletionChunk(json);
          } catch {
            // Ignore non-json lines
          }
        }
      },
    };
  }

  async completionsV2(
    request: ChatCompletionV2Request,
    options?: RequestOptions
  ): Promise<ChatCompletionResponse> {
    const url = `${this.dispatcher.getApiBaseUrl()}/v2/chat/completions`;
    const headers: Record<string, string> = {
      'content-type': 'application/json',
      ...options?.headers,
    };
    if (request.session_affinity) {
      headers['x-session-affinity'] = request.session_affinity;
    }
    if (options?.idempotencyKey) {
      headers['idempotency-key'] = options.idempotencyKey;
    }

    const httpReq: HttpRequest = {
      method: 'POST',
      url,
      headers,
      body: JSON.stringify({ ...request, stream: false }),
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      operationKind: 'STATELESS_POST',
    };

    const res = await this.dispatcher.execute(httpReq);
    if (res.status >= 400) {
      const text = await res.text();
      throw await createHttpError(res.status, text, (n) => res.headers.get(n));
    }

    return (await res.json()) as ChatCompletionResponse;
  }

  async completionsV2Stream(
    request: ChatCompletionV2Request,
    options?: RequestOptions
  ): Promise<AsyncIterable<ChatCompletionChunk>> {
    const url = `${this.dispatcher.getApiBaseUrl()}/v2/chat/completions`;
    const headers: Record<string, string> = {
      'content-type': 'application/json',
      Accept: 'text/event-stream',
      ...options?.headers,
    };
    if (request.session_affinity) {
      headers['x-session-affinity'] = request.session_affinity;
    }
    if (options?.idempotencyKey) {
      headers['idempotency-key'] = options.idempotencyKey;
    }

    const httpReq: HttpRequest = {
      method: 'POST',
      url,
      headers,
      body: JSON.stringify({ ...request, stream: true }),
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      operationKind: 'STATELESS_POST',
    };

    const res = await this.dispatcher.execute(httpReq);
    if (res.status >= 400) {
      const text = await res.text();
      throw await createHttpError(res.status, text, (n) => res.headers.get(n));
    }

    const stream = res.bodyStream();
    if (!stream) {
      throw new Error('Response stream not available');
    }

    return {
      async *[Symbol.asyncIterator]() {
        for await (const sseEvent of parseSseStream(stream, { signal: options?.signal })) {
          if (!sseEvent.data || sseEvent.data.trim() === '[DONE]') {
            return;
          }
          try {
            const json = JSON.parse(sseEvent.data) as Record<string, unknown>;
            yield new ChatCompletionChunk(json);
          } catch {
            // Ignore non-json lines
          }
        }
      },
    };
  }

  async listModels(options?: RequestOptions): Promise<ChatModelsResponse> {
    const url = `${this.dispatcher.getApiBaseUrl()}/v2/models`;
    const headers: Record<string, string> = { ...options?.headers };

    const httpReq: HttpRequest = {
      method: 'GET',
      url,
      headers,
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      operationKind: 'IDEMPOTENT',
    };

    const res = await this.dispatcher.execute(httpReq);
    if (res.status >= 400) {
      const text = await res.text();
      throw await createHttpError(res.status, text, (n) => res.headers.get(n));
    }

    return (await res.json()) as ChatModelsResponse;
  }

  async getModel(modelId: string, options?: RequestOptions): Promise<ChatModelInfo> {
    const url = `${this.dispatcher.getApiBaseUrl()}/v2/models/${encodeURIComponent(modelId)}`;
    const headers: Record<string, string> = { ...options?.headers };

    const httpReq: HttpRequest = {
      method: 'GET',
      url,
      headers,
      signal: options?.signal,
      timeoutMs: options?.timeoutMs,
      operationKind: 'IDEMPOTENT',
    };

    const res = await this.dispatcher.execute(httpReq);
    if (res.status >= 400) {
      const text = await res.text();
      throw await createHttpError(res.status, text, (n) => res.headers.get(n));
    }

    return (await res.json()) as ChatModelInfo;
  }
}
