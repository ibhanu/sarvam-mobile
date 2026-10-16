import Foundation
import Testing
@testable import Sarvam

@Suite("SDK Models Roundtrip & Property Tests")
struct ModelsTests {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - ChatModels
    @Test("ChatModels initializers and Codable")
    func testChatModels() throws {
        let msg = ChatMessage(role: "user", content: "Hello")
        #expect(msg.role == "user")
        #expect(msg.content == "Hello")
        let msgData = try encoder.encode(msg)
        let decodedMsg = try decoder.decode(ChatMessage.self, from: msgData)
        #expect(decodedMsg == msg)

        let req = ChatCompletionRequest(
            model: .sarvam105b,
            messages: [msg],
            stream: true,
            temperature: 0.7,
            maxTokens: 100,
            topP: 0.9
        )
        #expect(req.model == .sarvam105b)
        #expect(req.messages.count == 1)
        #expect(req.stream == true)
        #expect(req.temperature == 0.7)
        #expect(req.maxTokens == 100)
        #expect(req.topP == 0.9)
        let reqData = try encoder.encode(req)
        let decodedReq = try decoder.decode(ChatCompletionRequest.self, from: reqData)
        #expect(decodedReq == req)

        let delta = ChatDelta(role: "assistant", content: "Hi")
        #expect(delta.role == "assistant")
        #expect(delta.content == "Hi")
        let deltaData = try encoder.encode(delta)
        let decodedDelta = try decoder.decode(ChatDelta.self, from: deltaData)
        #expect(decodedDelta == delta)

        let choice = ChatChoice(index: 0, message: msg, delta: delta, finishReason: "stop")
        #expect(choice.index == 0)
        #expect(choice.message == msg)
        #expect(choice.delta == delta)
        #expect(choice.finishReason == "stop")
        let choiceData = try encoder.encode(choice)
        let decodedChoice = try decoder.decode(ChatChoice.self, from: choiceData)
        #expect(decodedChoice == choice)

        let usage = ChatUsage(promptTokens: 10, completionTokens: 20, totalTokens: 30)
        #expect(usage.promptTokens == 10)
        #expect(usage.completionTokens == 20)
        #expect(usage.totalTokens == 30)
        let usageData = try encoder.encode(usage)
        let decodedUsage = try decoder.decode(ChatUsage.self, from: usageData)
        #expect(decodedUsage == usage)

        let resp = ChatCompletionResponse(id: "chat-1", choices: [choice], usage: usage)
        #expect(resp.id == "chat-1")
        #expect(resp.choices.count == 1)
        #expect(resp.usage == usage)
        let respData = try encoder.encode(resp)
        let decodedResp = try decoder.decode(ChatCompletionResponse.self, from: respData)
        #expect(decodedResp == resp)

        let chunk = ChatCompletionChunk(id: "chunk-1", choices: [choice], usage: usage)
        #expect(chunk.firstDeltaContent == "Hi")
        let chunkData = try encoder.encode(chunk)
        let decodedChunk = try decoder.decode(ChatCompletionChunk.self, from: chunkData)
        #expect(decodedChunk == chunk)

        let emptyChunk = ChatCompletionChunk(id: "chunk-empty", choices: [], usage: nil)
        #expect(emptyChunk.firstDeltaContent == nil)

        let modelInfo = ChatModelInfo(id: "model-1")
        #expect(modelInfo.id == "model-1")
        let modelListData = try encoder.encode(ChatModelListResponse(models: [modelInfo]))
        let decodedModelList = try decoder.decode(ChatModelListResponse.self, from: modelListData)
        #expect(decodedModelList.models == [modelInfo])
    }

