package de.haphone.app.test

import android.content.pm.ServiceInfo

/**
 * Foreground-service types for SipService, most capable first; the service tries them in
 * order until the system accepts one. Pure (SDK level passed in), unit-tested.
 *  - API < 29: the type argument is ignored -> 0.
 *  - API 29..33: no specialUse; idle = 0 (none), in call = phoneCall (+ microphone on 30+).
 *  - API 34+: idle = specialUse, in call = specialUse|phoneCall|microphone, then without mic.
 */
object ForegroundTypes {
    private const val API_Q = 29
    private const val API_R = 30
    private const val API_U = 34

    fun candidates(sdkInt: Int, inCall: Boolean): List<Int> {
        if (sdkInt < API_Q) return listOf(0)
        val base = if (sdkInt >= API_U) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0
        if (!inCall) return listOf(base)
        val phone = base or ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
        val withMic = if (sdkInt >= API_R) phone or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else phone
        return listOf(withMic, phone, base).distinct()
    }
}
