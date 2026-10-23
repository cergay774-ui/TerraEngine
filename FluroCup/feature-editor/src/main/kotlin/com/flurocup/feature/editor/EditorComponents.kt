package com.flurocup.feature.editor

import android.graphics.Color as AndroidColor
import androidx.annotation.OptIn
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.AspectRatio
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.AutoFixHigh
import androidx.compose.material.icons.rounded.BorderOuter
import androidx.compose.material.icons.rounded.Colorize
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.ContentCut
import androidx.compose.material.icons.rounded.Crop
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material.icons.rounded.FlipToBack
import androidx.compose.material.icons.rounded.FlipToFront
import androidx.compose.material.icons.rounded.Masks
import androidx.compose.material.icons.rounded.Opacity
import androidx.compose.material.icons.rounded.OpenWith
import androidx.compose.material.icons.rounded.PictureInPicture
import androidx.compose.material.icons.rounded.SwapHoriz
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.ripple
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import com.flurocup.core.engine.proxy.ProxyState
import com.flurocup.core.model.AspectRatio
import com.flurocup.core.model.HdrType
import com.flurocup.core.model.MediaKind
import com.flurocup.core.model.frameRateLabel
import com.flurocup.core.model.resolutionLabel

/** The project frame with the player inside; it springs to a new shape when the aspect ratio changes. */
@OptIn(UnstableApi::class)
@Composable
internal fun PreviewSurface(
    player: Player?,
    aspectRatio: Float,
    modifier: Modifier = Modifier,
    overlay: @Composable BoxScope.() -> Unit = {},
) {
    val ratio by animateFloatAsState(
        targetValue = aspectRatio,
        animationSpec = spring(dampingRatio = Spring.DampingRatioLowBouncy, stiffness = Spring.StiffnessMediumLow),
        label = "previewAspect",
    )
    Box(
        modifier = modifier
            .aspectRatio(ratio)
            .clip(RoundedCornerShape(10.dp))
            .background(Color.Black),
    ) {
        AndroidView(
            factory = { context ->
                PlayerView(context).apply {
                    useController = false
                    resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                    setShutterBackgroundColor(AndroidColor.BLACK)
                    setKeepContentOnPlayerReset(true)
                    this.player = player
                }
            },
            update = { it.player = player },
            onRelease = { it.player = null },
            modifier = Modifier.fillMaxSize(),
        )
        overlay()
    }
}

@Composable
internal fun AspectRatioRow(selected: AspectRatio?, onSelect: (AspectRatio) -> Unit) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(AspectRatio.entries) { ratio ->
            val label = when (ratio) {
                AspectRatio.ORIGINAL -> stringResource(R.string.editor_aspect_original)
                AspectRatio.FREE -> stringResource(R.string.editor_aspect_free)
                else -> "${ratio.widthRatio}:${ratio.heightRatio}"
            }
            FilterChip(
                selected = ratio == selected,
                onClick = { onSelect(ratio) },
                label = { Text(label) },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.18f),
                    selectedLabelColor = MaterialTheme.colorScheme.primary,
                ),
            )
        }
    }
}

/** One tool of the bottom panel. */
internal data class EditorTool(
    val icon: ImageVector,
    val label: String,
    val enabled: Boolean = true,
    val destructive: Boolean = false,
    val onClick: () -> Unit,
)

