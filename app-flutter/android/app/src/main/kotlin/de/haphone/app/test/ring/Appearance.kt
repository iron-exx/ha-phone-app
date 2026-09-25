package de.haphone.app.test.ring

import android.content.Context
import android.content.res.Configuration
import android.util.Log

/**
 * In-app "Erscheinungsbild" (Ich tab): Dunkel, Hell or Wie System. Nachtwache
 * is dark-first, so anything unknown or missing means [DARK]. The wire values
 * are the ones Dart sends via `setAppearance` (lib/services/appearance.dart).
 */
enum class Appearance(val wire: String) {
    DARK("dark"),
    LIGHT("light"),
    SYSTEM("system");

    /** Effective dark theme for this choice; [systemNight] only matters for [SYSTEM]. */
    fun isDark(systemNight: Boolean): Boolean = when (this) {
        DARK -> true
        LIGHT -> false
        SYSTEM -> systemNight
    }

    companion object {
        val DEFAULT = DARK

        fun fromWire(value: String?): Appearance = entries.firstOrNull { it.wire == value } ?: DEFAULT

        /** Night flag of a Configuration.uiMode value. */
        fun isNightUiMode(uiMode: Int): Boolean =
            (uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
    }
}

/**
 * Persists [Appearance] natively so the ringing screen (IncomingCallActivity)
 * can apply it even when it starts without the Flutter engine running.
 */
object AppearanceStore {
    private const val TAG = "Appearance"
    private const val PREFS = "haphone_appearance"
    private const val KEY_MODE = "mode"

    fun load(ctx: Context): Appearance =
        Appearance.fromWire(ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_MODE, null))

    fun save(ctx: Context, appearance: Appearance) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_MODE, appearance.wire).apply()
        Log.i(TAG, "saved ${appearance.wire}")
    }

    /** Effective dark theme for [ctx] (stored choice + the context's current night mode). */
    fun isDark(ctx: Context): Boolean =
        load(ctx).isDark(Appearance.isNightUiMode(ctx.resources.configuration.uiMode))
}
