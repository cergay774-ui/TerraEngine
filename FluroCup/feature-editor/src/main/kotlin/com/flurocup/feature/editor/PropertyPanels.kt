package com.flurocup.feature.editor

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Colorize
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.flurocup.core.model.ChromaKey
import com.flurocup.core.model.ClipBorder
import com.flurocup.core.model.ClipLook
import com.flurocup.core.model.ClipMask
import com.flurocup.core.model.ClipTransform
import com.flurocup.core.model.CropRect
import com.flurocup.core.model.MaskShape
import kotlin.math.roundToInt

/** The property panels that open in place of the timeline, so the preview stays visible. */
enum class EditorPanel(val editsLookLive: Boolean) {
    TRANSFORM(false),
    OPACITY(true),
    CROP(false),
    MASK(true),
    CHROMA(true),
    BORDER(true),
}

/**
 * Panel frame: title and a done button. Edits inside call [onLook] while a slider moves (shown
 * live) and [onLookDone] when it is let go (saved as one undo step).
 */
@Composable
internal fun PanelFrame(title: String, onDone: () -> Unit, content: @Composable () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceContainerLow, RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp))
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            IconButton(onClick = onDone) {
                Icon(Icons.Rounded.Check, contentDescription = stringResource(R.string.editor_done), tint = MaterialTheme.colorScheme.primary)
            }
        }
        Column(
            Modifier
                .heightIn(max = 300.dp)
                .verticalScroll(rememberScrollState()),
        ) { content() }
    }
}

@Composable
internal fun LabeledSlider(
    label: String,
    value: Float,
    range: ClosedFloatingPointRange<Float>,
    format: (Float) -> String,
    onChange: (Float) -> Unit,
    onDone: () -> Unit,
) {
    Column(Modifier.padding(vertical = 2.dp)) {
        Row {
            Text(label, style = MaterialTheme.typography.labelLarge, modifier = Modifier.weight(1f))
            Text(format(value), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
        }
        Slider(value = value.coerceIn(range), onValueChange = onChange, onValueChangeFinished = onDone, valueRange = range)
    }
}

private fun percent(v: Float) = "${(v * 100).roundToInt()}%"
private fun degrees(v: Float) = "${v.roundToInt()}°"

@Composable
internal fun TransformPanel(look: ClipLook, onLook: (ClipLook) -> Unit, onLookDone: (ClipLook) -> Unit, onDone: () -> Unit) {
    val t = look.transform
    fun with(transform: ClipTransform) = look.copy(transform = transform)
    PanelFrame(stringResource(R.string.editor_tool_transform), onDone) {
        LabeledSlider(stringResource(R.string.editor_scale), t.scale, 0.1f..4f, ::percent, { onLook(with(t.copy(scale = it))) }) { onLookDone(look) }
        LabeledSlider(stringResource(R.string.editor_rotation), t.rotation, -180f..180f, ::degrees, { onLook(with(t.copy(rotation = it))) }) { onLookDone(look) }
        LabeledSlider(stringResource(R.string.editor_position_x), t.x, -1f..1f, ::percent, { onLook(with(t.copy(x = it))) }) { onLookDone(look) }
        LabeledSlider(stringResource(R.string.editor_position_y), t.y, -1f..1f, ::percent, { onLook(with(t.copy(y = it))) }) { onLookDone(look) }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(vertical = 6.dp)) {
            FilterChip(
                selected = t.flipHorizontal,
                onClick = { with(t.copy(flipHorizontal = !t.flipHorizontal)).also { onLook(it); onLookDone(it) } },
                label = { Text(stringResource(R.string.editor_flip_h)) },
                colors = chipColors(),
            )
            FilterChip(
                selected = t.flipVertical,
                onClick = { with(t.copy(flipVertical = !t.flipVertical)).also { onLook(it); onLookDone(it) } },
                label = { Text(stringResource(R.string.editor_flip_v)) },
                colors = chipColors(),
            )
            Spacer(Modifier.weight(1f))
            TextButton(onClick = {
                val reset = with(ClipTransform())
                onLook(reset)
                onLookDone(reset)
            }) { Text(stringResource(R.string.editor_reset)) }
        }
    }
}

@Composable
internal fun OpacityPanel(look: ClipLook, onLook: (ClipLook) -> Unit, onLookDone: (ClipLook) -> Unit, onDone: () -> Unit) {
    PanelFrame(stringResource(R.string.editor_tool_opacity), onDone) {
        LabeledSlider(stringResource(R.string.editor_opacity), look.opacity, 0f..1f, ::percent, { onLook(look.copy(opacity = it)) }) {
            onLookDone(look)
        }
    }
}

