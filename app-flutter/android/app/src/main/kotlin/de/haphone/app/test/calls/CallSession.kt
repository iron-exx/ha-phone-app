package de.haphone.app.test.calls

/**
 * Up to two SIP calls at once, the way a desk phone handles them: the [focused]
 * call is the one on screen, [other] is either on hold or ringing as call waiting.
 * Pure state (no Android/PJSIP), keyed by the pjsua call id; main thread only.
 * [PENDING_ID] marks an outgoing call whose pjsua id is not known yet.
 */
class CallSession {
    data class Line(val callId: Int, val call: CurrentCall)

    var focused: Line? = null
        private set
    var other: Line? = null
        private set
    var conference: Boolean = false
        private set

    val isEmpty: Boolean get() = focused == null && other == null
    val hasTwoCalls: Boolean get() = focused != null && other != null

    /** Where a new incoming call goes: on screen, as call waiting, or rejected (486). */
    enum class IncomingRole { FOCUSED, WAITING, REJECT }

    fun addIncoming(callId: Int, call: CurrentCall): IncomingRole = when {
        focused == null -> { focused = Line(callId, call); IncomingRole.FOCUSED }
        other == null -> { other = Line(callId, call.copy(state = "waiting")); IncomingRole.WAITING }
        else -> IncomingRole.REJECT
    }

    /** New outgoing call; an existing call is put on hold behind it (consultation). */
    fun addOutgoing(callId: Int, call: CurrentCall): Boolean {
        val current = focused
        if (current != null && other != null) return false
        if (current != null) other = current.copy(call = current.call.copy(onHold = true))
        focused = Line(callId, call)
        conference = false
        return true
    }

    fun bindPendingId(realId: Int) {
        focused?.takeIf { it.callId == PENDING_ID }?.let { focused = it.copy(callId = realId) }
    }

    fun find(callId: Int): Line? = listOfNotNull(focused, other).firstOrNull { it.callId == callId }

    fun update(callId: Int, transform: (CurrentCall) -> CurrentCall) {
        focused?.takeIf { it.callId == callId }?.let { focused = it.copy(call = transform(it.call)) }
        other?.takeIf { it.callId == callId }?.let { other = it.copy(call = transform(it.call)) }
    }

    fun updateFocused(transform: (CurrentCall) -> CurrentCall) {
        focused?.let { update(it.callId, transform) }
    }

    fun confirm(callId: Int, atMs: Long) = update(callId) {
        if (it.connectedAtMs > 0) it.copy(state = "confirmed") else it.copy(state = "confirmed", connectedAtMs = atMs)
    }

    /** Removes the call; if it was on screen, the remaining one moves up. Returns the removed line. */
    fun remove(callId: Int): Line? {
        val f = focused
        val o = other
        return when {
            f?.callId == callId -> { focused = o; other = null; conference = false; f }
            o?.callId == callId -> { other = null; conference = false; o }
            else -> null
        }
    }

    /** Makeln: the held call comes back, the current one goes on hold. */
    fun swap(): Boolean {
        val f = focused ?: return false
        val o = other ?: return false
        if (o.call.state == "waiting") return false
        focused = o.copy(call = o.call.copy(onHold = false))
        other = f.copy(call = f.call.copy(onHold = true))
        conference = false
        return true
    }

    /** Take the waiting call; the current one goes on hold. */
    fun acceptWaiting(): Boolean {
        val f = focused ?: return false
        val o = other ?: return false
        if (o.call.state != "waiting") return false
        focused = o.copy(call = o.call.copy(state = "connecting"))
        other = f.copy(call = f.call.copy(onHold = true))
        conference = false
        return true
    }

    fun startConference(): Boolean {
        val f = focused ?: return false
        val o = other ?: return false
        if (o.call.state != "confirmed" || f.call.state != "confirmed") return false
        focused = f.copy(call = f.call.copy(onHold = false))
        other = o.copy(call = o.call.copy(onHold = false))
        conference = true
        return true
    }

    fun toChannelMap(): Map<String, Any>? {
        val f = focused ?: return null
        val map = f.call.toChannelMap().toMutableMap()
        other?.let { map["other"] = it.call.toChannelMap() }
        map["conference"] = conference
        return map
    }

    companion object {
        const val PENDING_ID = Int.MIN_VALUE
    }
}
