package com.flurocup.core.engine.segmentation

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import androidx.exifinterface.media.ExifInterface
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.Segmentation
import com.google.mlkit.vision.segmentation.selfie.SelfieSegmenterOptions
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.nio.ByteOrder
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.max
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

/**
 * Cuts a person out of a photo with ML Kit selfie segmentation (on device, no network) and saves
 * the result as a PNG with a transparent background.
 */
@Singleton
class BackgroundRemover @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    /** Writes the cut-out of the photo at [uri] to [output]; returns its size, or null if no person was found. */
    suspend fun cutOut(uri: Uri, output: File): Pair<Int, Int>? {
        val photo = withContext(Dispatchers.IO) { decode(uri) } ?: return null
        val segmenter = Segmentation.getClient(
            SelfieSegmenterOptions.Builder().setDetectorMode(SelfieSegmenterOptions.SINGLE_IMAGE_MODE).build(),
        )
        try {
            val mask = suspendCancellableCoroutine { cont ->
                segmenter.process(InputImage.fromBitmap(photo, 0))
                    .addOnSuccessListener { cont.resume(it) }
                    .addOnFailureListener { cont.resumeWithException(it) }
            }
            return withContext(Dispatchers.Default) {
                val width = mask.width
                val height = mask.height
                val buffer = mask.buffer.order(ByteOrder.nativeOrder())
                buffer.rewind()
                val scaled = if (photo.width != width || photo.height != height) {
                    Bitmap.createScaledBitmap(photo, width, height, true)
                } else {
                    photo
                }
                val pixels = IntArray(width * height)
                scaled.getPixels(pixels, 0, width, 0, 0, width, height)
                var personPixels = 0
                for (i in pixels.indices) {
                    val confidence = buffer.float
                    val alpha = (confidence.coerceIn(0f, 1f) * 255).toInt()
                    if (alpha > 128) personPixels++
                    pixels[i] = (alpha shl 24) or (pixels[i] and 0x00FFFFFF)
                }
                if (personPixels < pixels.size / 200) return@withContext null
                val result = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                result.setPixels(pixels, 0, width, 0, 0, width, height)
                withContext(Dispatchers.IO) {
                    output.parentFile?.mkdirs()
                    output.outputStream().use { result.compress(Bitmap.CompressFormat.PNG, 100, it) }
                }
                width to height
            }
        } finally {
            segmenter.close()
        }
    }

    private fun decode(uri: Uri): Bitmap? {
        val resolver = context.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / sample > MAX_SIDE) sample *= 2
        val bitmap = resolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
        } ?: return null
        val rotation = runCatching { resolver.openInputStream(uri)?.use { ExifInterface(it).rotationDegrees } ?: 0 }.getOrDefault(0)
        val upright = if (rotation == 0) bitmap else {
            Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, Matrix().apply { postRotate(rotation.toFloat()) }, true)
        }
        return if (upright.config == Bitmap.Config.ARGB_8888) upright else upright.copy(Bitmap.Config.ARGB_8888, false)
    }

    private companion object {
        const val MAX_SIDE = 2048
    }
}