    // MARK: - DocAiModels
    @Test("DocAiModels initializers and Codable")
    func testDocAiModels() throws {
        let startJob = DocAIStartJobResponse(jobId: "job-1", status: "running", runId: "run-1")
        #expect(startJob.jobId == "job-1")
        #expect(startJob.status == "running")
        #expect(startJob.runId == "run-1")
        let startData = try encoder.encode(startJob)
        let decodedStart = try decoder.decode(DocAIStartJobResponse.self, from: startData)
        #expect(decodedStart == startJob)

        let presignReq = DocAIPresignUploadRequest(contentType: "application/pdf")
        #expect(presignReq.contentType == "application/pdf")
        let presignReqData = try encoder.encode(presignReq)
        let decodedPresignReq = try decoder.decode(DocAIPresignUploadRequest.self, from: presignReqData)
        #expect(decodedPresignReq == presignReq)

        let presignResp = DocAIPresignUploadResponse(
            uploadId: "up-1",
            method: "PUT",
            url: "https://upload.url",
            headers: ["x-ms-blob": "true"],
            expiresAt: "2026-10-16T12:00:00Z"
        )
        #expect(presignResp.uploadId == "up-1")
        #expect(presignResp.method == "PUT")
        #expect(presignResp.url == "https://upload.url")
        #expect(presignResp.headers?["x-ms-blob"] == "true")
        #expect(presignResp.expiresAt == "2026-10-16T12:00:00Z")
        let presignRespData = try encoder.encode(presignResp)
        let decodedPresignResp = try decoder.decode(DocAIPresignUploadResponse.self, from: presignRespData)
        #expect(decodedPresignResp == presignResp)

        let usage = DocAIUsage(numPages: 5, numCharacters: 1200)
        #expect(usage.numPages == 5)
        #expect(usage.numCharacters == 1200)

        let statusResp = DocAIJobStatusResponse(
            jobId: "job-1",
            status: "completed",
            pipeline: "digitise",
            usage: usage,
            createdAt: "2026-10-16T10:00:00Z",
            updatedAt: "2026-10-16T10:05:00Z"
        )
        #expect(statusResp.jobId == "job-1")
        #expect(statusResp.pipeline == "digitise")
        let statusData = try encoder.encode(statusResp)
        let decodedStatus = try decoder.decode(DocAIJobStatusResponse.self, from: statusData)
        #expect(decodedStatus == statusResp)

        let downloadResp = DocAIDownloadURLResponse(
            method: "GET",
            url: "https://download.url",
            headers: ["X-Key": "val"],
            expiresAt: "2026-10-16T13:00:00Z"
        )
        #expect(downloadResp.url == "https://download.url")
        let downloadData = try encoder.encode(downloadResp)
        let decodedDownload = try decoder.decode(DocAIDownloadURLResponse.self, from: downloadData)
        #expect(decodedDownload == downloadResp)

        // DocAIJobResultsResponse
        let resultsResp = DocAIJobResultsResponse(rawBody: "{\"pages\":[1,2]}")
        #expect(resultsResp.rawBody == "{\"pages\":[1,2]}")
        let resultsData = try encoder.encode(resultsResp)
        let decodedResults = try decoder.decode(DocAIJobResultsResponse.self, from: resultsData)
        #expect(!decodedResults.rawBody.isEmpty)

        // Test decoding DocAIJobResultsResponse from JSON object
        let dictJson = "{\"field\":\"value\"}".data(using: .utf8)!
        let decodedFromDict = try decoder.decode(DocAIJobResultsResponse.self, from: dictJson)
        #expect(decodedFromDict.rawBody.contains("value") || decodedFromDict.rawBody == "{}")
    }

