import 'dart:convert';
import 'dart:typed_data';

import 'package:sarvam/sarvam.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('JobPoller Unit Tests', () {
    test('waitUntilComplete returns value when completed', () async {
      final clock = MockClock();
      final poller = JobPoller(clock: clock);
      var polls = 0;

      final result = await poller.waitUntilComplete<String>(
        pollFn: () async {
          polls++;
          if (polls < 3) return 'pending';
          return 'completed';
        },
        isComplete: (status) => status == 'completed',
        pollInterval: const Duration(seconds: 1),
      );

      expect(result, 'completed');
      expect(polls, 3);
      expect(clock.recordedSleeps, [
        const Duration(seconds: 1),
        const Duration(seconds: 1),
      ]);
    });

    test('waitUntilComplete throws ServerException on failure', () async {
      final clock = MockClock();
      final poller = JobPoller(clock: clock);

      expect(
        () => poller.waitUntilComplete<String>(
          pollFn: () async => 'failed',
          isComplete: (status) => status == 'completed',
          isFailed: (status) => status == 'failed',
          failureMessage: (status) => 'Custom job failed',
        ),
        throwsA(isA<ServerException>().having(
          (e) => e.message,
          'message',
          'Custom job failed',
        )),
      );
    });

    test('waitUntilComplete throws TimeoutException when timeout exceeded', () async {
      final clock = MockClock();
      final poller = JobPoller(clock: clock);

      expect(
        () => poller.waitUntilComplete<String>(
          pollFn: () async => 'running',
          isComplete: (status) => status == 'completed',
          pollInterval: const Duration(seconds: 5),
          timeout: const Duration(seconds: 10),
        ),
        throwsA(isA<TimeoutException>().having(
          (e) => e.message,
          'message',
          contains('timed out'),
        )),
      );
    });

    test('waitUntilComplete throws JobCancelledException when cancelled', () async {
      final clock = MockClock();
      final poller = JobPoller(clock: clock);
      final cancelToken = CancellationToken();
      cancelToken.cancel();

      expect(
        () => poller.waitUntilComplete<String>(
          pollFn: () async => 'running',
          isComplete: (status) => status == 'completed',
          cancellationToken: cancelToken,
        ),
        throwsA(isA<JobCancelledException>()),
      );
    });
  });

  group('VoiceCloningResource Unit Tests', () {
    test('listVoices calls GET /voices with idempotent kind', () async {
      final transport = MockHttpTransport((req) async {
        expect(req.method, 'GET');
        expect(req.url.path, '/voices');
        expect(req.operationKind, OperationKind.idempotent);
        return jsonResponse(data: {
          'voices': [
            {
              'voice_id': 'svc-123',
              'name': 'Test Voice',
              'status': 'saved',
            }
          ]
        });
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('test-key'),
        transport: transport,
      );

      final res = await client.voiceCloning.listVoices();
      expect(res.voices.length, 1);
      expect(res.voices.first.voiceId, 'svc-123');
      expect(res.voices.first.name, 'Test Voice');
    });

    test('createVoice calls POST /voices/create with multipart jobCreate', () async {
      final transport = MockHttpTransport((req) async {
        expect(req.method, 'POST');
        expect(req.url.path, '/voices/create');
        expect(req.operationKind, OperationKind.jobCreate);
        expect(req.files?.length, 1);
        expect(req.files?.first.field, 'file');
        expect(req.fields?['name'], 'New Voice');
        expect(req.fields?['language'], 'hi-IN');
        return jsonResponse(
          statusCode: 201,
          data: {
            'status': 'success',
            'data': {
              'voice_id': 'svc-new-1',
              'status': 'saved',
              'reference_text': 'Audio transcript',
            }
          },
        );
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('test-key'),
        transport: transport,
      );

      final res = await client.voiceCloning.createVoice(
        VoiceCreateRequest(
          file: SarvamFileInput.fromBytes(
            'file',
            Uint8List.fromList([1, 2, 3, 4]),
            filename: 'audio.wav',
            contentType: 'audio/wav',
          ),
          name: 'New Voice',
          language: LanguageCode.hiIn,
        ),
      );

      expect(res.voiceId, 'svc-new-1');
      expect(res.status, 'saved');
      expect(res.referenceText, 'Audio transcript');
    });

    test('getVoice and deleteVoice operate with idempotent kind', () async {
      final transport = MockHttpTransport((req) async {
        if (req.method == 'GET') {
          expect(req.url.path, '/voices/svc-123');
          expect(req.operationKind, OperationKind.idempotent);
          return jsonResponse(data: {
            'voice_id': 'svc-123',
            'name': 'My Voice',
            'status': 'saved',
          });
        } else {
          expect(req.method, 'DELETE');
          expect(req.url.path, '/voices/delete/svc-123');
          expect(req.operationKind, OperationKind.idempotent);
          return jsonResponse(data: {'status': 'deleted'});
        }
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('test-key'),
        transport: transport,
      );

      final voice = await client.voiceCloning.getVoice('svc-123');
      expect(voice.voiceId, 'svc-123');
      expect(voice.name, 'My Voice');

      final deleteRes = await client.voiceCloning.deleteVoice('svc-123');
      expect(deleteRes['status'], 'deleted');
    });

    test('convert calls POST /voices/clone and decodes Base64 audioBytes', () async {
      final originalAudioBytes = Uint8List.fromList([10, 20, 30, 40, 50]);
      final base64Audio = base64Encode(originalAudioBytes);

      final transport = MockHttpTransport((req) async {
        expect(req.method, 'POST');
        expect(req.url.path, '/voices/clone');
        expect(req.operationKind, OperationKind.multipartCompute);
        expect(req.fields?['text'], 'Namaste');
        expect(req.fields?['language_code'], 'hi-IN');
        expect(req.fields?['voice_id'], 'svc-123');

        return jsonResponse(data: {
          'audio': base64Audio,
          'audio_b64': base64Audio,
          'request_id': 'req_clone_001',
          'audio_duration': 1.5,
        });
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('test-key'),
        transport: transport,
      );

      final res = await client.voiceCloning.convert(
        const VoiceCloneRequest(
          text: 'Namaste',
          languageCode: LanguageCode.hiIn,
          voiceId: 'svc-123',
        ),
      );

      expect(res.requestId, 'req_clone_001');
      expect(res.audioDuration, 1.5);
      expect(res.audioBytes, originalAudioBytes);
    });

    test('stream calls POST /voices/clone/stream with chunked bytes', () async {
      final chunk1 = Uint8List.fromList([1, 2, 3]);
      final chunk2 = Uint8List.fromList([4, 5, 6]);

      final transport = MockHttpTransport((req) async {
        expect(req.method, 'POST');
        expect(req.url.path, '/voices/clone/stream');
        expect(req.isStreaming, isTrue);
        return chunkedBinaryResponse(chunks: [chunk1, chunk2]);
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('test-key'),
        transport: transport,
      );

      final chunks = await client.voiceCloning.stream(
        const VoiceCloneRequest(
          text: 'Hello',
          languageCode: LanguageCode.enIn,
          voiceId: 'svc-123',
        ),
      ).toList();

      expect(chunks.length, 2);
      expect(chunks[0], chunk1);
      expect(chunks[1], chunk2);
    });

    test('connect establishes WS session and sends initial config frame', () async {
      final wsFactory = MockWebSocketFactory();
      final client = SarvamClient(
        auth: ApiKeyAuth('test-key'),
        transport: MockHttpTransport((req) async => jsonResponse(data: {})),
        webSocketFactory: wsFactory,
      );

      final session = await client.voiceCloning.connect(
        const VoiceCloningStreamingConfig(
          targetLanguageCode: LanguageCode.hiIn,
          voiceId: 'svc-123',
        ),
      );

      expect(wsFactory.lastUri?.path, '/voices/clone/ws');
      expect(wsFactory.lastUri?.queryParameters['send_completion_event'], 'true');
      expect(wsFactory.session.sentFrames.length, 1);

      final sentPayload = jsonDecode(wsFactory.session.sentFrames.first as String)
          as Map<String, dynamic>;
      expect(sentPayload['type'], 'config');
      expect(sentPayload['data']['target_language_code'], 'hi-IN');
      expect(sentPayload['data']['voice_id'], 'svc-123');

      // Send text and flush through session
      session.sendText('Kaisa chal raha hai?');
      expect(wsFactory.session.sentFrames.length, 2);
      final textPayload = jsonDecode(wsFactory.session.sentFrames[1] as String)
          as Map<String, dynamic>;
      expect(textPayload['type'], 'text');
      expect(textPayload['data']['text'], 'Kaisa chal raha hai?');

      await session.close();
      expect(wsFactory.session.isClosed, isTrue);
    });
  });

  group('DocAiResource Unit Tests', () {
    test('digitise accepts files array with OperationKind.jobCreate', () async {
      final transport = MockHttpTransport((req) async {
        expect(req.method, 'POST');
        expect(req.url.path, '/doc-ai/v1/job/digitise');
        expect(req.operationKind, OperationKind.jobCreate);
        expect(req.files?.length, 2);
        expect(req.files?.every((f) => f.field == 'file'), isTrue);
        expect(req.fields?['language'], 'hi-IN');

        return jsonResponse(
          statusCode: 201,
          data: {
            'job_id': 'job_digitise_1',
            'status': 'pending',
          },
        );
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('test-key'),
        transport: transport,
      );

      final res = await client.docAi.digitise(
        DocAiDigitiseRequest(
          file: [
            SarvamFileInput.fromBytes('file', Uint8List.fromList([1, 2]), filename: 'doc1.pdf'),
            SarvamFileInput.fromBytes('file', Uint8List.fromList([3, 4]), filename: 'doc2.pdf'),
          ],
          language: LanguageCode.hiIn,
        ),
      );

      expect(res.jobId, 'job_digitise_1');
      expect(res.status, 'pending');
    });

    test('extract auto-serializes schema Map into JSON string multipart field', () async {
      final transport = MockHttpTransport((req) async {
        expect(req.method, 'POST');
        expect(req.url.path, '/doc-ai/v1/job/extract');
        expect(req.operationKind, OperationKind.jobCreate);
        expect(req.files?.length, 1);
        expect(req.files?.first.field, 'file');
        expect(req.fields?['schema'], jsonEncode({'type': 'object', 'properties': {'invoice': {'type': 'string'}}}));

        return jsonResponse(
          statusCode: 201,
          data: {
            'job_id': 'job_extract_1',
            'status': 'pending',
          },
        );
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('test-key'),
        transport: transport,
      );

      final res = await client.docAi.extract(
        DocAiExtractRequest(
          file: SarvamFileInput.fromBytes('file', Uint8List.fromList([1]), filename: 'inv.pdf'),
          schema: {
            'type': 'object',
            'properties': {'invoice': {'type': 'string'}}
          },
        ),
      );

      expect(res.jobId, 'job_extract_1');
      expect(res.status, 'pending');
    });

    test('getStatus, getResults, getDownloadUrl, and createUploadUrl work correctly', () async {
      final transport = MockHttpTransport((req) async {
        if (req.url.path == '/doc-ai/v1/job/upload') {
          expect(req.operationKind, OperationKind.statelessPost);
          return jsonResponse(
            statusCode: 201,
            data: {
              'upload_id': 'upl_123',
              'method': 'PUT',
              'url': 'https://upload.blob.core.windows.net/test',
              'expires_at': '2026-10-17T00:00:00Z',
            },
          );
        } else if (req.url.path.endsWith('/status')) {
          expect(req.operationKind, OperationKind.idempotent);
          return jsonResponse(data: {
            'job_id': 'job_123',
            'status': 'completed',
            'pipeline': 'digitise',
          });
        } else if (req.url.path.endsWith('/results')) {
          expect(req.operationKind, OperationKind.idempotent);
          return jsonResponse(data: {
            'type': 'digitise',
            'job_id': 'job_123',
            'status': 'completed',
            'documents': [
              {'page': 1, 'text': 'Hello Document'}
            ],
          });
        } else if (req.url.path.endsWith('/download-url')) {
          return jsonResponse(data: {
            'method': 'GET',
            'url': 'https://download.blob.core.windows.net/test',
          });
        }
        throw UnimplementedError(req.url.path);
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('test-key'),
        transport: transport,
      );

      final uploadUrl = await client.docAi.createUploadUrl(
        const DocAiPresignUploadRequest(fileName: 'test.pdf'),
      );
      expect(uploadUrl.uploadId, 'upl_123');

      final status = await client.docAi.getStatus('job_123');
      expect(status.isCompleted, isTrue);

      final results = await client.docAi.getResults('job_123');
      expect(results.type, 'digitise');
      expect(results.documents?.length, 1);

      final download = await client.docAi.getDownloadUrl('job_123');
      expect(download.url, contains('download.blob'));
    });

    test('digitiseAndWait and extractAndWait poll until completion', () async {
      var pollCount = 0;
      final clock = MockClock();
      final transport = MockHttpTransport((req) async {
        if (req.url.path == '/doc-ai/v1/job/digitise') {
          return jsonResponse(
            statusCode: 201,
            data: {'job_id': 'job_auto_1', 'status': 'pending'},
          );
        } else if (req.url.path.endsWith('/status')) {
          pollCount++;
          return jsonResponse(data: {
            'job_id': 'job_auto_1',
            'status': pollCount >= 2 ? 'completed' : 'pending',
          });
        } else if (req.url.path.endsWith('/results')) {
          return jsonResponse(data: {
            'type': 'digitise',
            'job_id': 'job_auto_1',
            'status': 'completed',
            'documents': [{'text': 'Extracted content'}],
          });
        }
        throw UnimplementedError(req.url.path);
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('test-key'),
        transport: transport,
        clock: clock,
      );

      final res = await client.docAi.digitiseAndWait(
        DocAiDigitiseRequest(
          file: SarvamFileInput.fromBytes('file', Uint8List.fromList([1, 2]), filename: 'doc.pdf'),
        ),
      );

      expect(res.status, 'completed');
      expect(pollCount, 2);
    });
  });

  group('PronunciationDictionaryResource Unit Tests', () {
    test('CRUD operations execute correctly', () async {
      final transport = MockHttpTransport((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/dict_1')) {
          return jsonResponse(data: {
            'dict_id': 'dict_1',
            'name': 'Medical terms',
            'status': 'active',
          });
        } else if (req.method == 'GET') {
          return jsonResponse(data: {
            'dictionaries': [
              {'dict_id': 'dict_1', 'name': 'Medical terms'},
            ]
          });
        } else if (req.method == 'POST') {
          expect(req.operationKind, OperationKind.multipartCompute);
          expect(req.files?.first.field, 'file');
          return jsonResponse(data: {
            'dict_id': 'dict_1',
            'status': 'created',
          });
        } else if (req.method == 'PUT') {
          expect(req.url.queryParameters['dict_id'], 'dict_1');
          return jsonResponse(data: {
            'dict_id': 'dict_1',
            'status': 'updated',
          });
        } else if (req.method == 'DELETE') {
          expect(req.url.queryParameters['dict_id'], 'dict_1');
          return jsonResponse(data: {'status': 'deleted'});
        }
        throw UnimplementedError();
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('test-key'),
        transport: transport,
      );

      final list = await client.pronunciationDictionary.list();
      expect(list.dictionaries.length, 1);

      final file = SarvamFileInput.fromBytes('file', Uint8List.fromList([1]), filename: 'dict.pls');
      final created = await client.pronunciationDictionary.create(file);
      expect(created.dictId, 'dict_1');

      final updated = await client.pronunciationDictionary.update('dict_1', file);
      expect(updated.status, 'updated');

      final item = await client.pronunciationDictionary.get('dict_1');
      expect(item.name, 'Medical terms');

      final deleted = await client.pronunciationDictionary.delete('dict_1');
      expect(deleted['status'], 'deleted');
    });
  });

  group('SpeechToTextJobResource & SpeechToTextTranslateJobResource Unit Tests', () {
    test('SpeechToTextJobResource full lifecycle and waitUntilComplete', () async {
      var pollCount = 0;
      final clock = MockClock();
      final transport = MockHttpTransport((req) async {
        if (req.method == 'POST' && req.url.path == '/speech-to-text/job/v1') {
          expect(req.operationKind, OperationKind.jobCreate);
          return jsonResponse(data: {
            'job_id': 'stt_job_1',
            'job_state': 'Accepted',
          });
        } else if (req.url.path == '/speech-to-text/job/v1/upload-files') {
          return jsonResponse(data: {
            'job_id': 'stt_job_1',
            'job_state': 'Accepted',
            'upload_urls': {'audio.wav': {'url': 'https://upload.blob'}},
          });
        } else if (req.url.path.endsWith('/start')) {
          return jsonResponse(data: {
            'job_id': 'stt_job_1',
            'job_state': 'Pending',
          });
        } else if (req.url.path.endsWith('/status')) {
          pollCount++;
          return jsonResponse(data: {
            'job_id': 'stt_job_1',
            'job_state': pollCount >= 2 ? 'Completed' : 'Running',
          });
        } else if (req.url.path == '/speech-to-text/job/v1/download-files') {
          return jsonResponse(data: {
            'job_id': 'stt_job_1',
            'job_state': 'Completed',
            'download_urls': {'0.json': {'url': 'https://download.blob'}},
          });
        }
        throw UnimplementedError(req.url.path);
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('test-key'),
        transport: transport,
        clock: clock,
      );

      final init = await client.speechToTextJob.initialise(
        const SpeechToTextJobInitRequest(jobParameters: {'language_code': 'hi-IN'}),
      );
      expect(init.jobId, 'stt_job_1');

      final upload = await client.speechToTextJob.getUploadLinks('stt_job_1', ['audio.wav']);
      expect(upload.uploadUrls.containsKey('audio.wav'), isTrue);

      final start = await client.speechToTextJob.start('stt_job_1');
      expect(start.jobState, 'Pending');

      final completed = await client.speechToTextJob.waitUntilComplete('stt_job_1');
      expect(completed.isCompleted, isTrue);
      expect(pollCount, 2);

      final download = await client.speechToTextJob.getDownloadLinks('stt_job_1', ['0.json']);
      expect(download.downloadUrls.containsKey('0.json'), isTrue);
    });

    test('SpeechToTextTranslateJobResource targets /speech-to-text-translate/job/v1', () async {
      final transport = MockHttpTransport((req) async {
        expect(req.url.path, '/speech-to-text-translate/job/v1');
        return jsonResponse(data: {
          'job_id': 'stt_trans_1',
          'job_state': 'Accepted',
        });
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('test-key'),
        transport: transport,
      );

      final res = await client.speechToTextTranslateJob.initialise(
        const SpeechToTextJobInitRequest(jobParameters: {'target_language_code': 'en-IN'}),
      );
      expect(res.jobId, 'stt_trans_1');
    });
  });

  group('DocumentTranslationResource Unit Tests', () {
    test('DocumentTranslation lifecycle and export', () async {
      var pollCount = 0;
      final clock = MockClock();
      final transport = MockHttpTransport((req) async {
        if (req.method == 'POST' && req.url.path == '/translate/document/jobs') {
          expect(req.operationKind, OperationKind.jobCreate);
          return jsonResponse(
            statusCode: 201,
            data: {'job_id': 'doc_job_1', 'job_state': 'Accepted'},
          );
        } else if (req.url.path.endsWith('/start')) {
          return jsonResponse(data: {'job_id': 'doc_job_1', 'job_state': 'Running'});
        } else if (req.url.path.endsWith('/live-status')) {
          pollCount++;
          return jsonResponse(data: {
            'job_id': 'doc_job_1',
            'job_name': 'Contract.pdf',
            'job_state': pollCount >= 2 ? 'Completed' : 'Running',
            'progress': pollCount >= 2 ? 100 : 50,
          });
        } else if (req.url.path.endsWith('/export')) {
          return jsonResponse(data: {'export_id': 'exp_1', 'status': 'Pending'});
        } else if (req.url.path.endsWith('/export/status')) {
          return jsonResponse(data: {
            'export_id': 'exp_1',
            'job_id': 'doc_job_1',
            'target_language_code': 'hi-IN',
            'format': 'pdf',
            'export_state': 'Completed',
            'download_url': 'https://download.blob.pdf',
          });
        }
        throw UnimplementedError(req.url.path);
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('test-key'),
        transport: transport,
        clock: clock,
      );

      final createRes = await client.documentTranslation.create(
        const DocumentTranslationCreateRequest(
          sourceLanguageCode: LanguageCode.enIn,
          targetLanguageCodes: [LanguageCode.hiIn],
          fileUrl: 'https://files.blob/doc.pdf',
        ),
      );
      expect(createRes.jobId, 'doc_job_1');

      final startRes = await client.documentTranslation.start('doc_job_1');
      expect(startRes.jobState, 'Running');

      final liveStatus = await client.documentTranslation.waitUntilComplete('doc_job_1');
      expect(liveStatus.isCompleted, isTrue);
      expect(liveStatus.progress, 100);

      final exportRes = await client.documentTranslation.triggerExport('doc_job_1', lang: 'hi-IN', format: 'pdf');
      expect(exportRes.exportId, 'exp_1');

      final exportStatus = await client.documentTranslation.getExportStatus('doc_job_1', exportId: 'exp_1');
      expect(exportStatus.isCompleted, isTrue);
      expect(exportStatus.downloadUrl, 'https://download.blob.pdf');
    });
  });

  group('DubbingResource Unit Tests', () {
    test('DubbingResource routes to dubbing host and maps parameters', () async {
      var pollCount = 0;
      final clock = MockClock();
      final transport = MockHttpTransport((req) async {
        // Crucial verification: host URL starts with dubbingBaseUrl!
        expect(req.url.toString(), startsWith('https://api.sarvam.ai/dubbing'));

        if (req.method == 'POST' && req.url.path == '/dubbing/jobs') {
          expect(req.operationKind, OperationKind.jobCreate);
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          // Verification: sourceLanguageCode mapped to src_lang and targetLanguageCodes to target_langs!
          expect(body['src_lang'], 'en-IN');
          expect(body['target_langs'], ['hi-IN', 'ta-IN']);

          return jsonResponse(data: {
            'status': 'success',
            'data': {'job_id': 'dub_123', 'status': 'queued'},
          });
        } else if (req.url.path.endsWith('/start')) {
          return jsonResponse(data: {
            'status': 'success',
            'data': {'job_id': 'dub_123', 'status': 'in_progress'},
          });
        } else if (req.url.path.endsWith('/live-status')) {
          pollCount++;
          return jsonResponse(data: {
            'status': 'success',
            'data': {
              'job_id': 'dub_123',
              'status': pollCount >= 2 ? 'completed' : 'in_progress',
              'progress': pollCount >= 2 ? 100 : 40,
            },
          });
        } else if (req.url.path.endsWith('/export-status')) {
          return jsonResponse(data: {
            'status': 'success',
            'data': {'exports': <Map<String, dynamic>>[]},
          });
        }
        throw UnimplementedError(req.url.path);
      });

      final client = SarvamClient(
        auth: ApiKeyAuth('test-key'),
        transport: transport,
        clock: clock,
      );

      final createRes = await client.dubbing.create(
        const DubbingCreateRequest(
          sourceLanguageCode: LanguageCode.enIn,
          targetLanguageCodes: [LanguageCode.hiIn, LanguageCode.taIn],
        ),
      );
      expect(createRes.jobId, 'dub_123');

      final startRes = await client.dubbing.start('dub_123');
      expect(startRes.status, 'in_progress');

      final completed = await client.dubbing.waitUntilComplete('dub_123');
      expect(completed.isCompleted, isTrue);
      expect(completed.progress, 100);

      final exportStatus = await client.dubbing.getExportStatus('dub_123');
      expect(exportStatus.status, 'success');
    });
  });
}
