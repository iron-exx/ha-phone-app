package de.haphone.app.test.sip

/**
 * Client-side digit sanitization mirroring the server-side `_dial_string`
 * pattern in ~/projects/Ha-Phone/ha-phone/backend/routers/extensions.py
 * (Security V5 -- prevents SIP URI/header injection via a malformed
 * dialpad string, T-2-08). Reused for dial (CALL-03), DTMF (CALL-02),
 * and blind-transfer target entry (CALL-04) per D-12/D-13/D-14 -- one
 * function, three call sites.
 */
object DialString {
    private val ALLOWED = Regex("[^0-9+*#]")

    fun sanitize(raw: String): String = ALLOWED.replace(raw, "")

    fun toSipUri(sanitized: String, domain: String): String {
        require(sanitized.isNotEmpty()) { "Cannot build a sip: URI with no digits" }
        return "sip:$sanitized@$domain;transport=tls"
    }
}
