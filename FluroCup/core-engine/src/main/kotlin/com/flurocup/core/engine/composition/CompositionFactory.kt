package com.flurocup.core.engine.composition

import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import com.flurocup.core.model.MediaClip
import com.flurocup.core.model.MediaKind
import com.flurocup.core.model.edit.MainTrackEdits
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Turns the project timeline into a Media3 [Composition]. The same composition drives the preview
 * (CompositionPlayer) and the export (Transformer), so what is seen is what gets exported.
 */
@OptIn(UnstableApi::class)
object CompositionFactory {

    /**
     * @param uriFor which file to read for a clip: the proxy for preview, the original for export.
     * @param imageFrameRate frame rate photos are shown at.
     * @return null if there is nothing to play.
     */
    fun mainTrack(clips: List<MediaClip>, uriFor: (MediaClip) -> String, imageFrameRate: Float = 30f): Composition? {
        val items = clips.filter { it.source.kind != MediaKind.AUDIO && it.durationUs > 0 }.map { clip ->
            if (clip.source.kind == MediaKind.IMAGE) image(clip, uriFor(clip), imageFrameRate) else video(clip, uriFor(clip))
        }
        if (items.isEmpty()) return null
        return Composition.Builder(EditedMediaItemSequence.Builder(items).build()).build()
    }

    private fun image(clip: MediaClip, uri: String, frameRate: Float): EditedMediaItem {
        val item = MediaItem.Builder()
            .setUri(uri)
            .setImageDurationMs(max(1L, clip.durationUs / 1000))
            .build()
        return EditedMediaItem.Builder(item)
            .setFrameRate(frameRate.roundToInt().coerceIn(1, 120))
            .build()
    }

    private fun video(clip: MediaClip, uri: String): EditedMediaItem {
        val sourceUs = MainTrackEdits.sourceDurationUs(clip)
        val endUs = min(clip.trimEndUs, sourceUs)
        val item = MediaItem.Builder()
            .setUri(uri)
            .setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionUs(clip.trimStartUs.coerceIn(0L, endUs))
                    .setEndPositionUs(endUs)
                    .build(),
            )
            .build()
        // CompositionPlayer needs every item's full length, before clipping.
        return EditedMediaItem.Builder(item)
            .setDurationUs(max(1L, sourceUs))
            .build()
    }
}
