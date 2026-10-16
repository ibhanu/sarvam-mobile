import { SarvamClient, SarvamClientConfig } from '@sarvam/core';
import { ReactNativeFetchTransport } from './adapters/fetch-transport.js';
import { ReactNativeWebSocketFactory } from './adapters/websocket.js';

export interface SarvamReactNativeClientConfig extends SarvamClientConfig {
  // Additional React Native specific options can be added here
}

export class SarvamReactNativeClient extends SarvamClient {
  constructor(config: SarvamReactNativeClientConfig) {
    super({
      ...config,
      httpTransport:
        config.httpTransport ??
        new ReactNativeFetchTransport({ defaultTimeoutMs: config.timeoutMs }),
      wsFactory: config.wsFactory ?? new ReactNativeWebSocketFactory(),
      userAgentPrefix: config.userAgentPrefix ?? 'sarvam-react-native/0.1.0',
    });
  }
}
