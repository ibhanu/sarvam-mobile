import Foundation

/// Stateless request builder and response decoder for Speech-to-Text endpoints.
public final class SpeechToTextResource: Sendable {
    private let config: SarvamClientConfig
    private let executor: RequestExecutor

    init(config: SarvamClientConfig) {
        self.config = config
        self.executor = RequestExecutor(config: config)
    }

    /// Transcribes speech audio to text using the Saaras model family.
    public func transcribe(
        file: FileInput,
        options: SpeechToTextOptions? = nil,
        requestOptions: RequestOptions? = nil
    ) async throws -> SpeechToTextResponse {
        try await performSpeechRequest(
            path: "/speech-to-text",
            file: file,
            options: options,
            requestOptions: requestOptions
        )
    }

    /// Transcribes and translates speech audio to English or another target language.
    public func translate(
        file: FileInput,
        options: SpeechToTextOptions? = nil,
        requestOptions: RequestOptions? = nil
    ) async throws -> SpeechToTextResponse {
        try await performSpeechRequest(
            path: "/speech-to-text-translate",
            file: file,
            options: options,
            requestOptions: requestOptions
        )
    }

    /// Connects to the real-time bidirectional streaming STT WebSocket.
    public func connect(
        config: SttRealtimeConfig = SttRealtimeConfig(),
        options: RequestOptions? = nil
    ) async throws -> SttRealtimeSession {
        try await SttRealtimeSession.connect(
            config: config,
            environment: self.config.environment,
            authProvider: self.config.authProvider,
            webSocketFactory: self.config.webSocketFactory
        )
    }

    private func performSpeechRequest(
        path: String,
        file: FileInput,
        options: SpeechToTextOptions?,
        requestOptions: RequestOptions?
    ) async throws -> SpeechToTextResponse {
        let url = URL(string: "\(config.environment.apiBaseUrl)\(path)")!

        var fields: [String: String] = [:]
        if let model = options?.model {
            fields["model"] = model.rawValue
        }
        if let lang = options?.languageCode {
            fields["language_code"] = lang.rawValue
        }
        if let prompt = options?.prompt {
            fields["prompt"] = prompt
        }
        if let timestamps = options?.withTimestamps {
            fields["with_timestamps"] = String(timestamps)
        }
        if let diarization = options?.withDiarization {
            fields["with_diarization"] = String(diarization)
        }
        if let speakers = options?.numSpeakers {
            fields["num_speakers"] = String(speakers)
        }

        let multipartBuilder = MultipartFormDataBuilder()
        let bodyData = try multipartBuilder.build(fields: fields, files: [("file", file)])

        var headers = requestOptions?.headers ?? [:]
        headers["content-type"] = multipartBuilder.contentTypeHeader

        let httpRequest = HTTPRequest(
            method: .post,
            url: url,
            headers: headers,
            body: bodyData,
            operationKind: .multipartCompute,
            timeoutInterval: requestOptions?.timeoutInterval,
            idempotencyKey: requestOptions?.idempotencyKey,
            isReplayable: file.isReplayable
        )

        let response = try await executor.execute(request: httpRequest)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(SpeechToTextResponse.self, from: response.body)
        } catch {
            throw SarvamError.decodingError(
                rawBody: String(data: response.body, encoding: .utf8),
                message: "Failed to decode SpeechToTextResponse: \(error.localizedDescription)",
                cause: error.localizedDescription
            )
        }
    }
}
