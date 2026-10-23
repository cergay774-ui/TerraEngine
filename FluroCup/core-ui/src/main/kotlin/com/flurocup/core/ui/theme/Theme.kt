package com.flurocup.core.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** FluroCup brand colours: a bright teal-to-violet gradient on near-black. */
object FluroColors {
    val Teal = Color(0xFF2EE6D6)
    val Aqua = Color(0xFF38BDF8)
    val Violet = Color(0xFF8B5CF6)
    val Orchid = Color(0xFFC084FC)

    val Background = Color(0xFF0B0B12)
    val Surface = Color(0xFF14141D)
    val SurfaceHigh = Color(0xFF1C1C28)
    val SurfaceHighest = Color(0xFF262635)
    val Outline = Color(0xFF34344A)
    val OnSurface = Color(0xFFF2F2F7)
    val OnSurfaceMuted = Color(0xFFA0A0B4)
    val Error = Color(0xFFFF5C7A)

    val BrandColors = listOf(Teal, Violet)

    /** The signature gradient for buttons and highlights. */
    val BrandGradient: Brush get() = Brush.linearGradient(BrandColors)
}

private val DarkScheme = darkColorScheme(
    primary = FluroColors.Teal,
    onPrimary = Color(0xFF00201D),
    primaryContainer = Color(0xFF00504A),
    onPrimaryContainer = Color(0xFFB2FFF6),
    secondary = FluroColors.Violet,
    onSecondary = Color.White,
    secondaryContainer = Color(0xFF3B2470),
    onSecondaryContainer = Color(0xFFEADDFF),
    tertiary = FluroColors.Orchid,
    background = FluroColors.Background,
    onBackground = FluroColors.OnSurface,
    surface = FluroColors.Surface,
    onSurface = FluroColors.OnSurface,
    surfaceVariant = FluroColors.SurfaceHigh,
    onSurfaceVariant = FluroColors.OnSurfaceMuted,
    surfaceContainerLowest = FluroColors.Background,
    surfaceContainerLow = FluroColors.Surface,
    surfaceContainer = FluroColors.Surface,
    surfaceContainerHigh = FluroColors.SurfaceHigh,
    surfaceContainerHighest = FluroColors.SurfaceHighest,
    outline = FluroColors.Outline,
    outlineVariant = Color(0xFF24243A),
    error = FluroColors.Error,
)

private val LightScheme = lightColorScheme(
    primary = Color(0xFF00897B),
    secondary = Color(0xFF6D28D9),
    tertiary = Color(0xFF9333EA),
)

private val FluroTypography = Typography().run {
    copy(
        displaySmall = displaySmall.copy(fontWeight = FontWeight.Bold, letterSpacing = (-0.5).sp),
        headlineSmall = headlineSmall.copy(fontWeight = FontWeight.Bold),
        titleLarge = titleLarge.copy(fontWeight = FontWeight.SemiBold),
        titleMedium = titleMedium.copy(fontWeight = FontWeight.SemiBold),
        labelLarge = labelLarge.copy(fontWeight = FontWeight.SemiBold),
    )
}

private val FluroShapes = Shapes(
    extraSmall = RoundedCornerShape(6.dp),
    small = RoundedCornerShape(10.dp),
    medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(22.dp),
    extraLarge = RoundedCornerShape(30.dp),
)

/** Style for the "FluroCup" wordmark. */
val WordmarkTextStyle = TextStyle(fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.5).sp)

@Composable
fun FluroTheme(
    darkTheme: Boolean = true,
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkScheme else LightScheme,
        typography = FluroTypography,
        shapes = FluroShapes,
        content = content,
    )
}
