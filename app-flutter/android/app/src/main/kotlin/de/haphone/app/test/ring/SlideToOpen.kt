package de.haphone.app.test.ring

/**
 * Geometry of the "Zum Öffnen nach rechts schieben" control. The thumb travels
 * from 0 to [maxOffset]; letting go at >= [TRIGGER_FRACTION] opens, anything
 * less snaps back, so a pocket brush never opens the door.
 */
object SlideToOpen {
    const val TRIGGER_FRACTION = 0.85f

    fun maxOffset(trackWidth: Float, thumbSize: Float, inset: Float): Float =
        (trackWidth - thumbSize - 2 * inset).coerceAtLeast(0f)

    fun clamp(offset: Float, maxOffset: Float): Float = offset.coerceIn(0f, maxOffset.coerceAtLeast(0f))

    fun progress(offset: Float, maxOffset: Float): Float =
        if (maxOffset <= 0f) 0f else (offset / maxOffset).coerceIn(0f, 1f)

    fun triggers(offset: Float, maxOffset: Float): Boolean =
        maxOffset > 0f && progress(offset, maxOffset) >= TRIGGER_FRACTION
}

/** State of the slider after it was released past the threshold. */
sealed interface DoorSlideState {
    /** Ready to drag. */
    data object Idle : DoorSlideState

    /** Webhook request running / call being answered for DTMF. */
    data class Busy(val label: String) : DoorSlideState

    /** Green "Tür geöffnet ✓" (2 s, then back to [Idle]). */
    data object Opened : DoorSlideState

    /** Red message on the track, thumb snapped back; draggable again. */
    data class Failed(val message: String) : DoorSlideState
}

val DoorSlideState.isDraggable: Boolean get() = this is DoorSlideState.Idle || this is DoorSlideState.Failed

/** Result of POST /api/mobile/door-open. */
enum class DoorOpenOutcome {
    OPENED,
    NO_WEBHOOK,
    UNAUTHORIZED,
    UNREACHABLE,
    ;

    /** German text for the slider, null on success. */
    val message: String?
        get() = when (this) {
            OPENED -> null
            NO_WEBHOOK -> "Tür-Webhook fehlt"
            UNAUTHORIZED -> "Gerät neu koppeln (QR-Code)"
            UNREACHABLE -> "Tür nicht erreichbar"
        }

    companion object {
        /** The PBX only knows numeric extensions; anything else never leaves the app (same rule as Dart). */
        private val EXTENSION = Regex("^\\d{1,10}$")

        fun isValidExtension(number: String): Boolean = EXTENSION.matches(number)

        fun fromHttpStatus(code: Int): DoorOpenOutcome = when {
            code in 200..299 -> OPENED
            code == 404 -> NO_WEBHOOK
            code == 401 || code == 403 -> UNAUTHORIZED
            else -> UNREACHABLE
        }
    }
}

object DoorSlideTexts {
    const val PROMPT = "Zum Öffnen nach rechts schieben"
    const val OPENING = "Tür wird geöffnet…"
    const val ANSWERING = "Nimmt an und sendet Tür-Code…"
    const val OPENED = "Tür geöffnet ✓"
    const val A11Y_ACTION = "Tür öffnen"
    const val OPENED_MS = 2_000L
    const val FAILED_MS = 3_500L
}
