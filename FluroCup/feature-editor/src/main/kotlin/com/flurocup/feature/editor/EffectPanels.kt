package com.flurocup.feature.editor

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
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.animation.Crossfade
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.material3.AssistChip
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.flurocup.core.model.ClipEffect
import com.flurocup.core.model.EffectCatalog
import com.flurocup.core.model.EffectDefinition
import com.flurocup.core.model.EffectParam
import com.flurocup.core.model.EffectParamType
import kotlin.math.roundToInt

/** Which effect sheet replaces the timeline: the picker, one effect's settings, or a clip's effects. */
sealed interface EffectSheet {
    /** Picks an effect: for the clip [clipId] (null: an effect track), or to replace [replacing]. */
    data class Picker(val clipId: String?, val replacing: EffectTarget? = null) : EffectSheet

    data class Params(val target: EffectTarget, val effectId: String) : EffectSheet

    data class ClipList(val clipId: String) : EffectSheet
}

/** The effect library by category, as tiles; a tap applies the effect at once. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun EffectPickerPanel(
    catalog: EffectCatalog,
    forClip: Boolean,
    previews: Map<String, ImageBitmap>,
    onShowCategory: (List<EffectDefinition>) -> Unit,
    onPick: (EffectDefinition) -> Unit,
    onDone: () -> Unit,
) {
    var category by rememberSaveable { mutableStateOf(catalog.categories.firstOrNull()?.id) }
    var picked by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(category) { onShowCategory(catalog.inCategory(category.orEmpty())) }
    PanelFrame(
        title = stringResource(if (forClip) R.string.editor_effects_clip_title else R.string.editor_effects_title),
        onDone = onDone,
        header = {
            Text(
                text = stringResource(if (forClip) R.string.editor_effects_for_clip else R.string.editor_effects_for_frame),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            LazyRow(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                modifier = Modifier.padding(vertical = 6.dp),
            ) {
                items(catalog.categories, key = { it.id }) { c ->
                    FilterChip(
                        selected = c.id == category,
                        onClick = { category = c.id },
                        label = { Text(c.name) },
                        colors = effectChipColors(),
                    )
                }
            }
        },
    ) {
        val index = catalog.categories.indexOfFirst { it.id == category }.coerceAtLeast(0)
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.padding(vertical = 4.dp),
        ) {
            catalog.inCategory(category.orEmpty()).forEach { definition ->
                EffectTile(
                    name = definition.name,
                    preview = previews[definition.id],
                    brush = categoryBrush(index, catalog.categories.size),
                    selected = definition.id == picked,
                ) {
                    picked = definition.id
                    onPick(definition)
                }
            }
        }
    }
}

/** An effect as a tile: its look on the current frame (a gradient until that is ready) and its name. */
@Composable
private fun EffectTile(name: String, preview: ImageBitmap?, brush: Brush, selected: Boolean, onClick: () -> Unit) {
    Column(
        modifier = Modifier
            .width(76.dp)
            .clip(RoundedCornerShape(12.dp))
            .clickable(onClick = onClick)
            .padding(vertical = 2.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .size(width = 68.dp, height = 52.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(brush)
                .then(if (selected) Modifier.border(2.dp, MaterialTheme.colorScheme.primary, RoundedCornerShape(12.dp)) else Modifier),
            contentAlignment = Alignment.Center,
        ) {
            Crossfade(targetState = preview, label = "effectPreview") { image ->
                if (image != null) {
                    Image(bitmap = image, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                } else {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Icon(Icons.Rounded.AutoAwesome, contentDescription = null, tint = Color.White.copy(alpha = 0.9f))
                    }
                }
            }
        }
        Spacer(Modifier.height(4.dp))
        Text(
            text = name,
            style = MaterialTheme.typography.labelSmall,
            maxLines = 2,
            minLines = 2,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
    }
}

/** A gradient per category, around the colour wheel, so categories are told apart at a glance. */
private fun categoryBrush(index: Int, count: Int): Brush {
    val hue = 170f + 360f * index / count.coerceAtLeast(1)
    return Brush.linearGradient(
        listOf(Color.hsv(hue % 360f, 0.65f, 0.85f), Color.hsv((hue + 50f) % 360f, 0.7f, 0.6f)),
    )
}

/**
 * One effect's settings, shown live while a slider moves ([onParams]) and saved when it is let
 * go ([onParamsDone]).
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun EffectParamsPanel(
    definition: EffectDefinition,
    params: Map<String, Float>,
    onParams: (Map<String, Float>) -> Unit,
    onParamsDone: (Map<String, Float>) -> Unit,
    onReplace: () -> Unit,
    onRemove: () -> Unit,
    onPlay: () -> Unit,
    onDone: () -> Unit,
) {
    val values = definition.resolve(params)
    PanelFrame(definition.name, onDone) {
        definition.params.forEach { param ->
            val value = values.getValue(param.id)
            when (param.type) {
                EffectParamType.FLOAT -> LabeledSlider(
                    label = param.name,
                    value = value,
                    range = param.min..param.max,
                    format = { formatParam(param, it) },
                    onChange = { onParams(params + (param.id to it)) },
                    onDone = { onParamsDone(params) },
                )
                EffectParamType.COLOR -> {
                    Text(param.name, style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(top = 6.dp))
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(vertical = 6.dp)) {
                        val swatches = (listOf(param.default) + EFFECT_COLORS.map { it.toFloat() }).distinct()
                        swatches.forEach { rgb ->
                            val selected = rgb.toInt() == value.toInt()
                            Box(
                                Modifier
                                    .size(30.dp)
                                    .clip(CircleShape)
                                    .background(Color(0xFF000000 or rgb.toLong()))
                                    .border(if (selected) 3.dp else 1.dp, if (selected) MaterialTheme.colorScheme.primary else Color.White.copy(alpha = 0.3f), CircleShape)
                                    .clickable {
                                        val next = params + (param.id to rgb)
                                        onParams(next)
                                        onParamsDone(next)
                                    },
                            )
                        }
                    }
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(vertical = 6.dp)) {
            OutlinedButton(onClick = onPlay) {
                Icon(Icons.Rounded.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(4.dp))
                Text(stringResource(R.string.editor_effect_play))
            }
            OutlinedButton(onClick = onReplace) { Text(stringResource(R.string.editor_effect_replace)) }
            TextButton(onClick = {
                onParams(emptyMap())
                onParamsDone(emptyMap())
            }) { Text(stringResource(R.string.editor_reset)) }
            Spacer(Modifier.weight(1f))
            TextButton(onClick = onRemove) {
                Text(stringResource(R.string.editor_tool_delete), color = MaterialTheme.colorScheme.error)
            }
        }
    }
}

private fun formatParam(param: EffectParam, value: Float): String = when {
    param.min == 0f && param.max == 1f -> "${(value * 100).roundToInt()}%"
    param.max - param.min >= 10f -> value.roundToInt().toString()
    else -> "%.1f".format(java.util.Locale.ROOT, value)
}

/** The effects on one clip: tap one to adjust it, the cross removes it. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun ClipEffectsPanel(
    effects: List<ClipEffect>,
    nameOf: (String) -> String,
    onOpen: (ClipEffect) -> Unit,
    onRemove: (ClipEffect) -> Unit,
    onAdd: () -> Unit,
    onDone: () -> Unit,
) {
    PanelFrame(stringResource(R.string.editor_effects_clip_title), onDone) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            effects.forEach { effect ->
                AssistChip(
                    onClick = { onOpen(effect) },
                    label = { Text(nameOf(effect.effectId)) },
                    leadingIcon = { Icon(Icons.Rounded.AutoAwesome, contentDescription = null, modifier = Modifier.size(16.dp)) },
                    trailingIcon = {
                        Icon(
                            Icons.Rounded.Close,
                            contentDescription = stringResource(R.string.editor_tool_delete),
                            modifier = Modifier
                                .size(18.dp)
                                .clip(CircleShape)
                                .clickable { onRemove(effect) },
                        )
                    },
                )
            }
        }
        OutlinedButton(onClick = onAdd, modifier = Modifier.padding(vertical = 8.dp)) {
            Icon(Icons.Rounded.Add, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text(stringResource(R.string.editor_effect_add))
        }
    }
}

@Composable
private fun effectChipColors() = FilterChipDefaults.filterChipColors(
    selectedContainerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.18f),
    selectedLabelColor = MaterialTheme.colorScheme.primary,
)

private val EFFECT_COLORS = listOf(0xFFFFFF, 0x000000, 0x2DE2C8, 0x8B5CF6, 0xFF5C8A, 0xFFB347, 0xFFE066, 0x38BDF8, 0xE53935, 0x4ADE80)