    // MARK: - DocumentTranslationModels
    @Test("DocumentTranslationModels initializers and Codable")
    func testDocumentTranslationModels() throws {
        let req = DocumentTranslationCreateRequest(
            sourceLanguageCode: .hiIn,
            targetLanguageCodes: [.enIn, .bnIn],
            originalFilename: "doc.pdf",
            jobName: "translate-job",
            genre: "legal",
            useNativeNumerals: true,
            styleGuidelines: "formal"
        )
        #expect(req.sourceLanguageCode == .hiIn)
        #expect(req.targetLanguageCodes == [.enIn, .bnIn])
        #expect(req.originalFilename == "doc.pdf")
        #expect(req.jobName == "translate-job")
        #expect(req.genre == "legal")
        #expect(req.useNativeNumerals == true)
        #expect(req.styleGuidelines == "formal")
        let reqData = try encoder.encode(req)
        let decodedReq = try decoder.decode(DocumentTranslationCreateRequest.self, from: reqData)
        #expect(decodedReq == req)

        let resp = DocumentTranslationCreateResponse(
            jobId: "dt-1",
            uploadUrl: "https://upload.url",
            expiresInHours: 24,
            sourceLanguageCode: "hi-IN",
            targetLanguageCodes: ["en-IN"]
        )
        #expect(resp.jobId == "dt-1")
        #expect(resp.expiresInHours == 24)
        let respData = try encoder.encode(resp)
        let decodedResp = try decoder.decode(DocumentTranslationCreateResponse.self, from: respData)
        #expect(decodedResp == resp)

        let startResp = DocumentTranslationStartResponse(jobId: "dt-1", jobState: "processing", numPages: 10, warnings: ["minor"])
        #expect(startResp.numPages == 10)
        #expect(startResp.warnings == ["minor"])
        let startData = try encoder.encode(startResp)
        let decodedStart = try decoder.decode(DocumentTranslationStartResponse.self, from: startData)
        #expect(decodedStart == startResp)

        let liveStatus = DocumentTranslationJobLiveStatusResponse(
            jobId: "dt-1",
            jobName: "translate-job",
            jobState: "in_progress",
            sourceLanguageCode: "hi-IN",
            progress: 50,
            createdAt: "2026-10-16",
            updatedAt: "2026-10-16",
            errorMessage: nil
        )
        #expect(liveStatus.progress == 50)
        let liveData = try encoder.encode(liveStatus)
        let decodedLive = try decoder.decode(DocumentTranslationJobLiveStatusResponse.self, from: liveData)
        #expect(decodedLive == liveStatus)

        let exportReq = DocumentTranslationExportRequest(
            lang: .enIn,
            format: "docx",
            fitLineHeight: true,
            fitFontShrink: false
        )
        #expect(exportReq.lang == .enIn)
        #expect(exportReq.format == "docx")
        #expect(exportReq.fitLineHeight == true)
        #expect(exportReq.fitFontShrink == false)
        let exportReqData = try encoder.encode(exportReq)
        let decodedExportReq = try decoder.decode(DocumentTranslationExportRequest.self, from: exportReqData)
        #expect(decodedExportReq == exportReq)

        let exportResp = DocumentTranslationExportStatusResponse(
            exportId: "exp-1",
            jobId: "dt-1",
            targetLanguageCode: "en-IN",
            format: "docx",
            exportState: "completed",
            downloadUrl: "https://dl.url",
            filename: "out.docx",
            fileSize: 1024,
            expiresInHours: 12,
            errorMessage: nil,
            createdAt: "2026-10-16"
        )
        #expect(exportResp.exportId == "exp-1")
        #expect(exportResp.fileSize == 1024)
        let exportRespData = try encoder.encode(exportResp)
        let decodedExportResp = try decoder.decode(DocumentTranslationExportStatusResponse.self, from: exportRespData)
        #expect(decodedExportResp == exportResp)
    }

    // MARK: - DubbingModels
    @Test("DubbingModels initializers and Codable")
    func testDubbingModels() throws {
        let req = DubbingCreateRequest(
            sourceLanguageCode: .hiIn,
            targetLanguageCodes: [.enIn],
            jobName: "dub-1",
            voiceCloning: true,
            voiceId: "v-123",
            pacePreset: "natural",
            numSpeakers: 2,
            disableWatermark: false,
            editorFlow: true,
            exportOptions: ["mp4"],
            register: "formal"
        )
        #expect(req.sourceLanguageCode == .hiIn)
        #expect(req.voiceCloning == true)
        #expect(req.voiceId == "v-123")
        #expect(req.numSpeakers == 2)
        #expect(req.editorFlow == true)
        #expect(req.register == "formal")
        let reqData = try encoder.encode(req)
        let decodedReq = try decoder.decode(DubbingCreateRequest.self, from: reqData)
        #expect(decodedReq == req)

        let data = DubbingCreateData(jobId: "dub-1", uploadUrl: "https://upload.url")
        #expect(data.jobId == "dub-1")
        let resp = DubbingCreateResponse(status: "success", message: "Created", data: data)
        #expect(resp.status == "success")
        #expect(resp.data?.jobId == "dub-1")
        let respData = try encoder.encode(resp)
        let decodedResp = try decoder.decode(DubbingCreateResponse.self, from: respData)
        #expect(decodedResp == resp)

        let startResp = DubbingStartResponse(status: "success", message: "Started")
        #expect(startResp.status == "success")
        let startData = try encoder.encode(startResp)
        let decodedStart = try decoder.decode(DubbingStartResponse.self, from: startData)
        #expect(decodedStart == startResp)

        let liveData = DubbingLiveStatusData(
            jobId: "dub-1",
            jobName: "dub-job",
            status: "running",
            progress: 30,
            currentStep: "tts",
            currentStepLabel: "Generating Audio",
            errorMessage: nil
        )
        #expect(liveData.progress == 30)
        #expect(liveData.currentStep == "tts")
        let liveResp = DubbingLiveStatusResponse(status: "success", message: "", data: liveData)
        let liveRespData = try encoder.encode(liveResp)
        let decodedLiveResp = try decoder.decode(DubbingLiveStatusResponse.self, from: liveRespData)
        #expect(decodedLiveResp == liveResp)

        let exportResp = DubbingExportStatusResponse(status: "success", message: "ready", rawData: "raw")
        #expect(exportResp.status == "success")
        #expect(exportResp.message == "ready")
        let exportData = try encoder.encode(exportResp)
        let decodedExport = try decoder.decode(DubbingExportStatusResponse.self, from: exportData)
        #expect(decodedExport.status == "success")
    }

