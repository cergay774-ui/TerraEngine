package com.flurocup.core.engine.preview

import android.content.Context
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.PreviewingMultipleInputVideoGraph
import androidx.media3.transformer.Composition
import androidx.media3.transformer.CompositionPlayer
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Real-time preview of the project through Media3 [CompositionPlayer], hardware decoding at the
 * source frame rate with synced audio. A CompositionPlayer plays one composition for its whole
 * life, so each timeline change builds a fresh player at the same position and releases the old
 * one. Use from the main thread only.
 */
@OptIn(UnstableApi::class)
class PreviewEngine(private val context: Context) {

    private val _player = MutableStateFlow<Player?>(null)

    /** The current player, for the preview surface; replaced after each timeline change. */
    val player: StateFlow<Player?> = _player.asStateFlow()

    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying.asStateFlow()

    private val _error = MutableStateFlow<PlaybackException?>(null)

    /** The last playback error, cleared when a new composition is set. */
    val error: StateFlow<PlaybackException?> = _error.asStateFlow()

    private var current: CompositionPlayer? = null

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
     * overlays) need Media3's multi-input video graph.
     */
    fun setComposition(composition: Composition?, startUs: Long, layered: Boolean = false) {
        val old = current
        old?.removeListener(listener)
        _isPlaying.value = false
        _error.value = null
        current = null
        if (composition != null) {
            val next = CompositionPlayer.Builder(context)
                .apply { if (layered) setPreviewingVideoGraphFactory(PreviewingMultipleInputVideoGraph.Factory()) }
                .build()
            next.addListener(listener)
            next.setComposition(composition)
            next.seekTo(startUs.coerceAtLeast(0L) / 1000)
            next.prepare()
            current = next
        }
        _player.value = current
        old?.release()
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

    /**
     * Redraws the current frame while paused, so a look changed live (position, mask, opacity)
     * shows at once. Throttled: a finger produces many changes per frame.
     */
    fun refresh() {
        val player = current ?: return
        if (player.isPlaying) return
        val now = android.os.SystemClock.uptimeMillis()
        if (now - lastRefreshAt < REFRESH_INTERVAL_MS) return
        lastRefreshAt = now
        player.seekTo(player.currentPosition)
    }

    private var lastRefreshAt = 0L

    fun release() {
        current?.removeListener(listener)
        current?.release()
        current = null
        _player.value = null
    }

    private companion object {
        const val TAG = "PreviewEngine"
        const val REFRESH_INTERVAL_MS = 33L
    }
}