@Composable
internal fun CropPanel(crop: CropRect, onCrop: (CropRect) -> Unit, onCropDone: (CropRect) -> Unit, onDone: () -> Unit) {
    PanelFrame(stringResource(R.string.editor_tool_crop), onDone) {
        LabeledSlider(stringResource(R.string.editor_crop_left), crop.left, 0f..0.45f, ::percent, { onCrop(crop.copy(left = it)) }) { onCropDone(crop) }
        LabeledSlider(stringResource(R.string.editor_crop_right), crop.right, 0f..0.45f, ::percent, { onCrop(crop.copy(right = it)) }) { onCropDone(crop) }
        LabeledSlider(stringResource(R.string.editor_crop_top), crop.top, 0f..0.45f, ::percent, { onCrop(crop.copy(top = it)) }) { onCropDone(crop) }
        LabeledSlider(stringResource(R.string.editor_crop_bottom), crop.bottom, 0f..0.45f, ::percent, { onCrop(crop.copy(bottom = it)) }) { onCropDone(crop) }
        TextButton(onClick = { onCrop(CropRect()); onCropDone(CropRect()) }) { Text(stringResource(R.string.editor_reset)) }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun MaskPanel(look: ClipLook, onLook: (ClipLook) -> Unit, onLookDone: (ClipLook) -> Unit, onDone: () -> Unit) {
    val mask = look.mask
    fun with(m: ClipMask?) = look.copy(mask = m)
    val shapes = listOf(
        null to R.string.editor_mask_none,
        MaskShape.LINEAR to R.string.editor_mask_linear,
        MaskShape.MIRROR to R.string.editor_mask_mirror,
        MaskShape.CIRCLE to R.string.editor_mask_circle,
        MaskShape.RECTANGLE to R.string.editor_mask_rect,
        MaskShape.HEART to R.string.editor_mask_heart,
        MaskShape.STAR to R.string.editor_mask_star,
    )
    PanelFrame(stringResource(R.string.editor_tool_mask), onDone) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            shapes.forEach { (shape, label) ->
                FilterChip(
                    selected = mask?.shape == shape,
                    onClick = {
                        val next = shape?.let { s -> (mask ?: ClipMask(s)).copy(shape = s) }
                        with(next).also { onLook(it); onLookDone(it) }
                    },
                    label = { Text(stringResource(label)) },
                    colors = chipColors(),
                )
            }
        }
        if (mask != null) {
            LabeledSlider(stringResource(R.string.editor_mask_feather), mask.feather, 0f..0.3f, ::percent, { onLook(with(mask.copy(feather = it))) }) { onLookDone(look) }
            LabeledSlider(stringResource(R.string.editor_mask_width), mask.width, 0.05f..2f, ::percent, { onLook(with(mask.copy(width = it))) }) { onLookDone(look) }
            LabeledSlider(stringResource(R.string.editor_mask_height), mask.height, 0.05f..2f, ::percent, { onLook(with(mask.copy(height = it))) }) { onLookDone(look) }
            LabeledSlider(stringResource(R.string.editor_position_x), mask.centerX, -0.5f..1.5f, ::percent, { onLook(with(mask.copy(centerX = it))) }) { onLookDone(look) }
            LabeledSlider(stringResource(R.string.editor_position_y), mask.centerY, -0.5f..1.5f, ::percent, { onLook(with(mask.copy(centerY = it))) }) { onLookDone(look) }
            LabeledSlider(stringResource(R.string.editor_rotation), mask.rotation, -180f..180f, ::degrees, { onLook(with(mask.copy(rotation = it))) }) { onLookDone(look) }
            if (mask.shape == MaskShape.RECTANGLE) {
                LabeledSlider(stringResource(R.string.editor_mask_radius), mask.cornerRadius, 0f..1f, ::percent, { onLook(with(mask.copy(cornerRadius = it))) }) {
                    onLookDone(look)
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.editor_mask_invert), modifier = Modifier.weight(1f))
                Switch(checked = mask.invert, onCheckedChange = { with(mask.copy(invert = it)).also { l -> onLook(l); onLookDone(l) } })
            }
        }
    }
}

