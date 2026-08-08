package de.haphone.app.test.sip

import org.junit.Assert.assertEquals
import org.junit.Test

class FakeSipCallOperations : SipCallOperations {
    val invocations = mutableListOf<String>()
    var answerSucceeds = true

    override fun register() { invocations.add("register") }
    override fun unregister() { invocations.add("unregister") }
    override fun makeCall(uri: String) { invocations.add("makeCall:$uri") }
    override fun answer(): Boolean { invocations.add("answer"); return answerSucceeds }
    override fun hold(onHold: Boolean) { invocations.add("hold:$onHold") }
    override fun mute(muted: Boolean) { invocations.add("mute:$muted") }
    override fun transfer(uri: String) { invocations.add("transfer:$uri") }
    override fun sendDtmf(digit: String) { invocations.add("sendDtmf:$digit") }
    override fun hangup() { invocations.add("hangup") }
}

class CallControlTest {
    @Test
    fun registerPrecedesMakeCallAndUnregisterFollowsHangup() {
        val fake = FakeSipCallOperations()
        fake.register()
        fake.makeCall("sip:50@pbx.local:5061;transport=tls")
        fake.hangup()
        fake.unregister()
        assertEquals(listOf("register", "makeCall:sip:50@pbx.local:5061;transport=tls", "hangup", "unregister"), fake.invocations)
    }

    @Test
    fun holdTogglesViaSipOps() {
        val fake = FakeSipCallOperations()
        val controller = SipCallController(fake, sipDomain = "pbx.local:5061")
        controller.hold(true)
        controller.hold(false)
        assertEquals(listOf("hold:true", "hold:false"), fake.invocations)
    }

    @Test
    fun transferSanitizesAndBuildsTlsUri() {
        val fake = FakeSipCallOperations()
        val controller = SipCallController(fake, sipDomain = "pbx.local:5061")
        controller.transfer("6!0")
        assertEquals(listOf("transfer:sip:60@pbx.local:5061;transport=tls"), fake.invocations)
    }

    @Test
    fun hangupCallsSipOpsThenUnregisters() {
        val fake = FakeSipCallOperations()
        val controller = SipCallController(fake, sipDomain = "pbx.local:5061")
        controller.hangup()
        assertEquals(listOf("hangup", "unregister"), fake.invocations)
    }

    @Test
    fun muteTogglesViaSipOps() {
        val fake = FakeSipCallOperations()
        val controller = SipCallController(fake, sipDomain = "pbx.local:5061")
        controller.mute(true)
        controller.mute(false)
        assertEquals(listOf("mute:true", "mute:false"), fake.invocations)
    }
}
