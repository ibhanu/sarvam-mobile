import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:sarvam/sarvam.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('SarvamClient Factories and Resource Access Unit Tests', () {
    test('SarvamClient.withApiKey, withTokenProvider, withProxy, and close', () async {
      final mockTransport = MockHttpTransport((req) async => jsonResponse(data: {}));
      final mockWs = MockWebSocketFactory();

      final clientKey = SarvamClient.withApiKey(
        'api-key-test',
        transport: mockTransport,
        webSocketFactory: mockWs,
      );
      expect(clientKey.config.auth, isA<ApiKeyAuth>());
      expect(clientKey.text, isNotNull);
      expect(clientKey.speechToText, isNotNull);
      expect(clientKey.textToSpeech, isNotNull);
      expect(clientKey.chat, isNotNull);
      expect(clientKey.responses, isNotNull);
      expect(clientKey.jobs, isNotNull);
      expect(clientKey.voiceCloning, isNotNull);
      expect(clientKey.docAi, isNotNull);
      expect(clientKey.pronunciationDictionary, isNotNull);
      expect(clientKey.speechToTextJob, isNotNull);
      expect(clientKey.speechToTextTranslateJob, isNotNull);
      expect(clientKey.documentTranslation, isNotNull);
      expect(clientKey.dubbing, isNotNull);

      clientKey.close();
      expect(mockTransport.isClosed, isTrue);

      final clientToken = SarvamClient.withTokenProvider(
        () async => const AuthToken(token: 'tok-1', expiresAtEpochMs: 999999),
        transport: MockHttpTransport((req) async => jsonResponse(data: {})),
        webSocketFactory: mockWs,
      );
      expect(clientToken.config.auth, isA<TokenAuth>());

      final clientProxy = SarvamClient.withProxy(
        'https://myproxy.internal',
        transport: MockHttpTransport((req) async => jsonResponse(data: {})),
        webSocketFactory: mockWs,
      );
      expect(clientProxy.config.auth, isA<ProxyAuth>());
      expect(clientProxy.config.environment.apiBaseUrl, 'https://myproxy.internal');
    });
  });

  group('SpeechToTextResource & Models Unit Tests', () {
    test('transcribe and translate send multipart fields and parse responses', () async {
      HttpRequest? lastRequest;
      final mockTransport = MockHttpTransport((req) async {
        lastRequest = req;
        if (req.url.path.contains('speech-to-text-translate')) {
          return jsonResponse(data: {
            'transcript': 'Namaste',
            'translated_transcript': 'Hello',
            'source_language_code': 'hi-IN',
            'target_language_code': 'en-IN',
          });
        }
        return jsonResponse(data: {
          'transcript': 'Namaste duniya',
          'language_code': 'hi-IN',
        });
      });

      final client = SarvamClient.withApiKey('key-1', transport: mockTransport);

      final file = SarvamFileInput.fromBytes('file', Uint8List.fromList([1, 2, 3]), filename: 'sample.wav');

      // transcribe
      final resp1 = await client.speechToText.transcribe(
        file: file,
        languageCode: LanguageCode.hiIn,
        model: SttModel.saarasV3,
        mode: SttMode.transcribe,
        options: const RequestOptions(headers: {'x-opt': '1'}),
      );
      expect(resp1.transcript, 'Namaste duniya');
      expect(resp1.languageCode?.value, 'hi-IN');
      expect(resp1.toString(), contains('Namaste duniya'));
      expect(lastRequest?.fields?['language_code'], 'hi-IN');
      expect(lastRequest?.fields?['model'], 'saaras:v3');
      expect(lastRequest?.fields?['mode'], 'transcribe');
      expect(lastRequest?.headers['x-opt'], '1');

      // translate
      final resp2 = await client.speechToText.translate(
        file: file,
        sourceLanguageCode: LanguageCode.hiIn,
        targetLanguageCode: LanguageCode.enIn,
        model: SttModel.saarasV3,
        mode: SttMode.translate,
        options: const RequestOptions(headers: {'x-opt': '2'}),
      );
      expect(resp2.transcript, 'Namaste');
      expect(resp2.translatedTranscript, 'Hello');
      expect(resp2.sourceLanguageCode?.value, 'hi-IN');
      expect(resp2.targetLanguageCode?.value, 'en-IN');
      expect(resp2.toString(), contains('Hello'));
      expect(lastRequest?.fields?['source_language_code'], 'hi-IN');
      expect(lastRequest?.fields?['target_language_code'], 'en-IN');

      // SttRealtimeConfig query parameters
      const config = SttRealtimeConfig(
        languageCode: LanguageCode.hiIn,
        model: SttModel.saarasV3Realtime,
        sampleRate: 16000,
        streamType: 'input',
        mode: SttMode.transcribe,
        encoding: 'linear16',
        returnTimestamps: true,
        endpointing: true,
        threshold: 0.5,
        prefixPaddingMs: 200,
        silenceDurationMs: 400,
        minSpeechDurationMs: 100,
        prompt: 'test prompt',
        keyterms: ['sarvam', 'ai'],
      );
      final queryParams = config.toQueryParams();
      expect(queryParams['language_code'], 'hi-IN');
      expect(queryParams['stream_type'], 'input');
      expect(queryParams['encoding'], 'linear16');
      expect(queryParams['return_timestamps'], 'true');
      expect(queryParams['endpointing'], 'true');
      expect(queryParams['threshold'], '0.5');
      expect(queryParams['prefix_padding_ms'], '200');
      expect(queryParams['silence_duration_ms'], '400');
      expect(queryParams['min_speech_duration_ms'], '100');
      expect(queryParams['prompt'], 'test prompt');
      expect(queryParams['keyterms'], 'sarvam,ai');

      // connect
      final mockWs = MockWebSocketFactory();
      final clientWs = SarvamClient.withApiKey('key-1', transport: mockTransport, webSocketFactory: mockWs);
      final session = await clientWs.speechToText.connect(
        config,
        options: const RequestOptions(queryParams: {'extra': 'query'}, headers: {'x-ws': '1'}),
      );
      expect(mockWs.lastUri?.queryParameters['extra'], 'query');
      expect(mockWs.lastHeaders?['x-ws'], '1');
      await session.close();
    });
  });

  group('ChatResource & Models Unit Tests', () {
    test('completions, completionsStream, completionsV2, completionsV2Stream, models and session', () async {
      HttpRequest? lastRequest;
      final mockTransport = MockHttpTransport((req) async {
        lastRequest = req;
        if (req.url.path.contains('/v2/models/model-1')) {
          return jsonResponse(data: {'id': 'model-1'});
        }
        if (req.url.path.contains('/v2/models')) {
          return jsonResponse(data: {
            'models': [
              {'id': 'model-1'},
              {'id': 'model-2'},
            ],
          });
        }
        if (req.isStreaming) {
          final sseData = 'data: {"id":"c-1","choices":[{"index":0,"delta":{"role":"assistant","content":"Hi"}}]}\n\ndata: [DONE]\n\n';
          return sseResponse(ssePayload: sseData);
        }
        return jsonResponse(data: {
          'id': 'chat-100',
          'model': 'sarvam-2b',
          'choices': [
            {
              'index': 0,
              'message': {'role': 'assistant', 'content': 'Hello there!'},
              'finish_reason': 'stop',
            }
          ],
          'usage': {
            'prompt_tokens': 10,
            'completion_tokens': 5,
            'total_tokens': 15,
          },
        });
      });

      final client = SarvamClient.withApiKey('key-1', transport: mockTransport);

      // 1. completions unary
      final unary = await client.chat.completions(
        const ChatCompletionRequest(
          model: 'sarvam-2b',
          messages: [ChatMessage(role: 'user', content: 'hello')],
          temperature: 0.7,
          maxTokens: 50,
        ),
        options: const RequestOptions(headers: {'x-chat': '1'}),
      );
      expect(unary.id, 'chat-100');
      expect(unary.choices.first.message?.content, 'Hello there!');
      expect(unary.usage?.totalTokens, 15);
      expect(unary.usage?.toJson()['total_tokens'], 15);

      // 2. completionsStream
      final streamChunks = await client.chat.completionsStream(
        const ChatCompletionRequest(
          model: 'sarvam-2b',
          messages: [ChatMessage(role: 'user', content: 'stream please')],
        ),
      ).toList();
      expect(streamChunks.length, 1);
      expect(streamChunks.first.firstDeltaContent, 'Hi');

      // 3. completionsV2 unary
      final v2Unary = await client.chat.completionsV2(
        const ChatCompletionV2Request(
          model: 'sarvam-2b',
          messages: [ChatMessage(role: 'user', content: 'hello v2')],
          temperature: 0.8,
          maxTokens: 100,
        ),
      );
      expect(v2Unary.id, 'chat-100');

      // 4. completionsV2Stream
      final streamV2Chunks = await client.chat.completionsV2Stream(
        const ChatCompletionV2Request(
          model: 'sarvam-2b',
          messages: [ChatMessage(role: 'user', content: 'stream v2')],
        ),
      ).toList();
      expect(streamV2Chunks.length, 1);

      // 5. listModels & getModel
      final modelList = await client.chat.listModels(
        options: const RequestOptions(headers: {'x-mod': '1'}, timeout: Duration(seconds: 2)),
      );
      expect(modelList.models.length, 2);
      expect(modelList.models.first.id, 'model-1');
      expect(lastRequest?.headers['x-mod'], '1');

      final singleModel = await client.chat.getModel(
        'model-1',
        options: const RequestOptions(headers: {'x-mod': '2'}, timeout: Duration(seconds: 2)),
      );
      expect(singleModel.id, 'model-1');
      expect(lastRequest?.headers['x-mod'], '2');

      // 6. createSession & ChatSession affinity
      final session = client.chat.createSession(sessionId: 'sess-abc');
      expect(session.sessionId, 'sess-abc');
      await session.completions(
        const ChatCompletionRequest(model: 'm', messages: []),
        options: const RequestOptions(headers: {'custom-hdr': '1'}),
      );
      expect(lastRequest?.headers['x-session-affinity'], 'sess-abc');
      expect(lastRequest?.headers['custom-hdr'], '1');

      final autoSession = client.chat.createSession();
      expect(autoSession.sessionId, isNotEmpty);
      await autoSession.completionsV2(
        const ChatCompletionV2Request(model: 'm', messages: []),
      );
      expect(lastRequest?.headers['x-session-affinity'], autoSession.sessionId);

      await autoSession.completionsStream(
        const ChatCompletionRequest(model: 'm', messages: []),
      ).toList();

      await autoSession.completionsV2Stream(
        const ChatCompletionV2Request(model: 'm', messages: []),
      ).toList();

      // Empty choices on ChatCompletionChunk
      const emptyChunk = ChatCompletionChunk(id: 'c-empty', choices: []);
      expect(emptyChunk.firstDeltaContent, isNull);
    });
  });

  group('VoiceCloningResource & Models Unit Tests', () {
    test('listVoices, createVoice, getVoice, deleteVoice, convert, stream, connect', () async {
      final mockTransport = MockHttpTransport((req) async {
        if (req.url.path.endsWith('/voices') && req.method == 'GET') {
          return jsonResponse(data: {
            'voices': [
              {
                'voice_id': 'voice-1',
                'name': 'Voice One',
                'status': 'ready',
              }
            ],
          });
        }
        if (req.url.path.contains('/voices/voice-1') && req.method == 'GET') {
          return jsonResponse(data: {
            'voice_id': 'voice-1',
            'name': 'Voice One',
            'status': 'ready',
          });
        }
        if (req.url.path.contains('/voices/delete/voice-1') && req.method == 'DELETE') {
          return jsonResponse(data: {'deleted': true});
        }
        if (req.url.path.contains('/voices/create') && req.method == 'POST') {
          return jsonResponse(data: {
            'voice_id': 'voice-new',
            'status': 'created',
            'reference_text': 'ref',
          });
        }
        if (req.url.path.contains('/clone/stream')) {
          return chunkedBinaryResponse(chunks: [Uint8List.fromList([1, 2, 3])]);
        }
        if (req.url.path.contains('/clone')) {
          return jsonResponse(data: {
            'audio': base64Encode(Uint8List.fromList([4, 5, 6])),
            'request_id': 'clone-req-1',
            'audio_duration': 1.5,
          });
        }
        return jsonResponse(data: {});
      });

      final mockWs = MockWebSocketFactory();
      final client = SarvamClient.withApiKey('key-1', transport: mockTransport, webSocketFactory: mockWs);

      // listVoices with Map
      final listResp = await client.voiceCloning.listVoices();
      expect(listResp.voices.length, 1);
      expect(listResp.voices.first.name, 'Voice One');
      expect(listResp.voices.first.toString(), contains('Voice One'));

      // listVoices with List
      final listDirect = VoiceListResponse.fromJson([
        {'voice_id': 'v2', 'name': 'V2'},
      ]);
      expect(listDirect.voices.length, 1);

      // listVoices with empty map
      final listEmpty = VoiceListResponse.fromJson(<String, dynamic>{});
      expect(listEmpty.voices, isEmpty);

      // createVoice
      final createResp = await client.voiceCloning.createVoice(
        VoiceCreateRequest(
          name: 'New Voice',
          language: LanguageCode.hiIn,
          file: SarvamFileInput.fromBytes('file', Uint8List.fromList([9, 8])),
        ),
        options: const RequestOptions(headers: {'x-create': '1'}),
      );
      expect(createResp.voiceId, 'voice-new');
      expect(createResp.toString(), contains('voice-new'));

      // getVoice & deleteVoice
      final getVoice = await client.voiceCloning.getVoice('voice-1');
      expect(getVoice.voiceId, 'voice-1');

      final delVoice = await client.voiceCloning.deleteVoice('voice-1');
      expect(delVoice['deleted'], isTrue);

      // convert
      final cloneResp = await client.voiceCloning.convert(
        VoiceCloneRequest(
          text: 'Namaste',
          languageCode: LanguageCode.hiIn,
          voiceId: 'voice-1',
          refText: 'ref sample',
          pace: 1.1,
          outputAudioCodec: AudioCodec.wav,
          outputAudioBitrate: '128k',
          speechSampleRate: 16000,
          enableTextNormalization: true,
        ),
      );
      expect(cloneResp.requestId, 'clone-req-1');
      expect(cloneResp.audioBytes, [4, 5, 6]);
      expect(cloneResp.toString(), contains('clone-req-1'));

      // stream
      final streamBytes = await client.voiceCloning.stream(
        const VoiceCloneRequest(text: 'Stream', languageCode: LanguageCode.hiIn),
      ).toList();
      expect(streamBytes.first, [1, 2, 3]);

      // connect
      const streamConfig = VoiceCloningStreamingConfig(
        targetLanguageCode: LanguageCode.hiIn,
        voiceId: 'v-1',
        refAudio: 'data',
        refText: 'txt',
        pace: 1.0,
        speechSampleRate: 16000,
        outputAudioCodec: AudioCodec.wav,
        outputAudioBitrate: '128k',
        minBufferSize: 10,
        maxChunkLength: 20,
        enablePretts: true,
        useSubprotocolAuth: true,
      );
      final wsSession = await client.voiceCloning.connect(
        streamConfig,
        options: const RequestOptions(headers: {'x-vc-ws': '1'}),
      );
      expect(mockWs.lastProtocols, isNotEmpty);
      await wsSession.close();
    });
  });

  group('PronunciationDictionaryResource & Models Unit Tests', () {
    test('list, create, update, get, delete operations and models', () async {
      final mockTransport = MockHttpTransport((req) async {
        if (req.method == 'GET' && req.url.pathSegments.length > 2) {
          // get specific dict
          return jsonResponse(data: {
            'data': {
              'dict_id': 'd-1',
              'name': 'MyDict',
              'status': 'active',
            }
          });
        }
        if (req.method == 'GET') {
          return jsonResponse(data: {
            'dictionaries': [
              {'dict_id': 'd-1', 'name': 'MyDict'}
            ]
          });
        }
        if (req.method == 'POST') {
          return jsonResponse(data: {'dict_id': 'd-new', 'status': 'created'});
        }
        if (req.method == 'PUT') {
          return jsonResponse(data: {'dict_id': 'd-1', 'status': 'updated'});
        }
        if (req.method == 'DELETE') {
          return jsonResponse(data: {'deleted': true});
        }
        return jsonResponse(data: {});
      });

      final client = SarvamClient.withApiKey('key-1', transport: mockTransport);

      // list
      final listResp = await client.pronunciationDictionary.list(
        options: const RequestOptions(headers: {'x-dict': '1'}),
      );
      expect(listResp.dictionaries.length, 1);
      expect(listResp.dictionaries.first.dictId, 'd-1');
      expect(listResp.dictionaries.first.toString(), contains('MyDict'));

      // list with List JSON
      final listFromJsonList = PronunciationDictionaryListResponse.fromJson([
        {'dict_id': 'd-2'}
      ]);
      expect(listFromJsonList.dictionaries.length, 1);

      // list with empty map
      final listFromEmptyMap = PronunciationDictionaryListResponse.fromJson(<String, dynamic>{});
      expect(listFromEmptyMap.dictionaries, isEmpty);

      // create with file.field == 'file'
      final fileFile = SarvamFileInput.fromBytes('file', Uint8List.fromList([1, 2]));
      final createResp1 = await client.pronunciationDictionary.create(fileFile);
      expect(createResp1.dictId, 'd-new');
      expect(createResp1.toString(), contains('d-new'));

      // create with file.field != 'file' and file.bytes != null
      final fileOther = SarvamFileInput.fromBytes('dict_file', Uint8List.fromList([3, 4]));
      await client.pronunciationDictionary.create(fileOther);

      // create with file.streamFactory
      final fileStream = SarvamFileInput.fromStream('dict_stream', () => Stream.value([5, 6]), 2);
      await client.pronunciationDictionary.create(fileStream);

      // update with file.field == 'file'
      final updateResp = await client.pronunciationDictionary.update('d-1', fileFile);
      expect(updateResp.dictId, 'd-1');

      // update with file.bytes and file.streamFactory
      await client.pronunciationDictionary.update('d-1', fileOther);
      await client.pronunciationDictionary.update('d-1', fileStream);

      // get
      final getResp = await client.pronunciationDictionary.get('d-1');
      expect(getResp.dictId, 'd-1');

      // delete with json
      final delResp = await client.pronunciationDictionary.delete('d-1');
      expect(delResp['deleted'], isTrue);
    });
  });

  group('DocAiResource & Models Unit Tests', () {
    test('digitise, extract, createUploadUrl, getStatus, getResults, getDownloadUrl, digitiseAndWait, extractAndWait', () async {
      var pollCalls = 0;
      final mockTransport = MockHttpTransport((req) async {
        if (req.url.path.contains('/status')) {
          pollCalls++;
          return jsonResponse(data: {
            'job_id': 'doc-job-1',
            'status': pollCalls >= 2 ? 'completed' : 'processing',
          });
        }
        if (req.url.path.contains('/results')) {
          return jsonResponse(data: {
            'job_id': 'doc-job-1',
            'data': {'extracted': 'text'},
          });
        }
        if (req.url.path.contains('/download-url')) {
          return jsonResponse(data: {
            'job_id': 'doc-job-1',
            'url': 'https://download.docai.com/file.pdf',
          });
        }
        if (req.url.path.contains('/upload')) {
          return jsonResponse(data: {
            'upload_url': 'https://upload.docai.com/file',
            'upload_id': 'up-123',
          });
        }
        // digitise or extract
        return jsonResponse(data: {
          'job_id': 'doc-job-1',
          'status': 'Started',
        });
      });

      final client = SarvamClient.withApiKey('key-1', transport: mockTransport);
      final file1 = SarvamFileInput.fromBytes('file', Uint8List(4), filename: 'a.pdf');
      final file2 = SarvamFileInput.fromBytes('other', Uint8List(4), filename: 'b.pdf');

      // 1. digitise with single file
      final digResp = await client.docAi.digitise(
        DocAiDigitiseRequest(file: file1, language: LanguageCode.hiIn, contentType: 'application/pdf'),
      );
      expect(digResp.jobId, 'doc-job-1');
      expect(digResp.toString(), contains('doc-job-1'));

      // digitise with List<SarvamFileInput>
      await client.docAi.digitise(DocAiDigitiseRequest(file: [file1, file2]));

      // digitise with generic List
      await client.docAi.digitise(DocAiDigitiseRequest(file: <dynamic>[file1]));

      // 2. extract with single file, schema Map, and fields
      final extResp = await client.docAi.extract(
        DocAiExtractRequest(
          file: file1,
          schema: {'name': 'string'},
          configId: 'cfg-1',
          outputFormat: 'json',
          classification: true,
          model: 'doc-v1',
        ),
      );
      expect(extResp.jobId, 'doc-job-1');

      // extract with List<SarvamFileInput>
      await client.docAi.extract(DocAiExtractRequest(file: [file1, file2]));
      // extract with generic List
      await client.docAi.extract(DocAiExtractRequest(file: <dynamic>[file1]));

      // 3. createUploadUrl
      final upResp = await client.docAi.createUploadUrl(
        const DocAiPresignUploadRequest(fileName: 'test.pdf', contentType: 'application/pdf'),
      );
      expect(upResp.uploadId, 'up-123');

      // 4. getStatus
      final statusResp = await client.docAi.getStatus('doc-job-1');
      expect(statusResp.isCompleted, isFalse);
      expect(statusResp.isFailed, isFalse);
      expect(statusResp.toString(), contains('doc-job-1'));

      // 5. getResults
      final resResp = await client.docAi.getResults(
        'doc-job-1',
        format: 'json',
        options: const RequestOptions(queryParams: {'p': '1'}),
      );
      expect(resResp.jobId, 'doc-job-1');
      expect(resResp.toString(), contains('doc-job-1'));

      // 6. getDownloadUrl
      final downResp = await client.docAi.getDownloadUrl('doc-job-1');
      expect(downResp.url, contains('https://download.docai.com'));

      // 7. digitiseAndWait and extractAndWait
      pollCalls = 0;
      final waitDig = await client.docAi.digitiseAndWait(
        DocAiDigitiseRequest(file: file1),
        pollInterval: const Duration(milliseconds: 1),
      );
      expect(waitDig.jobId, 'doc-job-1');

      pollCalls = 0;
      final waitExt = await client.docAi.extractAndWait(
        DocAiExtractRequest(file: file1),
        pollInterval: const Duration(milliseconds: 1),
      );
      expect(waitExt.jobId, 'doc-job-1');
    });
  });

  group('DocumentTranslationResource & DubbingResource Unit Tests', () {
    test('DocumentTranslationResource operations and models', () async {
      var liveCalls = 0;
      final mockTransport = MockHttpTransport((req) async {
        if (req.url.path.contains('/start')) {
          return jsonResponse(data: {'job_id': 'dt-1', 'job_state': 'Started'});
        }
        if (req.url.path.contains('/live-status')) {
          liveCalls++;
          return jsonResponse(data: {
            'job_id': 'dt-1',
            'job_state': liveCalls >= 2 ? 'Completed' : 'Processing',
            'progress': liveCalls >= 2 ? 100 : 50,
          });
        }
        if (req.url.path.contains('/export/status')) {
          return jsonResponse(data: {
            'export_id': 'exp-1',
            'job_id': 'dt-1',
            'target_language_code': 'hi-IN',
            'format': 'pdf',
            'export_state': 'Completed',
            'download_url': 'https://dt.download/file.pdf',
          });
        }
        if (req.url.path.contains('/export')) {
          return jsonResponse(data: {'export_id': 'exp-1', 'status': 'Queued'});
        }
        // create
        return jsonResponse(data: {'job_id': 'dt-1', 'job_state': 'Created'});
      });

      final client = SarvamClient.withApiKey('key-1', transport: mockTransport);

      final createResp = await client.documentTranslation.create(
        const DocumentTranslationCreateRequest(
          sourceLanguageCode: LanguageCode.enIn,
          targetLanguageCodes: [LanguageCode.hiIn],
          fileUrl: 'https://files.com/doc.pdf',
          jobName: 'TestDoc',
          extraParameters: {'custom': 'param'},
        ),
      );
      expect(createResp.jobId, 'dt-1');
      expect(createResp.toString(), contains('dt-1'));

      await client.documentTranslation.start('dt-1');

      final liveStatus = await client.documentTranslation.getLiveStatus('dt-1');
      expect(liveStatus.jobId, 'dt-1');
      expect(liveStatus.toString(), contains('dt-1'));

      final exportResp = await client.documentTranslation.triggerExport(
        'dt-1',
        lang: 'hi-IN',
        format: 'pdf',
        fitLineHeight: true,
        fitFontShrink: false,
        options: const RequestOptions(queryParams: {'export_param': '1'}),
      );
      expect(exportResp.exportId, 'exp-1');

      final exportStatus = await client.documentTranslation.getExportStatus(
        'dt-1',
        lang: 'hi-IN',
        exportId: 'exp-1',
        options: const RequestOptions(queryParams: {'status_param': '1'}),
      );
      expect(exportStatus.isCompleted, isTrue);
      expect(exportStatus.isFailed, isFalse);
      expect(exportStatus.toString(), contains('https://dt.download/file.pdf'));

      liveCalls = 0;
      final waitComplete = await client.documentTranslation.waitUntilComplete(
        'dt-1',
        pollInterval: const Duration(milliseconds: 1),
      );
      expect(waitComplete.isCompleted, isTrue);
    });

    test('DubbingResource operations and models', () async {
      var dubbingCalls = 0;
      final mockTransport = MockHttpTransport((req) async {
        if (req.url.path.contains('/start')) {
          return jsonResponse(data: {'job_id': 'dub-1', 'status': 'Started'});
        }
        if (req.url.path.contains('/live-status')) {
          dubbingCalls++;
          return jsonResponse(data: {
            'job_id': 'dub-1',
            'status': dubbingCalls >= 2 ? 'completed' : 'processing',
            'progress': dubbingCalls >= 2 ? 100 : 40,
          });
        }
        if (req.url.path.contains('/export-status')) {
          return jsonResponse(data: {
            'status': 'completed',
            'data': {'download_url': 'https://dub.download/out.mp4'},
          });
        }
        // create
        return jsonResponse(data: {'job_id': 'dub-1', 'status': 'created'});
      });

      final client = SarvamClient.withApiKey('key-1', transport: mockTransport);

      final createResp = await client.dubbing.create(
        const DubbingCreateRequest(
          sourceLanguageCode: LanguageCode.enIn,
          targetLanguageCodes: [LanguageCode.hiIn],
          extraParameters: {'dubbing_mode': 'full'},
        ),
      );
      expect(createResp.jobId, 'dub-1');
      expect(createResp.toString(), contains('dub-1'));

      await client.dubbing.start('dub-1');

      final liveStatus = await client.dubbing.getLiveStatus('dub-1');
      expect(liveStatus.jobId, 'dub-1');
      expect(liveStatus.toString(), contains('dub-1'));

      final exportStatus = await client.dubbing.getExportStatus(
        'dub-1',
        limit: 10,
        options: const RequestOptions(queryParams: {'p': '1'}),
      );
      expect(exportStatus.status, 'completed');
      expect(exportStatus.toString(), contains('completed'));

      dubbingCalls = 0;
      final waitDub = await client.dubbing.waitUntilComplete(
        'dub-1',
        pollInterval: const Duration(milliseconds: 1),
      );
      expect(waitDub.isCompleted, isTrue);
      expect(waitDub.isFailed, isFalse);
    });
  });

  group('SpeechToTextJobResource, JobsResource, ResponsesResource Unit Tests', () {
    test('SpeechToTextJobModels and JobsResource signed URL upload', () async {
      HttpRequest? lastRequest;
      final mockTransport = MockHttpTransport((req) async {
        lastRequest = req;
        return jsonResponse(data: {});
      });

      final client = SarvamClient.withApiKey('key-1', transport: mockTransport);

      // uploadToSignedUrl with bytes
      final fileBytes = SarvamFileInput.fromBytes('file', Uint8List.fromList([1, 2, 3]), contentType: 'audio/wav');
      expect(fileBytes.byteData, [1, 2, 3]);
      await client.jobs.uploadToSignedUrl(
        'https://sas.blob.core.windows.net/upload',
        fileBytes,
        options: const RequestOptions(headers: {'x-custom': '1'}, timeout: Duration(seconds: 10)),
      );
      expect(lastRequest?.headers['x-ms-blob-type'], 'BlockBlob');
      expect(lastRequest?.headers['content-type'], 'audio/wav');
      expect(lastRequest?.bodyBytes, [1, 2, 3]);

      // uploadToSignedUrl with stream
      final fileStream = SarvamFileInput.fromStream('file', () => Stream.value([4, 5, 6]), 3);
      expect(fileStream.byteData, isNull);
      await client.jobs.uploadToSignedUrl(
        'https://sas.blob.core.windows.net/upload',
        fileStream,
      );
      expect(lastRequest?.bodyBytes, [4, 5, 6]);

      // uploadToSignedUrl with empty bytes
      final emptyFile = SarvamFileInput.fromBytes('file', Uint8List(0));
      await client.jobs.uploadToSignedUrl(
        'https://sas.blob.core.windows.net/upload',
        emptyFile,
      );
      expect(lastRequest?.bodyBytes, isEmpty);

      // SpeechToTextJobInitRequest & Status
      const initReq = SpeechToTextJobInitRequest(
        jobParameters: {'model': 'saaras:v3'},
        callback: {'url': 'https://webhook.site'},
      );
      final jsonInit = initReq.toJson();
      expect(jsonInit['job_parameters'], isNotNull);
      expect(jsonInit['callback'], isNotNull);

      final jobStatus = SpeechToTextJobStatus.fromJson({
        'job_id': 'job-stt-1',
        'job_state': 'completed',
        'total_files': 5,
        'successful_files_count': 5,
        'failed_files_count': 0,
      });
      expect(jobStatus.isCompleted, isTrue);
      expect(jobStatus.isFailed, isFalse);
      expect(jobStatus.toString(), contains('job-stt-1'));

      final uploadLinks = SpeechToTextJobUploadLinksResponse.fromJson({
        'job_id': 'job-stt-1',
        'job_state': 'ready',
        'upload_urls': {'file1.wav': 'https://upload.url'},
      });
      expect(uploadLinks.uploadUrls['file1.wav'], 'https://upload.url');

      final downloadLinks = SpeechToTextJobDownloadLinksResponse.fromJson({
        'job_id': 'job-stt-1',
        'job_state': 'completed',
        'download_urls': {'file1.json': 'https://download.url'},
      });
      expect(downloadLinks.downloadUrls['file1.json'], 'https://download.url');
    });

    test('ResponsesResource createStream parses ResponseEvents', () async {
      final sseData = '''
event: response.created
data: {"id":"resp-1","type":"response.created"}

event: response.completed
data: {"id":"resp-1","type":"response.completed"}

''';
      final mockTransport = MockHttpTransport((req) async => sseResponse(ssePayload: sseData));
      final client = SarvamClient.withApiKey('key-1', transport: mockTransport);

      final req = const ResponseStreamRequest(
        model: 'sarvam-2b',
        input: 'what is ai?',
        extra: {'temperature': 0.5},
      );
      final jsonReq = req.toJson();
      expect(jsonReq['temperature'], 0.5);

      final events = await client.responses.createStream(
        req,
        options: const RequestOptions(headers: {'x-resp': '1'}),
      ).toList();

      expect(events.length, 2);
      expect(events[0].event, 'response.created');
      expect(events[0].id, 'resp-1');
      expect(events[0].type, 'response.created');
      expect(events[0].toString(), contains('resp-1'));
    });
  });

  group('TextResource & TextToSpeechResource Unit Tests', () {
    test('TextResource translate, transliterate, identifyLanguage', () async {
      final mockTransport = MockHttpTransport((req) async {
        if (req.url.path.contains('/transliterate')) {
          return jsonResponse(data: {'transliterated_text': 'namaste'});
        }
        if (req.url.path.contains('/text-lid')) {
          return jsonResponse(data: {'detected_language': 'hi-IN', 'confidence': 0.99});
        }
        return jsonResponse(data: {'translated_text': 'hello'});
      });

      final client = SarvamClient.withApiKey('key-1', transport: mockTransport);

      final trans = await client.text.translate(
        const TranslateRequest(
          input: 'namaste',
          sourceLanguageCode: LanguageCode.hiIn,
          targetLanguageCode: LanguageCode.enIn,
        ),
      );
      expect(trans.translatedText, 'hello');
      expect(trans.toString(), contains('hello'));

      final translit = await client.text.transliterate(
        const TransliterateRequest(
          input: 'नमस्ते',
          sourceLanguageCode: LanguageCode.hiIn,
          targetLanguageCode: LanguageCode.enIn,
        ),
      );
      expect(translit.transliteratedText, 'namaste');
      expect(translit.toString(), contains('namaste'));

      final lid = await client.text.identifyLanguage(
        const IdentifyLanguageRequest(input: 'नमस्ते दुनिया'),
      );
      expect(lid.detectedLanguage.value, 'hi-IN');
      expect(lid.confidence, 0.99);
      expect(lid.toString(), contains('hi-IN'));
    });

    test('TextToSpeechResource convert, stream, connect and models', () async {
      final mockTransport = MockHttpTransport((req) async {
        if (req.url.path.contains('/text-to-speech/stream')) {
          return chunkedBinaryResponse(chunks: [Uint8List.fromList([10, 20])]);
        }
        return jsonResponse(data: {
          'audios': [
            {'audio': base64Encode(Uint8List.fromList([1, 2, 3]))},
            {'audio': base64Encode(Uint8List.fromList([4, 5, 6]))},
          ]
        });
      });

      final mockWs = MockWebSocketFactory();
      final client = SarvamClient.withApiKey('key-1', transport: mockTransport, webSocketFactory: mockWs);

      final req = const TextToSpeechRequest(
        text: 'hello',
        targetLanguageCode: LanguageCode.hiIn,
        speaker: Speaker.anushka,
        model: TtsModel.bulbulV3,
        pitch: 1.0,
        pace: 1.0,
        loudness: 1.0,
        speechSampleRate: 16000,
        enablePreprocessing: true,
        outputAudioCodec: AudioCodec.wav,
      );
      final jsonReq = req.toJson();
      expect(jsonReq['speaker'], 'anushka');
      expect(jsonReq['output_audio_codec'], 'wav');

      final convertResp = await client.textToSpeech.convert(req);
      expect(convertResp.audioCount, 2);
      expect(convertResp.audioBytes, [1, 2, 3]);
      expect(convertResp.firstAudioByteLength, 3);
      expect(convertResp.firstAudioBase64, isNotNull);
      expect(convertResp.toString(), contains('audioCount: 2'));

      // TtsAudioItem string constructor
      final itemStr = TtsAudioItem.fromJson('abc');
      expect(itemStr.audio, 'abc');

      // Empty TextToSpeechResponse
      const emptyTts = TextToSpeechResponse(audios: []);
      expect(emptyTts.firstAudioBase64, isNull);
      expect(emptyTts.audioBytes, isEmpty);

      // stream
      final chunks = await client.textToSpeech.stream(req).toList();
      expect(chunks.first, [10, 20]);

      // connect
      const wsConfig = TtsStreamingConfig(
        languageCode: LanguageCode.hiIn,
        speaker: Speaker.anushka,
        model: TtsModel.bulbulV3,
        useSubprotocolAuth: true,
      );
      final session = await client.textToSpeech.connect(wsConfig);
      expect(mockWs.lastProtocols, isNotEmpty);
      await session.close();
    });
  });

  group('Realtime Sessions and Event Subtypes Unit Tests', () {
    test('SttRealtimeSession operations, ping, flush, updateConfig, end, and all event models', () async {
      final wsSession = MockWebSocketSession();
      final session = SttRealtimeSession(wsSession);

      final events = <SttRealtimeEvent>[];
      final sub = session.events.listen(events.add);

      // Inbound event types
      wsSession.pushIncoming(jsonEncode({'event': 'session_begin', 'session_id': 's-1'}));
      wsSession.pushIncoming(jsonEncode({'event': 'vad_speech_start', 'timestamp_ms': 100}));
      wsSession.pushIncoming(jsonEncode({'event': 'vad_speech_end', 'timestamp_ms': 200}));
      wsSession.pushIncoming(jsonEncode({'event': 'transcript_partial', 'text': 'he', 'language': 'hi-IN'}));
      wsSession.pushIncoming(jsonEncode({
        'event': 'transcript_final',
        'text': 'hello',
        'language': 'hi-IN',
        'language_confidence': 0.95,
        'start_s': 0.1,
        'end_s': 1.2,
      }));
      wsSession.pushIncoming(jsonEncode({'event': 'session_end', 'duration_seconds': 5.5}));
      wsSession.pushIncoming(jsonEncode({'event': 'error', 'code': 'err_bad', 'message': 'bad frame'}));
      wsSession.pushIncoming(jsonEncode({'event': 'unrecognized', 'other': 'data'}));
      wsSession.pushIncoming('not json');
      wsSession.pushIncoming(12345); // non string/map

      await pumpEventQueue();

      expect(events[0], isA<SessionBegin>());
      expect(events[0].toString(), contains('s-1'));

      expect(events[1], isA<VadSpeechStart>());
      expect(events[1].toString(), contains('100'));

      expect(events[2], isA<VadSpeechEnd>());
      expect(events[2].toString(), contains('200'));

      expect(events[3], isA<TranscriptPartial>());
      expect(events[3].toString(), contains('he'));

      expect(events[4], isA<TranscriptFinal>());
      expect(events[4].toString(), contains('hello'));

      expect(events[5], isA<SessionEnd>());
      expect(events[5].toString(), contains('5.5'));

      expect(events[6], isA<SttError>());
      expect(events[6].toString(), contains('bad frame'));

      expect(events[7], isA<UnknownSttEvent>());
      expect(events[8], isA<UnknownSttEvent>());
      expect(events[9], isA<UnknownSttEvent>());

      // Outbound calls
      session.sendAudio(Uint8List.fromList([1, 2]));
      session.updateConfig(
        mode: SttMode.transcribe,
        keyterms: ['sarvam'],
        threshold: 0.8,
        silenceDurationMs: 300,
      );
      session.flush();
      session.ping();
      session.end();
      await session.close();

      expect(wsSession.sentFrames.length, 5);
      expect(wsSession.isClosed, isTrue);
      await sub.cancel();
    });

    test('TtsStreamingSession operations, sendText, flush, ping, and all event models', () async {
      final wsSession = MockWebSocketSession();
      final session = TtsStreamingSession(wsSession);

      final events = <TtsStreamEvent>[];
      final sub = session.events.listen(events.add);

      wsSession.pushIncoming(jsonEncode({
        'type': 'audio',
        'data': {
          'audio': base64Encode(Uint8List.fromList([1, 2, 3])),
          'content_type': 'audio/wav',
          'request_id': 'r-1',
        },
      }));
      wsSession.pushIncoming(jsonEncode({
        'type': 'event',
        'data': {'event': 'completion', 'request_id': 'r-1'},
      }));
      wsSession.pushIncoming(jsonEncode({
        'type': 'error',
        'message': 'tts failed',
        'code': 'synthesize_error',
      }));
      wsSession.pushIncoming(jsonEncode({'type': 'event', 'data': {'event': 'unknown_event'}}));
      wsSession.pushIncoming(jsonEncode({'type': 'unknown_type'}));
      wsSession.pushIncoming('not json');
      wsSession.pushIncoming(999);

      await pumpEventQueue();

      expect(events[0], isA<TtsAudioChunk>());
      expect(events[0].toString(), contains('audio/wav'));

      expect(events[1], isA<TtsCompleted>());
      expect(events[1].toString(), contains('r-1'));

      expect(events[2], isA<TtsError>());
      expect(events[2].toString(), contains('tts failed'));

      expect(events[3], isA<UnknownTtsEvent>());
      expect(events[4], isA<UnknownTtsEvent>());
      expect(events[5], isA<UnknownTtsEvent>());
      expect(events[6], isA<UnknownTtsEvent>());

      // Outbound
      session.sendText('Speak this text');
      session.flush();
      session.ping();
      await session.close();

      expect(wsSession.sentFrames.length, 3);
      expect(wsSession.isClosed, isTrue);
      await sub.cancel();
    });

    test('Remaining edge-case branches across resources, models, realtime, and core', () async {
      const opts = RequestOptions(
        headers: {'X-Custom': 'val'},
        queryParams: {'extra_q': '1'},
        timeout: Duration(seconds: 15),
      );
      expect(opts.copyWith(timeout: const Duration(seconds: 5)).headers, {'X-Custom': 'val'});

      // 1. Exceptions & retry-after parsing
      final isoFuture = DateTime.now().add(const Duration(seconds: 20)).toIso8601String();
      final exHttpDate = SarvamException.fromHttpResponse(
        statusCode: 429,
        rawBody: '{"error":{"message":"slow down"}}',
        headers: {'retry-after': isoFuture},
      ) as RateLimitException;
      expect(exHttpDate.retryAfterMs, greaterThan(0));

      final resetEpoch = ((DateTime.now().millisecondsSinceEpoch ~/ 1000) + 30).toString();
      final exReset = SarvamException.fromHttpResponse(
        statusCode: 429,
        rawBody: '{"error":{"message":"slow down"}}',
        headers: {'x-ratelimit-reset': resetEpoch},
      ) as RateLimitException;
      expect(exReset.retryAfterMs, greaterThan(0));

      final streamEx = StreamException(message: List.filled(1, 'err').join());
      expect(streamEx.message, 'err');
      final decEx = DecodingException(message: List.filled(1, 'bad').join());
      expect(decEx.message, 'bad');

      // 2. HttpRequest.copyWith & Credentials & JobPoller
      final baseReq = HttpRequest(
        url: Uri.parse('https://api.sarvam.ai/test'),
        method: 'POST',
        headers: const {'a': 'b'},
      );
      final copiedReq = baseReq.copyWith();
      expect(copiedReq.url, baseReq.url);
      expect(copiedReq.method, 'POST');

      final c1 = BearerToken(List.filled(1, 'tok').join(), expiresAtEpochMs: 100);
      final c2 = BearerToken(List.filled(1, 'tok').join(), expiresAtEpochMs: 100);
      expect(c1, equals(c2));

      final cancelEx = JobCancelledException(List.filled(1, 'aborted').join());
      expect(cancelEx.toString(), contains('JobCancelledException: aborted'));

      const poller = JobPoller();
      await expectLater(
        poller.waitUntilComplete<String>(
          pollFn: () async => 'running',
          isComplete: (s) => s == 'done',
          isFailed: (s) => false,
          isCancelled: () => true,
        ),
        throwsA(isA<JobCancelledException>()),
      );
      await expectLater(
        poller.waitUntilComplete<String>(
          pollFn: () async => 'failed',
          isComplete: (s) => false,
          isFailed: (s) => s == 'failed',
        ),
        throwsA(isA<ServerException>()),
      );

      // 3. RetryMiddleware branches
      var attempts = 0;
      final retryMw = RetryMiddleware(
        maxRetries: 2,
        baseBackoffMs: 1,
        maxBackoffMs: 2,
      );
      final resp503 = await retryMw.handle(baseReq, (req) async {
        attempts++;
        if (attempts == 1) {
          return HttpResponse(
            statusCode: 503,
            headers: const {},
            bodyBytes: utf8.encode('{"error":{"code":"rate_limit_exceeded_error"}}'),
          );
        }
        if (attempts == 2) {
          return HttpResponse(
            statusCode: 503,
            headers: const {},
            bodyBytes: utf8.encode('{"code":"rate_limit_exceeded_error"}'),
          );
        }
        return HttpResponse(statusCode: 200, headers: const {}, bodyBytes: utf8.encode('{}'));
      });
      expect(resp503.statusCode, 200);

      // Non-replayable 503 rate_limit_exceeded_error on multipartCompute
      final nonReplayFile = SarvamFileInput.fromStream(
        'file',
        () => Stream.value(Uint8List.fromList([1])),
        1,
        filename: 'a.wav',
        isReplayable: false,
      );
      final nonReplayReq = HttpRequest(
        url: Uri.parse('https://api.sarvam.ai/test'),
        method: 'POST',
        headers: const {},
        files: [nonReplayFile],
        operationKind: OperationKind.multipartCompute,
      );
      await expectLater(
        retryMw.handle(nonReplayReq, (req) async {
          return HttpResponse(
            statusCode: 503,
            headers: const {},
            bodyBytes: utf8.encode('{"code":"rate_limit_exceeded_error"}'),
          );
        }),
        throwsA(isA<RateLimitException>()),
      );

      // ConnectionException on statelessPost & replayable multipartCompute
      var netAttempts = 0;
      await retryMw.handle(
        baseReq.copyWith(operationKind: OperationKind.statelessPost),
        (req) async {
          netAttempts++;
          if (netAttempts == 1) throw const ConnectionException(message: 'offline');
          return HttpResponse(statusCode: 200, headers: const {}, bodyBytes: Uint8List(0));
        },
      );
      expect(netAttempts, 2);

      var mpNetAttempts = 0;
      await retryMw.handle(
        baseReq.copyWith(operationKind: OperationKind.multipartCompute),
        (req) async {
          mpNetAttempts++;
          if (mpNetAttempts == 1) throw const ConnectionException(message: 'offline');
          return HttpResponse(statusCode: 200, headers: const {}, bodyBytes: Uint8List(0));
        },
      );
      expect(mpNetAttempts, 2);

      // 4. Models & Realtime Event branches
      expect(
        const DocAiExtractRequest(schema: '{"a":1}').toFields()['schema'],
        '{"a":1}',
      );
      expect(
        const DocAiExtractRequest(schema: ['a', 'b']).toFields()['schema'],
        '["a","b"]',
      );
      final streamCustomField = SarvamFileInput.fromStream(
        'other_field',
        () => Stream.value(Uint8List.fromList([1, 2])),
        2,
        filename: 'doc.pdf',
      );
      expect(DocAiDigitiseRequest(file: streamCustomField).getFiles().first.field, 'file');
      expect(PronunciationDictionaryListResponse.fromJson({'dictionaries': 'invalid'}).dictionaries, isEmpty);
      expect(TtsAudioItem.fromJson(123).audio, '123');
      expect(VoiceListResponse.fromJson({'voices': 'invalid'}).voices, isEmpty);
      expect(
        VoiceCloneResponse(audio: '', audioB64: base64Encode([9, 8]), requestId: 'r').audioBytes,
        [9, 8],
      );
      expect(
        const VoiceCloneResponse(audio: '', audioB64: '', requestId: 'r').audioBytes,
        isEmpty,
      );

      expect(SttRealtimeEvent.fromJson({'event': 'session_begin', 'session_id': 's1'}), isA<SessionBegin>());
      final unkStt = SttRealtimeEvent.fromJson('[1,2,3]');
      expect(unkStt, isA<UnknownSttEvent>());
      expect(unkStt.toString(), contains('UnknownSttEvent'));

      expect(
        TtsStreamEvent.fromJson({'type': 'event', 'data': {'event': 'completion'}}),
        isA<TtsCompleted>(),
      );
      final unkTts = TtsStreamEvent.fromJson('[1,2,3]');
      expect(unkTts, isA<UnknownTtsEvent>());
      expect(unkTts.toString(), contains('UnknownTtsEvent'));
      final nestedTtsErr = TtsStreamEvent.fromJson(
        jsonEncode({'type': 'error', 'data': {'message': 'nested msg'}}),
      ) as TtsError;
      expect(nestedTtsErr.message, 'nested msg');

      // 5. Resources with options & failure callbacks
      final mockWs = MockWebSocketFactory();
      final client = SarvamClient.withApiKey(
        'key-1',
        webSocketFactory: mockWs,
        transport: MockHttpTransport((req) async {
          final path = req.url.path;
          if (path.endsWith('/status') || path.endsWith('/live-status')) {
            return jsonResponse(data: {
              'job_id': 'j-fail',
              'status': 'failed',
              'job_state': 'Failed',
              'error_message': 'boom',
            });
          }
          if (path.endsWith('/v2/models')) {
            return jsonResponse(data: {'data': <dynamic>[]});
          }
          if (path.contains('/voices/')) {
            return jsonResponse(data: {
              'data': {'voice_id': 'v1', 'status': 'ready'},
              'audio': base64Encode([1, 2]),
              'request_id': 'r1',
            });
          }
          if (path.contains('/text-to-speech/stream') || path.contains('/voices/clone/stream')) {
            return chunkedBinaryResponse(chunks: [Uint8List.fromList([1])]);
          }
          return jsonResponse(data: {
            'job_id': 'j-fail',
            'status': 'queued',
            'job_state': 'Accepted',
            'translated_text': 'hi',
            'transliterated_text': 'hi',
            'detected_language': 'hi-IN',
            'audios': [base64Encode([1])],
            'voices': <dynamic>[],
          });
        }),
      );

      // Chat
      await client.chat.listModels(options: opts);
      await client.chat.getModel('m1', options: opts);
      final chatSession = client.chat.createSession(sessionId: 'sess-1');
      await chatSession.completions(
        const ChatCompletionRequest(model: ChatModel.sarvamM, messages: []),
        options: opts,
      );

      // DocAI
      await client.docAi.digitise(const DocAiDigitiseRequest(uploadIds: 'u1'), options: opts);
      await client.docAi.extract(const DocAiExtractRequest(uploadIds: 'u1'), options: opts);
      await client.docAi.createUploadUrl(const DocAiPresignUploadRequest(fileName: 'f.pdf'), options: opts);
      await client.docAi.getStatus('j1', options: opts);
      await client.docAi.getResults('j1', options: opts);
      await client.docAi.getDownloadUrl('j1', options: opts);
      await expectLater(
        client.docAi.digitiseAndWait(
          const DocAiDigitiseRequest(uploadIds: 'u1'),
          pollInterval: const Duration(milliseconds: 1),
          options: opts,
        ),
        throwsA(isA<ServerException>()),
      );
      await expectLater(
        client.docAi.extractAndWait(
          const DocAiExtractRequest(uploadIds: 'u1'),
          pollInterval: const Duration(milliseconds: 1),
          options: opts,
        ),
        throwsA(isA<ServerException>()),
      );

      // DocumentTranslation
      await client.documentTranslation.create(
        const DocumentTranslationCreateRequest(
          sourceLanguageCode: LanguageCode.enIn,
          targetLanguageCodes: [LanguageCode.hiIn],
        ),
        options: opts,
      );
      await client.documentTranslation.start('j1', options: opts);
      await client.documentTranslation.getLiveStatus('j1', options: opts);
      await client.documentTranslation.triggerExport('j1', options: opts);
      await client.documentTranslation.getExportStatus('j1', options: opts);
      await expectLater(
        client.documentTranslation.waitUntilComplete(
          'j1',
          pollInterval: const Duration(milliseconds: 1),
          options: opts,
        ),
        throwsA(isA<ServerException>()),
      );

      // Dubbing
      await client.dubbing.create(
        const DubbingCreateRequest(sourceLanguageCode: LanguageCode.enIn, targetLanguageCodes: [LanguageCode.hiIn]),
        options: opts,
      );
      await client.dubbing.start('j1', options: opts);
      await client.dubbing.getLiveStatus('j1', options: opts);
      await client.dubbing.getExportStatus('j1', options: opts);
      await expectLater(
        client.dubbing.waitUntilComplete(
          'j1',
          pollInterval: const Duration(milliseconds: 1),
          options: opts,
        ),
        throwsA(isA<ServerException>()),
      );

      // PronunciationDictionary
      final customBytesFile = SarvamFileInput.fromBytes(
        'other',
        Uint8List.fromList([1, 2]),
        filename: 'dict.pls',
      );
      await client.pronunciationDictionary.create(customBytesFile, options: opts);
      await client.pronunciationDictionary.update('d1', customBytesFile, options: opts);
      await client.pronunciationDictionary.get('d1', options: opts);
      await client.pronunciationDictionary.delete('d1', options: opts);

      // SpeechToTextJob
      await client.speechToTextJob.initialise(
        const SpeechToTextJobInitRequest(jobParameters: <String, dynamic>{}),
        options: opts,
      );
      await client.speechToTextJob.getUploadLinks('j1', ['a.wav'], options: opts);
      await client.speechToTextJob.start('j1', ptuId: 'ptu-1', options: opts);
      await client.speechToTextJob.getStatus('j1', options: opts);
      await client.speechToTextJob.getDownloadLinks('j1', ['a.json'], options: opts);
      await expectLater(
        client.speechToTextJob.waitUntilComplete(
          'j1',
          pollInterval: const Duration(milliseconds: 1),
          options: opts,
        ),
        throwsA(isA<ServerException>()),
      );

      // Text & TextToSpeech
      await client.text.transliterate(
        const TransliterateRequest(
          input: 'a',
          sourceLanguageCode: LanguageCode.enIn,
          targetLanguageCode: LanguageCode.hiIn,
        ),
        options: opts,
      );
      await client.text.identifyLanguage(const IdentifyLanguageRequest(input: 'a'), options: opts);
      const ttsReq = TextToSpeechRequest(text: 'a', targetLanguageCode: LanguageCode.hiIn);
      await client.textToSpeech.convert(ttsReq, options: opts);
      await client.textToSpeech.stream(ttsReq, options: opts).toList();
      final ttsWs = await client.textToSpeech.connect(
        const TtsStreamingConfig(languageCode: LanguageCode.hiIn, speaker: Speaker.anushka),
        options: opts,
      );
      await ttsWs.close();

      // VoiceCloning
      await client.voiceCloning.listVoices(options: opts);
      await client.voiceCloning.createVoice(
        VoiceCreateRequest(file: customBytesFile, name: 'v', language: LanguageCode.hiIn),
        options: opts,
      );
      await client.voiceCloning.createVoice(
        VoiceCreateRequest(file: streamCustomField, name: 'v', language: LanguageCode.hiIn),
        options: opts,
      );
      await client.voiceCloning.getVoice('v1', options: opts);
      await client.voiceCloning.deleteVoice('v1', options: opts);
      await client.voiceCloning.convert(
        VoiceCloneRequest(text: 'hi', languageCode: LanguageCode.hiIn, refAudio: customBytesFile),
        options: opts,
      );
      await client.voiceCloning.convert(
        VoiceCloneRequest(text: 'hi', languageCode: LanguageCode.hiIn, refAudio: streamCustomField),
        options: opts,
      );
      await client.voiceCloning.stream(
        VoiceCloneRequest(text: 'hi', languageCode: LanguageCode.hiIn, refAudio: customBytesFile),
        options: opts,
      ).toList();
      await client.voiceCloning.stream(
        VoiceCloneRequest(text: 'hi', languageCode: LanguageCode.hiIn, refAudio: streamCustomField),
        options: opts,
      ).toList();
      final vcWs = await client.voiceCloning.connect(
        const VoiceCloningStreamingConfig(targetLanguageCode: LanguageCode.hiIn),
        options: opts,
      );
      await vcWs.close();
    });
  });
}
