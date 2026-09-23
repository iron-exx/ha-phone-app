package de.haphone.app.test.sip

import org.junit.Assert.assertEquals
import org.junit.Test

class DtmfControllerTest {
    @Test
    fun sendDtmfSanitizesBeforeInvokingSipOps() {
        val fake = FakeSipCallOperations()
        val controller = SipCallController(fake, sipDomain = "pbx.local:5061")
        controller.sendDtmf("5x")
        assertEquals(listOf("sendDtmf:5"), fake.invocations)
    }

    @Test
    fun makeCallSanitizesAndBuildsTlsUri() {
        val fake = FakeSipCallOperations()
        val controller = SipCallController(fake, sipDomain = "pbx.local:5061")
        controller.makeCall("1a50")
        assertEquals(listOf("register", "makeCall:sip:150@pbx.local:5061;transport=tls"), fake.invocations)
    }
}
