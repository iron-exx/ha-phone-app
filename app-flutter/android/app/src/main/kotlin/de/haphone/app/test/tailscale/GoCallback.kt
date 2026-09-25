package de.haphone.app.test.tailscale

import android.util.Log

/**
 * Runs a Java callback that Go calls through a method WITHOUT an error result.
 *
 * gomobile does not clear a Java exception thrown there: it stays pending, and the next
 * JNI call from that Go thread aborts the whole app ("Unknown reference: 42"). So such
 * callbacks must never throw; log and return [fallback] instead.
 */
internal inline fun <T> goSafe(what: String, fallback: T, block: () -> T): T =
    try {
        block()
    } catch (t: Throwable) {
        // Even logging must not throw here.
        runCatching { Log.e("GoCallback", "$what failed, returning fallback", t) }
        fallback
    }
