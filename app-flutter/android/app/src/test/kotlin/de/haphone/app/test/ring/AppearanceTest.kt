package de.haphone.app.test.ring

import android.content.res.Configuration
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AppearanceTest {
    @Test
    fun defaultIsDark() {
        assertEquals(Appearance.DARK, Appearance.DEFAULT)
        assertEquals(Appearance.DARK, Appearance.fromWire(null))
    }

    @Test
    fun unknownWireValueFallsBackToDark() {
        assertEquals(Appearance.DARK, Appearance.fromWire(""))
        assertEquals(Appearance.DARK, Appearance.fromWire("purple"))
    }

    @Test
    fun wireValuesRoundTrip() {
        for (a in Appearance.entries) assertEquals(a, Appearance.fromWire(a.wire))
        assertEquals(Appearance.LIGHT, Appearance.fromWire("light"))
        assertEquals(Appearance.SYSTEM, Appearance.fromWire("system"))
    }

    @Test
    fun darkIgnoresSystem() {
        assertTrue(Appearance.DARK.isDark(systemNight = false))
        assertTrue(Appearance.DARK.isDark(systemNight = true))
    }

    @Test
    fun lightIgnoresSystem() {
        assertFalse(Appearance.LIGHT.isDark(systemNight = false))
        assertFalse(Appearance.LIGHT.isDark(systemNight = true))
    }

    @Test
    fun systemFollowsSystem() {
        assertTrue(Appearance.SYSTEM.isDark(systemNight = true))
        assertFalse(Appearance.SYSTEM.isDark(systemNight = false))
    }

    @Test
    fun nightUiModeMask() {
        assertTrue(Appearance.isNightUiMode(Configuration.UI_MODE_NIGHT_YES or Configuration.UI_MODE_TYPE_NORMAL))
        assertFalse(Appearance.isNightUiMode(Configuration.UI_MODE_NIGHT_NO or Configuration.UI_MODE_TYPE_NORMAL))
        assertFalse(Appearance.isNightUiMode(Configuration.UI_MODE_NIGHT_UNDEFINED))
    }
}
