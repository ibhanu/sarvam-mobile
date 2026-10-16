import Foundation
import Testing
@testable import Sarvam

@Suite("Client Config, Environment, Auth & Utils Tests")
struct ClientConfigAndEnvTests {
    @Test("SarvamEnvironment resolution rules")
    func testSarvamEnvironment() {
        // Production
        let prod = SarvamEnvironment.production
        #expect(prod.apiBaseUrl == SarvamSpecMetadata.defaultApiBaseUrl)
        #expect(prod.dubbingBaseUrl == SarvamSpecMetadata.defaultDubbingBaseUrl)
        #expect(prod.wsBaseUrl == SarvamSpecMetadata.defaultWsBaseUrl)

        // Proxy with https
        let proxyHttps = SarvamEnvironment.proxy(baseUrl: "https://my-proxy.com/api/")
        #expect(proxyHttps.apiBaseUrl == "https://my-proxy.com/api")
        #expect(proxyHttps.dubbingBaseUrl == "https://my-proxy.com/api/dubbing")
        #expect(proxyHttps.wsBaseUrl == "wss://my-proxy.com/api")

        // Proxy with http
        let proxyHttp = SarvamEnvironment.proxy(baseUrl: "http://localhost:8080")
        #expect(proxyHttp.apiBaseUrl == "http://localhost:8080")
        #expect(proxyHttp.dubbingBaseUrl == "http://localhost:8080/dubbing")
        #expect(proxyHttp.wsBaseUrl == "ws://localhost:8080")

        // Proxy with custom scheme
        let proxyCustom = SarvamEnvironment.proxy(baseUrl: "custom://backend")
        #expect(proxyCustom.wsBaseUrl == "custom://backend")

        // Custom environment with explicit dubbing and ws
        let customExplicit = SarvamEnvironment(
            apiBaseUrl: "https://api.example.com/",
            dubbingBaseUrl: "https://dub.example.com/",
            wsBaseUrl: "wss://ws.example.com/"
        )
        #expect(customExplicit.apiBaseUrl == "https://api.example.com")
        #expect(customExplicit.dubbingBaseUrl == "https://dub.example.com")
        #expect(customExplicit.wsBaseUrl == "wss://ws.example.com")

        // Custom environment with defaults
        let customDefaultHttps = SarvamEnvironment(apiBaseUrl: "https://api.test.com")
        #expect(customDefaultHttps.dubbingBaseUrl == "https://api.test.com/dubbing")
        #expect(customDefaultHttps.wsBaseUrl == "wss://api.test.com")

        let customDefaultHttp = SarvamEnvironment(apiBaseUrl: "http://api.test.com")
        #expect(customDefaultHttp.wsBaseUrl == "ws://api.test.com")

        let customNoScheme = SarvamEnvironment(apiBaseUrl: "api.test.com")
        #expect(customNoScheme.wsBaseUrl == "api.test.com")

        // Equatable and Hashable
        #expect(customDefaultHttps == SarvamEnvironment(apiBaseUrl: "https://api.test.com/"))
        var set = Set<SarvamEnvironment>()
        set.insert(prod)
        set.insert(proxyHttps)
        #expect(set.count == 2)
    }

    @Test("SarvamClientConfig initializers and properties")
    func testClientConfig() {
        let auth = ApiKeyAuth(apiKey: "my-key")
        let config1 = SarvamClientConfig(
            authProvider: auth,
            defaultTimeoutInterval: 45,
            maxRetries: 3
        )
        #expect(config1.defaultTimeoutInterval == 45)
        #expect(config1.maxRetries == 3)
        #expect(config1.middlewares.count == 4) // UserAgent, Logging, Auth, Retry

        let customMiddlewares: [Middleware] = [UserAgentMiddleware()]
        let config2 = SarvamClientConfig(
            authProvider: auth,
            middlewares: customMiddlewares
        )
        #expect(config2.middlewares.count == 1)

        let config3 = SarvamClientConfig(apiKey: "convenience-key")
        #expect(config3.defaultTimeoutInterval == 60)
        #expect(config3.maxRetries == 2)
    }

    @Test("Auth providers getCredentials and invalidateToken")
    func testAuthProviders() async throws {
        // ApiKeyAuth
        let apiKeyAuth = ApiKeyAuth(apiKey: "secret-key")
        let keyCreds = try await apiKeyAuth.getCredentials()
        if case let .subscriptionKey(k) = keyCreds {
            #expect(k == "secret-key")
        } else {
            #expect(Bool(false), "Expected subscriptionKey")
        }
        await apiKeyAuth.invalidate()

        // ProxyAuth without headers provider
        let proxyAuthNil = ProxyAuth(proxyBaseUrl: "https://proxy.example.com")
        #expect(proxyAuthNil.proxyBaseUrl == "https://proxy.example.com")
        let nilCreds = try await proxyAuthNil.getCredentials()
        if case let .customHeaders(headers) = nilCreds {
            #expect(headers.isEmpty)
        }
        await proxyAuthNil.invalidate()

        // ProxyAuth with headers provider
        let proxyAuth = ProxyAuth(
            proxyBaseUrl: "https://proxy.example.com",
            headersProvider: { ["X-Custom-Auth": "proxy-token"] }
        )
        let proxyCreds = try await proxyAuth.getCredentials()
        if case let .customHeaders(headers) = proxyCreds {
            #expect(headers["X-Custom-Auth"] == "proxy-token")
        } else {
            #expect(Bool(false), "Expected customHeaders")
        }
        await proxyAuth.invalidate()
    }

    @Test("FileInput with Data, temporary file, non-existent file, and empty")
    func testFileInput() throws {
        // In-memory data
        let sampleData = Data("sample bytes".utf8)
        let inputData = FileInput(data: sampleData, fileName: "test.txt", mimeType: "text/plain", isReplayable: true)
        #expect(inputData.data == sampleData)
        #expect(inputData.fileName == "test.txt")
        #expect(inputData.mimeType == "text/plain")
        #expect(inputData.isReplayable)
        #expect(try inputData.readData() == sampleData)

        // Local file URL
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("sarvam_test_\(UUID().uuidString).bin")
        try sampleData.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let inputFile = FileInput(fileURL: tempFile)
        #expect(inputFile.fileName == tempFile.lastPathComponent)
        #expect(inputFile.mimeType == "application/octet-stream")
        #expect(try inputFile.readData() == sampleData)

        // Non-existent file URL
        let nonExistentFile = tempDir.appendingPathComponent("non_existent_\(UUID().uuidString).bin")
        let nonExistentInput = FileInput(fileURL: nonExistentFile)
        #expect(throws: SarvamError.self) {
            _ = try nonExistentInput.readData()
        }

        // Equatable
        let inputData2 = FileInput(data: sampleData, fileName: "test.txt", mimeType: "text/plain", isReplayable: true)
        #expect(inputData == inputData2)
    }

    @Test("SystemClockProvider and SystemRandomProvider")
    func testSystemProviders() async throws {
        let clock = SystemClockProvider()
        let now = clock.nowEpochMs()
        #expect(now > 1_600_000_000_000)

        try await clock.sleep(ms: 1)
        try await clock.sleep(ms: -10) // should return immediately without error

        let random = SystemRandomProvider()
        let d = random.nextDouble()
        #expect(d >= 0.0 && d < 1.0)

        let i = random.nextInt(in: 10...20)
        #expect(i >= 10 && i <= 20)
    }
}
