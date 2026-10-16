package ai.sarvam.core.middleware

import ai.sarvam.core.http.HttpRequest
import ai.sarvam.core.http.HttpResponse

public interface Middleware {
    public suspend fun intercept(
        request: HttpRequest,
        next: suspend (HttpRequest) -> HttpResponse
    ): HttpResponse
}
