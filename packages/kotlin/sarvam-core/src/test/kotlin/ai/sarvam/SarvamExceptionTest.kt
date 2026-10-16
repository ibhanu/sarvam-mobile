package ai.sarvam

import ai.sarvam.core.error.SarvamException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SarvamExceptionTest {

    @Test
    fun `HTTP 401 maps to AuthenticationException`() {
        val json = """{"error":{"code":"unauthorized","message":"Missing API key","request_id":"req_1"}}"""
        val ex = SarvamException.fromHttpResponse(401, emptyMap(), json)
        assertTrue(ex is SarvamException.AuthenticationException)
        val authEx = ex as SarvamException.AuthenticationException
        assertEquals(401, authEx.statusCode)
        assertEquals("unauthorized", authEx.code)
        assertEquals("req_1", authEx.requestId)
        assertEquals("Missing API key", authEx.message?.substringAfterLast(": "))
    }

    @Test
    fun `HTTP 403 with invalid_api_key_error maps to AuthenticationException`() {
        val json = """{"error":{"code":"invalid_api_key_error","message":"Invalid API key","request_id":"req_auth_403"}}"""
        val ex = SarvamException.fromHttpResponse(403, emptyMap(), json)
        assertTrue(ex is SarvamException.AuthenticationException)
        val authEx = ex as SarvamException.AuthenticationException
        assertEquals(403, authEx.statusCode)
        assertEquals("invalid_api_key_error", authEx.code)
        assertEquals("req_auth_403", authEx.requestId)
    }

    @Test
    fun `HTTP 403 with authentication_error maps to PermissionDeniedException`() {
        val json = """{"error":{"code":"authentication_error","message":"Tier locked","request_id":"req_perm_403"}}"""
        val ex = SarvamException.fromHttpResponse(403, emptyMap(), json)
        assertTrue(ex is SarvamException.PermissionDeniedException)
        val permEx = ex as SarvamException.PermissionDeniedException
        assertEquals(403, permEx.statusCode)
        assertEquals("authentication_error", permEx.code)
        assertEquals("req_perm_403", permEx.requestId)
    }

    @Test
    fun `HTTP 400 maps to BadRequestException`() {
        val json = """{"error":{"code":"bad_request","message":"Missing required field"}}"""
        val ex = SarvamException.fromHttpResponse(400, emptyMap(), json)
        assertTrue(ex is SarvamException.BadRequestException)
    }

    @Test
    fun `HTTP 404 maps to NotFoundException`() {
        val json = """{"error":{"code":"not_found","message":"Resource not found"}}"""
        val ex = SarvamException.fromHttpResponse(404, emptyMap(), json)
        assertTrue(ex is SarvamException.NotFoundException)
    }

    @Test
    fun `HTTP 413 maps to PayloadTooLargeException`() {
        val json = """{"error":{"code":"payload_too_large","message":"File exceeds 10MB limit"}}"""
        val ex = SarvamException.fromHttpResponse(413, emptyMap(), json)
        assertTrue(ex is SarvamException.PayloadTooLargeException)
    }

    @Test
    fun `HTTP 422 maps to UnprocessableEntityException`() {
        val json = """{"error":{"code":"unprocessable_entity","message":"Invalid audio encoding"}}"""
        val ex = SarvamException.fromHttpResponse(422, emptyMap(), json)
        assertTrue(ex is SarvamException.UnprocessableEntityException)
    }

    @Test
    fun `HTTP 429 maps to RateLimitException with retry-after-ms`() {
        val json = """{"error":{"code":"rate_limit_exceeded_error","message":"Rate limit exceeded","request_id":"req_rl_1"}}"""
        val headers = mapOf("retry-after-ms" to listOf("50"))
        val ex = SarvamException.fromHttpResponse(429, headers, json)
        assertTrue(ex is SarvamException.RateLimitException)
        val rlEx = ex as SarvamException.RateLimitException
        assertEquals(50L, rlEx.retryAfterMs)
        assertEquals("rate_limit_exceeded_error", rlEx.code)
        assertEquals("req_rl_1", rlEx.requestId)
    }

    @Test
    fun `HTTP 503 with rate_limit_exceeded_error maps to RateLimitException`() {
        val json = """{"error":{"code":"rate_limit_exceeded_error","message":"Capacity reached"}}"""
        val ex = SarvamException.fromHttpResponse(503, emptyMap(), json)
        assertTrue(ex is SarvamException.RateLimitException)
    }

    @Test
    fun `HTTP 500 maps to ServerException`() {
        val json = """{"error":{"code":"internal_server_error","message":"Glitch","request_id":"req_job_500"}}"""
        val ex = SarvamException.fromHttpResponse(500, emptyMap(), json)
        assertTrue(ex is SarvamException.ServerException)
        val srvEx = ex as SarvamException.ServerException
        assertEquals(500, srvEx.statusCode)
        assertEquals("internal_server_error", srvEx.code)
        assertEquals("req_job_500", srvEx.requestId)
    }
}
