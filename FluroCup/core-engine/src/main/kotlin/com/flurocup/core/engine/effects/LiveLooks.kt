package com.flurocup.core.engine.effects

import com.flurocup.core.model.ClipLook
import com.flurocup.core.model.MediaClip
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicReference

/**
 * The looks the preview's effects read, one per clip. The editor writes here while a finger or a
 * slider moves, and the next rendered frame shows it; nothing is rebuilt.
 */
class LiveLooks {
    private val looks = ConcurrentHashMap<String, AtomicReference<ClipLook>>()

    /** The reference for [clip], set to its saved look. */
    fun forClip(clip: MediaClip): AtomicReference<ClipLook> =
        looks.getOrPut(clip.id) { AtomicReference(clip.look) }.also { it.set(clip.look) }

    /** Shows [look] for the clip right away, without saving it. */
    fun set(clipId: String, look: ClipLook) {
        looks.getOrPut(clipId) { AtomicReference(look) }.set(look)
    }

    fun get(clipId: String): ClipLook? = looks[clipId]?.get()

    /** Forgets clips that are no longer in the project. */
    fun retainOnly(clipIds: Set<String>) {
        looks.keys.retainAll(clipIds)
    }
}
