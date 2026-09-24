package de.haphone.app.test

import android.telecom.DisconnectCause
import android.util.Log
import androidx.core.telecom.CallControlScope
import de.haphone.app.test.calls.TelecomCallRegistry
import kotlinx.coroutines.launch

/**
 * The app's Telecom calls, each tied to the SIP call it stands for ([TelecomCallRegistry]).
 * Replaces the former single `currentCallControlScope`, which was overwritten by every
 * new call and left a Telecom call stuck when the SIP call ended before `addCall` had
 * registered (see the registry's doc). Main thread only.
 */
class TelecomCalls {
    private val registry = TelecomCallRegistry<CallControlScope>()

    fun beginIncoming(sipCallId: Int?): Int = registry.begin(sipCallId, incoming = true)
    fun beginOutgoing(): Int = registry.begin(null, incoming = false)
    fun adoptPushCall(sipCallId: Int): Int? = registry.adoptPushCall(sipCallId)

    fun bindSipCall(token: Int, sipCallId: Int) = registry.bindSipCall(token, sipCallId)

    /** False when the call was released before Telecom registered it; then it is disconnected here. */
    fun onRegistered(token: Int, scope: CallControlScope): Boolean {
        if (registry.attach(token, scope)) return true
        disconnect(scope, DisconnectCause.REMOTE)
        return false
    }

    /** addCall failed, or Telecom itself disconnected the call: forget it without disconnecting again. */
    fun onFailed(token: Int) = registry.forget(token)

    fun isLive(token: Int) = registry.isLive(token)
    fun sipCallIdFor(token: Int): Int? = registry.sipCallIdFor(token)
    fun tokenFor(sipCallId: Int): Int? = registry.tokenFor(sipCallId)
    fun scopeFor(token: Int): CallControlScope? = registry.scopeFor(token)
    fun scopeForSipCall(sipCallId: Int): CallControlScope? = registry.tokenFor(sipCallId)?.let { registry.scopeFor(it) }
    fun markAnswered(token: Int) = registry.markAnswered(token)
    fun isAnswered(token: Int) = registry.isAnswered(token)
    fun hasUnansweredPushCall() = registry.hasUnansweredWithoutSipCall()
    fun moveSipCall(ended: Int, remaining: Int) = registry.moveSipCall(ended, remaining)

    /** The live Telecom call (audio routing, hold/active sync). */
    val current: CallControlScope? get() = registry.current()

    fun release(token: Int, cause: Int) {
        registry.release(token)?.let { disconnect(it, cause) }
    }

    fun releaseForSipCall(sipCallId: Int, cause: Int) {
        registry.releaseFor(sipCallId)?.let { disconnect(it, cause) }
    }

    fun releaseAll(cause: Int) {
        registry.releaseAll().forEach { disconnect(it, cause) }
    }

    private fun disconnect(scope: CallControlScope, cause: Int) {
        scope.launch {
            runCatching { scope.disconnect(DisconnectCause(cause)) }
                .onFailure { Log.w("TelecomCalls", "Telecom disconnect failed", it) }
        }
    }
}
