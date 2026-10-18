import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Swift C-FFI bridge to the shared `libsarvam_rust_core` native binary for iOS and macOS.
///
/// Supports both statically linked iOS `XCFramework` symbols (via `RTLD_DEFAULT`) and
/// dynamically loaded `.dylib` binaries (for macOS and `swift test`), keeping `Package.swift`
/// 100% free of `unsafeFlags` for SwiftPM and Swift Package Index compatibility.
public final class SarvamRustBridge: @unchecked Sendable {
    private typealias InvokeBytesFn = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<UInt64>?
    ) -> UnsafeMutablePointer<UInt8>?

    private typealias ResamplePcm16Fn = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UInt32,
        UInt16,
        UnsafeMutablePointer<UInt64>?
    ) -> UnsafeMutablePointer<UInt8>?

    private typealias FreeBytesFn = @convention(c) (
        UnsafeMutablePointer<UInt8>?,
        Int,
        Int
    ) -> Void

    private let handle: UnsafeMutableRawPointer?
    private let ownsHandle: Bool
    private let invokeBytesFn: InvokeBytesFn
    private let resamplePcm16Fn: ResamplePcm16Fn
    private let freeBytesFn: FreeBytesFn

    /// Initializes the Swift bridge against `libsarvam_rust_core`.
    ///
    /// - Parameter libraryPath: Optional path to `libsarvam_rust_core.dylib`. When `nil`, resolves symbols from the current process (`RTLD_DEFAULT`) or standard library search paths.
    public init(libraryPath: String? = nil) throws {
        let resolvedHandle: UnsafeMutableRawPointer?
        let shouldClose: Bool

        if let path = libraryPath, !path.isEmpty {
            guard let h = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
                let err = String(cString: dlerror())
                throw SarvamError.connectionError(
                    message: "Failed to load libsarvam_rust_core at \(path): \(err)"
                )
            }
            resolvedHandle = h
            shouldClose = true
        } else if let h = dlopen("libsarvam_rust_core.dylib", RTLD_NOW | RTLD_LOCAL) {
            resolvedHandle = h
            shouldClose = true
        } else {
            // Statically linked into iOS XCFramework / app binary
            resolvedHandle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT on Darwin
            shouldClose = false
        }

        guard
            let invokeSym = dlsym(resolvedHandle, "sarvam_rust_invoke_bytes"),
            let resampleSym = dlsym(resolvedHandle, "sarvam_rust_resample_pcm16"),
            let freeSym = dlsym(resolvedHandle, "sarvam_rust_free_bytes")
        else {
            if shouldClose, let h = resolvedHandle {
                dlclose(h)
            }
            throw SarvamError.connectionError(
                message: "Required sarvam_rust_* FFI symbols not found in binary"
            )
        }

        self.handle = resolvedHandle
        self.ownsHandle = shouldClose
        self.invokeBytesFn = unsafeBitCast(invokeSym, to: InvokeBytesFn.self)
        self.resamplePcm16Fn = unsafeBitCast(resampleSym, to: ResamplePcm16Fn.self)
        self.freeBytesFn = unsafeBitCast(freeSym, to: FreeBytesFn.self)
    }

    deinit {
        if ownsHandle, let h = handle {
            dlclose(h)
        }
    }

    /// Invokes a JSON command on the Rust core engine and returns the decoded JSON dictionary.
    public func invoke(_ command: [String: Any]) throws -> [String: Any] {
        let jsonData = try JSONSerialization.data(withJSONObject: command, options: [])
        var meta: [UInt64] = [0, 0]

        let outPtr: UnsafeMutablePointer<UInt8>? = jsonData.withUnsafeBytes { rawBuf in
            let base = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self)
            return invokeBytesFn(base, jsonData.count, &meta)
        }

        let outLen = Int(meta[0])
        let outCap = Int(meta[1])
        guard let ptr = outPtr, outLen > 0 else {
            throw SarvamError.decodingError(
                rawBody: nil,
                message: "Empty response from sarvam_rust_invoke_bytes"
            )
        }
        defer {
            if outCap > 0 {
                freeBytesFn(ptr, outLen, outCap)
            }
        }

        let responseData = Data(bytes: ptr, count: outLen)
        guard
            let obj = try JSONSerialization.jsonObject(with: responseData, options: []) as? [String: Any]
        else {
            throw SarvamError.decodingError(
                rawBody: nil,
                message: "Invalid JSON object from sarvam_rust_invoke_bytes"
            )
        }

        if let status = obj["status"] as? String, status == "err" {
            let errMessage = (obj["error"] as? String) ?? "Unknown Rust core error"
            throw SarvamError.badRequestError(
                statusCode: 400,
                code: nil,
                requestId: nil,
                message: errMessage
            )
        }

        return (obj["data"] as? [String: Any]) ?? [:]
    }

    public func version() throws -> [String: String] {
        let data = try invoke(["op": "version"])
        var out: [String: String] = [:]
        for (k, v) in data {
            if let s = v as? String {
                out[k] = s
            }
        }
        return out
    }

    public func resolveEnvironment(proxyBaseUrl: String? = nil) throws -> [String: String] {
        var cmd: [String: Any] = ["op": "resolveEnvironment"]
        if let proxyBaseUrl = proxyBaseUrl {
            cmd["proxyBaseUrl"] = proxyBaseUrl
        }
        let data = try invoke(cmd)
        var out: [String: String] = [:]
        for (k, v) in data {
            if let s = v as? String {
                out[k] = s
            }
        }
        return out
    }

    public func classifyHttpError(
        statusCode: Int,
        headers: [String: String] = [:],
        rawBody: String = "",
        nowEpochMs: Int64 = 0
    ) throws -> [String: Any] {
        return try invoke([
            "op": "classifyHttpError",
            "statusCode": statusCode,
            "headers": headers,
            "rawBody": rawBody,
            "nowEpochMs": nowEpochMs
        ])
    }

    public func evaluateRetry(input: [String: Any]) throws -> [String: Any] {
        return try invoke([
            "op": "evaluateRetry",
            "input": input
        ])
    }

    public func parseChatSse(_ rawSse: String) throws -> [String: Any] {
        return try invoke([
            "op": "parseChatSse",
            "rawSse": rawSse
        ])
    }

    public func parseResponsesSse(_ rawSse: String) throws -> [String: Any] {
        return try invoke([
            "op": "parseResponsesSse",
            "rawSse": rawSse
        ])
    }

    /// Zero-JSON-overhead binary PCM16 resampler to 16kHz mono linear-16 LE executed in Rust.
    public func resamplePcm16(
        inputBytes: Data,
        inputSampleRate: Int,
        channelCount: Int = 1
    ) -> Data {
        guard !inputBytes.isEmpty else { return Data() }
        var meta: [UInt64] = [0, 0]

        let outPtr: UnsafeMutablePointer<UInt8>? = inputBytes.withUnsafeBytes { rawBuf in
            let base = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self)
            return resamplePcm16Fn(
                base,
                inputBytes.count,
                UInt32(inputSampleRate),
                UInt16(channelCount),
                &meta
            )
        }

        let outLen = Int(meta[0])
        let outCap = Int(meta[1])
        guard let ptr = outPtr, outLen > 0 else {
            return Data()
        }
        defer {
            if outCap > 0 {
                freeBytesFn(ptr, outLen, outCap)
            }
        }
        return Data(bytes: ptr, count: outLen)
    }

    public func calculateAudioLevels(pcm16Bytes: Data) throws -> [String: Double] {
        let byteArray = [UInt8](pcm16Bytes).map { Int($0) }
        let data = try invoke([
            "op": "calculateAudioLevels",
            "pcm16Bytes": byteArray
        ])
        return [
            "rms": (data["rms"] as? Double) ?? 0.0,
            "peak": (data["peak"] as? Double) ?? 0.0,
            "dbFs": (data["dbFs"] as? Double) ?? -100.0
        ]
    }
}
