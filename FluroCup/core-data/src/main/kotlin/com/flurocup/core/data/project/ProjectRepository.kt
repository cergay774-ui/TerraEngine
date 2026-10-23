package com.flurocup.core.data.project

import android.graphics.Bitmap
import com.flurocup.core.data.db.ProjectDao
import com.flurocup.core.data.db.toEntity
import com.flurocup.core.data.db.toSummary
import com.flurocup.core.model.Project
import com.flurocup.core.model.ProjectSummary
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/** Creates, lists and stores projects. Room holds the list; each project's JSON file holds the rest. */
@Singleton
class ProjectRepository @Inject constructor(
    private val dao: ProjectDao,
    private val files: ProjectFileStore,
) {
    fun observeProjects(): Flow<List<ProjectSummary>> =
        dao.observeAll().map { rows -> rows.map { it.toSummary() } }

    suspend fun createProject(name: String): Project {
        val now = System.currentTimeMillis()
        val project = Project(id = UUID.randomUUID().toString(), name = name, createdAt = now, modifiedAt = now)
        save(project)
        return project
    }

    suspend fun load(id: String): Project? = files.read(id)

    /** Writes the project file and refreshes its row in the list. */
    suspend fun save(project: Project) {
        files.write(project)
        dao.upsert(project.toEntity(thumbnailPath = existingThumbnail(project.id)))
    }

    /** Stores the card frame and refreshes the list row so the card shows it. */
    suspend fun saveThumbnail(project: Project, bitmap: Bitmap) {
        files.writeThumbnail(project.id, bitmap)
        dao.upsert(project.toEntity(thumbnailPath = existingThumbnail(project.id)))
    }

    fun hasThumbnail(id: String): Boolean = files.thumbnailFile(id).isFile

    suspend fun rename(id: String, newName: String) {
        val project = files.read(id) ?: return
        save(project.copy(name = newName, modifiedAt = System.currentTimeMillis()))
    }

    suspend fun duplicate(id: String, newName: String): Project? {
        val original = files.read(id) ?: return null
        val now = System.currentTimeMillis()
        val copy = original.copy(id = UUID.randomUUID().toString(), name = newName, createdAt = now, modifiedAt = now)
        files.copy(original.id, copy.id)
        save(copy)
        return copy
    }

    suspend fun delete(id: String) {
        dao.delete(id)
        files.delete(id)
    }

    /**
     * The first "<prefix> N" name not taken yet, for example "Проект 3".
     */
    suspend fun nextDefaultName(prefix: String): String {
        val taken = dao.allNames().toSet()
        var n = 1
        while ("$prefix $n" in taken) n++
        return "$prefix $n"
    }

    /** "<name> (<suffix>)", numbered if that name is taken too. */
    suspend fun copyName(name: String, suffix: String): String {
        val taken = dao.allNames().toSet()
        val base = "$name ($suffix)"
        if (base !in taken) return base
        var n = 2
        while ("$name ($suffix $n)" in taken) n++
        return "$name ($suffix $n)"
    }

    private fun existingThumbnail(id: String): String? =
        files.thumbnailFile(id).takeIf { it.isFile }?.absolutePath
}
