package com.flurocup.core.engine.composition

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Crop
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import com.flurocup.core.engine.effects.BackgroundFillEffect
import com.flurocup.core.engine.effects.CatalogEffect
import com.flurocup.core.engine.effects.ClipLookEffect
import com.flurocup.core.engine.effects.EffectLibrary
import com.flurocup.core.model.Background
import com.flurocup.core.engine.effects.ClipTransformation
import com.flurocup.core.model.ClipLook
import com.flurocup.core.model.EffectItem
import com.flurocup.core.model.HdrType
import com.flurocup.core.model.MediaClip
import com.flurocup.core.model.MediaKind
import com.flurocup.core.model.Project
import com.flurocup.core.model.edit.MainTrackEdits
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.util.concurrent.atomic.AtomicReference
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** How to render a project: frame size and rate, which files to read, where live looks come from. */
data class RenderSpec(
    val width: Int,
    val height: Int,
    val frameRate: Float,
    /** The proxy for preview, the original for export. */
    val uriFor: (MediaClip) -> String,
    /** The look each clip's effects read; the preview passes live references here. */
    val lookFor: (MediaClip) -> AtomicReference<ClipLook>,
    /** Clips that get the look shader even with a plain look, so a look can be edited live. */
    val forceLookShader: Set<String> = emptySet(),
    /** The parameters each effect (by id) reads; the preview passes live references here. */
    val effectParamsFor: (id: String, saved: Map<String, Float>) -> AtomicReference<Map<String, Float>> =
        { _, saved -> AtomicReference(saved) },
)

/**
 * Turns a project into a Media3 [Composition]; the same one drives the preview (CompositionPlayer)
 * and the export (Transformer), so what is seen is what gets exported.
 *
 * Every clip is fitted to the output frame and placed by its transform, with transparent space
 * around it. With overlays, the composition has several sequences, which Media3's compositor
 * stacks with the first sequence on top and the first sequence's frames setting the output
 * timing. So the first sequence is an invisible full-length layer at the project frame rate,
 * then the overlay tracks from the top layer down, then the main track. Gaps on a layer are
 * filled with transparent frames, because video sequences can't have empty gaps.
 *
 * A clip's own effects run on its picture after its look, before it is fitted and placed. Effect
 * tracks run on the finished frame, bottom track first.
 */
