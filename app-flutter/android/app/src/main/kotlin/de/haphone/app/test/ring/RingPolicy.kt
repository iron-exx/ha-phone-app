package de.haphone.app.test.ring

/**
 * "Klingeln auf diesem Handy": a LOCAL setting of this device, independent of the
 * PBX presence. While ringing is off (or muted until [mutedUntilMs]) incoming calls
 * are rejected with 480 Temporarily Unavailable before any ringing UI, so a ring
 * group keeps ringing the other devices and a direct call runs into the PBX
 * fallback (voicemail / forwarding rule). Door-station calls still ring when
 * [allowDoor] ("Türklingel trotzdem") is set.
 *
 * Pure logic, unit-tested; persistence in [RingPolicyStore].
 */
data class RingPolicy(
    val enabled: Boolean = true,
    /** Epoch ms; 0 = not muted. A time in the past means ringing is back on. */
    val mutedUntilMs: Long = 0L,
    val allowDoor: Boolean = true,
) {
    enum class Decision { RING, RING_DOOR_OVERRIDE, REJECT_DISABLED, REJECT_MUTED }

    /** Muted until a time that has not passed yet. */
    fun isMutedAt(nowMs: Long): Boolean = mutedUntilMs > nowMs

    /** This handset rings for normal calls right now. */
    fun ringsAt(nowMs: Long): Boolean = enabled && !isMutedAt(nowMs)

    fun decide(nowMs: Long, isDoor: Boolean): Decision {
        if (ringsAt(nowMs)) return Decision.RING
        if (isDoor && allowDoor) return Decision.RING_DOOR_OVERRIDE
        return if (!enabled) Decision.REJECT_DISABLED else Decision.REJECT_MUTED
    }

    /** Drops an expired mute so the stored state and the UI agree. */
    fun normalized(nowMs: Long): RingPolicy =
        if (mutedUntilMs != 0L && mutedUntilMs <= nowMs) copy(mutedUntilMs = 0L) else this

    fun toMap(): Map<String, Any> = mapOf(
        "enabled" to enabled,
        "mutedUntil" to mutedUntilMs,
        "allowDoor" to allowDoor,
    )

    companion object {
        /** SIP 480 Temporarily Unavailable. */
        const val REJECT_STATUS = 480

        fun Decision.rejects(): Boolean = this == Decision.REJECT_DISABLED || this == Decision.REJECT_MUTED

        /** From the MethodChannel map; missing keys keep [base]'s values. */
        fun fromMap(map: Map<*, *>, base: RingPolicy = RingPolicy()): RingPolicy = RingPolicy(
            enabled = map["enabled"] as? Boolean ?: base.enabled,
            mutedUntilMs = (map["mutedUntil"] as? Number)?.toLong()?.coerceAtLeast(0L) ?: base.mutedUntilMs,
            allowDoor = map["allowDoor"] as? Boolean ?: base.allowDoor,
        )

        /**
         * A caller counts as a door station if the PBX marked its number as one
         * (door code, webhook opening or Home Assistant actions, see DoorCodes /
         * DoorActionClient) or the INVITE offers video (the Akuvox always does).
         */
        fun isDoor(number: String, knownDoor: (String) -> Boolean, hasVideo: Boolean): Boolean =
            hasVideo || (number.isNotBlank() && knownDoor(number))
    }
}
