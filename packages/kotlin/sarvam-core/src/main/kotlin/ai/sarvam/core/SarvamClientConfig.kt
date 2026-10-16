package ai.sarvam.core

import ai.sarvam.core.auth.AuthProvider
import ai.sarvam.core.http.HttpRequest
import ai.sarvam.core.http.HttpResponse
import ai.sarvam.core.http.HttpTransport
import ai.sarvam.core.middleware.Middleware
import ai.sarvam.core.util.Clock
import ai.sarvam.core.util.DefaultRandomSource
import ai.sarvam.core.util.JsonHelper
import ai.sarvam.core.util.RandomSource
import ai.sarvam.core.util.SystemClock
import ai.sarvam.core.ws.WebSocketFactory
import kotlinx.serialization.json.Json

public class SarvamClientConfig(
    public val environment: SarvamEnvironment,
    public val authProvider: AuthProvider,
    public val transport: HttpTransport,
    public val webSocketFactory: WebSocketFactory,
    public val middlewares: List<Middleware>,
    public val clock: Clock = SystemClock,
    public val randomSource: RandomSource = DefaultRandomSource,
    public val json: Json = JsonHelper.defaultJson
) {
    public suspend fun execute(request: HttpRequest): HttpResponse {
        val chain: suspend (HttpRequest) -> HttpResponse = middlewares.foldRight(
            initial = { req -> transport.execute(req) }
        ) { middleware, next ->
            { req -> middleware.intercept(req, next) }
        }
        return chain(request)
    }
}
