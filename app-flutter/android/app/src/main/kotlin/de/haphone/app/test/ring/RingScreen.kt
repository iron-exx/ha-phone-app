package de.haphone.app.test.ring

import android.view.SurfaceHolder
import android.view.SurfaceView
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import de.haphone.app.test.sip.VideoSurfaceBinder
import kotlin.math.roundToInt

/** Callbacks of the ringing screen; the Activity owns SIP, Telecom and the network. */
class RingActions(
    val onAnswer: () -> Unit,
    val onDecline: () -> Unit,
    val onSlideOpen: () -> Unit,
    val onDoorAction: (Int) -> Unit,
    /** Main thread only: may the SurfaceView bind itself (false once answered/declined). */
    val ownsVideoSurface: () -> Boolean,
)

private val SheetShape = RoundedCornerShape(topStart = 30.dp, topEnd = 30.dp)
private val SheetOverlap = 30.dp
private val CallButtonSize = 76.dp
private val SliderHeight = 64.dp
private val ThumbSize = 52.dp
private val ThumbInset = 6.dp

private val Tabular = TextStyle(fontFeatureSettings = "tnum")

@Composable
fun RingScreen(layout: RingLayout, meta: String, slideState: DoorSlideState, actions: RingActions) {
    val c = if (isSystemInDarkTheme()) NwColors.Dark else NwColors.Light
    when (layout.variant) {
        RingVariant.DOOR -> DoorRing(layout, meta, slideState, actions, c)
        RingVariant.NORMAL -> NormalRing(layout, actions, c)
    }
}

@Composable
private fun DoorRing(layout: RingLayout, meta: String, slideState: DoorSlideState, actions: RingActions, c: NwColors) {
    var sheetHeight by remember { mutableIntStateOf(0) }
    val density = LocalDensity.current
    val sheetDp = with(density) { sheetHeight.toDp() }
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        Box(
            Modifier
                .fillMaxSize()
                .padding(bottom = (sheetDp - SheetOverlap).coerceAtLeast(0.dp))
                .background(NwColors.VideoGround),
        ) {
            if (layout.showVideo) {
                Text(
                    "Video wird geladen…", color = NwColors.OnVideoMuted, fontFamily = NwFonts.Ui,
                    fontWeight = FontWeight.Bold, fontSize = 13.sp, modifier = Modifier.align(Alignment.Center),
                )
                LiveVideo(actions.ownsVideoSurface, Modifier.fillMaxWidth().aspectRatio(4f / 3f).align(Alignment.Center))
            } else {
                Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(NwIcons.Video, contentDescription = null, tint = Color(0xFF7D6D5A), modifier = Modifier.size(46.dp))
                    Text(
                        "Kein Live-Bild", color = Color(0xFF7D6D5A), fontFamily = NwFonts.Ui,
                        fontWeight = FontWeight.Bold, fontSize = 13.sp, modifier = Modifier.padding(top = 10.dp),
                    )
                }
            }
            // Keeps the title readable on any picture.
            Box(
                Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .height(220.dp)
                    .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.78f)))),
            )
            Row(
                Modifier.statusBarsPadding().fillMaxWidth().padding(horizontal = 20.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (layout.showLockedChip) {
                    OverlayChip(Color.Black.copy(alpha = 0.55f), NwColors.OnVideo, "Gesperrt", NwIcons.Lock)
                }
                Spacer(Modifier.weight(1f))
                if (layout.showLiveChip) LiveChip(c)
            }
            Column(
                Modifier
                    .align(Alignment.BottomStart)
                    .fillMaxWidth()
                    .padding(start = 20.dp, end = 20.dp, bottom = SheetOverlap + 18.dp),
            ) {
                Text(
                    layout.title.uppercase(), color = c.door.takeIf { layout.isDoorStation } ?: NwColors.OnVideoMuted,
                    fontFamily = NwFonts.Ui, fontWeight = FontWeight.ExtraBold, fontSize = 13.sp, letterSpacing = 0.08.em,
                    modifier = Modifier.semantics { heading() },
                )
                Text(
                    layout.displayName, color = NwColors.OnVideo, fontFamily = NwFonts.Display,
                    fontWeight = FontWeight.ExtraBold, fontSize = 40.sp, lineHeight = 42.sp,
                    maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 4.dp),
                )
                Text(meta, color = NwColors.OnVideoMuted, fontFamily = NwFonts.Ui, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, style = Tabular)
            }
        }
        Column(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .onSizeChanged { sheetHeight = it.height }
                .clip(SheetShape)
                .background(c.ground)
                .navigationBarsPadding()
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            if (layout.doorActions.isNotEmpty()) {
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    layout.doorActions.forEachIndexed { index, label ->
                        ActionChip(label, c) { actions.onDoorAction(index) }
                    }
                }
            }
            if (layout.showSlider) DoorSlider(slideState, c, actions.onSlideOpen)
            CallButtonRow(actions, c)
        }
    }
}