    // MARK: - JobModels
    @Test("JobModels initializers and Codable")
    func testJobModels() throws {
        let sttParams = SpeechToTextJobParameters(
            languageCode: .hiIn,
            model: .saarasV4,
            withTimestamps: true,
            withDiarization: true,
            numSpeakers: 3
        )
        #expect(sttParams.languageCode == .hiIn)
        #expect(sttParams.withTimestamps == true)
        #expect(sttParams.numSpeakers == 3)
        let sttReq = SpeechToTextJobInitRequest(jobParameters: sttParams)
        let sttReqData = try encoder.encode(sttReq)
        let decodedSttReq = try decoder.decode(SpeechToTextJobInitRequest.self, from: sttReqData)
        #expect(decodedSttReq == sttReq)

        let trParams = SpeechToTextTranslateJobParameters(
            model: .saarasV4,
            withTimestamps: false,
            withDiarization: false,
            numSpeakers: 1
        )
        #expect(trParams.model == .saarasV4)
        let trReq = SpeechToTextTranslateJobInitRequest(jobParameters: trParams)
        let trReqData = try encoder.encode(trReq)
        let decodedTrReq = try decoder.decode(SpeechToTextTranslateJobInitRequest.self, from: trReqData)
        #expect(decodedTrReq == trReq)

        let initResp = BulkJobInitResponse(jobId: "bulk-1", jobState: "created")
        #expect(initResp.jobId == "bulk-1")
        #expect(initResp.jobState == "created")
        let initRespData = try encoder.encode(initResp)
        let decodedInitResp = try decoder.decode(BulkJobInitResponse.self, from: initRespData)
        #expect(decodedInitResp == initResp)

        let filesReq = FilesRequest(jobId: "bulk-1", files: ["f1.wav", "f2.wav"])
        #expect(filesReq.files.count == 2)
        let filesReqData = try encoder.encode(filesReq)
        let decodedFilesReq = try decoder.decode(FilesRequest.self, from: filesReqData)
        #expect(decodedFilesReq == filesReq)

        let signedUrl = FileSignedURLDetails(fileUrl: "https://upload.url")
        #expect(signedUrl.fileUrl == "https://upload.url")

        let uploadResp = FilesUploadResponse(jobId: "bulk-1", jobState: "pending", uploadUrls: ["f1.wav": signedUrl])
        #expect(uploadResp.uploadUrls["f1.wav"]?.fileUrl == "https://upload.url")
        let uploadRespData = try encoder.encode(uploadResp)
        let decodedUploadResp = try decoder.decode(FilesUploadResponse.self, from: uploadRespData)
        #expect(decodedUploadResp == uploadResp)

        let downloadResp = FilesDownloadResponse(jobId: "bulk-1", jobState: "completed", downloadUrls: ["f1.json": signedUrl])
        #expect(downloadResp.downloadUrls["f1.json"]?.fileUrl == "https://upload.url")
        let downloadRespData = try encoder.encode(downloadResp)
        let decodedDownloadResp = try decoder.decode(FilesDownloadResponse.self, from: downloadRespData)
        #expect(decodedDownloadResp == downloadResp)

        let jobStatus = JobStatusResponse(
            jobId: "bulk-1",
            jobState: "completed",
            createdAt: "2026-10-16",
            updatedAt: "2026-10-16",
            totalFiles: 2,
            successfulFilesCount: 2,
            failedFilesCount: 0,
            errorMessage: nil
        )
        #expect(jobStatus.totalFiles == 2)
        #expect(jobStatus.successfulFilesCount == 2)
        let jobStatusData = try encoder.encode(jobStatus)
        let decodedJobStatus = try decoder.decode(JobStatusResponse.self, from: jobStatusData)
        #expect(decodedJobStatus == jobStatus)
    }

