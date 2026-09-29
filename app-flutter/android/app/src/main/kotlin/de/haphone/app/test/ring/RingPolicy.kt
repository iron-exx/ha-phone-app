package de.haphone.app.test.ring

/**
 * "Klingeln auf diesem Handy": a LOCAL setting of this device, independent of the
 * PBX presence. While ringing is off (or muted until [mutedUntilMs]) incoming calls
 * are rejected with 480 Temporarily Unavailable before any ringing UI, so a ring
 * group keeps ringing the other devices and a direct call runs into the PBX
 * fallback (voicemail / forwarding rule). Door-station calls still ring when
 * [allowDoor] ("Türklingel trotzdem") is set. [doorLoud] ("Türklingel auch bei
 * lautlos") makes door-station calls ring like an alarm clock (see RingAlert).
 *
 * Pure logic, unit-tested; persistence in [RingPolicyStore].
 */
data class RingPolicy(
    val enabled: Boolean = true,
    /** Epoch ms; 0 = not muted. A time in the past means ringing is back on. */
    val mutedUntilMs: Long = 0L,
    val allowDoor: Boolean = true,
    val doorLoud: Boolean = false,
) {
    enum class Decision { RING, RING_DOOR_OVERRIDE, REJECT_DISABLED, REJECT_MUTED }

    /** Muted until a time that has not passed yet. */
    fun isMutedAt(nowMs: Long): Boolean = mutedUntilMs > nowMs

    /** This handset rings for normal calls right now. */
    fun ringsAt(nowMs: Long): Boolean = enabled && !isMutedAt(nowMs)

    /** A door-station call rings despite a silent ringer (alarm stream). */
    fun ringsLoud(isDoor: Boolean): Boolean = isDoor && doorLoud

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
        "doorLoud" to doorLoud,
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
            doorLoud = map["doorLoud"] as? Boolean ?: base.doorLoud,
        )

        /**
         * A caller is a door station if the PBX's "Türstation" switch says so ([stations],
         * HA-Phone 0.7.138). Older PBX versions send no switch ([stations] null): then its
         * door settings (door code, webhook opening, Home Assistant actions, [knownDoor])
         * or an INVITE offering video count, as before.
         */
        fun isDoor(
            number: String,
            knownDoor: (String) -> Boolean,
            hasVideo: Boolean,
            stations: Set<String>? = null,
        ): Boolean =
            if (stations != null) number.isNotBlank() && number in stations
            else hasVideo || (number.isNotBlank() && knownDoor(number))
    }
}
