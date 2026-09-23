package de.haphone.app.test.calls

/** The one call this app handles at a time. Main thread only. */
data class CurrentCall(
    val historyId: String,
    val number: String,
    val name: String,
    val direction: String, // "incoming" | "outgoing"
    val video: Boolean,
    val doorCode: String,
    val state: String, // "ringing" | "connecting" | "confirmed"
    val connectedAtMs: Long = 0,
    val muted: Boolean = false,
    val onHold: Boolean = false,
    /** Labels of the door station's Home Assistant actions (index = button position). */
    val doorActions: List<String> = emptyList(),
) {
    fun toChannelMap(): Map<String, Any> = mapOf(
        "number" to number,
        "name" to name,
        "direction" to direction,
        "video" to video,
        "doorCode" to doorCode,
        "state" to state,
        "connectedAtMs" to connectedAtMs,
        "muted" to muted,
        "onHold" to onHold,
        "doorActions" to doorActions,
        // Every account registers over TLS (PjsuaEndpointHolder), so signalling is always encrypted.
        "secure" to true,
    )
}
