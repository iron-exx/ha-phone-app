package de.haphone.app.test.calls

import de.haphone.app.test.CallEventBus

/**
 * Glue between the PJSIP events and what the UI and the call history see: owns the
 * [CallSession] (up to two calls), writes history entries and tells Dart about changes.
 * Telecom and ringing-screen side effects stay in HAPhoneTestApplication. Main thread only.
 */
class CallCoordinator(
    private val history: CallHistoryStore,
    private val doorCodes: DoorCodes,
    private val doorActionLabels: (String) -> List<String> = { emptyList() },
    private val now: () -> Long = System::currentTimeMillis,
    /** An incoming call ended without being answered (doorbell picture notification). */
    private val onMissedIncoming: (number: String) -> Unit = {},
) {
    val session = CallSession()

    val currentCall: CurrentCall? get() = session.focused?.call

    private fun newCall(number: String, name: String, direction: String, video: Boolean, state: String): CurrentCall {
        val startedAt = now()
        val historyId = "$startedAt-$number"
        val entryName = if (name == number) "" else name
        history.update { CallHistory.add(it, CallHistoryEntry(historyId, number, entryName, direction, video, startedAt)) }
        historyChanged()
        return CurrentCall(
            historyId, number, entryName, direction, video, doorCodes.forNumber(number), state,
            doorActions = doorActionLabels(number),
        )
    }

    fun beginIncoming(callId: Int, number: String, name: String, video: Boolean): CallSession.IncomingRole {
        val role = session.addIncoming(callId, newCall(number, name, "incoming", video, "ringing"))
        changed(if (role == CallSession.IncomingRole.WAITING) "waiting" else "ringing")
        return role
    }

    /** Outgoing call before pjsua has an id for it ([bindOutgoing] follows). */
    fun beginOutgoing(number: String): Boolean {
        if (session.hasTwoCalls) return false
        val ok = session.addOutgoing(CallSession.PENDING_ID, newCall(number, "", "outgoing", false, "connecting"))
        changed("connecting")
        return ok
    }

    fun bindOutgoing(callId: Int) = session.bindPendingId(callId)

    /** makeCall threw: drop the pending line, the held call (if any) comes back on screen. */
    fun failOutgoing(): Boolean {
        ended(CallSession.PENDING_ID)
        return session.isEmpty
    }

    fun confirmed(callId: Int) {
        val line = session.find(callId) ?: return
        val at = now()
        session.confirm(callId, at)
        history.update { CallHistory.markAnswered(it, line.call.historyId, at) }
        historyChanged()
        changed("confirmed")
    }

    /** Returns true when no call is left (Telecom call and ringing UI can go). */
    fun ended(callId: Int): Boolean {
        val removed = session.remove(callId)
        if (removed != null) {
            history.update { CallHistory.markEnded(it, removed.call.historyId, now()) }
            historyChanged()
            if (removed.call.direction == "incoming" && removed.call.connectedAtMs == 0L) {
                onMissedIncoming(removed.call.number)
            }
        }
        return session.isEmpty
    }

    fun setMuted(muted: Boolean) = session.updateFocused { it.copy(muted = muted) }
    fun setHold(onHold: Boolean) = session.updateFocused { it.copy(onHold = onHold) }

    fun swap(): Boolean = session.swap().also { if (it) changed("swapped") }
    fun acceptWaiting(): Boolean = session.acceptWaiting().also { if (it) changed("connecting") }
    fun startConference(): Boolean = session.startConference().also { if (it) changed("conference") }

    fun snapshot(): Map<String, Any>? = session.toChannelMap()

    private fun changed(state: String) {
        val call = currentCall ?: return
        CallEventBus.emitCallState(call.number, call.direction, state)
    }

    private fun historyChanged() = CallEventBus.emit(mapOf("type" to "callHistoryChanged"))
}
