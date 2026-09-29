package de.haphone.app.test.ring

import android.content.Context
import android.util.Log

/**
 * Persists [RingPolicy] in SharedPreferences so the native incoming-call path
 * (PjsuaEndpointHolder.onIncomingCall) can read it without the Flutter engine.
 * Every decision is logged with tag [TAG].
 */
object RingPolicyStore {
    const val TAG = "RingPolicy"
    private const val PREFS = "haphone_ring_policy"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_MUTED_UNTIL = "mutedUntil"
    private const val KEY_ALLOW_DOOR = "allowDoor"
    private const val KEY_DOOR_LOUD = "doorLoud"

    @Volatile private var context: Context? = null

    /** Door-number lookup (DoorCodes + DoorActionClient), set by the application. */
    @Volatile var knownDoor: (String) -> Boolean = { false }

    /** The PBX's "Türstation" list (DoorCodes.stations), null on older PBX versions. */
    @Volatile var doorStations: () -> Set<String>? = { null }

    fun attach(ctx: Context, doorLookup: (String) -> Boolean, stations: () -> Set<String>?) {
        context = ctx.applicationContext
        knownDoor = doorLookup
        doorStations = stations
    }

    private fun isDoor(number: String, hasVideo: Boolean): Boolean =
        RingPolicy.isDoor(number, knownDoor, hasVideo, doorStations())

    fun load(): RingPolicy {
        val p = context?.getSharedPreferences(PREFS, Context.MODE_PRIVATE) ?: return RingPolicy()
        return RingPolicy(
            enabled = p.getBoolean(KEY_ENABLED, true),
            mutedUntilMs = p.getLong(KEY_MUTED_UNTIL, 0L),
            allowDoor = p.getBoolean(KEY_ALLOW_DOOR, true),
            doorLoud = p.getBoolean(KEY_DOOR_LOUD, false),
        ).normalized(System.currentTimeMillis())
    }

    fun save(policy: RingPolicy): RingPolicy {
        val normalized = policy.normalized(System.currentTimeMillis())
        context?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)?.edit()
            ?.putBoolean(KEY_ENABLED, normalized.enabled)
            ?.putLong(KEY_MUTED_UNTIL, normalized.mutedUntilMs)
            ?.putBoolean(KEY_ALLOW_DOOR, normalized.allowDoor)
            ?.putBoolean(KEY_DOOR_LOUD, normalized.doorLoud)
            ?.apply()
        Log.i(TAG, "saved enabled=${normalized.enabled} mutedUntil=${normalized.mutedUntilMs} allowDoor=${normalized.allowDoor} doorLoud=${normalized.doorLoud}")
        return normalized
    }

    /** "Türklingel auch bei lautlos" applies to this incoming call. */
    fun ringsLoud(number: String, hasVideo: Boolean): Boolean =
        load().ringsLoud(isDoor(number, hasVideo))

    /** Decision for an incoming call; called on the PJSIP worker thread (prefs reads are thread-safe). */
    fun decide(number: String, hasVideo: Boolean): RingPolicy.Decision {
        val now = System.currentTimeMillis()
        val policy = load()
        val door = isDoor(number, hasVideo)
        val decision = policy.decide(now, door)
        Log.i(
            TAG,
            "incoming from $number door=$door video=$hasVideo enabled=${policy.enabled} " +
                "mutedUntil=${policy.mutedUntilMs} allowDoor=${policy.allowDoor} -> $decision",
        )
        return decision
    }
}
