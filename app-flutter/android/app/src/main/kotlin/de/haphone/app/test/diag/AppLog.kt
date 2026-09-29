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

/** Pure (JVM-tested): strips credentials from log text. */
object AppLogRedactor {
    private val rules = listOf(
        Regex("""(?i)((?:Proxy-)?Authorization:\s*).*""") to "$1<entfernt>",
        Regex("""(?i)(WWW-Authenticate:\s*).*""") to "$1<entfernt>",
        Regex("""(?i)(X-Device-Token[=:"\s]+)[A-Za-z0-9._\-]+""") to "$1<entfernt>",
        Regex("""(?i)("?(?:password|passwort|sip_password|device_token|auth_key|authkey)"?\s*[=:]\s*"?)[^"\s,}]+""") to "$1<entfernt>",
        Regex("""tskey-[A-Za-z0-9\-]+""") to "tskey-<entfernt>",
    )

    fun redact(text: String): String = rules.fold(text) { acc, (re, repl) -> re.replace(acc, repl) }
}
