package com.flurocup.core.engine.preview

import android.content.Context
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** One clip of the main track as the preview plays it. */
data class PreviewClip(
    val id: String,
    val uri: String,
    val isImage: Boolean,
    val trimStartUs: Long,
    val trimEndUs: Long,
) {
    val durationUs: Long get() = trimEndUs - trimStartUs
}

/**
 * Basic preview of the main track as an ExoPlayer playlist. Stage 3 replaces it with Media3
 * CompositionPlayer, which also renders overlays and effects. Must be used on the main thread.
 */
@OptIn(UnstableApi::class)
class PreviewPlayer(context: Context) {

    val player: ExoPlayer = ExoPlayer.Builder(context).build()

    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying.asStateFlow()

    private var clips: List<PreviewClip> = emptyList()

    init {
        player.addListener(object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                _isPlaying.value = isPlaying
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                // Back to the start after the last clip, so play works again.
                if (playbackState == Player.STATE_ENDED) {
                    player.pause()
                    player.seekTo(0, 0L)
                }
            }
        })
    }

    val durationUs: Long get() = clips.sumOf { it.durationUs }

    /** Position on the project timeline, across clips. */
    val positionUs: Long
        get() {
            val index = player.currentMediaItemIndex.coerceIn(0, (clips.size - 1).coerceAtLeast(0))
            val before = clips.take(index).sumOf { it.durationUs }
            return before + player.currentPosition.coerceAtLeast(0L) * 1000
        }

    /** Replaces the playlist and keeps the current timeline position. */
    fun setClips(newClips: List<PreviewClip>) {
        if (newClips == clips) return
        val position = positionUs
        clips = newClips
        if (newClips.isEmpty()) {
            player.clearMediaItems()
            return
        }
        val items = newClips.map { clip ->
            MediaItem.Builder()
                .setMediaId(clip.id)
                .setUri(clip.uri)
                .apply {
                    if (clip.isImage) {
                        setImageDurationMs(clip.durationUs / 1000)
                    } else {
                        setClippingConfiguration(
                            MediaItem.ClippingConfiguration.Builder()
                                .setStartPositionMs(clip.trimStartUs / 1000)
                                .setEndPositionMs(if (clip.trimEndUs > 0) clip.trimEndUs / 1000 else C.TIME_END_OF_SOURCE)
                                .build(),
                        )
                    }
                }
                .build()
        }
        val (index, offsetUs) = locate(position)
        player.setMediaItems(items, index, offsetUs / 1000)
        player.prepare()
    }

    fun togglePlay() {
        if (player.isPlaying) player.pause() else if (clips.isNotEmpty()) player.play()
    }

    fun pause() = player.pause()

    fun seekTo(timelineUs: Long) {
        val (index, offsetUs) = locate(timelineUs)
        player.seekTo(index, offsetUs / 1000)
    }

    fun release() = player.release()

    private fun locate(timelineUs: Long): Pair<Int, Long> {
        var remaining = timelineUs.coerceAtLeast(0L)
        clips.forEachIndexed { i, clip ->
            if (remaining < clip.durationUs) return i to remaining
            remaining -= clip.durationUs
        }
        return 0 to 0L
    }
}
