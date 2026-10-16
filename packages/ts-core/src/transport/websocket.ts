import { RealtimeError } from '../errors.js';

export interface WebSocketOptions {
  headers?: Record<string, string>;
  protocols?: string | string[];
}

export type WebSocketEventListener = (...args: any[]) => void;

export interface WebSocketConnection {
  send(data: string | Uint8Array): void;
  close(code?: number, reason?: string): void;
  on(event: 'open', listener: () => void): void;
  on(event: 'message', listener: (data: string | Uint8Array) => void): void;
  on(event: 'error', listener: (err: any) => void): void;
  on(event: 'close', listener: (code: number, reason: string) => void): void;
  off?(event: string, listener: WebSocketEventListener): void;
}

export interface WebSocketFactory {
  connect(url: string, options?: WebSocketOptions): Promise<WebSocketConnection>;
}

class StandardWebSocketConnection implements WebSocketConnection {
  private readonly ws: any;
  private readonly listeners: Map<string, Set<WebSocketEventListener>> = new Map();

  constructor(ws: any) {
    this.ws = ws;

    this.ws.onopen = () => {
      this.emit('open');
    };

    this.ws.onmessage = (event: any) => {
      const data = event.data !== undefined ? event.data : event;
      if (typeof data === 'string') {
        this.emit('message', data);
      } else if (data instanceof Uint8Array) {
        this.emit('message', data);
      } else if (data instanceof ArrayBuffer) {
        this.emit('message', new Uint8Array(data));
      } else if (data && typeof data.arrayBuffer === 'function') {
        // Blob
        data.arrayBuffer().then((ab: ArrayBuffer) => {
          this.emit('message', new Uint8Array(ab));
        });
      } else if (data && data.buffer instanceof ArrayBuffer) {
        // TypedArray or array-buffer-like view
        this.emit('message', new Uint8Array(data.buffer, data.byteOffset ?? 0, data.byteLength ?? data.length));
      } else {
        this.emit('message', String(data));
      }
    };

    this.ws.onerror = (err: any) => {
      this.emit('error', err);
    };

    this.ws.onclose = (event: any) => {
      const code = event?.code ?? 1000;
      const reason = event?.reason ?? '';
      this.emit('close', code, reason);
    };
  }

  send(data: string | Uint8Array): void {
    this.ws.send(data);
  }

  close(code?: number, reason?: string): void {
    this.ws.close(code, reason);
  }

  on(event: 'open', listener: () => void): void;
  on(event: 'message', listener: (data: string | Uint8Array) => void): void;
  on(event: 'error', listener: (err: any) => void): void;
  on(event: 'close', listener: (code: number, reason: string) => void): void;
  on(event: string, listener: WebSocketEventListener): void {
    let set = this.listeners.get(event);
    if (!set) {
      set = new Set();
      this.listeners.set(event, set);
    }
    set.add(listener);
  }

  off(event: string, listener: WebSocketEventListener): void {
    this.listeners.get(event)?.delete(listener);
  }

  private emit(event: string, ...args: any[]): void {
    const set = this.listeners.get(event);
    if (set) {
      for (const listener of Array.from(set)) {
        try {
          listener(...args);
        } catch (e) {
          console.error(`Error in WebSocket ${event} listener:`, e);
        }
      }
    }
  }
}

/**
 * Default cross-platform WebSocketFactory.
 * Compatible with browsers, React Native, and Node environments.
 */
export class DefaultWebSocketFactory implements WebSocketFactory {
  private readonly customWsImpl?: any;

  constructor(customWsImpl?: any) {
    this.customWsImpl = customWsImpl;
  }

  async connect(url: string, options?: WebSocketOptions): Promise<WebSocketConnection> {
    const WS = this.customWsImpl ?? (globalThis as any).WebSocket;
    if (!WS) {
      throw new Error('WebSocket implementation not found in global scope. Provide a custom WebSocketFactory.');
    }

    const protocols = options?.protocols
      ? Array.isArray(options.protocols)
        ? options.protocols
        : [options.protocols]
      : [];

    return new Promise<WebSocketConnection>((resolve, reject) => {
      let ws: any;
      try {
        if (options?.headers && Object.keys(options.headers).length > 0) {
          try {
            // React Native 3-argument signature: new WebSocket(url, protocols, { headers })
            // ws package signature: new WebSocket(url, protocols, { headers })
            ws = new WS(url, protocols.length > 0 ? protocols : undefined, {
              headers: options.headers,
            });
          } catch {
            ws = new WS(url, protocols.length > 0 ? protocols : undefined);
          }
        } else {
          ws = new WS(url, protocols.length > 0 ? protocols : undefined);
        }
      } catch (err) {
        return reject(err);
      }

      const connection = new StandardWebSocketConnection(ws);

      let opened = false;
      const onOpen = () => {
        opened = true;
        resolve(connection);
      };

      const onError = (err: any) => {
        if (!opened) {
          reject(new RealtimeError('WebSocket connection failed during handshake', { cause: err }));
        }
      };

      const onClose = (code: number, reason: string) => {
        if (!opened) {
          reject(
            new RealtimeError(`WebSocket closed before opening with code ${code}: ${reason}`, {
              closeCode: code,
            })
          );
        }
      };

      connection.on('open', onOpen);
      connection.on('error', onError);
      connection.on('close', onClose);
    });
  }
}
