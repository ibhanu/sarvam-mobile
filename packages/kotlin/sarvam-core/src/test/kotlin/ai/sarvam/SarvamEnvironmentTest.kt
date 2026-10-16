package ai.sarvam

import ai.sarvam.core.SarvamEnvironment
import org.junit.Assert.assertEquals
import org.junit.Test

class SarvamEnvironmentTest {

    @Test
    fun `production environment has standard endpoints`() {
        val env = SarvamEnvironment.PRODUCTION
        assertEquals("https://api.sarvam.ai", env.apiBaseUrl)
        assertEquals("https://api.sarvam.ai/dubbing", env.dubbingBaseUrl)
        assertEquals("wss://api.sarvam.ai", env.wsBaseUrl)
    }

    @Test
    fun `proxy factory generates matching base URLs`() {
        val env = SarvamEnvironment.proxy("https://api.myapp.com/sarvam")
        assertEquals("https://api.myapp.com/sarvam", env.apiBaseUrl)
        assertEquals("https://api.myapp.com/sarvam/dubbing", env.dubbingBaseUrl)
        assertEquals("wss://api.myapp.com/sarvam", env.wsBaseUrl)
    }

    @Test
    fun `proxy factory strips trailing slashes`() {
        val env = SarvamEnvironment.proxy("https://api.myapp.com/sarvam/")
        assertEquals("https://api.myapp.com/sarvam", env.apiBaseUrl)
        assertEquals("https://api.myapp.com/sarvam/dubbing", env.dubbingBaseUrl)
        assertEquals("wss://api.myapp.com/sarvam", env.wsBaseUrl)
    }

    @Test
    fun `proxy factory converts http to ws`() {
        val env = SarvamEnvironment.proxy("http://localhost:8080")
        assertEquals("http://localhost:8080", env.apiBaseUrl)
        assertEquals("http://localhost:8080/dubbing", env.dubbingBaseUrl)
        assertEquals("ws://localhost:8080", env.wsBaseUrl)
    }
}