    // MARK: - PronunciationDictionaryModels
    @Test("PronunciationDictionaryModels initializers and Codable")
    func testPronunciationDictionaryModels() throws {
        let listResp = PronunciationDictionaryListResponse(dictionaryCount: 2, dictionaries: ["d1", "d2"])
        #expect(listResp.dictionaryCount == 2)
        #expect(listResp.dictionaries == ["d1", "d2"])
        let listData = try encoder.encode(listResp)
        let decodedList = try decoder.decode(PronunciationDictionaryListResponse.self, from: listData)
        #expect(decodedList == listResp)

        let createResp = PronunciationDictionaryCreateResponse(dictionaryId: "dict-1")
        #expect(createResp.dictionaryId == "dict-1")
        let createData = try encoder.encode(createResp)
        let decodedCreate = try decoder.decode(PronunciationDictionaryCreateResponse.self, from: createData)
        #expect(decodedCreate == createResp)

        let updateResp = PronunciationDictionaryUpdateResponse(dictionaryId: "dict-1", updatedPronunciations: ["test": ["ipa": "tɛst"]])
        #expect(updateResp.updatedPronunciations["test"]?["ipa"] == "tɛst")
        let updateData = try encoder.encode(updateResp)
        let decodedUpdate = try decoder.decode(PronunciationDictionaryUpdateResponse.self, from: updateData)
        #expect(decodedUpdate == updateResp)

        let dictData = PronunciationDictionaryData(pronunciations: ["word": ["phonetic": "wɜːd"]])
        #expect(dictData.pronunciations["word"]?["phonetic"] == "wɜːd")
        let dictDataBytes = try encoder.encode(dictData)
        let decodedDictData = try decoder.decode(PronunciationDictionaryData.self, from: dictDataBytes)
        #expect(decodedDictData == dictData)

        let delResp = PronunciationDictionaryDeleteResponse(success: true, message: "deleted")
        #expect(delResp.success)
        #expect(delResp.message == "deleted")
        let delData = try encoder.encode(delResp)
        let decodedDel = try decoder.decode(PronunciationDictionaryDeleteResponse.self, from: delData)
        #expect(decodedDel == delResp)
    }

    // MARK: - SpeechModels
    @Test("SpeechModels initializers and Codable")
    func testSpeechModels() throws {
        let opts = SpeechToTextOptions(
            model: .saarasV4,
            languageCode: .hiIn,
            prompt: "transcribe",
            withTimestamps: true,
            withDiarization: true,
            numSpeakers: 2
        )
        #expect(opts.model == .saarasV4)
        #expect(opts.languageCode == .hiIn)
        #expect(opts.prompt == "transcribe")
        #expect(opts.withTimestamps == true)
        #expect(opts.withDiarization == true)
        #expect(opts.numSpeakers == 2)

        let word = SttWordTimestamp(word: "Namaste", start: 0.1, end: 0.5)
        #expect(word.word == "Namaste")
        #expect(word.start == 0.1)
        #expect(word.end == 0.5)
        let wordData = try encoder.encode(word)
        let decodedWord = try decoder.decode(SttWordTimestamp.self, from: wordData)
        #expect(decodedWord == word)

        // SttDiarizedEntry & Transcript
        let entryJson = "{\"speaker_id\":\"spk_0\",\"transcript\":\"Hello\",\"start\":0.0,\"end\":1.0}".data(using: .utf8)!
        let entry = try decoder.decode(SttDiarizedEntry.self, from: entryJson)
        #expect(entry.speakerId == "spk_0")
        #expect(entry.transcript == "Hello")
        #expect(entry.start == 0.0)
        #expect(entry.end == 1.0)

        let transcript = SttDiarizedTranscript(entries: [entry])
        #expect(transcript.entries?.count == 1)
        let transcriptData = try encoder.encode(transcript)
        let decodedTranscript = try decoder.decode(SttDiarizedTranscript.self, from: transcriptData)
        #expect(decodedTranscript == transcript)

        let sttResp = SpeechToTextResponse(
            transcript: "Namaste",
            timestamps: [word],
            diarizedTranscript: transcript,
            languageCode: .hiIn
        )
        #expect(sttResp.transcript == "Namaste")
        #expect(sttResp.languageCode == .hiIn)
        let sttRespData = try encoder.encode(sttResp)
        let decodedSttResp = try decoder.decode(SpeechToTextResponse.self, from: sttRespData)
        #expect(decodedSttResp == sttResp)
    }

