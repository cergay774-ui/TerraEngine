package com.flurocup.core.engine.export

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.MediaMetadataRetriever
import android.net.Uri
import androidx.exifinterface.media.ExifInterface
import com.flurocup.core.model.MediaClip
import com.flurocup.core.model.MediaKind
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.max
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Grabs the full-quality frame of the original file at a timeline position. */
@Singleton
class FrameExporter @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    /** The frame under [timelineUs], or null if there is no clip there or it can't be read. */
    suspend fun frameAt(clips: List<MediaClip>, timelineUs: Long): Bitmap? = withContext(Dispatchers.IO) {
        val clip = clips.firstOrNull { timelineUs >= it.startUs && timelineUs < it.endUs } ?: clips.lastOrNull()
            ?: return@withContext null
        runCatching {
            if (clip.source.kind == MediaKind.IMAGE) {
                decodeImage(Uri.parse(clip.source.uri))
            } else {
                val offsetUs = (timelineUs - clip.startUs).coerceIn(0L, clip.durationUs)
                val sourceUs = clip.trimStartUs + (offsetUs * clip.speed).toLong()
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(context, Uri.parse(clip.source.uri))
                    retriever.getFrameAtTime(sourceUs, MediaMetadataRetriever.OPTION_CLOSEST)
                } finally {
                    runCatching { retriever.release() }
                }
            }
        }.getOrNull()
    }

    private fun decodeImage(uri: Uri): Bitmap? {
        val resolver = context.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / sample > MAX_IMAGE_SIDE) sample *= 2
        val bitmap = resolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
        } ?: return null
        val rotation = runCatching { resolver.openInputStream(uri)?.use { ExifInterface(it).rotationDegrees } ?: 0 }.getOrDefault(0)
        if (rotation == 0) return bitmap
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, Matrix().apply { postRotate(rotation.toFloat()) }, true)
    }

    private companion object {
        const val MAX_IMAGE_SIDE = 8192
    }
}
