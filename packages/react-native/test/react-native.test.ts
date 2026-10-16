import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createMockServer } from '../../../conformance/mock-server/dist/src/server.js';
type MockServerInstance = ReturnType<typeof createMockServer>;
import WebSocket from 'ws';
import {
  SarvamReactNativeClient,
  ReactNativeWebSocketFactory,
  ReactNativeFormDataAdapter,
  fromReactNativeUri,
  REACT_NATIVE_SDK_VERSION,
  DEFAULT_API_BASE_URL,
  DefaultWebSocketFactory,
} from '../dist/esm/index.js';

describe('@sarvam/react-native SDK Tests', () => {
  let server: MockServerInstance;

  before(async () => {
    server = createMockServer({ port: 0 });
    await server.start();
  });

  after(async () => {
    await server.stop();
  });

  describe('1. SDK Identity & Exports', () => {
    test('exports REACT_NATIVE_SDK_VERSION and @sarvam/core constants', () => {
      assert.equal(REACT_NATIVE_SDK_VERSION, '0.1.0');
      assert.equal(DEFAULT_API_BASE_URL, 'https://api.sarvam.ai');
    });

    test('SarvamReactNativeClient configures default User-Agent with sarvam-react-native prefix', async () => {
      const client = new SarvamReactNativeClient({
        apiKey: 'test-api-key',
        baseUrl: server.url,
      });

      await client.text.translate({
        input: 'Hello world',
        source_language_code: 'en-IN',
        target_language_code: 'hi-IN',
      });

      const recorded = server.getRecordedRequests('/translate');
      assert.ok(recorded.length > 0);
      const last = recorded[recorded.length - 1];
      const ua = last?.headers['user-agent'] as string;
      assert.ok(
        ua.startsWith('sarvam-react-native/0.1.0'),
        `User-Agent should start with sarvam-react-native/0.1.0, got: ${ua}`
      );
    });
  });

  describe('2. fromReactNativeUri Helper', () => {
    test('extracts file name and infers wav MIME type', () => {
      const fileInput = fromReactNativeUri('file:///data/user/0/com.app/cache/recording.wav');
      assert.deepEqual(fileInput, {
        uri: 'file:///data/user/0/com.app/cache/recording.wav',
        name: 'recording.wav',
        type: 'audio/wav',
      });
    });

    test('extracts file name and infers mp3 MIME type', () => {
      const fileInput = fromReactNativeUri('content://media/external/audio/speech.mp3');
      assert.deepEqual(fileInput, {
        uri: 'content://media/external/audio/speech.mp3',
        name: 'speech.mp3',
        type: 'audio/mpeg',
      });
    });

    test('uses custom filename and custom MIME type when supplied', () => {
      const fileInput = fromReactNativeUri(
        'file:///tmp/raw_audio',
        'custom_voice.raw',
        'audio/pcm'
      );
      assert.deepEqual(fileInput, {
        uri: 'file:///tmp/raw_audio',
        name: 'custom_voice.raw',
        type: 'audio/pcm',
      });
    });

    test('infers aac, ogg, opus, and octet-stream MIME types, strips query strings', () => {
      assert.equal(fromReactNativeUri('file:///audio.m4a').type, 'audio/aac');
      assert.equal(fromReactNativeUri('file:///audio.aac').type, 'audio/aac');
      assert.equal(fromReactNativeUri('file:///audio.ogg').type, 'audio/ogg');
      assert.equal(fromReactNativeUri('file:///audio.opus').type, 'audio/ogg');
      assert.equal(fromReactNativeUri('file:///audio.xyz').type, 'application/octet-stream');
      const withQuery = fromReactNativeUri('file:///recording.wav?token=123');
      assert.equal(withQuery.name, 'recording.wav');
    });
  });

  describe('3. ReactNativeFormDataAdapter', () => {
    test('appends native { uri, name, type } file object directly without Blob/Buffer conversion', () => {
      const formData = new FormData();
      const nativeFile = fromReactNativeUri('file:///cache/input.wav', 'input.wav', 'audio/wav');

      ReactNativeFormDataAdapter.appendFile(formData, 'file', nativeFile);
      assert.ok(formData.has('file'));
    });

    test('falls back to Blob when native append throws', () => {
      let appendedFallback = false;
      const throwingFormData: any = {
        append: (name: string, value: any, filename?: string) => {
          if (value && typeof value === 'object' && 'uri' in value) {
            throw new TypeError('Expected Blob on WebIDL platform');
          }
          if (value instanceof Blob) {
            appendedFallback = true;
          }
        },
      };

      const nativeFile = { uri: 'file:///input.wav', name: 'input.wav', type: 'audio/wav' };
      ReactNativeFormDataAdapter.appendFile(throwingFormData, 'file', nativeFile);
      assert.ok(appendedFallback);
    });

    test('appends Uint8Array, Blob, and generic values correctly', () => {
      const formData = new FormData();
      const bytes = new Uint8Array([1, 2, 3, 4]);
      ReactNativeFormDataAdapter.appendFile(formData, 'audio', bytes, 'sample.wav');
      assert.ok(formData.has('audio'));

      const blob = new Blob([new Uint8Array([5, 6])], { type: 'audio/wav' });
      ReactNativeFormDataAdapter.appendFile(formData, 'blob_file', blob, 'blob.wav');
      assert.ok(formData.has('blob_file'));

      // Generic non-Blob value with mock FormData
      const mockFormData: any = {
        appended: [] as any[],
        append(name: string, value: any, filename?: string) {
          this.appended.push({ name, value, filename });
        },
      };
      ReactNativeFormDataAdapter.appendFile(mockFormData, 'raw_string', 'hello' as any, 'text.txt');
      assert.equal(mockFormData.appended.length, 1);
      assert.equal(mockFormData.appended[0].value, 'hello');

      // Test fallback when global Blob is undefined
      const origBlob = (globalThis as any).Blob;
      try {
        Object.defineProperty(globalThis, 'Blob', { value: undefined, configurable: true, writable: true });
        const noBlobFormData: any = {
          appended: [] as any[],
          append(name: string, value: any, filename?: string) {
            this.appended.push({ name, value, filename });
          },
        };
        ReactNativeFormDataAdapter.appendFile(noBlobFormData, 'audio_raw', bytes, 'raw.pcm');
        assert.equal(noBlobFormData.appended.length, 1);
      } finally {
        Object.defineProperty(globalThis, 'Blob', { value: origBlob, configurable: true, writable: true });
      }
    });
  });

  describe('4. ReactNativeWebSocketFactory', () => {
    test('injects subprotocol fallback when running on React Native Web / Browser', async () => {
      const factory = new ReactNativeWebSocketFactory();
      const wsUrl = `${server.wsUrl}/speech-to-text-realtime/ws`;
      (globalThis as any).WebSocket = WebSocket;

      // 1. Api-Subscription-Key header without pre-existing subprotocol (pushes subprotocol)
      const connection1 = await factory.connect(wsUrl, {
        headers: {
          'Api-Subscription-Key': 'test-api-key',
        },
        protocols: 'custom-proto',
      });
      assert.ok(connection1);
      connection1.close();

      // 2. Api-Subscription-Key with existing subprotocol (triggers predicate callback without pushing)
      const connection1b = await factory.connect(wsUrl, {
        headers: {
          'api-subscription-key': 'test-api-key',
        },
        protocols: ['api-subscription-key.already-here'],
      });
      assert.ok(connection1b);
      connection1b.close();

      // 3. Authorization Bearer header without pre-existing subprotocol (pushes bearer.<token>)
      const connection2 = await factory.connect(wsUrl, {
        headers: {
          'Authorization': 'Bearer test-bearer-token',
        },
      });
      assert.ok(connection2);
      connection2.close();

      // 4. Authorization Bearer header with existing subprotocol
      const connection2b = await factory.connect(wsUrl, {
        headers: {
          'authorization': 'Bearer test-bearer-token',
        },
        protocols: ['bearer.already-present'],
      });
      assert.ok(connection2b);
      connection2b.close();
    });

    test('supports native React Native environment detection via HermesInternal and navigator', async () => {
      const factory = new ReactNativeWebSocketFactory();
      const wsUrl = `${server.wsUrl}/speech-to-text-realtime/ws`;
      (globalThis as any).WebSocket = WebSocket;

      // HermesInternal test
      (globalThis as any).HermesInternal = {};
      const connHermes = await factory.connect(wsUrl, {
        headers: { 'api-subscription-key': 'test-key' },
      });
      assert.ok(connHermes);
      connHermes.close();
      delete (globalThis as any).HermesInternal;

      // navigator.product === 'ReactNative' test
      const origDescriptor = Object.getOwnPropertyDescriptor(globalThis, 'navigator');
      try {
        Object.defineProperty(globalThis, 'navigator', {
          value: { product: 'ReactNative' },
          configurable: true,
          writable: true,
        });
        const connNav = await factory.connect(wsUrl, {
          headers: { 'api-subscription-key': 'test-key' },
        });
        assert.ok(connNav);
        connNav.close();
      } finally {
        if (origDescriptor) {
          Object.defineProperty(globalThis, 'navigator', origDescriptor);
        }
      }
    });
  });

  describe('5. End-to-End Client with Mock Server', () => {
    test('SarvamReactNativeClient executes translation and TTS convert successfully', async () => {
      const client = new SarvamReactNativeClient({
        apiKey: 'test-api-key',
        baseUrl: server.url,
        wsFactory: new DefaultWebSocketFactory(WebSocket),
      });

      // 1. Text translation
      const trans = await client.text.translate({
        input: 'Hello world',
        source_language_code: 'en-IN',
        target_language_code: 'hi-IN',
      });
      assert.equal(trans.translatedText, 'नमस्ते दुनिया');

      // 2. TTS convert
      const tts = await client.textToSpeech.convert(
        {
          text: 'नमस्ते दुनिया',
          target_language_code: 'hi-IN',
          speaker: 'meera',
        },
        {
          headers: {
            'x-mock-scenario': 'tts-rest-base64',
          },
        }
      );
      assert.equal(tts.audioBytes.length, 44);

      // 3. Azure SAS Blob Upload
      await client.jobs.uploadToSignedUrl(
        `${server.url}/mock-sas-upload?scenario=sas-blob-upload`,
        new Uint8Array([1, 2, 3, 4])
      );
    });
  });
});