    // MARK: - TextModels
    @Test("TextModels initializers and Codable")
    func testTextModels() throws {
        let trReq = TranslateRequest(
            input: "Hello",
            sourceLanguageCode: .enIn,
            targetLanguageCode: .hiIn,
            speakerGender: "Male",
            mode: "formal",
            model: "mayura:v1",
            enablePreprocessing: true
        )
        #expect(trReq.input == "Hello")
        #expect(trReq.speakerGender == "Male")
        #expect(trReq.enablePreprocessing == true)
        let trReqData = try encoder.encode(trReq)
        let decodedTrReq = try decoder.decode(TranslateRequest.self, from: trReqData)
        #expect(decodedTrReq == trReq)

        let trResp = TranslateResponse(translatedText: "Namaste")
        #expect(trResp.translatedText == "Namaste")
        let trRespData = try encoder.encode(trResp)
        let decodedTrResp = try decoder.decode(TranslateResponse.self, from: trRespData)
        #expect(decodedTrResp == trResp)

        let translitReq = TransliterateRequest(input: "namaste", sourceLanguageCode: .enIn, targetLanguageCode: .hiIn)
        #expect(translitReq.input == "namaste")
        let translitReqData = try encoder.encode(translitReq)
        let decodedTranslitReq = try decoder.decode(TransliterateRequest.self, from: translitReqData)
        #expect(decodedTranslitReq == translitReq)

        let translitResp = TransliterateResponse(transliteratedText: "नमस्ते")
        #expect(translitResp.transliteratedText == "नमस्ते")
        let translitRespData = try encoder.encode(translitResp)
        let decodedTranslitResp = try decoder.decode(TransliterateResponse.self, from: translitRespData)
        #expect(decodedTranslitResp == translitResp)

        let lidReq = TextLidRequest(input: "Hello world")
        #expect(lidReq.input == "Hello world")
        let lidReqData = try encoder.encode(lidReq)
        let decodedLidReq = try decoder.decode(TextLidRequest.self, from: lidReqData)
        #expect(decodedLidReq == lidReq)

        let lidResp = TextLidResponse(detectedLanguage: "en-IN", confidence: 0.98)
        #expect(lidResp.detectedLanguage == "en-IN")
        #expect(lidResp.confidence == 0.98)
        let lidRespData = try encoder.encode(lidResp)
        let decodedLidResp = try decoder.decode(TextLidResponse.self, from: lidRespData)
        #expect(decodedLidResp == lidResp)
    }

    // MARK: - TtsModels
    @Test("TtsModels initializers, Codable, and audio decoding properties")
    func testTtsModels() throws {
        let req = TextToSpeechRequest(
            text: "Hello",
            targetLanguageCode: .hiIn,
            speaker: .anushka,
            model: .bulbulV2,
            speechSampleRate: 16000,
            enablePreprocessing: true,
            outputAudioCodec: .wav
        )
        #expect(req.text == "Hello")
        #expect(req.targetLanguageCode == .hiIn)
        #expect(req.speaker == .anushka)
        #expect(req.model == .bulbulV2)
        #expect(req.speechSampleRate == 16000)
        #expect(req.enablePreprocessing == true)
        #expect(req.outputAudioCodec == .wav)
        let reqData = try encoder.encode(req)
        let decodedReq = try decoder.decode(TextToSpeechRequest.self, from: reqData)
        #expect(decodedReq == req)

        let item = TtsAudioItem(audio: "AQIDBA==")
        #expect(item.audio == "AQIDBA==")
        let itemData = try encoder.encode(item)
        let decodedItem = try decoder.decode(TtsAudioItem.self, from: itemData)
        #expect(decodedItem == item)

        let resp = TextToSpeechResponse(audios: [item])
        #expect(resp.audioCount == 1)
        #expect(resp.firstAudioBase64 == "AQIDBA==")
        #expect(resp.audioBytes == Data([1, 2, 3, 4]))

        let emptyResp = TextToSpeechResponse(audios: nil)
        #expect(emptyResp.audioCount == 0)
        #expect(emptyResp.firstAudioBase64 == nil)
        #expect(emptyResp.audioBytes == nil)
    }

