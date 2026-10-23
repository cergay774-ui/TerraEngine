package com.flurocup.core.engine.export

import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.io.IOException
import java.io.OutputStream
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

/**
 * Puts exports in the shared gallery: videos in Movies/FluroCup, sound in Music/FluroCup and
 * frames in Pictures/FluroCup. Android 9 and older need the storage permission for this.
 */
@Singleton
class MediaStoreSaver @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    val needsStoragePermission: Boolean get() = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    suspend fun saveVideo(file: File, displayName: String): Uri =
        saveFile(file, "$displayName.mp4", "video/mp4", Kind.VIDEO)

    suspend fun saveAudio(file: File, displayName: String): Uri =
        saveFile(file, "$displayName.m4a", "audio/mp4", Kind.AUDIO)

    suspend fun saveImage(bitmap: Bitmap, displayName: String): Uri =
        save("$displayName.png", "image/png", Kind.IMAGE) { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }

    private suspend fun saveFile(file: File, name: String, mimeType: String, kind: Kind): Uri =
        save(name, mimeType, kind) { out -> file.inputStream().use { it.copyTo(out) } }

    private enum class Kind(val directory: String) {
        VIDEO(Environment.DIRECTORY_MOVIES),
        AUDIO(Environment.DIRECTORY_MUSIC),
        IMAGE(Environment.DIRECTORY_PICTURES),
    }

    private suspend fun save(name: String, mimeType: String, kind: Kind, write: (OutputStream) -> Unit): Uri =
        withContext(Dispatchers.IO) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) saveScoped(name, mimeType, kind, write) else saveLegacy(name, mimeType, kind, write)
        }

    private fun saveScoped(name: String, mimeType: String, kind: Kind, write: (OutputStream) -> Unit): Uri {
        val resolver = context.contentResolver
        val collection = when (kind) {
            Kind.VIDEO -> MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            Kind.AUDIO -> MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            Kind.IMAGE -> MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "${kind.directory}/$FOLDER")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values) ?: throw IOException("MediaStore refused $name")
        try {
            val out = resolver.openOutputStream(uri) ?: throw IOException("Cannot write $uri")
            out.use(write)
            resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
            return uri
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
    }

    @Suppress("DEPRECATION")
    private suspend fun saveLegacy(name: String, mimeType: String, kind: Kind, write: (OutputStream) -> Unit): Uri {
        val dir = File(Environment.getExternalStoragePublicDirectory(kind.directory), FOLDER)
        if (!dir.isDirectory && !dir.mkdirs()) throw IOException("Cannot create $dir")
        var target = File(dir, name)
        var n = 2
        while (target.exists()) target = File(dir, name.substringBeforeLast('.') + " ($n)." + name.substringAfterLast('.')).also { n++ }
        target.outputStream().use(write)
        return suspendCancellableCoroutine { cont ->
            MediaScannerConnection.scanFile(context, arrayOf(target.path), arrayOf(mimeType)) { _, uri ->
                if (uri != null) cont.resume(uri) else cont.resumeWith(Result.failure(IOException("Gallery did not index $target")))
            }
        }
    }

    private companion object {
        const val FOLDER = "FluroCup"
    }
}
