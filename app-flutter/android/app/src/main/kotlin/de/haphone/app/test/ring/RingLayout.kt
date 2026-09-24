package de.haphone.app.test.ring

import java.time.LocalTime
import java.time.format.DateTimeFormatter

/** Which ringing screen to show. */
enum class RingVariant {
    /** Door station or video call: live picture on top, sheet with door controls below. */
    DOOR,

    /** Everything else: large avatar, name and number. */
    NORMAL,
}

/** How the slider opens the door. */
enum class DoorOpenMethod {
    /** POST /api/mobile/door-open (door_open_remote); the call keeps ringing. */
    WEBHOOK,

    /** Answer, then send the DTMF code once media is up (pending-DTMF mechanism). */
    DTMF,

    /** Nothing configured: no slider. */
    NONE,
}

/** What the ringing screen knows natively about the caller (DoorCodes / DoorActionClient data). */
data class RingInput(
    val callType: String?,
    val number: String,
    val callerName: String,
    val doorCode: String,
    val doorOpenRemote: Boolean,
    val doorActions: List<String>,
    val keyguardLocked: Boolean,
)

/** Everything the UI needs to decide; pure so it is covered by JVM tests. */
data class RingLayout(
    val variant: RingVariant,
    val displayName: String,
    /** Number shown under the name; empty when the name already is the number. */
    val displayNumber: String,
    val isDoorStation: Boolean,
    /** Bind the early-media SurfaceView (SDP offered video). */
    val showVideo: Boolean,
    /** "LIVE" chip: only when there is a picture to be live. */
    val showLiveChip: Boolean,
    /** "Gesperrt" chip: only over the keyguard. */
    val showLockedChip: Boolean,
    val title: String,
    val doorActions: List<String>,
    val openMethod: DoorOpenMethod,
    /**
     * "Mit Video annehmen": omitted. Answering always starts the call screen with the
     * door's video anyway and the app never sends its own camera, so the button would
     * do exactly what "Annehmen" does.
     */
    val showVideoAnswer: Boolean = false,
) {
    val showSlider: Boolean get() = openMethod != DoorOpenMethod.NONE
}

object RingLayouts {
    const val DOOR_TITLE = "Es klingelt an der Tür"
    const val VIDEO_TITLE = "Videoanruf"
    const val NORMAL_TITLE = "Eingehender Anruf"

    fun openMethod(doorOpenRemote: Boolean, doorCode: String): DoorOpenMethod = when {
        doorOpenRemote -> DoorOpenMethod.WEBHOOK
        doorCode.isNotBlank() -> DoorOpenMethod.DTMF
        else -> DoorOpenMethod.NONE
    }

    fun of(input: RingInput): RingLayout {
        val hasVideo = input.callType == "video" || input.callType == "door"
        val isDoorStation = input.doorCode.isNotBlank() || input.doorOpenRemote ||
            input.doorActions.isNotEmpty() || input.callType == "door"
        val variant = if (hasVideo || isDoorStation) RingVariant.DOOR else RingVariant.NORMAL
        val name = input.callerName.ifBlank { input.number }.ifBlank { "Unbekannt" }
        return RingLayout(
            variant = variant,
            displayName = name,
            displayNumber = if (name == input.number) "" else input.number,
            isDoorStation = isDoorStation,
            showVideo = hasVideo,
            showLiveChip = hasVideo,
            showLockedChip = input.keyguardLocked,
            title = when {
                isDoorStation -> DOOR_TITLE
                hasVideo -> VIDEO_TITLE
                else -> NORMAL_TITLE
            },
            doorActions = if (isDoorStation) input.doorActions else emptyList(),
            openMethod = if (isDoorStation) openMethod(input.doorOpenRemote, input.doorCode) else DoorOpenMethod.NONE,
        )
    }

    private val TIME = DateTimeFormatter.ofPattern("HH:mm")

    /** "16 · 10:44" under the door name (number left out when unknown). */
    fun meta(number: String, time: LocalTime): String =
        listOf(number, TIME.format(time)).filter { it.isNotBlank() }.joinToString(" · ")

    /** Up to two initials, "?" for nothing usable; digits-only names show "#". */
    fun initials(name: String): String {
        val words = name.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (words.isEmpty()) return "?"
        if (words.all { w -> w.all { it.isDigit() || it == '+' } }) return "#"
        return words.take(2).joinToString("") { it.take(1).uppercase() }
    }
}
