import Foundation

/// Events emitted during a real-time text-to-speech streaming session.
public enum TtsStreamEvent: Sendable, Equatable {
    case audioChunk(audioBytes: Data, contentType: String? = nil, requestId: String? = nil)
    case completed(requestId: String? = nil)
    case error(message: String, code: String? = nil)
    case unknown(rawJson: String)

    /// Parses incoming raw JSON text into a `TtsStreamEvent`.
    public static func parse(jsonString: String) -> TtsStreamEvent {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unknown(rawJson: jsonString)
        }

        let type = json["type"] as? String

        switch type {
        case "audio":
            let dataDict = json["data"] as? [String: Any]
            let b64 = (dataDict?["audio"] as? String) ?? (json["audio"] as? String)
            guard let b64Audio = b64, let audioData = Data(base64Encoded: b64Audio) else {
                return .unknown(rawJson: jsonString)
            }
            let contentType = dataDict?["content_type"] as? String
            let reqId = (dataDict?["request_id"] as? String) ?? (json["request_id"] as? String)
            return .audioChunk(audioBytes: audioData, contentType: contentType, requestId: reqId)

        case "event":
            let dataDict = json["data"] as? [String: Any]
            let eventName = dataDict?["event"] as? String
            let eventType = dataDict?["event_type"] as? String
            let reqId = (dataDict?["request_id"] as? String) ?? (json["request_id"] as? String)
            if eventName == "final" || eventType == "completion" {
                return .completed(requestId: reqId)
            }
            return .unknown(rawJson: jsonString)

        case "error":
            let dataDict = json["data"] as? [String: Any]
            let message = (dataDict?["message"] as? String) ?? (json["message"] as? String) ?? "Unknown TTS error"
            let code = (dataDict?["code"] as? String) ?? (json["code"] as? String)
            return .error(message: message, code: code)

        default:
            return .unknown(rawJson: jsonString)
        }
    }
}
