package de.haphone.app.test.diag

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AppLogRedactorTest {
    @Test
    fun sipDigestHeadersAreRemoved() {
        val out = AppLogRedactor.redact(
            "D/PJSIP: Authorization: Digest username=\"12\", nonce=\"abc\", response=\"deadbeef\"\n" +
                "D/PJSIP: WWW-Authenticate: Digest realm=\"asterisk\",nonce=\"x\"\n" +
                "D/PJSIP: INVITE sip:12@192.168.7.219 SIP/2.0",
        )
        assertFalse(out.contains("deadbeef"))
        assertFalse(out.contains("nonce=\"x\""))
        assertTrue(out.contains("Authorization: <entfernt>"))
        assertTrue(out.contains("INVITE sip:12@192.168.7.219"))
    }

    @Test
    fun tokensPasswordsAndTailscaleKeysAreRemoved() {
        val out = AppLogRedactor.redact(
            "X-Device-Token: s3cr3t.tok_en\n{\"sip_password\":\"hunter2\",\"device_token\":\"abc\"}\npassword=geheim auth_key=tskey-auth-kXYZ-123",
        )
        for (secret in listOf("s3cr3t", "hunter2", "\"abc\"", "geheim", "kXYZ")) assertFalse(secret, out.contains(secret))
    }

    @Test
    fun ordinaryLinesStayUntouched() {
        val line = "09-29 20:50:02.123 I IncomingCall: incoming 3 from 16: FOCUSED (pjsip waiting=false, video=false)"
        assertEquals(line, AppLogRedactor.redact(line))
    }
}
