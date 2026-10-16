import Foundation

/// Abstract protocol for hardware or synthetic audio input capture.
public protocol AudioCaptureDriver: Sendable {
    /// Native sample rate of captured audio (e.g. 48000, 44100, 16000).
    var sampleRate: Int { get }

    /// Number of channels produced by this driver (1 for mono, 2 for stereo).
    var channelCount: Int { get }

    /// Starts audio capture hardware or pipeline.
    func start() throws

    /// Reads up to `length` bytes of raw PCM audio.
    ///
    /// - Returns: `Data` chunk, or `nil` if stream ended / closed.
    func read(length: Int) throws -> Data?

    /// Halts audio capture.
    func stop()
}

/// Abstract protocol for hardware or synthetic audio output playback.
public protocol AudioPlaybackDriver: Sendable {
    /// Whether the playback driver is currently active.
    var isPlaying: Bool { get }

    /// Starts playback audio hardware.
    func start() throws

    /// Writes raw audio bytes to the playback hardware buffer.
    ///
    /// - Returns: Number of bytes written.
    func write(data: Data) throws -> Int

    /// Immediately flushes all queued audio buffers.
    func flush()

    /// Stops audio playback.
    func stop()
}

/// In-memory `AudioCaptureDriver` useful for unit testing or streaming predefined bytes.
public final class BufferAudioCaptureDriver: AudioCaptureDriver, @unchecked Sendable {
    public let sampleRate: Int
    public let channelCount: Int

    private let data: Data
    private let lock = NSLock()
    private var position: Int = 0
    private var isStarted: Bool = false

    public init(data: Data, sampleRate: Int = 48000, channelCount: Int = 1) {
        self.data = data
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        isStarted = true
    }

    public func read(length: Int) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard isStarted, position < data.count else { return nil }
        let available = min(length, data.count - position)
        let chunk = data.subdata(in: position..<(position + available))
        position += available
        return chunk
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        isStarted = false
    }
}

/// In-memory `AudioPlaybackDriver` for inspecting rendered audio chunks in tests.
public final class MemoryAudioPlaybackDriver: AudioPlaybackDriver, @unchecked Sendable {
    private let lock = NSLock()
    private var _writtenData: [Data] = []
    private var _isFlushed: Bool = false
    private var _isPlaying: Bool = false

    public init() {}

    public var writtenData: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return _writtenData
    }

    public var isFlushed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isFlushed
    }

    public var isPlaying: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isPlaying
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        _isPlaying = true
        _isFlushed = false
    }

    public func write(data: Data) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        _writtenData.append(data)
        return data.count
    }

    public func flush() {
        lock.lock()
        defer { lock.unlock() }
        _isFlushed = true
        _writtenData.removeAll()
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        _isPlaying = false
    }
}
