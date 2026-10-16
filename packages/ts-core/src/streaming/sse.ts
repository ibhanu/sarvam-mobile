import { StreamError } from '../errors.js';

export interface SseEvent {
  event?: string;
  data: string;
  id?: string;
  retry?: number;
}

export interface ParseSseOptions {
  isResponsesApi?: boolean;
  signal?: AbortSignal;
}

const RESPONSES_API_TERMINAL_EVENTS = new Set([
  'response.completed',
  'response.failed',
  'response.incomplete',
]);

/**
 * Parses raw SSE binary chunks into an async stream of SseEvents.
 * Safe across arbitrary chunk boundaries.
 */
export async function* parseSseStream(
  stream: AsyncIterable<Uint8Array>,
  options?: ParseSseOptions
): AsyncIterable<SseEvent> {
  const isResponsesApi = options?.isResponsesApi ?? false;
  const signal = options?.signal;

  const decoder = new TextDecoder('utf-8');
  let buffer = '';

  for await (const chunk of stream) {
    if (signal?.aborted) {
      throw signal.reason ?? new Error('Stream aborted');
    }

    buffer += decoder.decode(chunk, { stream: true });

    // Normalize \r\n to \n
    let eventBoundaryIdx: number;
    while ((eventBoundaryIdx = buffer.indexOf('\n\n')) !== -1) {
      const rawEventBlock = buffer.slice(0, eventBoundaryIdx);
      buffer = buffer.slice(eventBoundaryIdx + 2);

      const parsed = parseEventBlock(rawEventBlock);
      if (!parsed) {
        continue;
      }

      // Chat completions termination sentinel
      if (!isResponsesApi && parsed.data.trim() === '[DONE]') {
        return;
      }

      yield parsed;

      // Responses API termination check
      if (isResponsesApi) {
        if (parsed.event && RESPONSES_API_TERMINAL_EVENTS.has(parsed.event)) {
          return;
        }
        // Also check JSON data.type if event header wasn't set
        if (parsed.data.startsWith('{')) {
          try {
            const json = JSON.parse(parsed.data) as Record<string, unknown>;
            if (typeof json['type'] === 'string' && RESPONSES_API_TERMINAL_EVENTS.has(json['type'])) {
              return;
            }
          } catch {
            // Ignore JSON parse errors for non-JSON SSE data
          }
        }
      }
    }
  }

  // Flush remaining buffer
  buffer += decoder.decode();
  if (buffer.trim()) {
    const parsed = parseEventBlock(buffer);
    if (parsed) {
      if (!isResponsesApi && parsed.data.trim() === '[DONE]') {
        return;
      }
      yield parsed;
    }
  }
}

function parseEventBlock(block: string): SseEvent | null {
  const lines = block.split(/\r?\n/);
  let event: string | undefined;
  let id: string | undefined;
  let retry: number | undefined;
  const dataLines: string[] = [];

  for (const line of lines) {
    if (!line || line.startsWith(':')) {
      // Comment or empty line
      continue;
    }

    const colonIdx = line.indexOf(':');
    let field = line;
    let value = '';
    if (colonIdx !== -1) {
      field = line.slice(0, colonIdx);
      value = line.slice(colonIdx + 1);
      if (value.startsWith(' ')) {
        value = value.slice(1);
      }
    }

    switch (field) {
      case 'event':
        event = value;
        break;
      case 'id':
        id = value;
        break;
      case 'retry': {
        const parsedRetry = parseInt(value, 10);
        if (!isNaN(parsedRetry)) {
          retry = parsedRetry;
        }
        break;
      }
      case 'data':
        dataLines.push(value);
        break;
    }
  }

  if (dataLines.length === 0 && !event && !id) {
    return null;
  }

  return {
    event,
    id,
    retry,
    data: dataLines.join('\n'),
  };
}
