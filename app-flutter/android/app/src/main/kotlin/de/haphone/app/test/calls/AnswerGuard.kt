package de.haphone.app.test.calls

/**
 * Makes answering idempotent per SIP call: the ringing screen, the notification's
 * Annehmen action and Telecom's onAnswer (car, headset, watch) can all fire for the
 * same call, sometimes within milliseconds. Only the first one may send the 200 OK.
 * Pure, main thread only.
 */
class AnswerGuard {
    private val answered = mutableSetOf<Int>()

    /** True for the first answer attempt of [callId], false for every later one. */
    fun tryBegin(callId: Int): Boolean = answered.add(callId)

    fun isAnswered(callId: Int): Boolean = callId in answered

    /** The call ended: its id may be reused by pjsua for a later call. */
    fun forget(callId: Int) {
        answered.remove(callId)
    }

    fun clear() = answered.clear()
}
