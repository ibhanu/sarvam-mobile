import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:sarvam/sarvam.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('Conformance Test Suite (19 Scenarios from all-cases.json)', () {
    // 1. rest-auth-error-quirk
    test(
        '1. rest-auth-error-quirk: HTTP 403 with invalid_api_key_error maps to AuthenticationException',
        () async {
      final transport = MockHttpTransport((req) async {
        expect(req.url.path, '/translate');
        expect(req.headers['api-subscription-key'], 'invalid-key');
        return jsonResponse(
          statusCode: 403,
          data: <String, dynamic>{
            'error': <String, dynamic>{
              'code': 'invalid_api_key_error',
              'message': 'Invalid API key',
              'request_id': 'req_auth_403',
            },
          },
        );
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('invalid-key'),
        transport: transport,
      );

      try {
        await client.text.translate(
          const TranslateRequest(
            input: 'Hello world',
            sourceLanguageCode: LanguageCode.enIn,
            targetLanguageCode: LanguageCode.hiIn,
          ),
          options: const RequestOptions(
            headers: <String, String>{
              'x-mock-scenario': 'auth-invalid-api-key'
            },
          ),
        );
        fail('Expected AuthenticationException');
      } on AuthenticationException catch (e) {
        expect(e.statusCode, 403);
        expect(e.code, 'invalid_api_key_error');
        expect(e.requestId, 'req_auth_403');
        expect(e.message, 'Invalid API key');
      }
    });

    // 2. rest-idempotent-retry-500
    test(
        '2. rest-idempotent-retry-500: IDEMPOTENT GET Operation Retries on HTTP 500',
        () async {
      var attempt = 0;
      final clock = MockClock();
      final transport = MockHttpTransport((req) async {
        attempt++;
        if (attempt == 1) {
          expect(req.url.path, '/v2/models');
          expect(req.method, 'GET');
          return jsonResponse(
            statusCode: 500,
            data: <String, dynamic>{
              'error': <String, dynamic>{
                'code': 'internal_server_error',
                'message': 'Transient inference service failure',
                'request_id': 'req_glitch_500',
              },
            },
          );
        } else {
          return jsonResponse(
            statusCode: 200,
            data: <String, dynamic>{
              'models': <Map<String, dynamic>>[
                <String, dynamic>{'id': 'sarvam-2b'},
                <String, dynamic>{'id': 'saaras:v3'},
              ],
            },
          );
        }
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('test-api-key'),
        transport: transport,
        clock: clock,
      );

      final res = await client.chat.listModels();
      expect(transport.recordedRequests.length, 2);
      expect(res.models.length, 2);
      expect(res.models[0].id, 'sarvam-2b');
      expect(res.models[1].id, 'saaras:v3');
    });

    // 3. rest-job-creation-safety-500
    test(
        '3. rest-job-creation-safety-500: Job Creation Safety on HTTP 500 throws immediately without retrying',
        () async {
      var callCount = 0;
      final clock = MockClock();
      final transport = MockHttpTransport((req) async {
        callCount++;
        return jsonResponse(
          statusCode: 500,
          data: <String, dynamic>{
            'error': <String, dynamic>{
              'code': 'internal_server_error',
              'message': 'Internal server error',
              'request_id': 'req_job_500',
            },
          },
        );
      });

      // Pipeline test simulating JOB_CREATE operation without Idempotency-Key
      final pipeline = buildPipeline(transport, <Middleware>[
        UserAgentMiddleware(),
        RetryMiddleware(clock: clock),
        AuthMiddleware(ApiKeyAuth('test-api-key')),
      ]);

      final request = HttpRequest(
        url: Uri.parse('https://api.sarvam.ai/doc-ai/v1/job/digitise'),
        method: 'POST',
        headers: <String, String>{'content-type': 'application/json'},
        bodyBytes: utf8.encode(jsonEncode(
            <String, dynamic>{'language': 'hi', 'output_format': 'md'})),
        operationKind: OperationKind.jobCreate,
      );

      try {
        await pipeline(request);
        fail('Expected ServerException');
      } on ServerException catch (e) {
        expect(e.statusCode, 500);
        expect(e.code, 'internal_server_error');
        expect(e.requestId, 'req_job_500');
        expect(e.message, 'Internal server error');
        expect(callCount, 1,
            reason:
                'JOB_CREATE on 500 must NOT be retried without idempotency key');
      }
    });

    // 4. rest-permission-denied
    test(
        '4. rest-permission-denied: HTTP 403 with non-invalid_api_key_error maps to PermissionDeniedException',
        () async {
      final transport = MockHttpTransport((req) async {
        return jsonResponse(
          statusCode: 403,
          data: <String, dynamic>{
            'error': <String, dynamic>{
              'code': 'authentication_error',
              'message': 'Tier locked',
              'request_id': 'req_perm_403',
            },
          },
        );
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('tier-locked-key'),
        transport: transport,
      );

      try {
        await client.text.translate(
          const TranslateRequest(
            input: 'Hello world',
            sourceLanguageCode: LanguageCode.enIn,
            targetLanguageCode: LanguageCode.hiIn,
          ),
        );
        fail('Expected PermissionDeniedException');
      } on PermissionDeniedException catch (e) {
        expect(e.statusCode, 403);
        expect(e.code, 'authentication_error');
        expect(e.requestId, 'req_perm_403');
        expect(e.message, 'Tier locked');
        expect(transport.recordedRequests.length, 1);
      }
    });

    // 5. rest-rate-limit-retry
    test('5. rest-rate-limit-retry: Rate Limit 429 Retry with retry-after-ms',
        () async {
      var attempt = 0;
      final clock = MockClock();
      final transport = MockHttpTransport((req) async {
        attempt++;
        if (attempt == 1) {
          return jsonResponse(
            statusCode: 429,
            headers: <String, String>{'retry-after-ms': '50'},
            data: <String, dynamic>{
              'error': <String, dynamic>{
                'code': 'rate_limit_exceeded_error',
                'message': 'Rate limit exceeded',
                'request_id': 'req_rl_1',
              },
            },
          );
        } else {
          return jsonResponse(
            statusCode: 200,
            data: <String, dynamic>{
              'translated_text': 'नमस्ते दुनिया',
            },
          );
        }
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('test-api-key'),
        transport: transport,
        clock: clock,
      );

      final res = await client.text.translate(
        const TranslateRequest(
          input: 'Hello retry',
          sourceLanguageCode: LanguageCode.enIn,
          targetLanguageCode: LanguageCode.hiIn,
        ),
      );

      expect(transport.recordedRequests.length, 2);
      expect(clock.recordedSleeps.length, 1);
      expect(clock.recordedSleeps.first.inMilliseconds, 50);
      expect(res.translatedText, 'नमस्ते दुनिया');
    });

    // 6. rest-sas-blob-upload
    test('6. rest-sas-blob-upload: Azure SAS Blob Upload Header Validation',
        () async {
      final transport = MockHttpTransport((req) async {
        expect(req.method, 'PUT');
        expect(req.url.path, '/mock-sas-upload');
        expect(req.headers['x-ms-blob-type'], 'BlockBlob');
        expect(req.headers['content-type'], 'application/octet-stream');
        return HttpResponse(
          statusCode: 201,
          headers: <String, String>{'x-ms-request-id': 'mock-azure-req-1'},
          bodyBytes: Uint8List(0),
        );
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('test-api-key'),
        transport: transport,
      );

      final fileData =
          Uint8List.fromList(utf8.encode('mock-audio-binary-data'));
      await client.jobs.uploadToSignedUrl(
        'https://blob.core.windows.net/mock-sas-upload',
        SarvamFileInput.fromBytes('file', fileData,
            contentType: 'application/octet-stream'),
      );

      expect(transport.recordedRequests.length, 1);
      final req = transport.recordedRequests.first;
      expect(req.headers['x-ms-blob-type'], 'BlockBlob');
    });

    // 7. rest-text-identify-language-success
    test(
        '7. rest-text-identify-language-success: REST text.identifyLanguage Success',
        () async {
      final transport = MockHttpTransport((req) async {
        expect(req.url.path, '/text-lid');
        expect(req.headers['api-subscription-key'], 'test-api-key');
        return jsonResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'detected_language': 'hi-IN',
            'confidence': 0.99,
          },
        );
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('test-api-key'),
        transport: transport,
      );

      final res = await client.text.identifyLanguage(
        const IdentifyLanguageRequest(input: 'नमस्ते दुनिया'),
      );

      expect(res.detectedLanguage, LanguageCode.hiIn);
      expect(res.confidence, 0.99);
    });

    // 8. rest-text-translate-success
    test('8. rest-text-translate-success: REST text.translate Success',
        () async {
      final transport = MockHttpTransport((req) async {
        expect(req.url.path, '/translate');
        expect(req.headers['api-subscription-key'], 'test-api-key');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['input'], 'Hello world');
        expect(body['source_language_code'], 'en-IN');
        expect(body['target_language_code'], 'hi-IN');
        expect(body['speaker_gender'], 'Male');
        expect(body['mode'], 'formal');
        expect(body['model'], 'mayura:v1');
        return jsonResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'translated_text': 'नमस्ते दुनिया',
          },
        );
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('test-api-key'),
        transport: transport,
      );

      final res = await client.text.translate(
        const TranslateRequest(
          input: 'Hello world',
          sourceLanguageCode: LanguageCode.enIn,
          targetLanguageCode: LanguageCode.hiIn,
          speakerGender: 'Male',
          mode: 'formal',
          model: 'mayura:v1',
        ),
      );

      expect(res.translatedText, 'नमस्ते दुनिया');
    });

    // 9. rest-text-transliterate-success
    test('9. rest-text-transliterate-success: REST text.transliterate Success',
        () async {
      final transport = MockHttpTransport((req) async {
        expect(req.url.path, '/transliterate');
        expect(req.headers['api-subscription-key'], 'test-api-key');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['input'], 'namaste');
        expect(body['source_language_code'], 'en-IN');
        expect(body['target_language_code'], 'hi-IN');
        return jsonResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'transliterated_text': 'नमस्ते',
          },
        );
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('test-api-key'),
        transport: transport,
      );

      final res = await client.text.transliterate(
        const TransliterateRequest(
          input: 'namaste',
          sourceLanguageCode: LanguageCode.enIn,
          targetLanguageCode: LanguageCode.hiIn,
        ),
      );

      expect(res.transliteratedText, 'नमस्ते');
    });

    // 10. rest-token-auth-refresh
    test(
        '10. rest-token-auth-refresh: TokenAuth Invalidation and Single Retry on 403',
        () async {
      var tokenFetchCount = 0;
      var requestAttempt = 0;

      Future<AuthToken> tokenProvider() async {
        tokenFetchCount++;
        return AuthToken(
          token: 'token_v$tokenFetchCount',
          expiresAtEpochMs: DateTime.now().millisecondsSinceEpoch + 3600000,
        );
      }

      final transport = MockHttpTransport((req) async {
        requestAttempt++;
        if (requestAttempt == 1) {
          expect(req.headers['Authorization'], 'Bearer token_v1');
          return jsonResponse(
            statusCode: 403,
            data: <String, dynamic>{
              'error': <String, dynamic>{
                'code': 'invalid_api_key_error',
                'message': 'Token expired or invalid',
                'request_id': 'req_token_expired',
              },
            },
          );
        } else {
          expect(req.headers['Authorization'], 'Bearer token_v2');
          return jsonResponse(
            statusCode: 200,
            data: <String, dynamic>{
              'translated_text': 'नमस्ते दुनिया',
            },
          );
        }
      });

      final client = SarvamClient.withTokenProvider(
        tokenProvider,
        transport: transport,
      );

      final res = await client.text.translate(
        const TranslateRequest(
          input: 'Hello world',
          sourceLanguageCode: LanguageCode.enIn,
          targetLanguageCode: LanguageCode.hiIn,
        ),
      );

      expect(requestAttempt, 2);
      expect(tokenFetchCount, 2);
      expect(res.translatedText, 'नमस्ते दुनिया');
    });

    // 11. rest-tts-chunked-stream
    test('11. rest-tts-chunked-stream: TTS HTTP Chunked Binary Audio Stream',
        () async {
      final chunk0 = Uint8List.fromList(
          <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]);
      final chunk1 = Uint8List.fromList(<int>[
        17,
        18,
        19,
        20,
        21,
        22,
        23,
        24,
        25,
        26,
        27,
        28,
        29,
        30,
        31,
        32
      ]);
      final chunk2 = Uint8List.fromList(<int>[
        33,
        34,
        35,
        36,
        37,
        38,
        39,
        40,
        41,
        42,
        43,
        44,
        45,
        46,
        47,
        48
      ]);

      final transport = MockHttpTransport((req) async {
        expect(req.url.path, '/text-to-speech/stream');
        expect(req.isStreaming, isTrue);
        return chunkedBinaryResponse(
            chunks: <Uint8List>[chunk0, chunk1, chunk2]);
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('test-api-key'),
        transport: transport,
      );

      final chunks = <Uint8List>[];
      await for (final chunk in client.textToSpeech.stream(
        const TextToSpeechRequest(
          text: 'नमस्ते भारत',
          targetLanguageCode: LanguageCode.hiIn,
          speaker: Speaker.anushka,
        ),
      )) {
        chunks.add(chunk);
      }

      expect(chunks.length, 3);
      final totalBytes = chunks.fold<int>(0, (sum, c) => sum + c.length);
      expect(totalBytes, 48);

      final concatenated = <int>[];
      for (final c in chunks) {
        concatenated.addAll(c);
      }
      expect(concatenated.sublist(0, 5), <int>[1, 2, 3, 4, 5]);
      expect(concatenated.sublist(43, 48), <int>[44, 45, 46, 47, 48]);
    });

    // 12. rest-tts-base64-decoding
    test('12. rest-tts-base64-decoding: TTS REST Base64 Audio Decoding',
        () async {
      const b64 =
          'UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA=';
      final transport = MockHttpTransport((req) async {
        expect(req.url.path, '/text-to-speech');
        return jsonResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'audios': <Map<String, dynamic>>[
              <String, dynamic>{'audio': b64},
            ],
          },
        );
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('test-api-key'),
        transport: transport,
      );

      final res = await client.textToSpeech.convert(
        const TextToSpeechRequest(
          text: 'नमस्ते दुनिया',
          targetLanguageCode: LanguageCode.hiIn,
          speaker: Speaker.anushka,
          model: TtsModel.bulbulV3,
        ),
      );

      expect(res.audioCount, 1);
      expect(res.firstAudioBase64, b64);
      expect(res.audioBytes.length, 44);
      expect(res.firstAudioByteLength, 44);

      // Verify WAV magic header: RIFF (0x52, 0x49, 0x46, 0x46) and WAVE (0x57, 0x41, 0x56, 0x45)
      expect(res.audioBytes.sublist(0, 4), <int>[0x52, 0x49, 0x46, 0x46]);
      expect(res.audioBytes.sublist(8, 12), <int>[0x57, 0x41, 0x56, 0x45]);
    });

    // 13. sse-chat-v1-stream
    test('13. sse-chat-v1-stream: Chat V1 Standard SSE Streaming', () async {
      const rawSse =
          'data: {"id":"chatcmpl-v1-1","choices":[{"index":0,"delta":{"content":"Hi"}}]}\n\n'
          'data: {"id":"chatcmpl-v1-1","choices":[{"index":0,"delta":{"content":" there!"}}]}\n\n'
          'data: [DONE]\n';

      final transport = MockHttpTransport((req) async {
        expect(req.url.path, '/v1/chat/completions');
        expect(req.isStreaming, isTrue);
        return sseResponse(ssePayload: rawSse);
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('test-api-key'),
        transport: transport,
      );

      final chunks = <ChatCompletionChunk>[];
      await for (final chunk in client.chat.completionsStream(
        const ChatCompletionRequest(
          model: 'sarvam-2b',
          messages: <ChatMessage>[ChatMessage(role: 'user', content: 'Hi')],
        ),
      )) {
        chunks.add(chunk);
      }

      expect(chunks.length, 2);
      final accumulated = chunks.map((c) => c.firstDeltaContent ?? '').join();
      expect(accumulated, 'Hi there!');
    });

    // 14. sse-chat-v2-empty-choices
    test(
        '14. sse-chat-v2-empty-choices: Chat V2 SSE Stream with Empty Choices Usage Chunk',
        () async {
      const rawSse =
          'data: {"id":"chatcmpl-1","choices":[{"index":0,"delta":{"content":"Namaste"}}]}\n\n'
          'data: {"id":"chatcmpl-1","choices":[{"index":0,"delta":{"content":" world"}}]}\n\n'
          'data: {"id":"chatcmpl-1","choices":[],"usage":{"prompt_tokens":8,"completion_tokens":2,"total_tokens":10}}\n\n'
          'data: [DONE]\n';

      final transport = MockHttpTransport((req) async {
        expect(req.url.path, '/v2/chat/completions');
        return sseResponse(ssePayload: rawSse);
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('test-api-key'),
        transport: transport,
      );

      final chunks = <ChatCompletionChunk>[];
      await for (final chunk in client.chat.completionsV2Stream(
        const ChatCompletionV2Request(
          model: 'sarvam-2b',
          messages: <ChatMessage>[ChatMessage(role: 'user', content: 'Hello')],
        ),
      )) {
        chunks.add(chunk);
      }

      expect(chunks.length, 3);
      final accumulated = chunks.map((c) => c.firstDeltaContent ?? '').join();
      expect(accumulated, 'Namaste world');

      // The 3rd chunk must have empty choices and valid usage without throwing RangeError!
      final usageChunk = chunks[2];
      expect(usageChunk.choices.isEmpty, isTrue);
      expect(usageChunk.firstDeltaContent, isNull);
      expect(usageChunk.usage?.promptTokens, 8);
      expect(usageChunk.usage?.completionTokens, 2);
      expect(usageChunk.usage?.totalTokens, 10);
    });

    // 15. sse-responses-api-no-done
    test(
        '15. sse-responses-api-no-done: Responses API SSE Stream terminates on response.completed without [DONE]',
        () async {
      const rawSse = 'event: response.created\n'
          'data: {"id":"resp_001","type":"response.created"}\n\n'
          'event: response.output_item.added\n'
          'data: {"id":"resp_001","type":"response.output_item.added","item":{"id":"item_001","type":"message","role":"assistant"}}\n\n'
          'event: response.content_part.added\n'
          'data: {"id":"resp_001","type":"response.content_part.added","item_id":"item_001","part":{"type":"text","text":"Quantum computers use qubits."}}\n\n'
          'event: response.completed\n'
          'data: {"id":"resp_001","type":"response.completed","response":{"status":"completed"}}\n\n';

      final transport = MockHttpTransport((req) async {
        expect(req.url.path, '/v2/responses');
        return sseResponse(ssePayload: rawSse);
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('test-api-key'),
        transport: transport,
      );

      final events = <ResponseEvent>[];
      await for (final event in client.responses.createStream(
        const ResponseStreamRequest(
          model: 'glm-5.3',
          input: 'Explain quantum computing briefly',
        ),
      )) {
        events.add(event);
      }

      expect(events.length, 4);
      expect(events[0].event, 'response.created');
      expect(events[1].event, 'response.output_item.added');
      expect(events[2].event, 'response.content_part.added');
      expect(events[3].event, 'response.completed');
      expect(events[3].json['response']?['status'], 'completed');
    });

    // 16. ws-stt-invalid-sample-rate
    test(
        '16. ws-stt-invalid-sample-rate: WebSocket STT Realtime Invalid Sample Rate Rejection',
        () async {
      final wsFactory = MockWebSocketFactory();
      final client = SarvamClient(
        auth: ApiKeyAuth('test-api-key'),
        webSocketFactory: wsFactory,
      );

      try {
        await client.speechToText.connect(
          const SttRealtimeConfig(
            languageCode: LanguageCode.hiIn,
            sampleRate: 44100, // Invalid!
          ),
        );
        fail('Expected BadRequestException for sampleRate 44100');
      } on BadRequestException catch (e) {
        expect(e.statusCode, 400);
        expect(e.message, contains('sampleRate must be 16000 or 8000'));
      }
    });

    // 17. ws-stt-realtime
    test('17. ws-stt-realtime: WebSocket STT Realtime Full Turn', () async {
      final wsSession = MockWebSocketSession();
      final wsFactory = MockWebSocketFactory(session: wsSession);

      final client = SarvamClient(
        auth: ApiKeyAuth('test-api-key'),
        webSocketFactory: wsFactory,
      );

      final session = await client.speechToText.connect(
        const SttRealtimeConfig(
          languageCode: LanguageCode.hiIn,
          model: SttModel.saarasV3Realtime,
          sampleRate: 16000,
        ),
      );

      // Verify connection headers
      expect(wsFactory.lastUri?.path, '/speech-to-text-realtime/ws');
      expect(wsFactory.lastHeaders?['Api-Subscription-Key'], 'test-api-key');

      final receivedEvents = <SttRealtimeEvent>[];
      final sub = session.events.listen(receivedEvents.add);

      // Client sends audio and end
      session.sendAudio(Uint8List.fromList(<int>[0, 0, 0]));
      session.end();

      // Server emits frames
      wsSession.pushIncoming(jsonEncode(<String, dynamic>{
        'event': 'session_begin',
        'session_id': 'sess_stt_001',
      }));
      wsSession.pushIncoming(jsonEncode(<String, dynamic>{
        'event': 'vad_speech_start',
        'timestamp_ms': 100,
      }));
      wsSession.pushIncoming(jsonEncode(<String, dynamic>{
        'event': 'transcript_partial',
        'utterance_idx': 0,
        'text': 'नमस्ते',
        'language': 'hi-IN',
      }));
      wsSession.pushIncoming(jsonEncode(<String, dynamic>{
        'event': 'transcript_final',
        'utterance_idx': 0,
        'text': 'नमस्ते!',
        'language': 'hi-IN',
        'language_confidence': 0.99,
        'start_s': 0.1,
        'end_s': 1.5,
      }));
      wsSession.pushIncoming(jsonEncode(<String, dynamic>{
        'event': 'session_end',
      }));

      // Allow event stream to process
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(wsSession.sentFrames.length, 2);
      final frame1 =
          jsonDecode(wsSession.sentFrames[0] as String) as Map<String, dynamic>;
      expect(frame1['event'], 'audio_input');
      expect(frame1['audio'], 'AAAA');

      final frame2 =
          jsonDecode(wsSession.sentFrames[1] as String) as Map<String, dynamic>;
      expect(frame2['event'], 'end');

      expect(receivedEvents.length, 5);
      expect(receivedEvents[0], isA<SessionBegin>());
      expect((receivedEvents[0] as SessionBegin).sessionId, 'sess_stt_001');
      expect(receivedEvents[1], isA<VadSpeechStart>());
      expect((receivedEvents[1] as VadSpeechStart).timestampMs, 100);
      expect(receivedEvents[2], isA<TranscriptPartial>());
      expect((receivedEvents[2] as TranscriptPartial).text, 'नमस्ते');
      expect(receivedEvents[3], isA<TranscriptFinal>());
      final finalEvent = receivedEvents[3] as TranscriptFinal;
      expect(finalEvent.text, 'नमस्ते!');
      expect(finalEvent.language, LanguageCode.hiIn);
      expect(finalEvent.languageConfidence, 0.99);
      expect(finalEvent.startS, 0.1);
      expect(finalEvent.endS, 1.5);
      expect(receivedEvents[4], isA<SessionEnd>());

      await sub.cancel();
      await session.close();
      expect(wsSession.isClosed, isTrue);
    });

    // 18. ws-stt-subprotocol-auth
    test(
        '18. ws-stt-subprotocol-auth: WebSocket STT Realtime Subprotocol Authentication',
        () async {
      final wsSession = MockWebSocketSession();
      final wsFactory = MockWebSocketFactory(session: wsSession);

      final client = SarvamClient(
        auth: ApiKeyAuth('test-api-key'),
        webSocketFactory: wsFactory,
      );

      final session = await client.speechToText.connect(
        const SttRealtimeConfig(
          languageCode: LanguageCode.hiIn,
          model: SttModel.saarasV3Realtime,
          sampleRate: 16000,
          useSubprotocolAuth: true,
        ),
      );

      // Verify subprotocols set and no custom auth header
      expect(wsFactory.lastProtocols,
          <String>['api-subscription-key.test-api-key']);
      expect(wsFactory.lastHeaders?['Api-Subscription-Key'], isNull);

      final receivedEvents = <SttRealtimeEvent>[];
      final sub = session.events.listen(receivedEvents.add);

      session.sendAudio(Uint8List.fromList(<int>[0, 0, 0]));
      session.end();

      wsSession.pushIncoming(jsonEncode(<String, dynamic>{
        'event': 'session_begin',
        'session_id': 'sess_subprotocol_001',
      }));
      wsSession.pushIncoming(jsonEncode(<String, dynamic>{
        'event': 'transcript_final',
        'utterance_idx': 0,
        'text': 'नमस्ते!',
        'language': 'hi-IN',
      }));
      wsSession.pushIncoming(jsonEncode(<String, dynamic>{
        'event': 'session_end',
      }));

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(receivedEvents.length, 3);
      expect(receivedEvents[0], isA<SessionBegin>());
      expect(receivedEvents[1], isA<TranscriptFinal>());
      expect((receivedEvents[1] as TranscriptFinal).text, 'नमस्ते!');
      expect(receivedEvents[2], isA<SessionEnd>());

      await sub.cancel();
      await session.close();
    });

    // 19. ws-tts-streaming
    test(
        '19. ws-tts-streaming: WebSocket TTS Streaming Full Conversational Turn',
        () async {
      final wsSession = MockWebSocketSession();
      final wsFactory = MockWebSocketFactory(session: wsSession);

      final client = SarvamClient(
        auth: ApiKeyAuth('test-api-key'),
        webSocketFactory: wsFactory,
      );

      final session = await client.textToSpeech.connect(
        const TtsStreamingConfig(
          languageCode: LanguageCode.hiIn,
          speaker: Speaker.simran,
          model: TtsModel.bulbulV4Flash,
          speechSampleRate: 22050,
          outputAudioCodec: AudioCodec.mp3,
        ),
      );

      // Initial config frame must have been sent immediately upon connect
      expect(wsSession.sentFrames.length, 1);
      final initialFrame =
          jsonDecode(wsSession.sentFrames[0] as String) as Map<String, dynamic>;
      expect(initialFrame['type'], 'config');
      expect(initialFrame['data']['language_code'], 'hi-IN');
      expect(initialFrame['data']['speaker'], 'simran');
      expect(initialFrame['data']['model'], 'bulbul:v4-flash');
      expect(initialFrame['data']['speech_sample_rate'], 22050);
      expect(initialFrame['data']['output_audio_codec'], 'mp3');

      final receivedEvents = <TtsStreamEvent>[];
      final sub = session.events.listen(receivedEvents.add);

      session.sendText('नमस्ते भारत');
      session.flush();

      expect(wsSession.sentFrames.length, 3);
      final textFrame =
          jsonDecode(wsSession.sentFrames[1] as String) as Map<String, dynamic>;
      expect(textFrame['type'], 'text');
      expect(textFrame['data']['text'], 'नमस्ते भारत');

      final flushFrame =
          jsonDecode(wsSession.sentFrames[2] as String) as Map<String, dynamic>;
      expect(flushFrame['type'], 'flush');

      // Server emits 2 audio chunks and 1 event final
      const b64 =
          'UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA=';
      wsSession.pushIncoming(jsonEncode(<String, dynamic>{
        'type': 'audio',
        'data': <String, dynamic>{'audio': b64},
      }));
      wsSession.pushIncoming(jsonEncode(<String, dynamic>{
        'type': 'audio',
        'data': <String, dynamic>{'audio': b64},
      }));
      wsSession.pushIncoming(jsonEncode(<String, dynamic>{
        'type': 'event',
        'data': <String, dynamic>{'event': 'final'},
      }));

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(receivedEvents.length, 3);
      expect(receivedEvents[0], isA<TtsAudioChunk>());
      expect((receivedEvents[0] as TtsAudioChunk).audioBytes.length, 44);
      expect(receivedEvents[1], isA<TtsAudioChunk>());
      expect((receivedEvents[1] as TtsAudioChunk).audioBytes.length, 44);
      expect(receivedEvents[2], isA<TtsCompleted>());

      await sub.cancel();
      await session.close();
      expect(wsSession.isClosed, isTrue);
    });
  });
}
