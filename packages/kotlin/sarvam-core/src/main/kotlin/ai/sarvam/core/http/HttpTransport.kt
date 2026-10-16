package ai.sarvam.core.http

public interface HttpTransport {
    public suspend fun execute(request: HttpRequest): HttpResponse
}
