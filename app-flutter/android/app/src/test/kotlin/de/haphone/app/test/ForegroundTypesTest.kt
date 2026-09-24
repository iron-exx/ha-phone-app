package de.haphone.app.test

import android.content.pm.ServiceInfo
import org.junit.Assert.assertEquals
import org.junit.Test

class ForegroundTypesTest {
    private val special = ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
    private val phone = ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
    private val mic = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE

    @Test
    fun `before Android 10 the type is ignored`() {
        assertEquals(listOf(0), ForegroundTypes.candidates(26, inCall = true))
        assertEquals(listOf(0), ForegroundTypes.candidates(28, inCall = false))
    }

    @Test
    fun `Android 14 plus idles as specialUse and adds phoneCall and microphone in a call`() {
        assertEquals(listOf(special), ForegroundTypes.candidates(34, inCall = false))
        assertEquals(listOf(special or phone or mic, special or phone, special), ForegroundTypes.candidates(35, inCall = true))
    }

    @Test
    fun `Android 10 to 13 have no specialUse`() {
        assertEquals(listOf(0), ForegroundTypes.candidates(31, inCall = false))
        assertEquals(listOf(phone or mic, phone, 0), ForegroundTypes.candidates(30, inCall = true))
        assertEquals(listOf(phone, 0), ForegroundTypes.candidates(29, inCall = true))
    }
}
