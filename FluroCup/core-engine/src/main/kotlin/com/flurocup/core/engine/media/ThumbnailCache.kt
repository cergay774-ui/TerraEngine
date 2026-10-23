package com.flurocup.core.engine.media

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.util.LruCache
import androidx.exifinterface.media.ExifInterface
import com.flurocup.core.model.MediaKind
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.security.MessageDigest
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.max
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext

/**
 * Small frames for clip tiles and project cards. Frames are made once, kept in memory and as JPEGs
 * in internal storage, so scrolling never decodes video twice.
 */
@Singleton
class ThumbnailCache @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val dir = File(context.noBackupFilesDir, "thumbnails")
    private val memory = object : LruCache<String, Bitmap>(MEMORY_BYTES) {
        override fun sizeOf(key: String, value: Bitmap) = value.byteCount
    }
    /** Video decoders are a shared, limited resource; don't open many at once. */
    private val decoders = Semaphore(2)

    /** A frame at [timeUs] whose longer side is at most [maxSizePx], or null if none can be made. */
    suspend fun thumbnail(uri: Uri, kind: MediaKind, timeUs: Long = 0L, maxSizePx: Int = 320): Bitmap? {
        val key = key(uri, timeUs, maxSizePx)
        memory.get(key)?.let { return it }
        return withContext(Dispatchers.IO) {
            val file = File(dir, "$key.jpg")
            val cached = if (file.isFile) BitmapFactory.decodeFile(file.path) else null
            val bitmap = cached ?: decoders.withPermit { render(uri, kind, timeUs, maxSizePx) }?.also { save(it, file) }
            bitmap?.also { memory.put(key, it) }
        }
    }

    private fun render(uri: Uri, kind: MediaKind, timeUs: Long, maxSize: Int): Bitmap? = runCatching {
        when (kind) {
            MediaKind.IMAGE -> decodeImage(uri, maxSize)
            MediaKind.VIDEO -> decodeVideoFrame(uri, timeUs, maxSize)
            MediaKind.AUDIO -> null
        }
    }.getOrNull()

    private fun decodeVideoFrame(uri: Uri, timeUs: Long, maxSize: Int): Bitmap? {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(context, uri)
            val option = MediaMetadataRetriever.OPTION_CLOSEST_SYNC
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                retriever.getScaledFrameAtTime(timeUs, option, maxSize, maxSize)
            } else {
                retriever.getFrameAtTime(timeUs, option)?.let { scaleDown(it, maxSize) }
            }
        } finally {
            runCatching { retriever.release() }
        }
    }

    private fun decodeImage(uri: Uri, maxSize: Int): Bitmap? {
        val resolver = context.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxSize) sample *= 2
        val bitmap = resolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
        } ?: return null
        val rotation = runCatching { resolver.openInputStream(uri)?.use { ExifInterface(it).rotationDegrees } ?: 0 }.getOrDefault(0)
        val scaled = scaleDown(bitmap, maxSize)
        if (rotation == 0) return scaled
        return Bitmap.createBitmap(scaled, 0, 0, scaled.width, scaled.height, Matrix().apply { postRotate(rotation.toFloat()) }, true)
    }

    private fun scaleDown(bitmap: Bitmap, maxSize: Int): Bitmap {
        val longer = max(bitmap.width, bitmap.height)
        if (longer <= maxSize) return bitmap
        val scale = maxSize.toFloat() / longer
        return Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt().coerceAtLeast(1), (bitmap.height * scale).toInt().coerceAtLeast(1), true)
    }

    private fun save(bitmap: Bitmap, file: File) {
        runCatching {
            file.parentFile?.mkdirs()
            val temp = File(file.path + ".tmp")
            temp.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 85, it) }
            temp.renameTo(file)
        }
    }

    private fun key(uri: Uri, timeUs: Long, size: Int): String = sha1("$uri|$timeUs|$size")

    private companion object {
        const val MEMORY_BYTES = 24 * 1024 * 1024
    }
}

internal fun sha1(text: String): String =
    MessageDigest.getInstance("SHA-1").digest(text.toByteArray()).joinToString("") { "%02x".format(it) }
