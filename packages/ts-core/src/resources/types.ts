import { HttpRequest, HttpResponse } from '../transport/http.js';
import { AuthProvider } from '../auth.js';
import { WebSocketFactory } from '../transport/websocket.js';
import { Clock } from '../utils/timing.js';

export interface RequestOptions {
  signal?: AbortSignal;
  headers?: Record<string, string>;
  timeoutMs?: number;
  idempotencyKey?: string;
}

export interface ClientDispatcher {
  execute(request: HttpRequest): Promise<HttpResponse>;
  getApiBaseUrl(): string;
  getDubbingBaseUrl(): string;
  getWsBaseUrl?(): string;
  getAuthProvider?(): AuthProvider;
  getWebSocketFactory?(): WebSocketFactory;
  getClock?(): Clock;
}

