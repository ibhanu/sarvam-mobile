import {
  WebSocketFactory,
  WebSocketConnection,
  WebSocketOptions,
  DefaultWebSocketFactory,
} from '@sarvam/core';

/**
 * Detects whether the current environment is React Native native (iOS/Android)
 * versus React Native Web / standard browser.
 */
function isReactNativeNative(): boolean {
  if (typeof navigator !== 'undefined' && navigator.product === 'ReactNative') {
    return true;
  }
  // Check global Hermes or global react-native markers
  if (typeof (globalThis as any).HermesInternal !== 'undefined') {
    return true;
  }
  return false;
}

/**
 * React Native WebSocket factory.
 * On native iOS/Android, leverages React Native's 3-argument WebSocket constructor:
 * `new WebSocket(url, protocols, { headers })`.
 * On React Native Web / browsers, falls back cleanly to subprotocol authentication
 * `api-subscription-key.<key>` or `bearer.<token>`.
 */
export class ReactNativeWebSocketFactory implements WebSocketFactory {
  private readonly fallbackFactory: DefaultWebSocketFactory;

  constructor() {
    this.fallbackFactory = new DefaultWebSocketFactory();
  }

  async connect(url: string, options?: WebSocketOptions): Promise<WebSocketConnection> {
    const isNative = isReactNativeNative();

    if (!isNative) {
      // RN Web / Browser fallback: Ensure subprotocol is set if API key is in headers
      const protocols = options?.protocols
        ? Array.isArray(options.protocols)
          ? [...options.protocols]
          : [options.protocols]
        : [];

      if (options?.headers) {
        const apiKey =
          options.headers['api-subscription-key'] ||
          options.headers['Api-Subscription-Key'];
        if (apiKey && !protocols.some((p) => p.startsWith('api-subscription-key.'))) {
          protocols.push(`api-subscription-key.${apiKey}`);
        }

        const auth = options.headers['Authorization'] || options.headers['authorization'];
        if (auth && auth.startsWith('Bearer ') && !protocols.some((p) => p.startsWith('bearer.'))) {
          protocols.push(`bearer.${auth.slice('Bearer '.length)}`);
        }
      }

      // Connect without 3rd-argument headers (which break in browser WebSockets)
      return this.fallbackFactory.connect(url, {
        protocols,
      });
    }

    // Native React Native: pass custom headers directly to 3-argument constructor
    return this.fallbackFactory.connect(url, options);
  }
}
