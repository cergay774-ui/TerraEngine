package com.flurocup.feature.editor

import android.graphics.Bitmap
import android.graphics.Color as AndroidColor
import androidx.annotation.OptIn
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
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
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import com.flurocup.core.engine.preview.PreviewPlayer
import com.flurocup.core.engine.proxy.ProxyState
import com.flurocup.core.model.AspectRatio
import com.flurocup.core.model.HdrType
import com.flurocup.core.model.MediaClip
import com.flurocup.core.model.MediaKind
import com.flurocup.core.model.formatDuration
import com.flurocup.core.model.frameRateLabel
import com.flurocup.core.model.resolutionLabel
import com.flurocup.core.ui.components.GradientIconSurface
import com.flurocup.core.ui.theme.FluroColors
import kotlinx.coroutines.delay

/** The project frame with the player inside; it springs to a new shape when the aspect ratio changes. */
@OptIn(UnstableApi::class)
@Composable
internal fun PreviewSurface(player: Player, aspectRatio: Float) {
    val ratio by animateFloatAsState(
        targetValue = aspectRatio,
        animationSpec = spring(dampingRatio = Spring.DampingRatioLowBouncy, stiffness = Spring.StiffnessMediumLow),
        label = "previewAspect",
    )
    Box(
        modifier = Modifier
            .aspectRatio(ratio)
            .clip(RoundedCornerShape(12.dp))
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
    }
}

@Composable
internal fun PlaybackBar(
    isPlaying: Boolean,
    preview: PreviewPlayer,
    onTogglePlay: () -> Unit,
) {
    var positionUs by remember { mutableLongStateOf(0L) }
    var durationUs by remember { mutableLongStateOf(0L) }
    LaunchedEffect(isPlaying, preview) {
        while (true) {
            positionUs = preview.positionUs
            durationUs = preview.durationUs
            if (!isPlaying) {
                // Paused: refresh rarely, to pick up imports and seeks.
                delay(400)
            } else {
                delay(50)
            }
        }
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "${formatDuration(positionUs)} / ${formatDuration(durationUs)}",
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
        GradientIconSurface(onClick = onTogglePlay, modifier = Modifier.size(52.dp)) {
            Icon(
                imageVector = if (isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                contentDescription = stringResource(if (isPlaying) R.string.editor_pause else R.string.editor_play),
                modifier = Modifier.size(30.dp),
            )
        }
        Spacer(Modifier.weight(1f))
    }
}

@Composable
internal fun AspectRatioRow(selected: AspectRatio?, onSelect: (AspectRatio) -> Unit) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = 12.dp),
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

@Composable
internal fun ClipStrip(
    clips: List<ClipUi>,
    loadThumbnail: suspend (MediaClip) -> Bitmap?,
    onAdd: () -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyRow(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 12.dp),
        contentPadding = PaddingValues(horizontal = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        items(clips, key = { it.clip.id }) { clip ->
            ClipTile(clip, loadThumbnail, Modifier.animateItem())
        }
        item(key = "add") {
            AddTile(onAdd, Modifier.animateItem())
        }
    }
}

@Composable
private fun ClipTile(ui: ClipUi, loadThumbnail: suspend (MediaClip) -> Bitmap?, modifier: Modifier = Modifier) {
    val clip = ui.clip
    val info = clip.source.info
    val thumbnail by produceState<Bitmap?>(null, clip.source.uri, clip.trimStartUs) {
        value = loadThumbnail(clip)
    }
    Column(modifier.width(TILE_WIDTH)) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(16f / 10f)
                .clip(RoundedCornerShape(10.dp))
                .background(MaterialTheme.colorScheme.surfaceContainerHigh),
        ) {
            thumbnail?.let {
                Image(
                    bitmap = it.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            }
            Row(
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(4.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                hdrLabel(info?.hdr)?.let { Badge(it, FluroColors.Orchid) }
                if (info?.isVariableFrameRate == true) Badge(stringResource(R.string.editor_vfr), FluroColors.Aqua)
            }
            Badge(
                text = formatDuration(clip.durationUs),
                color = Color.White,
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(4.dp),
            )
        }
        Spacer(Modifier.height(4.dp))
        Text(
            text = clipFormatLabel(ui),
            style = MaterialTheme.typography.labelMedium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        codecLabel(info?.videoMimeType)?.let {
            Text(
                text = it,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
            )
        }
        ProxyStatus(ui)
    }
}

@Composable
private fun clipFormatLabel(ui: ClipUi): String {
    val info = ui.clip.source.info
    if (ui.clip.source.kind == MediaKind.IMAGE) {
        val size = info?.let { " · ${it.displayWidth}×${it.displayHeight}" }.orEmpty()
        return stringResource(R.string.editor_photo) + size
    }
    if (info == null || info.width <= 0) return ""
    val resolution = resolutionLabel(info.displayWidth, info.displayHeight)
    return if (info.frameRate > 0f) "$resolution · ${frameRateLabel(info.frameRate)} fps" else resolution
}

@Composable
private fun ProxyStatus(ui: ClipUi) {
    val canPlay = ui.clip.source.info?.canDecodeInRealTime != false
    when (val proxy = ui.proxy) {
        null -> if (!canPlay) StatusText(stringResource(R.string.editor_no_realtime), MaterialTheme.colorScheme.tertiary)
        ProxyState.Queued -> StatusText(stringResource(R.string.editor_proxy_queued), MaterialTheme.colorScheme.onSurfaceVariant)
        is ProxyState.Running -> Column {
            StatusText(
                stringResource(R.string.editor_proxy_running, (proxy.progress * 100).toInt()),
                MaterialTheme.colorScheme.primary,
            )
            LinearProgressIndicator(
                progress = { proxy.progress },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 2.dp),
            )
        }
        is ProxyState.Ready -> StatusText(stringResource(R.string.editor_proxy_ready), MaterialTheme.colorScheme.primary)
        is ProxyState.Failed -> StatusText(stringResource(R.string.editor_proxy_failed), MaterialTheme.colorScheme.error)
    }
}

@Composable
private fun StatusText(text: String, color: Color) {
    Text(text = text, style = MaterialTheme.typography.labelSmall, color = color, maxLines = 1)
}

@Composable
private fun Badge(text: String, color: Color, modifier: Modifier = Modifier) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelSmall,
        color = color,
        modifier = modifier
            .clip(RoundedCornerShape(4.dp))
            .background(Color.Black.copy(alpha = 0.6f))
            .padding(horizontal = 4.dp, vertical = 1.dp),
    )
}

@Composable
private fun AddTile(onClick: () -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.width(TILE_WIDTH)) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(16f / 10f)
                .clip(RoundedCornerShape(10.dp))
                .border(BorderStroke(1.5.dp, FluroColors.Teal.copy(alpha = 0.6f)), RoundedCornerShape(10.dp))
                .clickable(onClick = onClick),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Rounded.Add, contentDescription = null, tint = FluroColors.Teal)
        }
        Spacer(Modifier.height(4.dp))
        Text(stringResource(R.string.editor_add_media), style = MaterialTheme.typography.labelMedium)
    }
}

private val TILE_WIDTH = 120.dp

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
