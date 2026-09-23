package de.haphone.app.test

import com.google.crypto.tink.subtle.Ed25519Verify
import java.util.Base64

object EnvelopeVerifier {
    val canonicalFieldOrder = listOf("call_id", "call_type", "caller", "event_id", "expires_at", "issued_at", "v")

    fun canonicalBytes(envelope: Map<String, Any>): ByteArray? {
        val parts = mutableListOf<String>()
        for (key in canonicalFieldOrder) {
            val value = envelope[key] ?: return null
            when (value) {
                is Int, is Long -> parts.add("\"$key\":$value")
                is String -> {
                    val escaped = value.replace("\\", "\\\\").replace("\"", "\\\"")
                    parts.add("\"$key\":\"$escaped\"")
                }
                else -> return null
            }
        }
        return ("{" + parts.joinToString(",") + "}").toByteArray(Charsets.UTF_8)
    }

    fun verify(envelope: Map<String, Any>, publicKeyHex: String): Boolean = try {
        val sigB64 = envelope["sig"] as? String ?: return false
        val sigBytes = Base64.getDecoder().decode(sigB64)
        val canonical = canonicalBytes(envelope) ?: return false
        val verifier = Ed25519Verify(hexToBytes(publicKeyHex))
        verifier.verify(sigBytes, canonical)
        true
    } catch (e: Exception) {
        false
    }

    fun isExpired(envelope: Map<String, Any>, now: Long = System.currentTimeMillis() / 1000): Boolean {
        val expiresAt = (envelope["expires_at"] as? Number)?.toLong() ?: return true
        return now > expiresAt
    }

    private fun hexToBytes(hex: String): ByteArray {
        val out = ByteArray(hex.length / 2)
        for (i in out.indices) {
            out[i] = ((Character.digit(hex[i * 2], 16) shl 4) + Character.digit(hex[i * 2 + 1], 16)).toByte()
        }
        return out
    }
}