    // MARK: - VoiceCloningModels
    @Test("VoiceCloningModels initializers, Codable, and properties")
    func testVoiceCloningModels() throws {
        let detail = VoiceLibraryDetail(
            id: "v-1",
            name: "My Voice",
            language: "hi-IN",
            gender: "female",
            accent: "neutral",
            descriptor: "clear",
            status: "active",
            source: "cloned",
            createdBy: "user-1",
            createdAt: "2026-10-16",
            sampleDurationSeconds: 15.5,
            referenceText: "Sample text",
            previewAudioUrl: "https://preview.url",
            referenceAudioUrl: "https://ref.url",
            recordedAudioUrl: "https://rec.url"
        )
        #expect(detail.id == "v-1")
        #expect(detail.name == "My Voice")
        #expect(detail.gender == "female")
        #expect(detail.sampleDurationSeconds == 15.5)
        let detailData = try encoder.encode(detail)
        let decodedDetail = try decoder.decode(VoiceLibraryDetail.self, from: detailData)
        #expect(decodedDetail == detail)

        let listData = VoiceLibraryListData(voices: [detail], total: 1)
        #expect(listData.total == 1)
        let listResp = VoiceLibraryListResponse(status: "success", data: listData)
        let listRespData = try encoder.encode(listResp)
        let decodedListResp = try decoder.decode(VoiceLibraryListResponse.self, from: listRespData)
        #expect(decodedListResp == listResp)

        let detailResp = VoiceLibraryDetailResponse(status: "success", data: detail)
        let detailRespData = try encoder.encode(detailResp)
        let decodedDetailResp = try decoder.decode(VoiceLibraryDetailResponse.self, from: detailRespData)
        #expect(decodedDetailResp == detailResp)

        let createData = VoiceLibraryCreateData(voiceId: "v-1", status: "created", referenceText: "Sample text")
        #expect(createData.voiceId == "v-1")
        let createResp = VoiceLibraryCreateResponse(status: "success", data: createData)
        let createRespData = try encoder.encode(createResp)
        let decodedCreateResp = try decoder.decode(VoiceLibraryCreateResponse.self, from: createRespData)
        #expect(decodedCreateResp == createResp)

        let deleteResp = VoiceLibraryDeleteResponse()
        let deleteData = try encoder.encode(deleteResp)
        let decodedDelete = try decoder.decode(VoiceLibraryDeleteResponse.self, from: deleteData)
        #expect(decodedDelete == deleteResp)

        let cloneReq = VoiceCloneRequest(
            text: "Voice cloning test",
            languageCode: .hiIn,
            voiceId: "v-1",
            refAudio: FileInput(data: Data([1, 2, 3])),
            refText: "Reference",
            pace: 1.1,
            outputAudioCodec: .wav,
            speechSampleRate: 22050,
            enableQc: true,
            enableVad: true,
            enableTextNormalization: true,
            minAudioDuration: 1.0,
            maxAudioDuration: 10.0,
            refAudioDuration: 5.0
        )
        #expect(cloneReq.text == "Voice cloning test")
        #expect(cloneReq.languageCode == .hiIn)
        #expect(cloneReq.voiceId == "v-1")
        #expect(cloneReq.pace == 1.1)
        #expect(cloneReq.enableQc == true)
        #expect(cloneReq.refAudioDuration == 5.0)

        let cloneResp = VoiceCloneResponse(
            audio: "AQIDBA==",
            audioB64: "AQIDBA==",
            requestId: "req-clone-1",
            audioDuration: 3.5
        )
        #expect(cloneResp.audio == "AQIDBA==")
        #expect(cloneResp.audioDuration == 3.5)
        #expect(cloneResp.audioBytes == Data([1, 2, 3, 4]))
        let cloneRespData = try encoder.encode(cloneResp)
        let decodedCloneResp = try decoder.decode(VoiceCloneResponse.self, from: cloneRespData)
        #expect(decodedCloneResp == cloneResp)
    }
}
