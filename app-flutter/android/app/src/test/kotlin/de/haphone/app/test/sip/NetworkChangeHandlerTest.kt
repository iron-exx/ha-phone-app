package de.haphone.app.test.sip

import org.junit.Assert.assertEquals
import org.junit.Test

class NetworkChangeHandlerTest {
    @Test
    fun onNetworkAvailableInvokesHandleIpChangeOnNotifier() {
        val calls = mutableListOf<String>()
        val notifier = object : IpChangeNotifier {
            override fun handleIpChange() { calls.add("handleIpChange") }
        }
        val handler = NetworkChangeHandler(notifier)
        handler.onNetworkAvailable()
        assertEquals(listOf("handleIpChange"), calls)
    }
}
