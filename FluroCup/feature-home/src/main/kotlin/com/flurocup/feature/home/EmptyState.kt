package com.flurocup.feature.home

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.flurocup.core.ui.components.GradientIconSurface
import com.flurocup.core.ui.theme.FluroColors

/** Shown when there are no projects: one big, softly pulsing "Создать новый" button. */
@Composable
internal fun EmptyState(onCreate: () -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        PulsingCreateButton(onClick = onCreate)
        Spacer(Modifier.height(28.dp))
        Text(
            text = stringResource(R.string.home_create_new),
            style = MaterialTheme.typography.headlineSmall,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(8.dp))
        Text(
            text = stringResource(R.string.home_create_hint),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        // Lifts the group slightly above the true centre, where it reads better.
        Spacer(Modifier.height(64.dp))
    }
}

@Composable
private fun PulsingCreateButton(onClick: () -> Unit) {
    val transition = rememberInfiniteTransition(label = "createPulse")
    val breath by transition.animateFloat(
        initialValue = 1f,
        targetValue = 1.06f,
        animationSpec = infiniteRepeatable(tween(1300, easing = FastOutSlowInEasing), RepeatMode.Reverse),
        label = "breath",
    )
    val ripple by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(2600, easing = LinearEasing), RepeatMode.Restart),
        label = "ripple",
    )
    val stringNew = stringResource(R.string.home_create_new)

    Box(Modifier.size(220.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.matchParentSize()) {
            val base = 66.dp.toPx()
            val brush = Brush.linearGradient(FluroColors.BrandColors)
            // Two rings expanding outwards, half a cycle apart.
            listOf(ripple, (ripple + 0.5f) % 1f).forEach { p ->
                drawCircle(
                    brush = brush,
                    radius = base * (1f + 0.62f * p),
                    alpha = (1f - p) * 0.55f,
                    style = Stroke(width = 2.dp.toPx() * (1f - p) + 0.5f),
                )
            }
            drawCircle(
                brush = Brush.radialGradient(
                    listOf(FluroColors.Violet.copy(alpha = 0.35f), FluroColors.Teal.copy(alpha = 0f)),
                    radius = base * 1.6f,
                ),
                radius = base * 1.6f,
            )
        }
        GradientIconSurface(
            onClick = onClick,
            modifier = Modifier
                .graphicsLayer {
                    scaleX = breath
                    scaleY = breath
                }
                .size(132.dp),
        ) {
            Icon(Icons.Rounded.Add, contentDescription = stringNew, modifier = Modifier.size(64.dp))
        }
    }
}
