package com.flurocup.core.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.flurocup.core.ui.theme.FluroColors
import com.flurocup.core.ui.theme.WordmarkTextStyle

/**
 * The FluroCup mark: a glowing gradient cup with a play symbol. It is drawn relative to its size,
 * so it stays sharp at any scale, including while a shared-element transition resizes it.
 *
 * @param glow 0 draws no halo, 1 the full one.
 */
@Composable
fun FluroLogoMark(
    modifier: Modifier = Modifier,
    size: Dp = 48.dp,
    glow: Float = 1f,
) {
    Canvas(modifier.size(size)) {
        if (glow > 0f) drawGlow(glow)
        drawCup()
    }
}

private fun DrawScope.drawGlow(glow: Float) {
    val radius = size.minDimension * 0.78f
    drawCircle(
        brush = Brush.radialGradient(
            0f to FluroColors.Teal.copy(alpha = 0.42f * glow),
            0.45f to FluroColors.Violet.copy(alpha = 0.22f * glow),
            1f to Color.Transparent,
            center = center,
            radius = radius,
        ),
        radius = radius,
        center = center,
    )
}

private fun DrawScope.drawCup() {
    val s = size.minDimension
    fun p(x: Float, y: Float) = Offset(x * s, y * s)

    val gradient = Brush.linearGradient(
        colors = FluroColors.BrandColors,
        start = p(0.15f, 0.25f),
        end = p(0.85f, 0.85f),
    )

    // Handle, drawn first so the body overlaps its ends.
    drawArc(
        brush = Brush.linearGradient(
            listOf(FluroColors.Aqua, FluroColors.Violet),
            start = p(0.6f, 0.38f),
            end = p(0.9f, 0.7f),
        ),
        startAngle = -80f,
        sweepAngle = 165f,
        useCenter = false,
        topLeft = p(0.56f, 0.38f),
        size = Size(0.3f * s, 0.28f * s),
        style = Stroke(width = 0.075f * s, cap = StrokeCap.Round),
    )

    val body = Path().apply {
        moveTo(0.14f * s, 0.3f * s)
        lineTo(0.72f * s, 0.3f * s)
        lineTo(0.655f * s, 0.76f * s)
        quadraticTo(0.64f * s, 0.86f * s, 0.54f * s, 0.86f * s)
        lineTo(0.32f * s, 0.86f * s)
        quadraticTo(0.22f * s, 0.86f * s, 0.205f * s, 0.76f * s)
        close()
    }
    drawPath(body, gradient)

    // Rim highlight.
    drawLine(
        color = Color.White.copy(alpha = 0.55f),
        start = p(0.2f, 0.34f),
        end = p(0.66f, 0.34f),
        strokeWidth = 0.025f * s,
        cap = StrokeCap.Round,
    )

    // Play symbol cut into the cup.
    val play = Path().apply {
        moveTo(0.37f * s, 0.46f * s)
        lineTo(0.55f * s, 0.575f * s)
        lineTo(0.37f * s, 0.69f * s)
        close()
    }
    drawPath(play, FluroColors.Background.copy(alpha = 0.9f))

    // Rising "fluorescent" wisps.
    val wisp = Stroke(width = 0.04f * s, cap = StrokeCap.Round)
    listOf(0.3f to FluroColors.Teal, 0.5f to FluroColors.Orchid).forEach { (x, color) ->
        val path = Path().apply {
            moveTo(x * s, 0.22f * s)
            cubicTo((x - 0.05f) * s, 0.16f * s, (x + 0.05f) * s, 0.12f * s, x * s, 0.06f * s)
        }
        drawPath(path, color.copy(alpha = 0.85f), style = wisp)
    }
}

/** "FluroCup" with "Fluro" in the brand gradient. */
@Composable
fun FluroWordmark(
    modifier: Modifier = Modifier,
    fontSize: TextUnit = 24.sp,
    style: TextStyle = WordmarkTextStyle,
) {
    Text(
        text = buildAnnotatedString {
            withStyle(SpanStyle(brush = FluroColors.BrandGradient)) { append("Fluro") }
            withStyle(SpanStyle(color = FluroColors.OnSurface)) { append("Cup") }
        },
        modifier = modifier,
        style = style.copy(fontSize = fontSize),
    )
}

@Preview
@Composable
private fun FluroLogoPreview() {
    FluroLogoMark(size = 160.dp)
}
