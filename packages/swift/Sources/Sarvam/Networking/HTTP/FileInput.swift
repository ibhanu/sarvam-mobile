import Foundation

/// Binary file input container for multipart compute uploads or blob storage transfers.
public struct FileInput: Sendable, Equatable {
    public let data: Data?
    public let fileURL: URL?
    public let fileName: String?
    public let mimeType: String?
    public let isReplayable: Bool

    /// Creates a FileInput from in-memory Data.
    public init(
        data: Data,
        fileName: String? = "file.bin",
        mimeType: String? = "application/octet-stream",
        isReplayable: Bool = true
    ) {
        self.data = data
        self.fileURL = nil
        self.fileName = fileName
        self.mimeType = mimeType
        self.isReplayable = isReplayable
    }

    /// Creates a FileInput from a local file URL.
    public init(
        fileURL: URL,
        fileName: String? = nil,
        mimeType: String? = nil,
        isReplayable: Bool = true
    ) {
        self.data = nil
        self.fileURL = fileURL
        self.fileName = fileName ?? fileURL.lastPathComponent
        self.mimeType = mimeType ?? "application/octet-stream"
        self.isReplayable = isReplayable
    }

    /// Reads the binary payload into memory.
    public func readData() throws -> Data {
        if let data = self.data {
            return data
        }
        if let fileURL = self.fileURL {
            do {
                return try Data(contentsOf: fileURL)
            } catch {
                throw SarvamError.badRequestError(
                    statusCode: 400,
                    code: "file_read_error",
                    requestId: nil,
                    message: "Unable to read file input from \(fileURL.path): \(error.localizedDescription)"
                )
            }
        }
        return Data()
    }
}
