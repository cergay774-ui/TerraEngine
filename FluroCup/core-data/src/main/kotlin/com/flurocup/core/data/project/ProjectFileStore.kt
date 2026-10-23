package com.flurocup.core.data.project

import android.content.Context
import android.graphics.Bitmap
import com.flurocup.core.model.Project
import com.flurocup.core.model.projectFromJson
import com.flurocup.core.model.toJson
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.io.IOException
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Project files in internal storage: `files/projects/<id>/project.json`, plus the project's
 * thumbnail and cached data next to it. Writes go to a temporary file first and are then renamed,
 * so a crash mid-save never leaves a half-written project.
 */
@Singleton
class ProjectFileStore @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val root = File(context.filesDir, "projects")

    fun projectDir(id: String): File = File(root, id)

    fun thumbnailFile(id: String): File = File(projectDir(id), THUMBNAIL_NAME)

    suspend fun write(project: Project): Unit = withContext(Dispatchers.IO) {
        val dir = projectDir(project.id)
        if (!dir.isDirectory && !dir.mkdirs()) throw IOException("Cannot create $dir")
        val target = File(dir, PROJECT_FILE_NAME)
        val temp = File(dir, "$PROJECT_FILE_NAME.tmp")
        temp.writeText(project.toJson())
        if (!temp.renameTo(target)) {
            target.delete()
            if (!temp.renameTo(target)) throw IOException("Cannot save $target")
        }
    }

    /** Saves the frame shown on the project's card. */
    suspend fun writeThumbnail(id: String, bitmap: Bitmap): Unit = withContext(Dispatchers.IO) {
        val dir = projectDir(id)
        if (!dir.isDirectory && !dir.mkdirs()) throw IOException("Cannot create $dir")
        val temp = File(dir, "$THUMBNAIL_NAME.tmp")
        temp.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 88, it) }
        val target = thumbnailFile(id)
        if (!temp.renameTo(target)) {
            target.delete()
            temp.renameTo(target)
        }
    }

    /** Returns null if the project has no file or the file cannot be read. */
    suspend fun read(id: String): Project? = withContext(Dispatchers.IO) {
        val file = File(projectDir(id), PROJECT_FILE_NAME)
        if (!file.isFile) return@withContext null
        runCatching { projectFromJson(file.readText()) }.getOrNull()
    }

    suspend fun copy(fromId: String, toId: String): Unit = withContext(Dispatchers.IO) {
        val from = projectDir(fromId)
        if (from.isDirectory) from.copyRecursively(projectDir(toId), overwrite = true)
    }

    suspend fun delete(id: String): Unit = withContext(Dispatchers.IO) {
        projectDir(id).deleteRecursively()
    }

    private companion object {
        const val PROJECT_FILE_NAME = "project.json"
        const val THUMBNAIL_NAME = "thumbnail.jpg"
    }
}