@Composable
private fun NormalRing(layout: RingLayout, actions: RingActions, c: NwColors) {
    Column(
        Modifier.fillMaxSize().background(c.ground).statusBarsPadding().navigationBarsPadding().padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(Modifier.fillMaxWidth().heightIn(min = 28.dp)) {
            if (layout.showLockedChip) OverlayChip(c.raised, c.text, "Gesperrt", NwIcons.Lock)
        }
        Spacer(Modifier.weight(0.6f))
        Text(
            layout.title.uppercase(), color = c.muted, fontFamily = NwFonts.Ui, fontWeight = FontWeight.ExtraBold,
            fontSize = 13.sp, letterSpacing = 0.08.em, modifier = Modifier.semantics { heading() },
        )
        Box(
            Modifier.padding(top = 24.dp).size(112.dp).background(c.high, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                RingLayouts.initials(layout.displayName), color = c.text, fontFamily = NwFonts.Display,
                fontWeight = FontWeight.ExtraBold, fontSize = 40.sp,
            )
        }
        Text(
            layout.displayName, color = c.text, fontFamily = NwFonts.Display, fontWeight = FontWeight.ExtraBold,
            fontSize = 36.sp, lineHeight = 40.sp, textAlign = TextAlign.Center, maxLines = 2,
            overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 20.dp),
        )
        if (layout.displayNumber.isNotBlank()) {
            Text(
                layout.displayNumber, color = c.muted, fontFamily = NwFonts.Ui, fontWeight = FontWeight.SemiBold,
                fontSize = 16.sp, style = Tabular, modifier = Modifier.padding(top = 6.dp),
            )
        }
        Spacer(Modifier.weight(1f))
        CallButtonRow(actions, c)
    }
}

/** Ablehnen left, Annehmen right: the positions never change between variants. */
@Composable
private fun CallButtonRow(actions: RingActions, c: NwColors) {
    Row(
        Modifier.fillMaxWidth().padding(start = 18.dp, end = 18.dp, top = 6.dp, bottom = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.Bottom,
    ) {
        CallButton("Ablehnen", c.end, c.endInk, NwIcons.PhoneOff, c, actions.onDecline)
        CallButton("Annehmen", c.answer, c.answerInk, NwIcons.Phone, c, actions.onAnswer)
    }
}

@Composable
private fun CallButton(label: String, fill: Color, ink: Color, icon: ImageVector, c: NwColors, onClick: () -> Unit) {
    Column(
        Modifier.clip(RoundedCornerShape(20.dp)).clickable(role = Role.Button, onClick = onClick).padding(4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(Modifier.size(CallButtonSize).background(fill, CircleShape), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = ink, modifier = Modifier.size(30.dp))
        }
        Text(
            label, color = c.text, fontFamily = NwFonts.Ui, fontWeight = FontWeight.Bold, fontSize = 13.sp,
            modifier = Modifier.padding(top = 8.dp),
        )
    }
}

@Composable
private fun OverlayChip(bg: Color, fg: Color, label: String, icon: ImageVector) {
    Row(
        Modifier.height(28.dp).background(bg, RoundedCornerShape(14.dp)).padding(horizontal = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = fg, modifier = Modifier.size(13.dp))
        Text(label, color = fg, fontFamily = NwFonts.Ui, fontWeight = FontWeight.ExtraBold, fontSize = 12.sp, modifier = Modifier.padding(start = 6.dp))
    }
}

@Composable
private fun LiveChip(c: NwColors) {
    Row(
        Modifier.height(28.dp).background(c.end, RoundedCornerShape(14.dp)).padding(horizontal = 11.dp)
            .semantics(mergeDescendants = true) { contentDescription = "Live-Bild" },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(7.dp).background(Color.White, CircleShape))
        Text("LIVE", color = Color.White, fontFamily = NwFonts.Ui, fontWeight = FontWeight.ExtraBold, fontSize = 12.sp, modifier = Modifier.padding(start = 6.dp))
    }
}

@Composable
private fun ActionChip(label: String, c: NwColors, onClick: () -> Unit) {
    Box(
        Modifier.heightIn(min = 48.dp).clip(RoundedCornerShape(24.dp)).background(c.raised)
            .clickable(role = Role.Button, onClick = onClick).padding(horizontal = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = c.text, fontFamily = NwFonts.Ui, fontWeight = FontWeight.Bold, fontSize = 14.sp, maxLines = 1)
    }
}

