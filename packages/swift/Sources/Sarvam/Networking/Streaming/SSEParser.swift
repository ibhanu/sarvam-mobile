import Foundation

/// Structured Server-Sent Event (SSE).
public struct SSEEvent: Sendable, Equatable {
    public let event: String?
    public let data: String
    public let id: String?
    public let retry: Int?

    public init(event: String? = nil, data: String, id: String? = nil, retry: Int? = nil) {
        self.event = event
        self.data = data
        self.id = id
        self.retry = retry
    }
}

/// Robust streaming parser for Server-Sent Events (SSE).
///
/// Implements RFC 8895 / WHATWG EventSource parsing rules:
/// - Handles arbitrary byte chunk boundaries
/// - Buffers multiline `data:` fields joined with `\n`
/// - Respects `[DONE]` sentinel and event-driven completion (`response.completed`)
public enum SSEParser {
    public static func parse(
        byteStream: AsyncThrowingStream<Data, Error>,
        terminateOnDoneSentinel: Bool = true,
        customTermination: (@Sendable (SSEEvent) -> Bool)? = nil
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream<SSEEvent, Error> { continuation in
            let task = Task {
                var buffer = ""

                do {
                    for try await chunk in byteStream {
                        guard let text = String(data: chunk, encoding: .utf8) else { continue }
                        buffer += text

                        // Process complete SSE blocks delimited by \n\n or \r\n\r\n
                        while true {
                            let separatorRange: Range<String.Index>?
                            if let r = buffer.range(of: "\r\n\r\n") {
                                separatorRange = r
                            } else if let r = buffer.range(of: "\n\n") {
                                separatorRange = r
                            } else {
                                separatorRange = nil
                            }

                            guard let range = separatorRange else {
                                break
                            }

                            let block = String(buffer[..<range.lowerBound])
                            buffer.removeSubrange(..<range.upperBound)

                            if let event = parseBlock(block) {
                                // Check termination condition
                                if terminateOnDoneSentinel && event.data.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                                    continuation.finish()
                                    return
                                }

                                if let customTerm = customTermination, customTerm(event) {
                                    continuation.yield(event)
                                    continuation.finish()
                                    return
                                }

                                continuation.yield(event)
                            }
                        }
                    }

                    // Process any remaining event in buffer on EOF
                    let remaining = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !remaining.isEmpty, let event = parseBlock(remaining) {
                        if terminateOnDoneSentinel && event.data.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                            continuation.finish()
                            return
                        }
                        if let customTerm = customTermination, customTerm(event) {
                            continuation.yield(event)
                            continuation.finish()
                            return
                        }
                        continuation.yield(event)
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

    private static func parseBlock(_ block: String) -> SSEEvent? {
        let lines = block.components(separatedBy: .newlines)
        var eventType: String?
        var dataLines: [String] = []
        var id: String?
        var retry: Int?

        for line in lines {
            if line.isEmpty || line.hasPrefix(":") {
                // Comment or empty line
                continue
            }

            if line.hasPrefix("data:") {
                var content = String(line.dropFirst(5))
                if content.hasPrefix(" ") {
                    content.removeFirst()
                }
                dataLines.append(content)
            } else if line.hasPrefix("event:") {
                var content = String(line.dropFirst(6))
                if content.hasPrefix(" ") {
                    content.removeFirst()
                }
                eventType = content
            } else if line.hasPrefix("id:") {
                var content = String(line.dropFirst(3))
                if content.hasPrefix(" ") {
                    content.removeFirst()
                }
                id = content
            } else if line.hasPrefix("retry:") {
                var content = String(line.dropFirst(6))
                if content.hasPrefix(" ") {
                    content.removeFirst()
                }
                retry = Int(content)
            }
        }

        if dataLines.isEmpty && eventType == nil {
            return nil
        }

        return SSEEvent(
            event: eventType,
            data: dataLines.joined(separator: "\n"),
            id: id,
            retry: retry
        )
    }
}
