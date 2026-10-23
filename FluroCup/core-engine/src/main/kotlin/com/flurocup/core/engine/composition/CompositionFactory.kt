package com.flurocup.core.engine.composition

import androidx.annotation.OptIn
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
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
     * @param videoEffects effects on the whole output, such as the export frame size.
     * @param hdrMode a [Composition.HdrMode], or null for Media3's default (keep HDR).
     * @param forceAudioTrack adds silence where clips have no sound, so mixed timelines export.
     * @param audioOnly the clips' sound only, with silence in place of photos.
     * @return null if there is nothing to play or export.
     */
    fun mainTrack(
        clips: List<MediaClip>,
        uriFor: (MediaClip) -> String,
        imageFrameRate: Float = 30f,
        videoEffects: List<Effect> = emptyList(),
        hdrMode: Int? = null,
        forceAudioTrack: Boolean = false,
        audioOnly: Boolean = false,
    ): Composition? {
        val playable = clips.filter { it.source.kind != MediaKind.AUDIO && it.durationUs > 0 }
        if (playable.isEmpty()) return null
        val sequence = EditedMediaItemSequence.Builder()
        playable.forEach { clip ->
            when {
                // Gaps are allowed in audio-only sequences: a photo becomes silence of its length.
                audioOnly && clip.source.kind == MediaKind.IMAGE -> sequence.addGap(clip.durationUs)
                clip.source.kind == MediaKind.IMAGE -> sequence.addItem(image(clip, uriFor(clip), imageFrameRate))
                else -> sequence.addItem(video(clip, uriFor(clip), removeVideo = audioOnly))
            }
        }
        if (audioOnly && playable.none { it.source.kind == MediaKind.VIDEO }) return null
        return Composition.Builder(sequence.build())
            .apply {
                if (videoEffects.isNotEmpty()) setEffects(Effects(emptyList(), videoEffects))
                if (hdrMode != null) setHdrMode(hdrMode)
                if (forceAudioTrack || audioOnly) experimentalSetForceAudioTrack(true)
            }
            .build()
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

    private fun video(clip: MediaClip, uri: String, removeVideo: Boolean): EditedMediaItem {
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
            .apply { if (removeVideo) setRemoveVideo(true) }
            .build()
    }
}
