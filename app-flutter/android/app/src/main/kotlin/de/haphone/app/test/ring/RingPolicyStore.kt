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

    @Volatile private var context: Context? = null

    /** Door-number lookup (DoorCodes + DoorActionClient), set by the application. */
    @Volatile var knownDoor: (String) -> Boolean = { false }

    fun attach(ctx: Context, doorLookup: (String) -> Boolean) {
        context = ctx.applicationContext
        knownDoor = doorLookup
    }

    fun load(): RingPolicy {
        val p = context?.getSharedPreferences(PREFS, Context.MODE_PRIVATE) ?: return RingPolicy()
        return RingPolicy(
            enabled = p.getBoolean(KEY_ENABLED, true),
            mutedUntilMs = p.getLong(KEY_MUTED_UNTIL, 0L),
            allowDoor = p.getBoolean(KEY_ALLOW_DOOR, true),
        ).normalized(System.currentTimeMillis())
    }

    fun save(policy: RingPolicy): RingPolicy {
        val normalized = policy.normalized(System.currentTimeMillis())
        context?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)?.edit()
            ?.putBoolean(KEY_ENABLED, normalized.enabled)
            ?.putLong(KEY_MUTED_UNTIL, normalized.mutedUntilMs)
            ?.putBoolean(KEY_ALLOW_DOOR, normalized.allowDoor)
            ?.apply()
        Log.i(TAG, "saved enabled=${normalized.enabled} mutedUntil=${normalized.mutedUntilMs} allowDoor=${normalized.allowDoor}")
        return normalized
    }

    /** Decision for an incoming call; called on the PJSIP worker thread (prefs reads are thread-safe). */
    fun decide(number: String, hasVideo: Boolean): RingPolicy.Decision {
        val now = System.currentTimeMillis()
        val policy = load()
        val door = RingPolicy.isDoor(number, knownDoor, hasVideo)
        val decision = policy.decide(now, door)
        Log.i(
            TAG,
            "incoming from $number door=$door video=$hasVideo enabled=${policy.enabled} " +
                "mutedUntil=${policy.mutedUntilMs} allowDoor=${policy.allowDoor} -> $decision",
        )
        return decision
    }
}
