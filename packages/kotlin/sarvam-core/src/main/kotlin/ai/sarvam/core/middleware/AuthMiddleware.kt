package ai.sarvam.core.middleware

import ai.sarvam.core.auth.AuthProvider
import ai.sarvam.core.auth.SarvamCredentials
import ai.sarvam.core.auth.TokenAuth
import ai.sarvam.core.error.SarvamException
import ai.sarvam.core.http.HttpRequest
import ai.sarvam.core.http.HttpResponse

public class AuthMiddleware(
    private val authProvider: AuthProvider
) : Middleware {

    override suspend fun intercept(
        request: HttpRequest,
        next: suspend (HttpRequest) -> HttpResponse
    ): HttpResponse {
        val initialCredentials = authProvider.getCredentials()
        val reqWithAuth = applyCredentials(request, initialCredentials)
        return try {
            next(reqWithAuth)
        } catch (e: SarvamException.AuthenticationException) {
            // Only retry once if authProvider is TokenAuth and can refresh credentials
            if (authProvider is TokenAuth) {
                authProvider.invalidate()
                val freshCredentials = authProvider.getCredentials()
                if (freshCredentials != initialCredentials) {
                    val retriedReq = applyCredentials(request, freshCredentials)
                    return next(retriedReq)
                }
            }
            throw e
        }
    }

    private fun applyCredentials(request: HttpRequest, credentials: SarvamCredentials): HttpRequest {
        return when (credentials) {
            is SarvamCredentials.SubscriptionKey -> {
                request.withHeader("api-subscription-key", credentials.key)
            }
            is SarvamCredentials.BearerToken -> {
                request.withHeader("Authorization", "Bearer ${credentials.token}")
            }
            is SarvamCredentials.CustomHeaders -> {
                request.withHeaders(credentials.headers)
            }
        }
    }
}
