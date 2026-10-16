import Foundation
import Testing
@testable import Sarvam

@Suite("Auth Provider Tests")
struct AuthTests {

    @Test("ApiKeyAuth returns subscriptionKey and does not crash")
    func testApiKeyAuth() async throws {
        let auth = ApiKeyAuth(apiKey: "sk-12345")
        let creds = try await auth.getCredentials()
        #expect(creds == .subscriptionKey("sk-12345"))
        await auth.invalidate()
        let creds2 = try await auth.getCredentials()
        #expect(creds2 == .subscriptionKey("sk-12345"))
    }

    @Test("TokenAuth single-flight deduplication across concurrent requests")
    func testTokenAuthSingleFlight() async throws {
        actor RefreshCounter {
            var count = 0
            func increment() -> Int {
                count += 1
                return count
            }
        }
        let counter = RefreshCounter()
        let clock = MockClockProvider()

        let tokenAuth = TokenAuth(
            tokenProvider: {
                let c = await counter.increment()
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms simulated network
                return AuthToken(token: "token-\(c)", expiresAtEpochMs: clock.nowEpochMs() + 300_000)
            },
            clock: clock
        )

        // Launch 5 concurrent calls
        async let c1 = tokenAuth.getCredentials()
        async let c2 = tokenAuth.getCredentials()
        async let c3 = tokenAuth.getCredentials()
        async let c4 = tokenAuth.getCredentials()
        async let c5 = tokenAuth.getCredentials()

        let results = try await [c1, c2, c3, c4, c5]

        let totalRefreshes = await counter.count
        #expect(totalRefreshes == 1)
        for res in results {
            #expect(res == .bearerToken(token: "token-1", expiresAtEpochMs: clock.nowEpochMs() + 300_000))
        }
    }

    @Test("TokenAuth proactive expiry within 60s buffer")
    func testTokenAuthExpiryBuffer() async throws {
        let clock = MockClockProvider(initialEpochMs: 1_000_000)
        actor Counter {
            var count = 0
            func next() -> String {
                count += 1
                return "token-\(count)"
            }
        }
        let counter = Counter()

        let tokenAuth = TokenAuth(
            tokenProvider: {
                let tok = await counter.next()
                // Expires in 120 seconds (120,000 ms)
                return AuthToken(token: tok, expiresAtEpochMs: clock.nowEpochMs() + 120_000)
            },
            clock: clock,
            expiryBufferMs: 60_000
        )

        // First fetch
        let c1 = try await tokenAuth.getCredentials()
        #expect(c1 == .bearerToken(token: "token-1", expiresAtEpochMs: 1_120_000))

        // Advance clock by 30 seconds (remaining: 90s > 60s buffer) -> should reuse cached
        clock.advance(ms: 30_000)
        let c2 = try await tokenAuth.getCredentials()
        #expect(c2 == .bearerToken(token: "token-1", expiresAtEpochMs: 1_120_000))

        // Advance clock by 40 more seconds (total advance: 70s, remaining: 50s < 60s buffer) -> should refresh!
        clock.advance(ms: 40_000)
        let c3 = try await tokenAuth.getCredentials()
        #expect(c3 == .bearerToken(token: "token-2", expiresAtEpochMs: 1_070_000 + 120_000))
    }

    @Test("ProxyAuth injects custom headers")
    func testProxyAuth() async throws {
        let proxy = ProxyAuth(
            proxyBaseUrl: "https://api.mycorp.internal/sarvam",
            headersProvider: {
                ["x-app-session": "sess_abc123", "x-tenant-id": "tenant_xyz"]
            }
        )

        let creds = try await proxy.getCredentials()
        guard case let .customHeaders(headers) = creds else {
            Issue.record("Expected customHeaders")
            return
        }
        #expect(headers["x-app-session"] == "sess_abc123")
        #expect(headers["x-tenant-id"] == "tenant_xyz")
    }
}
