package com.flurocup.core.model

import kotlinx.serialization.Serializable

/**
 * Where a clip sits in the frame. Position is the offset of the clip's centre from the frame's
 * centre, as a fraction of the frame (0.5 = half a frame to the right / down). Scale 1 fits the
 * clip into the frame; rotation is clockwise, in degrees.
 */
@Serializable
data class ClipTransform(
    val x: Float = 0f,
    val y: Float = 0f,
    val scale: Float = 1f,
    val rotation: Float = 0f,
    val flipHorizontal: Boolean = false,
    val flipVertical: Boolean = false,
) {
    companion object {
        /** New overlays start at half size in the middle, so they read as picture-in-picture. */
        val OVERLAY_DEFAULT = ClipTransform(scale = 0.5f)
    }
}

/** How much is cut from each side of the source picture, as fractions of its size. */
@Serializable
data class CropRect(
    val left: Float = 0f,
    val top: Float = 0f,
    val right: Float = 0f,
    val bottom: Float = 0f,
) {
    val isEmpty: Boolean get() = left <= 0f && top <= 0f && right <= 0f && bottom <= 0f

    /** Keeps at least 10% of the picture on each axis. */
    fun clamped(): CropRect {
        fun side(v: Float) = v.coerceIn(0f, 0.9f)
        var l = side(left)
        var r = side(right)
        var t = side(top)
        var b = side(bottom)
        if (l + r > 0.9f) { val k = 0.9f / (l + r); l *= k; r *= k }
        if (t + b > 0.9f) { val k = 0.9f / (t + b); t *= k; b *= k }
        return CropRect(l, t, r, b)
    }
}

/**
 * Green-screen removal. [similarity] is how close to [colorArgb] a pixel must be to disappear,
 * [smoothness] softens the edge, [spill] removes the key colour's tint from what stays.
 */
@Serializable
data class ChromaKey(
    val colorArgb: Long = 0xFF00FF00,
    val similarity: Float = 0.3f,
    val smoothness: Float = 0.08f,
    val spill: Float = 0.5f,
)

@Serializable
enum class MaskShape { LINEAR, MIRROR, CIRCLE, RECTANGLE, HEART, STAR }

/**
 * A shape that hides part of the clip. Centre and size are fractions of the clip's picture
 * (0.5 = middle); [feather] softens the edge, as a fraction of the picture's shorter side.
 */
@Serializable
data class ClipMask(
    val shape: MaskShape,
    val centerX: Float = 0.5f,
    val centerY: Float = 0.5f,
    val width: Float = 0.6f,
    val height: Float = 0.6f,
    val rotation: Float = 0f,
    val feather: Float = 0.03f,
    val cornerRadius: Float = 0.2f,
    val invert: Boolean = false,
)

/** A line around the clip; [width] is a fraction of the picture's shorter side. */
@Serializable
data class ClipBorder(
    val width: Float = 0f,
    val colorArgb: Long = 0xFFFFFFFF,
)

/**
 * How an overlay mixes with what is under it. Stored now, rendered by FluroCup's own compositor
 * (Media3's built-in one only does normal alpha blending).
 */
@Serializable
enum class BlendMode {
    NORMAL, MULTIPLY, SCREEN, OVERLAY, SOFT_LIGHT, HARD_LIGHT, LIGHTEN, DARKEN,
    ADD, DIFFERENCE, EXCLUSION, COLOR, LUMINOSITY,
}

/**
 * Everything about a clip's look that can change while it plays without rebuilding the preview:
 * the preview reads these values on every frame.
 */
data class ClipLook(
    val transform: ClipTransform = ClipTransform(),
    val opacity: Float = 1f,
    val chromaKey: ChromaKey? = null,
    val mask: ClipMask? = null,
    val border: ClipBorder = ClipBorder(),
    val cornerRadius: Float = 0f,
) {
    /** True if the look needs the shader pass (anything beyond position, size and rotation). */
    val needsShader: Boolean
        get() = opacity < 1f || chromaKey != null || mask != null || border.width > 0f || cornerRadius > 0f
}
