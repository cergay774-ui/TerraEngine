package com.flurocup.core.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Accent colour pairs for the gradient; the first is FluroCup's own. */
enum class AccentPalette(val first: Color, val second: Color, val third: Color, val onAccent: Color) {
    FLURO(Color(0xFF2EE6D6), Color(0xFF8B5CF6), Color(0xFFC084FC), Color(0xFF0B0B12)),
    SUNSET(Color(0xFFFFB347), Color(0xFFFF4F8B), Color(0xFFFF7A59), Color(0xFF1A0B0B)),
    OCEAN(Color(0xFF38BDF8), Color(0xFF2563EB), Color(0xFF60A5FA), Color(0xFFFFFFFF)),
    FOREST(Color(0xFFA3E635), Color(0xFF10B981), Color(0xFF6EE7B7), Color(0xFF07140B)),
    ROSE(Color(0xFFF9A8D4), Color(0xFFDB2777), Color(0xFFF472B6), Color(0xFF1A0712)),
    GOLD(Color(0xFFFDE047), Color(0xFFF97316), Color(0xFFFBBF24), Color(0xFF1A1205)),
    NEON(Color(0xFF22D3EE), Color(0xFFE879F9), Color(0xFFA3E635), Color(0xFF0B0B12)),
}

enum class ThemeMode { SYSTEM, DARK, LIGHT, CUSTOM }

/** The look the user picked; [customDark] and [accent] apply to [ThemeMode.CUSTOM]. */
data class ThemeSettings(
    val mode: ThemeMode = ThemeMode.DARK,
    val customDark: Boolean = true,
    val accent: AccentPalette = AccentPalette.FLURO,
) {
    fun isDark(systemDark: Boolean): Boolean = when (mode) {
        ThemeMode.SYSTEM -> systemDark
        ThemeMode.DARK -> true
        ThemeMode.LIGHT -> false
        ThemeMode.CUSTOM -> customDark
    }

    val effectiveAccent: AccentPalette get() = if (mode == ThemeMode.CUSTOM) accent else AccentPalette.FLURO
}

/** Every colour the app draws with directly, for one theme. */
data class FluroPalette(
    val accent: AccentPalette,
    val dark: Boolean,
    val background: Color,
    val surface: Color,
    val surfaceHigh: Color,
    val surfaceHighest: Color,
    val outline: Color,
    val onSurface: Color,
    val onSurfaceMuted: Color,
    /** Strongest contrast with the background: the playhead, selection outlines. */
    val contrast: Color,
    val onContrast: Color,
) {
    companion object {
        fun of(accent: AccentPalette, dark: Boolean) = if (dark) {
            FluroPalette(
                accent, true,
                background = Color(0xFF0B0B12), surface = Color(0xFF14141D), surfaceHigh = Color(0xFF1C1C28),
                surfaceHighest = Color(0xFF262635), outline = Color(0xFF34344A),
                onSurface = Color(0xFFF2F2F7), onSurfaceMuted = Color(0xFFA0A0B4),
                contrast = Color.White, onContrast = Color.Black,
            )
        } else {
            FluroPalette(
                accent, false,
                background = Color(0xFFF5F5FA), surface = Color(0xFFFFFFFF), surfaceHigh = Color(0xFFEDEDF4),
                surfaceHighest = Color(0xFFE1E1EB), outline = Color(0xFFC6C6D4),
                onSurface = Color(0xFF15151E), onSurfaceMuted = Color(0xFF5C5C6E),
                contrast = Color(0xFF15151E), onContrast = Color.White,
            )
        }
    }
}

/**
 * FluroCup's colours for the current theme. They are read from snapshot state, so screens and
 * canvases that use them redraw when the theme changes.
 */
object FluroColors {
    private var palette by mutableStateOf(FluroPalette.of(AccentPalette.FLURO, dark = true))

    val current: FluroPalette get() = palette

    /** Switches every colour below; called by [FluroTheme]. */
    fun use(next: FluroPalette) {
        if (palette != next) palette = next
    }

    val Teal: Color get() = palette.accent.first
    val Aqua: Color get() = palette.accent.third
    val Violet: Color get() = palette.accent.second
    val Orchid: Color get() = palette.accent.third

