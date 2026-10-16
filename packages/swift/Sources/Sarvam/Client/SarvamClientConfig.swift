import Foundation

/// Configuration options for initializing a `SarvamClient`.
public struct SarvamClientConfig: Sendable {
    public var environment: SarvamEnvironment
    public var authProvider: AuthProvider
    public var transport: HTTPTransport
    public var webSocketFactory: WebSocketFactory
    public var middlewares: [Middleware]
    public var clock: ClockProvider
    public var random: RandomProvider
    public var defaultTimeoutInterval: TimeInterval
    public var maxRetries: Int

    public init(
        authProvider: AuthProvider,
        environment: SarvamEnvironment = .production,
        transport: HTTPTransport = URLSessionHTTPTransport(),
        webSocketFactory: WebSocketFactory = URLSessionWebSocketFactory(),
        middlewares: [Middleware]? = nil,
        clock: ClockProvider = SystemClockProvider(),
        random: RandomProvider = SystemRandomProvider(),
        defaultTimeoutInterval: TimeInterval = 60,
        maxRetries: Int = 2
    ) {
        self.authProvider = authProvider
        self.environment = environment
        self.transport = transport
        self.webSocketFactory = webSocketFactory
        self.clock = clock
        self.random = random
        self.defaultTimeoutInterval = defaultTimeoutInterval
        self.maxRetries = maxRetries

        if let customMiddlewares = middlewares {
            self.middlewares = customMiddlewares
        } else {
            // Default production middleware pipeline:
            // UserAgent -> Logging -> Auth -> Retry -> Transport
            self.middlewares = [
                UserAgentMiddleware(),
                LoggingMiddleware(),
                AuthMiddleware(authProvider: authProvider),
                RetryMiddleware(
                    defaultMaxRetries: maxRetries,
                    clock: clock,
                    random: random
                )
            ]
        }
    }

    /// Convenience initializer using a static subscription key.
    public init(
        apiKey: String,
        environment: SarvamEnvironment = .production,
        transport: HTTPTransport = URLSessionHTTPTransport(),
        webSocketFactory: WebSocketFactory = URLSessionWebSocketFactory(),
        clock: ClockProvider = SystemClockProvider(),
        random: RandomProvider = SystemRandomProvider(),
        defaultTimeoutInterval: TimeInterval = 60,
        maxRetries: Int = 2
    ) {
        let auth = ApiKeyAuth(apiKey: apiKey)
        self.init(
            authProvider: auth,
            environment: environment,
            transport: transport,
            webSocketFactory: webSocketFactory,
            clock: clock,
            random: random,
            defaultTimeoutInterval: defaultTimeoutInterval,
            maxRetries: maxRetries
        )
    }
}
