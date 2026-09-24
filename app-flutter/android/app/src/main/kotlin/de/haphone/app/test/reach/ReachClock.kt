package de.haphone.app.test.reach

/**
 * The reachability maths (expiry, due times, backoff windows) runs on the monotonic
 * `SystemClock.elapsedRealtime()`, which keeps counting in deep sleep and does not jump
 * when the user or the network changes the wall clock. Wall-clock time is only for
 * display (Erreichbarkeit screen) and for what is persisted across reboots, where the
 * elapsed clock restarts at 0. Pure, unit-tested.
 */
object ReachClock {
    /** An elapsed-realtime instant as wall-clock ms, given both clocks read at the same moment. */
    fun toWall(elapsedMs: Long?, nowElapsedMs: Long, nowWallMs: Long): Long? =
        elapsedMs?.let { nowWallMs - (nowElapsedMs - it) }

    /** A persisted wall-clock instant on the elapsed-realtime axis (may be negative: before boot). */
    fun toElapsed(wallMs: Long?, nowElapsedMs: Long, nowWallMs: Long): Long? =
        wallMs?.let { nowElapsedMs - (nowWallMs - it) }

    fun toWall(p: PersistedReach, nowElapsedMs: Long, nowWallMs: Long) = PersistedReach(
        toWall(p.lastRegisteredAtMs, nowElapsedMs, nowWallMs),
        toWall(p.expiresAtMs, nowElapsedMs, nowWallMs),
        toWall(p.lastWakeupAtMs, nowElapsedMs, nowWallMs),
        toWall(p.lastTransportDropAtMs, nowElapsedMs, nowWallMs),
    )

    fun toElapsed(p: PersistedReach, nowElapsedMs: Long, nowWallMs: Long) = PersistedReach(
        toElapsed(p.lastRegisteredAtMs, nowElapsedMs, nowWallMs),
        toElapsed(p.expiresAtMs, nowElapsedMs, nowWallMs),
        toElapsed(p.lastWakeupAtMs, nowElapsedMs, nowWallMs),
        toElapsed(p.lastTransportDropAtMs, nowElapsedMs, nowWallMs),
    )
}