/**
 * "Zum Öffnen nach rechts schieben": the thumb must be dragged >= 85 % of the way
 * (SlideToOpen), otherwise it springs back. TalkBack gets the custom action
 * "Tür öffnen" instead of a drag.
 */
@Composable
private fun DoorSlider(state: DoorSlideState, c: NwColors, onTrigger: () -> Unit) {
    val density = LocalDensity.current
    val thumbPx = with(density) { ThumbSize.toPx() }
    val insetPx = with(density) { ThumbInset.toPx() }
    var trackWidth by remember { mutableIntStateOf(0) }
    var offset by remember { mutableFloatStateOf(0f) }
    val maxOffset = SlideToOpen.maxOffset(trackWidth.toFloat(), thumbPx, insetPx)
    val draggable = state.isDraggable

    LaunchedEffect(state, maxOffset) {
        val target = when (state) {
            is DoorSlideState.Idle, is DoorSlideState.Failed -> 0f
            is DoorSlideState.Busy, is DoorSlideState.Opened -> maxOffset
        }
        if (offset != target) animate(offset, target, animationSpec = spring()) { v, _ -> offset = v }
    }

    val (track, border, fg, label) = when (state) {
        is DoorSlideState.Idle -> SliderLook(c.doorSoft, c.doorStroke, c.door, DoorSlideTexts.PROMPT)
        is DoorSlideState.Busy -> SliderLook(c.doorSoft, c.doorStroke, c.door, state.label)
        is DoorSlideState.Opened -> SliderLook(c.okSurface, c.okStroke, c.okText, DoorSlideTexts.OPENED)
        is DoorSlideState.Failed -> SliderLook(c.doorSoft, c.end, c.end, state.message)
    }
    val shape = RoundedCornerShape(SliderHeight / 2)
    Box(
        Modifier
            .fillMaxWidth()
            .height(SliderHeight)
            .clip(shape)
            .background(track)
            .border(1.dp, border, shape)
            .onSizeChanged { trackWidth = it.width }
            .semantics(mergeDescendants = true) {
                contentDescription = label
                if (draggable) {
                    customActions = listOf(CustomAccessibilityAction(DoorSlideTexts.A11Y_ACTION) { onTrigger(); true })
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            label, color = fg, fontFamily = NwFonts.Ui, fontWeight = FontWeight.ExtraBold, fontSize = 15.sp,
            textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(start = ThumbSize + ThumbInset * 2, end = 16.dp),
        )
        Box(
            Modifier
                .align(Alignment.CenterStart)
                .offset { IntOffset((insetPx + offset).roundToInt(), 0) }
                .size(ThumbSize)
                .background(if (state is DoorSlideState.Opened) c.answer else c.door, CircleShape)
                .draggable(
                    orientation = Orientation.Horizontal,
                    enabled = draggable,
                    state = rememberDraggableState { delta -> offset = SlideToOpen.clamp(offset + delta, maxOffset) },
                    onDragStopped = {
                        if (SlideToOpen.triggers(offset, maxOffset)) {
                            onTrigger()
                        } else {
                            animate(offset, 0f, animationSpec = spring()) { v, _ -> offset = v }
                        }
                    },
                ),
            contentAlignment = Alignment.Center,
        ) {
            when (state) {
                is DoorSlideState.Busy -> CircularProgressIndicator(color = c.doorInk, strokeWidth = 2.5.dp, modifier = Modifier.size(22.dp))
                is DoorSlideState.Opened -> Icon(NwIcons.Check, contentDescription = null, tint = c.answerInk, modifier = Modifier.size(24.dp))
                else -> Icon(NwIcons.Door, contentDescription = null, tint = c.doorInk, modifier = Modifier.size(24.dp))
            }
        }
    }
}

private data class SliderLook(val track: Color, val border: Color, val fg: Color, val label: String)

/** Early-media picture; binds only while this screen still owns the video (see IncomingCallActivity). */
@Composable
private fun LiveVideo(ownsVideoSurface: () -> Boolean, modifier: Modifier) {
    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            SurfaceView(ctx).apply {
                holder.addCallback(object : SurfaceHolder.Callback {
                    override fun surfaceCreated(h: SurfaceHolder) {}
                    override fun surfaceChanged(h: SurfaceHolder, format: Int, w: Int, hgt: Int) {
                        if (ownsVideoSurface()) VideoSurfaceBinder.setSurface(h.surface)
                    }
                    override fun surfaceDestroyed(h: SurfaceHolder) {
                        VideoSurfaceBinder.clearSurface(h.surface)
                    }
                })
            }
        },
    )
}
