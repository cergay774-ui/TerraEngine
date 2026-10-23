package com.flurocup.core.engine.effects

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicReference

/**
 * Values the preview's effects read every frame, by id. The editor writes here while a slider
 * moves; the next frame shows it and nothing is rebuilt.
 */
class LiveValues<T : Any> {
    private val values = ConcurrentHashMap<String, AtomicReference<T>>()

    /** The reference for [id], set to [saved]. */
    fun forId(id: String, saved: T): AtomicReference<T> =
        values.getOrPut(id) { AtomicReference(saved) }.also { it.set(saved) }

    fun set(id: String, value: T) {
        values.getOrPut(id) { AtomicReference(value) }.set(value)
    }

    fun get(id: String): T? = values[id]?.get()

    fun retainOnly(ids: Set<String>) {
        values.keys.retainAll(ids)
    }
}
