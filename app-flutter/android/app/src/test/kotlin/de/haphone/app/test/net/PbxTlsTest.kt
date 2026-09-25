package de.haphone.app.test.net

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PbxTlsTest {
    private val pin = PbxTls.Pin("ab".repeat(32), 8443)

    @Test
    fun `base url is plain http without a pin`() {
        assertEquals("http://192.168.7.10", PbxTls.baseUrl("192.168.7.10", PbxTls.Pin.NONE))
        assertEquals("http://192.168.7.10:8080", PbxTls.baseUrl("192.168.7.10:8080", PbxTls.Pin.NONE))
    }

    @Test
    fun `base url switches to the https port with a pin, dropping any http port`() {
        assertEquals("https://192.168.7.10:8443", PbxTls.baseUrl("192.168.7.10", pin))
        assertEquals("https://100.117.178.114:8443", PbxTls.baseUrl("100.117.178.114:80", pin))
        assertEquals("https://[fd7a::1]:8443", PbxTls.baseUrl("[fd7a::1]:80", pin))
        assertEquals("https://[fd7a::1]:8443", PbxTls.baseUrl("fd7a::1", pin))
    }

    @Test
    fun `sha256 hex of der bytes`() {
        // sha256("abc")
        assertEquals(
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            PbxTls.sha256Hex("abc".toByteArray()),
        )
    }

    @Test
    fun `pin matches case-insensitively and ignores colons`() {
        val der = "abc".toByteArray()
        assertTrue(PbxTls.matches(der, "BA:78:16:BF:8F:01:CF:EA:41:41:40:DE:5D:AE:22:23:B0:03:61:A3:96:17:7A:9C:B4:10:FF:61:F2:00:15:AD"))
        assertFalse(PbxTls.matches(der, "00".repeat(32)))
        assertFalse(PbxTls.matches(der, ""))
    }

    @Test
    fun `pin is usable only with a fingerprint and a port`() {
        assertTrue(pin.isSet)
        assertFalse(PbxTls.Pin("ab".repeat(32), 0).isSet)
        assertFalse(PbxTls.Pin("", 8443).isSet)
        assertFalse(PbxTls.Pin("nothex", 8443).isSet)
    }

    @Test
    fun `sip tls is accepted only with the pinned cert`() {
        val der = "abc".toByteArray()
        val pem = "-----BEGIN CERTIFICATE-----\n" + java.util.Base64.getEncoder().encodeToString(der) + "\n-----END CERTIFICATE-----\n"
        val good = PbxTls.Pin(PbxTls.sha256Hex(der), 8443)
        assertTrue(PbxTls.acceptSipTls(good, isTls = true, remoteCertPem = pem))
        assertFalse(PbxTls.acceptSipTls(pin, isTls = true, remoteCertPem = pem))
        assertFalse(PbxTls.acceptSipTls(good, isTls = true, remoteCertPem = null))
        assertFalse(PbxTls.acceptSipTls(good, isTls = true, remoteCertPem = "garbage"))
        assertTrue(PbxTls.acceptSipTls(PbxTls.Pin.NONE, isTls = true, remoteCertPem = null))
        assertTrue(PbxTls.acceptSipTls(good, isTls = false, remoteCertPem = null))
    }
}