@Composable
internal fun ChromaKeyPanel(
    look: ClipLook,
    onLook: (ClipLook) -> Unit,
    onLookDone: (ClipLook) -> Unit,
    onPickColor: () -> Unit,
    onDone: () -> Unit,
) {
    val key = look.chromaKey
    fun with(k: ChromaKey?) = look.copy(chromaKey = k)
    PanelFrame(stringResource(R.string.editor_tool_chroma), onDone) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.editor_chroma_on), modifier = Modifier.weight(1f))
            Switch(checked = key != null, onCheckedChange = { on ->
                with(if (on) ChromaKey() else null).also { onLook(it); onLookDone(it) }
            })
        }
        if (key != null) {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(vertical = 4.dp)) {
                Box(
                    Modifier
                        .size(32.dp)
                        .clip(CircleShape)
                        .background(Color(key.colorArgb.toInt()))
                        .border(2.dp, Color.White, CircleShape),
                )
                Spacer(Modifier.width(12.dp))
                OutlinedButton(onClick = onPickColor) {
                    Icon(Icons.Rounded.Colorize, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(stringResource(R.string.editor_chroma_pick))
                }
                Spacer(Modifier.width(8.dp))
                listOf(0xFF00FF00, 0xFF0047BB).forEach { preset ->
                    Box(
                        Modifier
                            .padding(horizontal = 4.dp)
                            .size(28.dp)
                            .clip(CircleShape)
                            .background(Color(preset.toInt()))
                            .clickable { with(key.copy(colorArgb = preset)).also { onLook(it); onLookDone(it) } },
                    )
                }
            }
            LabeledSlider(stringResource(R.string.editor_chroma_similarity), key.similarity, 0f..1f, ::percent, { onLook(with(key.copy(similarity = it))) }) { onLookDone(look) }
            LabeledSlider(stringResource(R.string.editor_chroma_smoothness), key.smoothness, 0f..1f, ::percent, { onLook(with(key.copy(smoothness = it))) }) { onLookDone(look) }
            LabeledSlider(stringResource(R.string.editor_chroma_spill), key.spill, 0f..1f, ::percent, { onLook(with(key.copy(spill = it))) }) { onLookDone(look) }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun BorderPanel(look: ClipLook, onLook: (ClipLook) -> Unit, onLookDone: (ClipLook) -> Unit, onDone: () -> Unit) {
    val border = look.border
    PanelFrame(stringResource(R.string.editor_tool_border), onDone) {
        LabeledSlider(stringResource(R.string.editor_border_width), border.width, 0f..0.1f, { "${(it * 1000).roundToInt() / 10f}%" }, {
            onLook(look.copy(border = border.copy(width = it)))
        }) { onLookDone(look) }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(vertical = 4.dp)) {
            BORDER_COLORS.forEach { color ->
                val selected = border.colorArgb == color
                Box(
                    Modifier
                        .size(30.dp)
                        .clip(CircleShape)
                        .background(Color(color.toInt()))
                        .border(if (selected) 3.dp else 1.dp, if (selected) MaterialTheme.colorScheme.primary else Color.White.copy(alpha = 0.4f), CircleShape)
                        .clickable {
                            look.copy(border = ClipBorder(width = if (border.width > 0f) border.width else 0.01f, colorArgb = color))
                                .also { onLook(it); onLookDone(it) }
                        },
                )
            }
        }
        LabeledSlider(stringResource(R.string.editor_corner_radius), look.cornerRadius, 0f..0.5f, ::percent, { onLook(look.copy(cornerRadius = it)) }) {
            onLookDone(look)
        }
    }
}

/** Shows a frame of the clip; a tap on it picks that pixel's colour for the chroma key. */
@Composable
internal fun ColorPickDialog(frame: Bitmap, onPick: (Long) -> Unit, onDismiss: () -> Unit) {
    var viewSize by remember { mutableStateOf(IntSize.Zero) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.editor_chroma_pick)) },
        text = {
            Column {
                Text(stringResource(R.string.editor_chroma_pick_hint), style = MaterialTheme.typography.bodySmall)
                Spacer(Modifier.height(8.dp))
                Image(
                    bitmap = frame.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.FillBounds,
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(frame.width.toFloat() / frame.height)
                        .clip(RoundedCornerShape(8.dp))
                        .onSizeChanged { viewSize = it }
                        .pointerInput(frame) {
                            detectTapGestures { tap ->
                                if (viewSize.width == 0 || viewSize.height == 0) return@detectTapGestures
                                val x = (tap.x / viewSize.width * frame.width).toInt().coerceIn(0, frame.width - 1)
                                val y = (tap.y / viewSize.height * frame.height).toInt().coerceIn(0, frame.height - 1)
                                onPick(frame.getPixel(x, y).toLong() and 0xFFFFFFFFL or 0xFF000000L)
                            }
                        },
                )
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.editor_done)) } },
    )
}

@Composable
private fun chipColors() = FilterChipDefaults.filterChipColors(
    selectedContainerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.18f),
    selectedLabelColor = MaterialTheme.colorScheme.primary,
)

private val BORDER_COLORS = listOf(0xFFFFFFFF, 0xFF000000, 0xFF2EE6D6, 0xFF8B5CF6, 0xFFFF5C7A, 0xFFFFD166, 0xFF38BDF8)
