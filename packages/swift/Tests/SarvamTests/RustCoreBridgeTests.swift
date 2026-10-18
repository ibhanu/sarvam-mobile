import Foundation
import XCTest
@testable import Sarvam

final class RustCoreBridgeTests: XCTestCase {
    private func resolveDylibPath() -> String {
        let testFileUrl = URL(fileURLWithPath: #filePath)
        let repoRoot = testFileUrl
            .deletingLastPathComponent() // SarvamTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // swift
            .deletingLastPathComponent() // packages
            .deletingLastPathComponent() // sarvam-mobile
        return repoRoot
            .appendingPathComponent("packages/rust-core/target/release/libsarvam_rust_core.dylib")
            .path
    }

    func testRustCoreBridgeVersionEnvironmentErrorsRetrySseAndAudioDsp() throws {
        let dylibPath = resolveDylibPath()
        guard FileManager.default.fileExists(atPath: dylibPath) else {
            print("Skipping RustCoreBridgeTests: \(dylibPath) not found.")
            return
        }
        let bridge = try SarvamRustBridge(libraryPath: dylibPath)

        // 1. Version & Proxy Environment
        let ver = try bridge.version()
        XCTAssertFalse(ver["rustCoreVersion"]?.isEmpty ?? true)
        XCTAssertEqual(ver["specVersion"], "2026-10-16")

        let env = try bridge.resolveEnvironment(proxyBaseUrl: "https://bff.sarvam.ai/ios/")
        XCTAssertEqual(env["apiBaseUrl"], "https://bff.sarvam.ai/ios")
        XCTAssertEqual(env["dubbingBaseUrl"], "https://bff.sarvam.ai/ios/dubbing")
        XCTAssertEqual(env["wsBaseUrl"], "wss://bff.sarvam.ai/ios")

        // 2. HTTP 403 invalid_api_key_error Quirk -> AuthenticationError
        let classified = try bridge.classifyHttpError(
            statusCode: 403,
            headers: ["x-request-id": "req_swift_ffi_403"],
            rawBody: #"{"error":{"code":"invalid_api_key_error","message":"Invalid API key"}}"#
        )
        XCTAssertEqual(classified["type"] as? String, "AuthenticationError")
        XCTAssertEqual(classified["shouldTriggerTokenRefresh"] as? Bool, true)
        XCTAssertEqual(classified["requestId"] as? String, "req_swift_ffi_403")

        // 3. Safe Retry Matrix
        let retryDecision = try bridge.evaluateRetry(input: [
            "operationKind": "STATELESS_POST",
            "attempt": 0,
            "maxRetries": 2,
            "statusCode": 429,
            "headers": ["retry-after-ms": "65"],
            "rawBody": "",
            "isNetworkOrTimeoutError": false,
            "isTimeoutError": false,
            "isReplayableBody": true,
            "hasIdempotencyKey": false,
            "isTokenAuth": false,
            "hasRefreshedToken": false,
            "randomFactor": 0.5,
            "nowEpochMs": 0
        ])
        XCTAssertEqual(retryDecision["action"] as? String, "backoffAndRetry")
        XCTAssertEqual(retryDecision["delayMs"] as? Int, 65)

        // 4. SSE Chat V2 & Responses API
        let chatSse = try bridge.parseChatSse(
            "data: {\"id\":\"1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Nomoshkar\"}}]}\n\n" +
            "data: {\"id\":\"1\",\"choices\":[],\"usage\":{\"prompt_tokens\":4,\"completion_tokens\":2,\"total_tokens\":6}}\n\n" +
            "data: [DONE]\n"
        )
        XCTAssertEqual(chatSse["accumulatedContent"] as? String, "Nomoshkar")
        XCTAssertEqual(chatSse["terminatedOnDone"] as? Bool, true)

        let respSse = try bridge.parseResponsesSse(
            "event: response.completed\n" +
            "data: {\"id\":\"r1\",\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n\n"
        )
        XCTAssertEqual(respSse["terminatedOnEvent"] as? String, "response.completed")
        XCTAssertEqual(respSse["finalResponseStatus"] as? String, "completed")

        // 5. Binary FFI 16kHz PCM16 Resampler & Audio Levels
        var pcm48k = Data(count: 480 * 2)
        pcm48k.withUnsafeMutableBytes { buf in
            for i in 0..<480 {
                let sample: Int16 = (i % 2 == 0) ? 16384 : -16384
                buf.storeBytes(of: sample.littleEndian, toByteOffset: i * 2, as: Int16.self)
            }
        }
        let resampled16k = bridge.resamplePcm16(inputBytes: pcm48k, inputSampleRate: 48000, channelCount: 1)
        XCTAssertEqual(resampled16k.count, 160 * 2)
        XCTAssertEqual(bridge.resamplePcm16(inputBytes: Data(), inputSampleRate: 48000).count, 0)

        let levels = try bridge.calculateAudioLevels(pcm16Bytes: resampled16k)
        XCTAssertEqual(levels["peak"] ?? 0.0, 0.5, accuracy: 0.02)
        XCTAssertEqual(levels["rms"] ?? 0.0, 0.5, accuracy: 0.02)
    }
}
