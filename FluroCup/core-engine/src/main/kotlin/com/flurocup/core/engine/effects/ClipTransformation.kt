package com.flurocup.core.engine.effects

import android.graphics.Matrix
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.MatrixTransformation
import com.flurocup.core.model.ClipLook
import java.util.concurrent.atomic.AtomicReference

/**
 * Places a clip in the output frame: position, scale, rotation and flips from its look, read
 * every frame so the preview can follow a finger. Works in normalised device coordinates on a
 * frame of [aspect] (width / height), correcting for the frame's shape so rotation doesn't skew.
 */
@OptIn(UnstableApi::class)
class ClipTransformation(
    private val look: AtomicReference<ClipLook>,
    private val aspect: Float,
) : MatrixTransformation {

    private val matrix = Matrix()

    override fun getMatrix(presentationTimeUs: Long): Matrix {
        val t = look.get().transform
        val scale = t.scale.coerceIn(0.01f, 20f)
        matrix.reset()
        matrix.postScale(if (t.flipHorizontal) -scale else scale, if (t.flipVertical) -scale else scale)
        // Rotate in a square space so a non-square frame isn't sheared.
        matrix.postScale(aspect, 1f)
        // NDC has y up, so a clockwise turn on screen is a negative angle here.
        matrix.postRotate(-t.rotation)
        matrix.postScale(1f / aspect, 1f)
        // Position is a fraction of the frame; NDC spans 2 units, and its y axis points up.
        matrix.postTranslate(t.x * 2f, -t.y * 2f)
        return matrix
    }
}
