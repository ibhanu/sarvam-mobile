import Foundation

public struct ResponsesRequest: Codable, Sendable, Equatable {
    public var model: String
    public var input: String

    public init(model: String, input: String) {
        self.model = model
        self.input = input
    }
}
