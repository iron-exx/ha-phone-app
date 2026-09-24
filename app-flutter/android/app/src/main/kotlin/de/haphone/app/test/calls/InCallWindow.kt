package de.haphone.app.test.calls

/**
 * Whether a call is up (answered, connecting outgoing, or held), so the Flutter call screen
 * may show over the keyguard like the stock dialer does: MainActivity observes this and sets
 * showWhenLocked/turnScreenOn only while it is true. Without a call the flags are off again,
 * so the normal app (tabs, settings) is never usable over the lock screen. The keyguard is
 * never dismissed for the call. Ringing is not "active": that is IncomingCallActivity's job.
 * Pure state (no Android); main thread only. Fed from SipService.setInCall.
 */
object InCallWindow {
    fun interface Listener {
        fun onChanged(active: Boolean)
    }

    var isActive: Boolean = false
        private set

    private val listeners = LinkedHashSet<Listener>()

    /** Notifies listeners only on a real change. */
    fun setActive(active: Boolean) {
        if (isActive == active) return
        isActive = active
        listeners.toList().forEach { it.onChanged(active) }
    }

    /** Adds [listener] and immediately tells it the current state. */
    fun observe(listener: Listener) {
        listeners.add(listener)
        listener.onChanged(isActive)
    }

    fun remove(listener: Listener) {
        listeners.remove(listener)
    }

    /** For tests: back to "no call", no listeners. */
    internal fun reset() {
        listeners.clear()
        isActive = false
    }
}
