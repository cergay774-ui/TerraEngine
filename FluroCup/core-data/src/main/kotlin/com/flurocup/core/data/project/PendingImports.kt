package com.flurocup.core.data.project

import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Files picked on the home screen for a project that the editor has not imported yet.
 * The editor takes them once when it opens the project.
 */
@Singleton
class PendingImports @Inject constructor() {
    private val pending = ConcurrentHashMap<String, List<String>>()

    fun put(projectId: String, uris: List<String>) {
        pending[projectId] = uris
    }

    fun take(projectId: String): List<String> = pending.remove(projectId).orEmpty()
}