@OptIn(UnstableApi::class)
@Singleton
class CompositionBuilder @Inject constructor(
    @ApplicationContext private val context: Context,
    private val effects: EffectLibrary,
) {

    /** True if the project needs the multi-layer path (and so a multi-input preview graph). */
    fun isLayered(project: Project): Boolean = overlayLayers(project).isNotEmpty()

    /**
     * @param compositionEffects effects on the finished frame, such as a frame-rate drop.
     * @param keepHdr keep HDR when possible; layered projects are always tone-mapped to SDR,
     *     because Media3's compositor mixes SDR only.
     * @param forExport adds silence where clips have no sound, which Transformer needs.
     */
    fun video(
        project: Project,
        spec: RenderSpec,
        compositionEffects: List<Effect> = emptyList(),
        keepHdr: Boolean = true,
        forExport: Boolean = false,
    ): Composition? {
        val main = playable(MainTrackEdits.clips(project))
        val layers = overlayLayers(project)
        if (main.isEmpty() && layers.isEmpty()) return null
        val totalUs = max(main.lastOrNull()?.endUs ?: 0L, layers.maxOfOrNull { layer -> layer.last().endUs } ?: 0L)

        val sequences = if (layers.isEmpty()) {
            listOf(sequence(trackTypesFor(main)) { main.forEach { addItem(item(it, spec)) } })
        } else {
            buildList {
                add(sequence(VIDEO_ONLY) { addItem(filler(totalUs, spec)) })
                // Overlay tracks are stored bottom-up; the compositor wants the top layer first.
                layers.asReversed().forEach { add(layered(it, totalUs, spec)) }
                if (main.isNotEmpty()) add(layered(main, totalUs, spec))
            }
        }

        val clips = main + layers.flatten()
        val anyHdr = clips.any { (it.source.info?.hdr ?: HdrType.NONE) != HdrType.NONE }
        val hasSound = clips.any(::hasAudio)
        // Transparent areas (masks, keys, opacity, space around a smaller clip) end up as the
        // project background, the same on screen and in the file.
        val background = (project.settings.background as? Background.Color)?.argb ?: 0xFF000000
        val finalEffects = buildList {
            add(BackgroundFillEffect(background))
            addAll(trackEffects(project, totalUs, spec))
            addAll(compositionEffects)
        }
        return Composition.Builder(sequences)
            .apply {
                setEffects(Effects(emptyList(), finalEffects))
                if (anyHdr && (layers.isNotEmpty() || !keepHdr)) setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL)
                if (forExport && hasSound) experimentalSetForceAudioTrack(true)
            }
            .build()
    }

    /** The sound of all tracks, mixed, with silence for photos and gaps; null if there is none. */
    fun audioOnly(project: Project, uriFor: (MediaClip) -> String): Composition? {
        val tracks = listOf(playable(MainTrackEdits.clips(project))) + overlayLayers(project)
        val sequences = tracks.filter { track -> track.any(::hasAudio) }.map { clips ->
            sequence(AUDIO_ONLY) {
                var t = 0L
                clips.forEach { clip ->
                    if (clip.startUs > t) addGap(clip.startUs - t)
                    if (hasAudio(clip)) addItem(video(clip, uriFor(clip), effects = emptyList(), removeVideo = true)) else addGap(clip.durationUs)
                    t = clip.endUs
                }
            }
        }
        if (sequences.isEmpty()) return null
        return Composition.Builder(sequences).experimentalSetForceAudioTrack(true).build()
    }

    fun hasAudio(clip: MediaClip): Boolean =
        clip.source.kind == MediaKind.VIDEO && (clip.source.info?.audioTrackCount ?: 1) > 0

    private fun overlayLayers(project: Project): List<List<MediaClip>> =
        project.timeline.overlayTracks
            .filterNot { it.hidden }
            .map { track -> playable(track.items.filterIsInstance<MediaClip>()).sortedBy { it.startUs } }
            .filter { it.isNotEmpty() }

    private fun trackEffects(project: Project, totalUs: Long, spec: RenderSpec): List<Effect> =
        project.timeline.effectTracks
            .filterNot { it.hidden }
            .flatMap { track -> track.items.filterIsInstance<EffectItem>() }
            .filter { it.startUs < totalUs && it.durationUs > 0 }
            .sortedBy { it.startUs }
            .mapNotNull { catalogEffect(it.id, it.effectId, it.params, it.startUs, it.durationUs, spec, clipEffect = false) }

    private fun catalogEffect(
        id: String,
        effectId: String,
        params: Map<String, Float>,
        startUs: Long,
        durationUs: Long,
        spec: RenderSpec,
        clipEffect: Boolean,
    ): Effect? {
        val definition = effects.definition(effectId) ?: return null
        return CatalogEffect(effects.fragmentShader(definition), definition, spec.effectParamsFor(id, params), startUs, durationUs, clipEffect)
    }

    private fun playable(clips: List<MediaClip>) = clips.filter { it.source.kind != MediaKind.AUDIO && it.durationUs > 0 }

    private fun layered(clips: List<MediaClip>, totalUs: Long, spec: RenderSpec): EditedMediaItemSequence = sequence(trackTypesFor(clips)) {
        var t = 0L
        clips.forEach { clip ->
            if (clip.startUs - t >= MIN_FILLER_US) addItem(filler(clip.startUs - t, spec))
            addItem(item(clip, spec))
            t = max(t, clip.endUs)
        }
        // A layer that ended would keep showing its last frame; transparent frames cover the rest.
        if (totalUs - t >= MIN_FILLER_US) addItem(filler(totalUs - t, spec))
    }

    private fun item(clip: MediaClip, spec: RenderSpec): EditedMediaItem {
        val effects = buildList<Effect> {
            if (!clip.crop.isEmpty) {
                val c = clip.crop.clamped()
                add(Crop(-1f + 2f * c.left, 1f - 2f * c.right, -1f + 2f * c.bottom, 1f - 2f * c.top))
            }
            val look = spec.lookFor(clip)
            if (clip.look.needsShader || clip.id in spec.forceLookShader) add(ClipLookEffect(look))
            clip.effects.forEach { fx ->
                catalogEffect(fx.id, fx.effectId, fx.params, clip.startUs, clip.durationUs, spec, clipEffect = true)?.let(::add)
            }
            add(Presentation.createForWidthAndHeight(spec.width, spec.height, Presentation.LAYOUT_SCALE_TO_FIT))
            add(ClipTransformation(look, spec.width.toFloat() / spec.height))
        }
        return if (clip.source.kind == MediaKind.IMAGE) {
            image(spec.uriFor(clip), clip.durationUs, spec.frameRate, effects)
        } else {
            video(clip, spec.uriFor(clip), effects, removeVideo = false)
        }
    }

    private fun image(uri: String, durationUs: Long, frameRate: Float, effects: List<Effect>): EditedMediaItem {
        val item = MediaItem.Builder()
            .setUri(uri)
            .setImageDurationMs(max(1L, (durationUs + 500) / 1000))
            .build()
        return EditedMediaItem.Builder(item)
            .setFrameRate(frameRate.roundToInt().coerceIn(1, 120))
            .setEffects(Effects(emptyList(), effects))
            .build()
    }

    private fun video(clip: MediaClip, uri: String, effects: List<Effect>, removeVideo: Boolean): EditedMediaItem {
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
            .setEffects(Effects(emptyList(), effects))
            .apply { if (removeVideo) setRemoveVideo(true) }
            .build()
    }

    /**
     * Transparent frames for [durationUs], at the output size: the compositor takes its output
     * size from the first layer, which is a filler.
     */
    private fun filler(durationUs: Long, spec: RenderSpec): EditedMediaItem =
        image(
            transparentFrameUri(),
            durationUs,
            spec.frameRate,
            effects = listOf(Presentation.createForWidthAndHeight(spec.width, spec.height, Presentation.LAYOUT_STRETCH_TO_FIT)),
        )

    private fun transparentFrameUri(): String {
        val file = File(context.filesDir, "engine/transparent.png")
        if (!file.isFile) {
            file.parentFile?.mkdirs()
            val bitmap = Bitmap.createBitmap(16, 16, Bitmap.Config.ARGB_8888)
            val temp = File(file.path + ".tmp")
            temp.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            temp.renameTo(file)
            bitmap.recycle()
        }
        return Uri.fromFile(file).toString()
    }

    /** Sound only if some clip on the track has it; photos and silent clips then get silence. */
    private fun trackTypesFor(clips: List<MediaClip>): Set<Int> =
        if (clips.any(::hasAudio)) AUDIO_AND_VIDEO else VIDEO_ONLY

    /**
     * A sequence with these track types. Declaring sound is enough for Media3 to fill photos and
     * silent clips with silence; its older "force audio track" switch must not be combined with
     * declared track types (it throws).
     */
    private inline fun sequence(trackTypes: Set<Int>, block: EditedMediaItemSequence.Builder.() -> Unit): EditedMediaItemSequence =
        EditedMediaItemSequence.Builder(trackTypes).apply(block).build()

    private companion object {
        const val MIN_FILLER_US = 2_000L
        val VIDEO_ONLY = setOf(C.TRACK_TYPE_VIDEO)
        val AUDIO_ONLY = setOf(C.TRACK_TYPE_AUDIO)
        val AUDIO_AND_VIDEO = setOf(C.TRACK_TYPE_AUDIO, C.TRACK_TYPE_VIDEO)
    }
}
