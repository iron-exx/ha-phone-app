package de.haphone.app.test.ring

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import de.haphone.app.test.R

/** "Nachtwache" colour roles, same values as lib/theme/app_colors.dart (NwColors). */
data class NwColors(
    val ground: Color,
    val surface: Color,
    val raised: Color,
    val high: Color,
    val stroke: Color,
    val text: Color,
    val muted: Color,
    val faint: Color,
    val answer: Color,
    val answerInk: Color,
    val end: Color,
    val endInk: Color,
    val door: Color,
    val doorInk: Color,
    val doorSoft: Color,
    val doorStroke: Color,
    val okSurface: Color,
    val okStroke: Color,
    val okText: Color,
) {
    companion object {
        val Dark = NwColors(
            ground = Color(0xFF0B0F14), surface = Color(0xFF131A22), raised = Color(0xFF1B2430),
            high = Color(0xFF243040), stroke = Color(0xFF2A3544), text = Color(0xFFEAF0F6),
            muted = Color(0xFFA3B0BF), faint = Color(0xFF7B8898),
            answer = Color(0xFF2FBF71), answerInk = Color(0xFF032313),
            end = Color(0xFFE5484D), endInk = Color.White,
            door = Color(0xFFF5A524), doorInk = Color(0xFF2A1800), doorSoft = Color(0xFF3A2A0E),
            doorStroke = Color(0xFF5A4216),
            okSurface = Color(0xFF0F2A1C), okStroke = Color(0xFF1E4D33), okText = Color(0xFF7EE2A8),
        )
        val Light = NwColors(
            ground = Color(0xFFF4F6F9), surface = Color.White, raised = Color(0xFFEAEEF3),
            high = Color(0xFFDCE3EB), stroke = Color(0xFFD5DCE4), text = Color(0xFF0F172A),
            muted = Color(0xFF475569), faint = Color(0xFF64748B),
            answer = Color(0xFF1F9D57), answerInk = Color.White,
            end = Color(0xFFD92D32), endInk = Color.White,
            door = Color(0xFFC77A00), doorInk = Color.White, doorSoft = Color(0xFFFFF1D6),
            doorStroke = Color(0xFFF0D29A),
            okSurface = Color(0xFFE7F7EE), okStroke = Color(0xFFB7E4C9), okText = Color(0xFF166534),
        )

        /** Text on the (always dark) live picture, independent of the system theme. */
        val OnVideo = Color(0xFFEAF0F6)
        val OnVideoMuted = Color(0xFFC9D2DC)
        val VideoGround = Color(0xFF15110D)
    }
}

/** Bundled Nachtwache fonts (res/font, copies of assets/fonts). */
object NwFonts {
    val Display = FontFamily(
        Font(R.font.bricolage_bold, FontWeight.Bold),
        Font(R.font.bricolage_extrabold, FontWeight.ExtraBold),
    )
    val Ui = FontFamily(
        Font(R.font.manrope_semibold, FontWeight.SemiBold),
        Font(R.font.manrope_bold, FontWeight.Bold),
        Font(R.font.manrope_extrabold, FontWeight.ExtraBold),
    )
}

/** Lucide-style stroke icons from the mockups (docs/design/mockups/gen.py). */
object NwIcons {
    private fun lucide(name: String, vararg paths: String, strokeWidth: Float = 2f): ImageVector =
        ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f).apply {
            paths.forEach {
                addPath(
                    pathData = addPathNodes(it),
                    fill = null,
                    stroke = SolidColor(Color.Black),
                    strokeLineWidth = strokeWidth,
                    strokeLineCap = StrokeCap.Round,
                    strokeLineJoin = StrokeJoin.Round,
                )
            }
        }.build()

    val Door = lucide(
        "door", "M13 4h3a2 2 0 0 1 2 2v14", "M2 20h3", "M13 20h9", "M10 12v.01",
        "M13 4.6v16.2a1 1 0 0 1-1.2 1L5 20V5.6a2 2 0 0 1 1.5-1.9l4-1a2 2 0 0 1 2.5 1.9z",
    )
    val Phone = lucide(
        "phone",
        "M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1.9.4 1.8.7 2.7a2 2 0 0 1-.5 2.1L8 9.8a16 16 0 0 0 6 6l1.3-1.3a2 2 0 0 1 2.1-.4c.9.3 1.8.6 2.7.7a2 2 0 0 1 1.7 2z",
        strokeWidth = 2.2f,
    )
    val PhoneOff = lucide(
        "phone-off",
        "M10.7 13.3a16 16 0 0 1-2.7-3.5l1.3-1.3a2 2 0 0 0 .5-2.1c-.3-.9-.6-1.8-.7-2.7A2 2 0 0 0 7.1 2h-3a2 2 0 0 0-2 2.2 19.8 19.8 0 0 0 3.1 8.6",
        "M22 2 2 22",
        "M14.7 16.4a16 16 0 0 0 1.4.6l1.3-1.3a2 2 0 0 1 2.1-.4c.9.3 1.8.6 2.7.7a2 2 0 0 1 1.7 2v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1",
        strokeWidth = 2.2f,
    )
    val Video = lucide(
        "video", "m16 13 5.2 3.1a.5.5 0 0 0 .8-.4V8.3a.5.5 0 0 0-.8-.4L16 11",
        "M2 8a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2z",
        strokeWidth = 1.4f,
    )
    val Lock = lucide(
        "lock", "M6 11h12a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2z", "M8 11V7a4 4 0 0 1 8 0v4",
        strokeWidth = 2.4f,
    )
    val Check = lucide("check", "M20 6 9 17l-5-5", strokeWidth = 2.6f)
    val Bulb = lucide(
        "bulb", "M9 18h6", "M10 22h4",
        "M15.1 14c.2-1 .7-1.7 1.5-2.5A6 6 0 1 0 6 8c0 1.3.5 2.6 1.5 3.5.7.8 1.3 1.5 1.5 2.5",
    )
}
