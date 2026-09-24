package de.haphone.app.test.calls

/**
 * Bookkeeping for the Telecom calls this app registered, keyed by a token handed out
 * before `CallsManager.addCall` and tied to the SIP call id the Telecom call stands for.
 * Pure (generic over the scope type so it runs on the JVM), main thread only.
 *
 * Why: `addCall` registers asynchronously. A SIP call can end (caller gives up, PBX
 * CANCEL) before Telecom hands back its CallControlScope. Releasing then found no
 * scope and did nothing, and the scope that arrived afterwards kept a ghost call in
 * the system (car/Bluetooth showed a call forever). Now a release before registration
 * is remembered, and [attach] tells the caller to disconnect at once.
 *
 * With two SIP calls (call waiting, consultation) there is still one Telecom call; when
 * the SIP call it stands for ends while the other stays, [moveSipCall] re-binds it.
 */
class TelecomCallRegistry<S : Any> {
    private data class Entry<S>(
        val sipCallId: Int?,
        val scope: S?,
        val incoming: Boolean,
        val answered: Boolean = false,
    )

    private val live = LinkedHashMap<Int, Entry<S>>()
    /** Released before their scope arrived: [attach] must disconnect them. */
    private val releasedEarly = mutableSetOf<Int>()
    private var nextToken = 1

    /** A Telecom call is about to be registered for [sipCallId] (null: push, or outgoing before makeCall). */
    fun begin(sipCallId: Int?, incoming: Boolean = true): Int {
        val token = nextToken++
        live[token] = Entry(sipCallId, null, incoming)
        return token
    }

    /**
     * The INVITE of a push-announced call arrived: bind it to the still-ringing incoming
     * Telecom call that has no SIP call yet, instead of reporting a second one. Null if none.
     */
    fun adoptPushCall(sipCallId: Int): Int? {
        val token = live.entries.firstOrNull { (_, e) -> e.incoming && e.sipCallId == null && !e.answered }?.key
            ?: return null
        bindSipCall(token, sipCallId)
        return token
    }

    /** Outgoing call: pjsua assigned the SIP call id after Telecom registered the call. */
    fun bindSipCall(token: Int, sipCallId: Int) {
        live[token]?.let { live[token] = it.copy(sipCallId = sipCallId) }
    }

    /**
     * Telecom registered the call. Returns false when it was released meanwhile: the
     * caller must disconnect [scope] right away.
     */
    fun attach(token: Int, scope: S): Boolean {
        if (releasedEarly.remove(token)) return false
        val entry = live[token] ?: return false
        live[token] = entry.copy(scope = scope)
        return true
    }

    /** addCall failed: nothing to disconnect, forget the token. */
    fun forget(token: Int) {
        live.remove(token)
        releasedEarly.remove(token)
    }

    fun isLive(token: Int): Boolean = token in live

    fun sipCallIdFor(token: Int): Int? = live[token]?.sipCallId

    fun tokenFor(sipCallId: Int): Int? = live.entries.firstOrNull { it.value.sipCallId == sipCallId }?.key

    fun scopeFor(token: Int): S? = live[token]?.scope

    fun markAnswered(token: Int) {
        live[token]?.let { live[token] = it.copy(answered = true) }
    }

    fun isAnswered(token: Int): Boolean = live[token]?.answered == true

    /** A registered push call that no SIP call has taken over yet (still ringing). */
    fun hasUnansweredWithoutSipCall(): Boolean = live.values.any { it.incoming && it.sipCallId == null && !it.answered }

    /** SIP call [ended] is gone but [remaining] stays up in the same Telecom call. */
    fun moveSipCall(ended: Int, remaining: Int) {
        val token = tokenFor(ended) ?: return
        live[token]?.let { live[token] = it.copy(sipCallId = remaining) }
    }

    /**
     * Ends the bookkeeping for [token]. Returns the scope to disconnect, or null when Telecom
     * has not registered the call yet -- then the later [attach] returns false.
     */
    fun release(token: Int): S? {
        val entry = live.remove(token) ?: return null
        if (entry.scope == null) releasedEarly.add(token)
        return entry.scope
    }

    fun releaseFor(sipCallId: Int): S? = tokenFor(sipCallId)?.let { release(it) }

    /** Everything goes (last call ended); returns the registered scopes to disconnect. */
    fun releaseAll(): List<S> = live.keys.toList().mapNotNull { release(it) }

    /** The most recently registered live scope (audio routing, hold, active). */
    fun current(): S? = live.values.lastOrNull { it.scope != null }?.scope

    val isEmpty: Boolean get() = live.isEmpty()
}
