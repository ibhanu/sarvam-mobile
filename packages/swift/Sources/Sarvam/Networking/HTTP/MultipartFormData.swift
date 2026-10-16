import Foundation

/// Multipart/form-data builder without external dependencies.
public struct MultipartFormDataBuilder: Sendable {
    public let boundary: String

    public init(boundary: String = "Boundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    public var contentTypeHeader: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    /// Builds multipart body data from text fields and file inputs.
    public func build(
        fields: [String: String],
        files: [(name: String, file: FileInput)]
    ) throws -> Data {
        var body = Data()

        // Append text fields
        for (key, value) in fields {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }

        // Append files
        for (name, file) in files {
            let fileData = try file.readData()
            let fileName = file.fileName ?? "file.bin"
            let mimeType = file.mimeType ?? "application/octet-stream"

            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n")
            body.append("Content-Type: \(mimeType)\r\n\r\n")
            body.append(fileData)
            body.append("\r\n")
        }

        // Closing boundary
        body.append("--\(boundary)--\r\n")
        return body
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
