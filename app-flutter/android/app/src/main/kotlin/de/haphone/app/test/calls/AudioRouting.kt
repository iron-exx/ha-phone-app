package de.haphone.app.test.calls

import androidx.core.telecom.CallControlScope
import androidx.core.telecom.CallEndpointCompat
import de.haphone.app.test.CallEventBus
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * Mirrors the Telecom call's audio endpoints (earpiece, speaker, Bluetooth, headset)
 * for the Flutter call screen. Android owns routing; we only ask for a change via
 * [CallControlScope.requestEndpointChange]. Collectors live in the call's own scope,
 * so they end with the call.
 */
object AudioRouting {
    // attach() runs on a Telecom coroutine thread, detach()/select() on main.
    @Volatile private var scope: CallControlScope? = null
    @Volatile private var available: List<CallEndpointCompat> = emptyList()
    @Volatile private var current: CallEndpointCompat? = null
    @Volatile private var collectors: List<Job> = emptyList()

    fun attach(callScope: CallControlScope) {
        detach()
        scope = callScope
        collectors = listOf(
            callScope.launch {
                callScope.availableEndpoints.collect {
                    available = it
                    emitChanged()
                }
            },
            callScope.launch {
                callScope.currentCallEndpoint.collect {
                    current = it
                    emitChanged()
                }
            },
        )
    }

    /** Stops the collectors now: the Telecom call scope itself only ends later, asynchronously. */
    fun detach() {
        collectors.forEach { it.cancel() }
        collectors = emptyList()
        scope = null
        available = emptyList()
        current = null
    }

    fun snapshot(): Map<String, Any> = mapOf(
        "current" to (current?.identifier?.toString() ?: ""),
        "routes" to available.map {
            mapOf("id" to it.identifier.toString(), "name" to it.name.toString(), "type" to typeName(it.type))
        },
    )

    /** false when there is no call or no endpoint with that id. */
    fun select(id: String): Boolean {
        val callScope = scope ?: return false
        val target = available.firstOrNull { it.identifier.toString() == id } ?: return false
        callScope.launch {
            val result = runCatching { callScope.requestEndpointChange(target) }
            android.util.Log.i("AudioRouting", "endpoint change to ${target.name}: $result")
        }
        return true
    }

    private fun emitChanged() {
        CallEventBus.emit(mapOf("type" to "audioRoute") + snapshot())
    }

    private fun typeName(type: Int): String = when (type) {
        CallEndpointCompat.TYPE_EARPIECE -> "earpiece"
        CallEndpointCompat.TYPE_SPEAKER -> "speaker"
        CallEndpointCompat.TYPE_BLUETOOTH -> "bluetooth"
        CallEndpointCompat.TYPE_WIRED_HEADSET -> "headset"
        else -> "other"
    }
}
