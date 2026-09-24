package de.haphone.app.test

import android.content.Context
import android.os.PowerManager

/**
 * Short partial wake locks around work that must finish before the CPU sleeps again:
 * an incoming INVITE until the ringing UI/notification is posted, and a network change
 * until PJSIP has restarted its transport. Always time-limited, so a missed [release]
 * costs at most [TIMEOUT_MS] of battery. Any thread (PowerManager is thread-safe).
 */
object ShortWakeLock {
    const val TIMEOUT_MS = 10_000L

    @Volatile private var appContext: Context? = null
    private val locks = mutableMapOf<String, PowerManager.WakeLock>()

    fun attach(context: Context) {
        appContext = context.applicationContext
    }

    fun acquire(tag: String, timeoutMs: Long = TIMEOUT_MS) {
        val context = appContext ?: return
        runCatching {
            val lock = synchronized(locks) {
                locks.getOrPut(tag) {
                    context.getSystemService(PowerManager::class.java)
                        .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "HAPhone:$tag")
                        .also { it.setReferenceCounted(false) }
                }
            }
            lock.acquire(timeoutMs)
        }.onFailure { android.util.Log.w("ShortWakeLock", "acquire $tag failed", it) }
    }

    fun release(tag: String) {
        val lock = synchronized(locks) { locks[tag] } ?: return
        runCatching { if (lock.isHeld) lock.release() }
    }

    const val INCOMING_CALL = "incoming"
    const val NETWORK_CHANGE = "network"
}
