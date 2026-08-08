package de.haphone.app.test.sip

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * Accumulates dialed digits for the 3 reuse contexts (D-12/D-13/D-14):
 * outgoing-call dialing, in-call DTMF entry, and blind-transfer target
 * entry -- one state holder, three call sites. Each appended character is
 * sanitized immediately so `current` never contains anything but
 * [0-9+*#].
 */
class DialedNumberState {
    var current: String by mutableStateOf("")
        private set

    fun append(char: Char) {
        val sanitized = DialString.sanitize(char.toString())
        if (sanitized.isNotEmpty()) current += sanitized
    }

    fun backspace() {
        if (current.isNotEmpty()) current = current.dropLast(1)
    }

    fun clear() {
        current = ""
    }

    fun toCallUri(domain: String): String = DialString.toSipUri(current, domain)
}
