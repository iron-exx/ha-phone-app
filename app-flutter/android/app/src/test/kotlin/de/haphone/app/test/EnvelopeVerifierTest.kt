package de.haphone.app.test

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EnvelopeVerifierTest {

    private val publicKeyHex = "8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c"
    private val fixtureSig =
        "OkK98iMhFXjo/2IRqckexlCdJfj2dQo4T/CMoedRvwOGfTCsGrA3et4nxvSvlMActs+ijn6bW91Ge3+gcIn/BA=="
    private val expectedCanonical =
        "{\"call_id\":\"11111111-1111-1111-1111-111111111111\",\"call_type\":\"audio\"," +
            "\"caller\":\"HA-Phone Testanruf\",\"event_id\":\"22222222-2222-2222-2222-222222222222\"," +
            "\"expires_at\":1700000030,\"issued_at\":1700000000,\"v\":1}"

    private fun fixtureEnvelope(): Map<String, Any> = mapOf(
        "call_id" to "11111111-1111-1111-1111-111111111111",
        "call_type" to "audio",
        "caller" to "HA-Phone Testanruf",
        "event_id" to "22222222-2222-2222-2222-222222222222",
        "expires_at" to 1700000030,
        "issued_at" to 1700000000,
        "v" to 1,
    )

    @Test
    fun goldenCanonicalBytesMatchFixture() {
        val bytes = EnvelopeVerifier.canonicalBytes(fixtureEnvelope())
        assertEquals(expectedCanonical, String(bytes!!, Charsets.UTF_8))
    }

    @Test
    fun goldenSignatureVerifies() {
        val signed = fixtureEnvelope() + ("sig" to fixtureSig)
        assertTrue(EnvelopeVerifier.verify(signed, publicKeyHex))
    }

    @Test
    fun tamperedCallerFailsVerification() {
        val signed = fixtureEnvelope() + ("sig" to fixtureSig) + ("caller" to "HA-Phone Testanrufx")
        assertFalse(EnvelopeVerifier.verify(signed, publicKeyHex))
    }

    @Test
    fun isExpiredTrueForPastTimestamp() {
        val envelope = fixtureEnvelope()
        assertTrue(EnvelopeVerifier.isExpired(envelope, now = 1700000031L))
    }

    @Test
    fun isExpiredFalseForFutureTimestamp() {
        val envelope = fixtureEnvelope()
        assertFalse(EnvelopeVerifier.isExpired(envelope, now = 1700000029L))
    }
}