/** The bottom tool panel; its set of tools slides over when the selection changes. */
@Composable
internal fun ToolPanel(
    panelKey: Any,
    tools: List<EditorTool>,
    modifier: Modifier = Modifier,
) {
    AnimatedContent(
        targetState = panelKey to tools,
        contentKey = { it.first },
        transitionSpec = {
            (slideInVertically(spring(stiffness = Spring.StiffnessMediumLow)) { it / 2 } + fadeIn())
                .togetherWith(slideOutVertically(spring(stiffness = Spring.StiffnessMedium)) { it / 2 } + fadeOut())
        },
        label = "toolPanel",
        modifier = modifier,
    ) { (_, current) ->
        LazyRow(
            modifier = Modifier.fillMaxWidth(),
            contentPadding = PaddingValues(horizontal = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            items(current, key = { it.label }) { tool -> ToolButton(tool) }
        }
    }
}

@Composable
private fun ToolButton(tool: EditorTool) {
    val haptics = LocalHapticFeedback.current
    val color = when {
        !tool.enabled -> MaterialTheme.colorScheme.onSurface.copy(alpha = 0.35f)
        tool.destructive -> MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.onSurface
    }
    Column(
        modifier = Modifier
            .width(68.dp)
            .clip(RoundedCornerShape(12.dp))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = ripple(),
                enabled = tool.enabled,
                role = Role.Button,
            ) {
                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                tool.onClick()
            }
            .padding(vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(tool.icon, contentDescription = null, tint = color, modifier = Modifier.size(24.dp))
        Spacer(Modifier.height(4.dp))
        Text(
            text = tool.label,
            style = MaterialTheme.typography.labelSmall,
            color = color,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
    }
}

/** The tools for what is selected: nothing, a main-track clip, or an overlay. */
@Composable
internal fun editorTools(
    state: EditorUiState,
    onSplit: () -> Unit,
    onDuplicate: () -> Unit,
    onReplace: () -> Unit,
    onDelete: () -> Unit,
    onPanel: (EditorPanel) -> Unit,
    onLayer: (up: Boolean) -> Unit,
    onRemoveBackground: () -> Unit,
    onAdd: () -> Unit,
    onAddOverlay: () -> Unit,
    onFormat: () -> Unit,
    onEffects: () -> Unit,
    onEffectParams: () -> Unit,
    onEffectReplace: () -> Unit,
): List<EditorTool> {
    if (state.selectedEffect != null) {
        return listOf(
            EditorTool(Icons.Rounded.Tune, stringResource(R.string.editor_tool_effect_params), onClick = onEffectParams),
            EditorTool(Icons.Rounded.SwapHoriz, stringResource(R.string.editor_tool_replace), onClick = onEffectReplace),
            EditorTool(Icons.Rounded.ContentCut, stringResource(R.string.editor_tool_split), onClick = onSplit),
            EditorTool(Icons.Rounded.ContentCopy, stringResource(R.string.editor_tool_duplicate), onClick = onDuplicate),
            EditorTool(Icons.Rounded.DeleteOutline, stringResource(R.string.editor_tool_delete), destructive = true, onClick = onDelete),
        )
    }
    val selected = state.selectedClip
    if (selected == null) {
        return listOf(
            EditorTool(Icons.Rounded.Add, stringResource(R.string.editor_tool_add), onClick = onAdd),
            EditorTool(Icons.Rounded.AutoAwesome, stringResource(R.string.editor_tool_effects), enabled = state.durationUs > 0, onClick = onEffects),
            EditorTool(Icons.Rounded.PictureInPicture, stringResource(R.string.editor_tool_overlay), enabled = state.durationUs > 0, onClick = onAddOverlay),
            EditorTool(Icons.Rounded.ContentCut, stringResource(R.string.editor_tool_split), enabled = state.clips.isNotEmpty(), onClick = onSplit),
            EditorTool(Icons.Rounded.AspectRatio, stringResource(R.string.editor_tool_format), onClick = onFormat),
        )
    }
    val trackIndex = state.selectedOverlayTrackIndex
    return buildList {
        add(EditorTool(Icons.Rounded.ContentCut, stringResource(R.string.editor_tool_split), onClick = onSplit))
        add(EditorTool(Icons.Rounded.AutoAwesome, stringResource(R.string.editor_tool_effects), onClick = onEffects))
        add(EditorTool(Icons.Rounded.OpenWith, stringResource(R.string.editor_tool_transform)) { onPanel(EditorPanel.TRANSFORM) })
        add(EditorTool(Icons.Rounded.Opacity, stringResource(R.string.editor_tool_opacity)) { onPanel(EditorPanel.OPACITY) })
        add(EditorTool(Icons.Rounded.Crop, stringResource(R.string.editor_tool_crop)) { onPanel(EditorPanel.CROP) })
        add(EditorTool(Icons.Rounded.Masks, stringResource(R.string.editor_tool_mask)) { onPanel(EditorPanel.MASK) })
        add(EditorTool(Icons.Rounded.Colorize, stringResource(R.string.editor_tool_chroma)) { onPanel(EditorPanel.CHROMA) })
        add(EditorTool(Icons.Rounded.BorderOuter, stringResource(R.string.editor_tool_border)) { onPanel(EditorPanel.BORDER) })
        if (selected.clip.source.kind == MediaKind.IMAGE) {
            add(EditorTool(Icons.Rounded.AutoFixHigh, stringResource(R.string.editor_tool_remove_bg), enabled = !state.removingBackground, onClick = onRemoveBackground))
        }
        if (trackIndex != null) {
            add(EditorTool(Icons.Rounded.FlipToFront, stringResource(R.string.editor_tool_layer_up), enabled = trackIndex > 0) { onLayer(true) })
            add(EditorTool(Icons.Rounded.FlipToBack, stringResource(R.string.editor_tool_layer_down), enabled = trackIndex < state.overlays.lastIndex) { onLayer(false) })
        }
        add(EditorTool(Icons.Rounded.ContentCopy, stringResource(R.string.editor_tool_duplicate), onClick = onDuplicate))
        add(EditorTool(Icons.Rounded.SwapHoriz, stringResource(R.string.editor_tool_replace), onClick = onReplace))
        add(EditorTool(Icons.Rounded.DeleteOutline, stringResource(R.string.editor_tool_delete), destructive = true, onClick = onDelete))
    }
}

/** "4K · 60 fps · HEVC · HDR10 · VFR · Прокси 42%" for the selected clip. */
@Composable
internal fun clipInfoLine(ui: ClipUi): String {
    val info = ui.clip.source.info
    val parts = mutableListOf<String>()
    if (ui.clip.source.kind == MediaKind.IMAGE) {
        parts += stringResource(R.string.editor_photo)
        if (info != null) parts += "${info.displayWidth}×${info.displayHeight}"
    } else if (info != null && info.width > 0) {
        val resolution = resolutionLabel(info.displayWidth, info.displayHeight)
        parts += if (info.frameRate > 0f) "$resolution · ${frameRateLabel(info.frameRate)} fps" else resolution
        codecLabel(info.videoMimeType)?.let { parts += it }
        hdrLabel(info.hdr)?.let { parts += it }
        if (info.isVariableFrameRate) parts += stringResource(R.string.editor_vfr)
    }
    when (val proxy = ui.proxy) {
        ProxyState.Queued -> parts += stringResource(R.string.editor_proxy_queued)
        is ProxyState.Running -> parts += stringResource(R.string.editor_proxy_running, (proxy.progress * 100).toInt())
        is ProxyState.Ready -> parts += stringResource(R.string.editor_proxy_ready)
        is ProxyState.Failed -> parts += stringResource(R.string.editor_proxy_failed)
        null -> if (info?.canDecodeInRealTime == false) parts += stringResource(R.string.editor_no_realtime)
    }
    return parts.joinToString(" · ")
}

private fun hdrLabel(hdr: HdrType?): String? = when (hdr) {
    HdrType.HDR10 -> "HDR10"
    HdrType.HDR10_PLUS -> "HDR10+"
    HdrType.HLG -> "HLG"
    HdrType.DOLBY_VISION -> "Dolby Vision"
    HdrType.NONE, null -> null
}

private fun codecLabel(mime: String?): String? = when (mime) {
    null -> null
    "video/avc" -> "H.264"
    "video/hevc" -> "HEVC"
    "video/av01" -> "AV1"
    "video/x-vnd.on2.vp9" -> "VP9"
    "video/x-vnd.on2.vp8" -> "VP8"
    "video/dolby-vision" -> "Dolby Vision"
    "video/mp4v-es" -> "MPEG-4"
    "video/3gpp" -> "H.263"
    else -> mime.substringAfter('/').uppercase()
}
