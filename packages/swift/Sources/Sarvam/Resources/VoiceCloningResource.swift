import Foundation

/// Stateless request builder and response decoder for Voice Cloning endpoints.
public final class VoiceCloningResource: Sendable {
    private let config: SarvamClientConfig
    private let executor: RequestExecutor

    init(config: SarvamClientConfig) {
        self.config = config
        self.executor = RequestExecutor(config: config)
    }

    /// Lists cloned voices in the user's voice library.
    public func listVoices(options: RequestOptions? = nil) async throws -> VoiceLibraryListResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)/voices")!
        let httpRequest = HTTPRequest(
            method: .get,
            url: url,
            headers: options?.headers ?? [:],
            operationKind: .idempotent,
            timeoutInterval: options?.timeoutInterval,
            idempotencyKey: options?.idempotencyKey
        )

        let response = try await executor.execute(request: httpRequest)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(VoiceLibraryListResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode VoiceLibraryListResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Creates a cloned voice from a reference audio clip in one shot.
    public func createVoice(
        file: FileInput,
        name: String,
        language: String,
        style: String? = nil,
        gender: String? = nil,
        options: RequestOptions? = nil
    ) async throws -> VoiceLibraryCreateResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)/voices/create")!

        var fields: [String: String] = [
            "name": name,
            "language": language
        ]
        if let style = style {
            fields["style"] = style
        }
        if let gender = gender {
            fields["gender"] = gender
        }

        let multipartBuilder = MultipartFormDataBuilder()
        let bodyData = try multipartBuilder.build(fields: fields, files: [("file", file)])

        var headers = options?.headers ?? [:]
        headers["content-type"] = multipartBuilder.contentTypeHeader

        let httpRequest = HTTPRequest(
            method: .post,
            url: url,
            headers: headers,
            body: bodyData,
            operationKind: .jobCreate,
            timeoutInterval: options?.timeoutInterval,
            idempotencyKey: options?.idempotencyKey,
            isReplayable: file.isReplayable
        )

        let response = try await executor.execute(request: httpRequest)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(VoiceLibraryCreateResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode VoiceLibraryCreateResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Retrieves details of a specific voice from the voice library.
    public func getVoice(voiceId: String, options: RequestOptions? = nil) async throws -> VoiceLibraryDetailResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)/voices/\(voiceId)")!
        let httpRequest = HTTPRequest(
            method: .get,
            url: url,
            headers: options?.headers ?? [:],
            operationKind: .idempotent,
            timeoutInterval: options?.timeoutInterval,
            idempotencyKey: options?.idempotencyKey
        )

        let response = try await executor.execute(request: httpRequest)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(VoiceLibraryDetailResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode VoiceLibraryDetailResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Deletes a voice from the voice library.
    public func deleteVoice(voiceId: String, options: RequestOptions? = nil) async throws -> VoiceLibraryDeleteResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)/voices/delete/\(voiceId)")!
        let httpRequest = HTTPRequest(
            method: .delete,
            url: url,
            headers: options?.headers ?? [:],
            operationKind: .idempotent,
            timeoutInterval: options?.timeoutInterval,
            idempotencyKey: options?.idempotencyKey
        )

        let response = try await executor.execute(request: httpRequest)
        if response.body.isEmpty {
            return VoiceLibraryDeleteResponse()
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(VoiceLibraryDeleteResponse.self, from: response.body)
        } catch {
            return VoiceLibraryDeleteResponse()
        }
    }

    /// Synthesizes speech using a cloned voice.
    public func convert(
        _ request: VoiceCloneRequest,
        options: RequestOptions? = nil
    ) async throws -> VoiceCloneResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)/voices/clone")!
        let (fields, files, isReplayable) = buildVoiceCloneMultipart(request: request)

        let multipartBuilder = MultipartFormDataBuilder()
        let bodyData = try multipartBuilder.build(fields: fields, files: files)

        var headers = options?.headers ?? [:]
        headers["content-type"] = multipartBuilder.contentTypeHeader

        let httpRequest = HTTPRequest(
            method: .post,
            url: url,
            headers: headers,
            body: bodyData,
            operationKind: .multipartCompute,
            timeoutInterval: options?.timeoutInterval,
            idempotencyKey: options?.idempotencyKey,
            isReplayable: isReplayable
        )

        let response = try await executor.execute(request: httpRequest)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(VoiceCloneResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode VoiceCloneResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }

    /// Streams synthesized audio from a cloned voice via HTTP chunked transfer.
    public func stream(
        _ request: VoiceCloneRequest,
        options: RequestOptions? = nil
    ) -> AsyncThrowingStream<Data, Error> {
        let executor = self.executor
        let apiBaseUrl = config.environment.apiBaseUrl

        return AsyncThrowingStream<Data, Error> { continuation in
            let task = Task {
                do {
                    let url = URL(string: "\(apiBaseUrl)/voices/clone/stream")!
                    let (fields, files, isReplayable) = self.buildVoiceCloneMultipart(request: request)

                    let multipartBuilder = MultipartFormDataBuilder()
                    let bodyData = try multipartBuilder.build(fields: fields, files: files)

                    var headers = options?.headers ?? [:]
                    headers["content-type"] = multipartBuilder.contentTypeHeader

                    let httpRequest = HTTPRequest(
                        method: .post,
                        url: url,
                        headers: headers,
                        body: bodyData,
                        operationKind: .multipartCompute,
                        timeoutInterval: options?.timeoutInterval,
                        idempotencyKey: options?.idempotencyKey,
                        isReplayable: isReplayable
                    )

                    let (_, dataStream) = try await executor.executeStream(request: httpRequest)
                    for try await chunk in dataStream {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// Connects to the real-time WebSocket voice cloning streaming session.
    public func connect(
        config: TtsStreamingConfig = TtsStreamingConfig(),
        options: RequestOptions? = nil
    ) async throws -> TtsStreamingSession {
        try await TtsStreamingSession.connect(
            config: config,
            environment: self.config.environment,
            authProvider: self.config.authProvider,
            webSocketFactory: self.config.webSocketFactory,
            endpointPath: "/voices/clone/ws"
        )
    }

    private func buildVoiceCloneMultipart(request: VoiceCloneRequest) -> (fields: [String: String], files: [(name: String, file: FileInput)], isReplayable: Bool) {
        var fields: [String: String] = [
            "text": request.text,
            "language_code": request.languageCode.rawValue
        ]
        if let voiceId = request.voiceId {
            fields["voice_id"] = voiceId
        }
        if let refText = request.refText {
            fields["ref_text"] = refText
        }
        if let pace = request.pace {
            fields["pace"] = String(pace)
        }
        if let codec = request.outputAudioCodec {
            fields["output_audio_codec"] = codec.rawValue
        }
        if let rate = request.speechSampleRate {
            fields["speech_sample_rate"] = String(rate)
        }
        if let qc = request.enableQc {
            fields["enable_qc"] = String(qc)
        }
        if let vad = request.enableVad {
            fields["enable_vad"] = String(vad)
        }
        if let norm = request.enableTextNormalization {
            fields["enable_text_normalization"] = String(norm)
        }
        if let minDur = request.minAudioDuration {
            fields["min_audio_duration"] = String(minDur)
        }
        if let maxDur = request.maxAudioDuration {
            fields["max_audio_duration"] = String(maxDur)
        }
        if let refDur = request.refAudioDuration {
            fields["ref_audio_duration"] = String(refDur)
        }

        var files: [(name: String, file: FileInput)] = []
        var isReplayable = true
        if let refAudio = request.refAudio {
            files.append(("ref_audio", refAudio))
            isReplayable = refAudio.isReplayable
        }

        return (fields, files, isReplayable)
    }
}
