package de.haphone.app.test.diag

/**
 * The app's own logcat (Ich -> Diagnose -> "Protokoll an die Anlage senden"). An app may read
 * its own process log without any permission. Credentials are cut out before it leaves the phone.
 */
object AppLog {
    private const val MAX_LINES = 12_000
    private const val MAX_CHARS = 1_800_000

    /** Blocking (runs logcat): call off the main thread. */
    fun read(pid: Int = android.os.Process.myPid()): String {
        val proc = ProcessBuilder("logcat", "-d", "-v", "threadtime", "-t", MAX_LINES.toString(), "--pid", pid.toString())
            .redirectErrorStream(true)
            .start()
        val text = proc.inputStream.bufferedReader().use { it.readText() }
        proc.waitFor()
        return AppLogRedactor.redact(text).takeLast(MAX_CHARS)
    }
}

/**
 * Pure (JVM-tested): masks DTMF digits in PJSIP log lines. Door codes and PINs typed during a
 * call (voicemail, bank IVR) must not end up in logcat, let alone in an uploaded log.
 * pjsua: "Call 0 sending DTMF 4711# using RFC2833 method"; pjmedia: "Sending DTMF digit id 4";
 * SIP INFO bodies: "Signal=4".
 */
object DtmfMask {
    private val rules = listOf(
        Regex("""(?i)(sending DTMF\s+)(?!digit\b)[0-9A-D*#]+""") to "$1<entfernt>",
        Regex("""(?i)(DTMF digit(?: id)?\s+)[0-9A-D*#]""") to "$1<entfernt>",
        Regex("""(?i)(\bSignal\s*=\s*)[0-9A-D*#]+""") to "$1<entfernt>",
    )

    fun mask(text: String): String =
        if (!text.contains("DTMF", ignoreCase = true) && !text.contains("Signal", ignoreCase = true)) text
        else rules.fold(text) { acc, (re, repl) -> re.replace(acc, repl) }
}

/** Pure (JVM-tested): strips credentials from log text. */
object AppLogRedactor {
    private val rules = listOf(
        Regex("""(?i)((?:Proxy-)?Authorization:\s*).*""") to "$1<entfernt>",
        Regex("""(?i)(WWW-Authenticate:\s*).*""") to "$1<entfernt>",
        Regex("""(?i)(X-Device-Token[=:"\s]+)[A-Za-z0-9._\-]+""") to "$1<entfernt>",
        Regex("""(?i)("?(?:password|passwort|sip_password|device_token|auth_key|authkey)"?\s*[=:]\s*"?)[^"\s,}]+""") to "$1<entfernt>",
        Regex("""tskey-[A-Za-z0-9\-]+""") to "tskey-<entfernt>",
    )

    fun redact(text: String): String = DtmfMask.mask(rules.fold(text) { acc, (re, repl) -> re.replace(acc, repl) })
}
