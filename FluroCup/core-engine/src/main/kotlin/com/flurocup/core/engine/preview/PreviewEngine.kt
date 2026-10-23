package com.flurocup.core.engine.preview

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.ExperimentalApi
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.MultipleInputVideoGraph
import androidx.media3.transformer.Composition
import androidx.media3.transformer.CompositionPlayer
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Real-time preview of the project through Media3 [CompositionPlayer]: hardware decoding at the
 * source frame rate with synced audio.
 *
 * One player is kept and given each new composition (Media3 1.9+ allows that), so edits don't
 * tear the preview down. Only switching between a plain and a layered (multi-input) project
 * needs a new player. Use from the main thread only.
 */
@OptIn(UnstableApi::class, ExperimentalApi::class)
class PreviewEngine(private val context: Context) {

    private val _player = MutableStateFlow<Player?>(null)

    /** The current player, for the preview surface. */
    val player: StateFlow<Player?> = _player.asStateFlow()

    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying.asStateFlow()

    private val _error = MutableStateFlow<PlaybackException?>(null)

    /** The last playback error, cleared when a new composition is set. */
    val error: StateFlow<PlaybackException?> = _error.asStateFlow()

    private var current: CompositionPlayer? = null
    private var currentLayered = false
    private val handler = Handler(Looper.getMainLooper())
    private var refreshPending = false

    private val listener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            _isPlaying.value = isPlaying
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            if (playbackState == Player.STATE_ENDED) current?.pause()
        }

        override fun onPlayerError(error: PlaybackException) {
            Log.w(TAG, "Preview failed", error)
            _error.value = error
        }
    }

    /** Position in the composition, which equals the project timeline. */
    val positionUs: Long get() = (current?.currentPosition ?: 0L).coerceAtLeast(0L) * 1000

    /**
     * Shows [composition] from [startUs]; null clears the preview. [layered] compositions (with
     * overlays) need the multi-input video graph.
     */
    fun setComposition(composition: Composition?, startUs: Long, layered: Boolean = false) {
        _error.value = null
        if (composition == null) {
            releasePlayer()
            return
        }
        val player = current?.takeIf { layered == currentLayered } ?: createPlayer(layered)
        player.setComposition(composition, startUs.coerceAtLeast(0L) / 1000)
        if (player.playbackState == Player.STATE_IDLE) player.prepare()
    }

    private fun createPlayer(layered: Boolean): CompositionPlayer {
        releasePlayer()
        val player = CompositionPlayer.Builder(context)
            .apply {
                if (layered) {
                    setVideoGraphFactory(MultipleInputVideoGraph.Factory())
                } else {
                    // Keeps the last frame so a look change can be redrawn without seeking.
                    experimentalSetEnableReplayableCache(true)
                }
            }
            .build()
        player.addListener(listener)
        current = player
        currentLayered = layered
        _player.value = player
        return player
    }

    private fun releasePlayer() {
        val old = current ?: return
        old.removeListener(listener)
        current = null
        _player.value = null
        _isPlaying.value = false
        old.release()
    }

    fun play() {
        val player = current ?: return
        if (player.playbackState == Player.STATE_ENDED) player.seekTo(0)
        player.play()
    }

    fun pause() {
        current?.pause()
    }

    fun togglePlay() {
        if (current?.isPlaying == true) pause() else play()
    }

    fun seekTo(timelineUs: Long) {
        current?.seekTo(timelineUs.coerceAtLeast(0L) / 1000)
    }

    /** Fast, approximate seeking while a finger drags the timeline. */
    fun setScrubbing(scrubbing: Boolean) {
        runCatching { current?.setScrubbingModeEnabled(scrubbing) }
    }

    /**
     * Shows a look changed live (position, mask, opacity) on the paused frame. The last request
     * in a burst always runs, so the frame never stays on an older value.
     */
    fun refresh() {
        if (refreshPending) return
        refreshPending = true
        handler.postDelayed(
            {
                refreshPending = false
                redrawNow()
            },
            if (currentLayered) LAYERED_REFRESH_MS else REFRESH_MS,
        )
    }

    private fun redrawNow() {
        val player = current ?: return
        if (player.isPlaying) return
        if (currentLayered) {
            // The redraw cache covers one input only; layered previews re-render by seeking.
            player.seekTo(player.currentPosition)
        } else {
            runCatching { player.experimentalRedrawLastFrame() }
                .onFailure { player.seekTo(player.currentPosition) }
        }
    }

    fun release() {
        handler.removeCallbacksAndMessages(null)
        releasePlayer()
    }

    private companion object {
        const val TAG = "PreviewEngine"
        const val REFRESH_MS = 16L
        const val LAYERED_REFRESH_MS = 40L
    }
}
