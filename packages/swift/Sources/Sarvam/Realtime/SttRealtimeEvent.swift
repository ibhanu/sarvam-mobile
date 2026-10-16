import Foundation

/// Events emitted during a real-time speech-to-text session.
public enum SttRealtimeEvent: Sendable, Equatable {
    case sessionBegin(sessionId: String)
    case vadSpeechStart(timestampMs: Int64?)
    case vadSpeechEnd(timestampMs: Int64?)
    case transcriptPartial(utteranceIdx: Int?, text: String, language: LanguageCode?)
    case transcriptFinal(
        utteranceIdx: Int?,
        text: String,
        language: LanguageCode?,
        languageConfidence: Double? = nil,
        startS: Double? = nil,
        endS: Double? = nil
    )
    case sessionEnd(durationSeconds: Double? = nil)
    case error(code: String?, message: String)
    case unknown(rawJson: String)

    /// Parses incoming raw JSON text into an `SttRealtimeEvent`.
    public static func parse(jsonString: String) -> SttRealtimeEvent {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unknown(rawJson: jsonString)
        }

        let event = json["event"] as? String

        switch event {
        case "session_begin":
            let sessionId = json["session_id"] as? String ?? ""
            return .sessionBegin(sessionId: sessionId)

        case "vad_speech_start", "speech_start":
            let ts = (json["timestamp_ms"] as? NSNumber)?.int64Value
            return .vadSpeechStart(timestampMs: ts)

        case "vad_speech_end", "speech_end":
            let ts = (json["timestamp_ms"] as? NSNumber)?.int64Value
            return .vadSpeechEnd(timestampMs: ts)

        case "transcript_partial":
            let utteranceIdx = json["utterance_idx"] as? Int
            let text = json["text"] as? String ?? ""
            let lang = (json["language"] as? String).map { LanguageCode(rawValue: $0) }
            return .transcriptPartial(utteranceIdx: utteranceIdx, text: text, language: lang)

        case "transcript_final", "transcript":
            let utteranceIdx = json["utterance_idx"] as? Int
            let text = json["text"] as? String ?? ""
            let lang = (json["language"] as? String).map { LanguageCode(rawValue: $0) }
            let conf = json["language_confidence"] as? Double
            let start = json["start_s"] as? Double
            let end = json["end_s"] as? Double
            return .transcriptFinal(
                utteranceIdx: utteranceIdx,
                text: text,
                language: lang,
                languageConfidence: conf,
                startS: start,
                endS: end
            )

        case "session_end":
            let duration = json["duration_seconds"] as? Double
            return .sessionEnd(durationSeconds: duration)

        case "error":
            let code = json["code"] as? String
            let message = json["message"] as? String ?? "Unknown STT error"
            return .error(code: code, message: message)

        default:
            return .unknown(rawJson: jsonString)
        }
    }
}
