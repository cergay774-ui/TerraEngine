package com.flurocup.app.splash

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.flurocup.app.R
import com.flurocup.core.ui.components.FluroLogoMark
import com.flurocup.core.ui.components.FluroWordmark
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The animated splash: the mark springs in with a breathing glow, the wordmark and tagline follow,
 * then [onFinished] hands over to the home screen, where the mark flies into the top bar.
 */
@Composable
fun FluroSplash(
    markModifier: Modifier,
    onFinished: () -> Unit,
) {
    val mark = remember { Animatable(0f) }
    val text = remember { Animatable(0f) }
    val finished by rememberUpdatedState(onFinished)

    val glowTransition = rememberInfiniteTransition(label = "splashGlow")
    val glowPulse by glowTransition.animateFloat(
        initialValue = 0.75f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(900, easing = FastOutSlowInEasing), RepeatMode.Reverse),
        label = "glowPulse",
    )

    LaunchedEffect(Unit) {
        launch { mark.animateTo(1f, spring(dampingRatio = 0.6f, stiffness = Spring.StiffnessLow)) }
        delay(260)
        text.animateTo(1f, tween(520, easing = FastOutSlowInEasing))
        delay(520)
        finished()
    }

    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            FluroLogoMark(
                modifier = markModifier.graphicsLayer {
                    val m = mark.value
                    alpha = m.coerceIn(0f, 1f)
                    scaleX = 0.7f + 0.3f * m
                    scaleY = 0.7f + 0.3f * m
                },
                size = 136.dp,
                glow = glowPulse * mark.value.coerceIn(0f, 1f),
            )
            Spacer(Modifier.height(20.dp))
            FluroWordmark(
                fontSize = 40.sp,
                modifier = Modifier.graphicsLayer {
                    alpha = text.value
                    translationY = (1f - text.value) * 24.dp.toPx()
                },
            )
            Spacer(Modifier.height(8.dp))
            Text(
                text = stringResource(R.string.splash_tagline),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.graphicsLayer {
                    alpha = text.value * 0.9f
                    translationY = (1f - text.value) * 32.dp.toPx()
                },
            )
        }
    }
}