    val Background: Color get() = palette.background
    val Surface: Color get() = palette.surface
    val SurfaceHigh: Color get() = palette.surfaceHigh
    val SurfaceHighest: Color get() = palette.surfaceHighest
    val Outline: Color get() = palette.outline
    val OnSurface: Color get() = palette.onSurface
    val OnSurfaceMuted: Color get() = palette.onSurfaceMuted
    val Error = Color(0xFFFF5C7A)
    val Contrast: Color get() = palette.contrast
    val OnContrast: Color get() = palette.onContrast

    /** Text and icons on the brand gradient. */
    val OnBrand: Color get() = palette.accent.onAccent

    val BrandColors: List<Color> get() = listOf(Teal, Violet)

    /** The signature gradient for buttons and highlights. */
    val BrandGradient: Brush get() = Brush.linearGradient(BrandColors)
}

private fun colorScheme(p: FluroPalette) = if (p.dark) {
    darkColorScheme(
        primary = p.accent.first,
        onPrimary = p.accent.onAccent,
        primaryContainer = lerp(p.accent.first, Color.Black, 0.6f),
        onPrimaryContainer = lerp(p.accent.first, Color.White, 0.7f),
        secondary = p.accent.second,
        onSecondary = Color.White,
        secondaryContainer = lerp(p.accent.second, Color.Black, 0.55f),
        onSecondaryContainer = lerp(p.accent.second, Color.White, 0.75f),
        tertiary = p.accent.third,
        background = p.background,
        onBackground = p.onSurface,
        surface = p.surface,
        onSurface = p.onSurface,
        surfaceVariant = p.surfaceHigh,
        onSurfaceVariant = p.onSurfaceMuted,
        surfaceContainerLowest = p.background,
        surfaceContainerLow = p.surface,
        surfaceContainer = p.surface,
        surfaceContainerHigh = p.surfaceHigh,
        surfaceContainerHighest = p.surfaceHighest,
        outline = p.outline,
        outlineVariant = lerp(p.outline, p.background, 0.4f),
        error = FluroColors.Error,
    )
} else {
    // Bright accents are too pale for text on white: a darker shade is used for text and icons.
    val primary = lerp(p.accent.first, Color.Black, 0.38f)
    val secondary = lerp(p.accent.second, Color.Black, 0.2f)
    lightColorScheme(
        primary = primary,
        onPrimary = Color.White,
        primaryContainer = lerp(p.accent.first, Color.White, 0.7f),
        onPrimaryContainer = lerp(p.accent.first, Color.Black, 0.7f),
        secondary = secondary,
        onSecondary = Color.White,
        secondaryContainer = lerp(p.accent.second, Color.White, 0.75f),
        onSecondaryContainer = lerp(p.accent.second, Color.Black, 0.6f),
        tertiary = lerp(p.accent.third, Color.Black, 0.3f),
        background = p.background,
        onBackground = p.onSurface,
        surface = p.surface,
        onSurface = p.onSurface,
        surfaceVariant = p.surfaceHigh,
        onSurfaceVariant = p.onSurfaceMuted,
        surfaceContainerLowest = Color.White,
        surfaceContainerLow = p.surface,
        surfaceContainer = p.surfaceHigh,
        surfaceContainerHigh = p.surfaceHigh,
        surfaceContainerHighest = p.surfaceHighest,
        outline = p.outline,
        outlineVariant = lerp(p.outline, p.background, 0.4f),
        error = Color(0xFFD92D4F),
    )
}

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
    settings: ThemeSettings = ThemeSettings(),
    content: @Composable () -> Unit,
) {
    val dark = settings.isDark(isSystemInDarkTheme())
    val palette = remember(settings.effectiveAccent, dark) { FluroPalette.of(settings.effectiveAccent, dark) }
    // Set before the content reads it, so the first frame already has the right colours.
    FluroColors.use(palette)
    MaterialTheme(
        colorScheme = remember(palette) { colorScheme(palette) },
        typography = FluroTypography,
        shapes = FluroShapes,
        content = content,
    )
}
