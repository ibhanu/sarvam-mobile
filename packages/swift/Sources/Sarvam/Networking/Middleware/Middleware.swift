import Foundation

/// Execution context for a middleware request.
public protocol Middleware: Sendable {
    func process(
        request: HTTPRequest,
        next: @Sendable (HTTPRequest) async throws -> HTTPResponse
    ) async throws -> HTTPResponse
}
