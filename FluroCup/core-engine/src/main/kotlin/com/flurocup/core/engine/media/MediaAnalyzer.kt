package com.flurocup.core.engine.media

import android.content.Context
import android.graphics.BitmapFactory
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import androidx.exifinterface.media.ExifInterface
import com.flurocup.core.model.FrameRateEstimator
import com.flurocup.core.model.HdrType
import com.flurocup.core.model.MediaInfo
import com.flurocup.core.model.MediaKind
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** A file that was read successfully on import. */
data class AnalyzedMedia(
    val uri: Uri,
    val kind: MediaKind,
    val info: MediaInfo,
    val displayName: String?,
)

/** Why a file could not be imported; the UI turns [reason] into a readable message. */
class MediaImportException(
    val reason: Reason,
    val displayName: String?,
    cause: Throwable? = null,
) : Exception("${reason.name}: $displayName", cause) {
    enum class Reason { UNSUPPORTED_TYPE, NO_VIDEO_TRACK, UNREADABLE, CORRUPT }
}

/**
 * Reads what the editor needs to know about a picked file: size, rotation, frame rate (including
 * variable rate), bitrate, codecs, HDR format, duration, audio tracks and whether the device can
 * decode it in real time. Only the container is read; nothing is decoded, so this is quick.
 */
@Singleton
class MediaAnalyzer @Inject constructor(
    @ApplicationContext private val context: Context,
    private val codecSupport: CodecSupport,
) {

    suspend fun analyze(uri: Uri): AnalyzedMedia = withContext(Dispatchers.IO) {
        val name = displayName(uri)
        val type = runCatching { context.contentResolver.getType(uri) }.getOrNull().orEmpty()
        try {
            when {
                type.startsWith("image/") -> AnalyzedMedia(uri, MediaKind.IMAGE, analyzeImage(uri, name), name)
                type.startsWith("video/") || type.isEmpty() -> AnalyzedMedia(uri, MediaKind.VIDEO, analyzeVideo(uri, name), name)
                type.startsWith("audio/") -> AnalyzedMedia(uri, MediaKind.AUDIO, analyzeAudio(uri, name), name)
                else -> throw MediaImportException(MediaImportException.Reason.UNSUPPORTED_TYPE, name)
            }
        } catch (e: MediaImportException) {
            throw e
        } catch (e: SecurityException) {
            throw MediaImportException(MediaImportException.Reason.UNREADABLE, name, e)
        } catch (e: Exception) {
            throw MediaImportException(MediaImportException.Reason.CORRUPT, name, e)
        }
    }

    private fun analyzeVideo(uri: Uri, name: String?): MediaInfo {
        val extractor = MediaExtractor()
        val retriever = MediaMetadataRetriever()
        try {
            try {
                extractor.setDataSource(context, uri, null)
            } catch (e: Exception) {
                throw MediaImportException(MediaImportException.Reason.CORRUPT, name, e)
            }
            runCatching { retriever.setDataSource(context, uri) }

            var videoIndex = -1
            var video: MediaFormat? = null
            var audioCount = 0
            var audioMime: String? = null
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                when {
                    mime.startsWith("video/") && videoIndex < 0 -> {
                        videoIndex = i
                        video = format
                    }
                    mime.startsWith("audio/") -> {
                        audioCount++
                        if (audioMime == null) audioMime = mime
                    }
                }
            }
            val format = video ?: throw MediaImportException(MediaImportException.Reason.NO_VIDEO_TRACK, name)
            val mime = format.getString(MediaFormat.KEY_MIME)!!

            val width = format.intOrNull(MediaFormat.KEY_WIDTH) ?: retriever.int(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH) ?: 0
            val height = format.intOrNull(MediaFormat.KEY_HEIGHT) ?: retriever.int(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT) ?: 0
            if (width <= 0 || height <= 0) throw MediaImportException(MediaImportException.Reason.CORRUPT, name)
            val rotation = (format.intOrNull(MediaFormat.KEY_ROTATION)
                ?: retriever.int(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION) ?: 0).let { ((it % 360) + 360) % 360 }
            val durationUs = format.longOrNull(MediaFormat.KEY_DURATION)
                ?: retriever.long(MediaMetadataRetriever.METADATA_KEY_DURATION)?.times(1000) ?: 0L
            val bitrate = format.intOrNull(MediaFormat.KEY_BIT_RATE)
                ?: retriever.int(MediaMetadataRetriever.METADATA_KEY_BITRATE) ?: 0

            extractor.selectTrack(videoIndex)
            val timestamps = ArrayList<Long>(TIMESTAMP_SAMPLES)
            while (timestamps.size < TIMESTAMP_SAMPLES) {
                val time = extractor.sampleTime
                if (time < 0) break
                timestamps += time
                if (!extractor.advance()) break
            }
            val estimate = FrameRateEstimator.estimate(timestamps)
            val declaredFps = format.floatOrNull(MediaFormat.KEY_FRAME_RATE)?.takeIf { it > 0f }
            val frameRate = estimate?.fps ?: declaredFps ?: frameRateFromCount(retriever, durationUs) ?: 30f

            return MediaInfo(
                width = width,
                height = height,
                rotationDegrees = rotation,
                frameRate = frameRate,
                isVariableFrameRate = estimate?.isVariable ?: false,
                bitrate = bitrate,
                videoMimeType = mime,
                audioMimeType = audioMime,
                hdr = hdrType(mime, format, retriever),
                durationUs = durationUs,
                audioTrackCount = audioCount,
                canDecodeInRealTime = codecSupport.canDecodeInRealTime(mime, width, height, frameRate, format),
            )
        } finally {
            extractor.release()
            runCatching { retriever.release() }
        }
    }

    private fun analyzeImage(uri: Uri, name: String?): MediaInfo {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
            ?: throw MediaImportException(MediaImportException.Reason.UNREADABLE, name)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) throw MediaImportException(MediaImportException.Reason.CORRUPT, name)
        val rotation = runCatching {
            context.contentResolver.openInputStream(uri)?.use { ExifInterface(it).rotationDegrees } ?: 0
        }.getOrDefault(0)
        return MediaInfo(
            width = bounds.outWidth,
            height = bounds.outHeight,
            rotationDegrees = rotation,
            durationUs = DEFAULT_IMAGE_DURATION_US,
        )
    }

    private fun analyzeAudio(uri: Uri, name: String?): MediaInfo {
        val retriever = MediaMetadataRetriever()
        try {
            try {
                retriever.setDataSource(context, uri)
            } catch (e: Exception) {
                throw MediaImportException(MediaImportException.Reason.CORRUPT, name, e)
            }
            return MediaInfo(
                width = 0,
                height = 0,
                bitrate = retriever.int(MediaMetadataRetriever.METADATA_KEY_BITRATE) ?: 0,
                audioMimeType = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE),
                durationUs = (retriever.long(MediaMetadataRetriever.METADATA_KEY_DURATION) ?: 0L) * 1000,
                audioTrackCount = 1,
            )
        } finally {
            runCatching { retriever.release() }
        }
    }

    private fun hdrType(mime: String, format: MediaFormat, retriever: MediaMetadataRetriever): HdrType {
        if (mime == MediaFormat.MIMETYPE_VIDEO_DOLBY_VISION) return HdrType.DOLBY_VISION
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && mime == MediaFormat.MIMETYPE_VIDEO_HEVC &&
            format.intOrNull(MediaFormat.KEY_PROFILE) == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10Plus
        ) {
            return HdrType.HDR10_PLUS
        }
        val transfer = format.intOrNull(MediaFormat.KEY_COLOR_TRANSFER)
            ?: if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                retriever.int(MediaMetadataRetriever.METADATA_KEY_COLOR_TRANSFER)
            } else {
                null
            }
        return when (transfer) {
            MediaFormat.COLOR_TRANSFER_ST2084 -> HdrType.HDR10
            MediaFormat.COLOR_TRANSFER_HLG -> HdrType.HLG
            else -> HdrType.NONE
        }
    }

    private fun frameRateFromCount(retriever: MediaMetadataRetriever, durationUs: Long): Float? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || durationUs <= 0) return null
        val frames = retriever.int(MediaMetadataRetriever.METADATA_KEY_VIDEO_FRAME_COUNT) ?: return null
        return FrameRateEstimator.snap((frames * 1_000_000.0 / durationUs).toFloat())
    }

    private fun displayName(uri: Uri): String? = runCatching {
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }
    }.getOrNull() ?: uri.lastPathSegment

    companion object {
        /** How long a photo stays on screen when it is added. */
        const val DEFAULT_IMAGE_DURATION_US = 3_000_000L
        private const val TIMESTAMP_SAMPLES = 240
    }
}

private fun MediaFormat.intOrNull(key: String): Int? =
    if (!containsKey(key)) null else runCatching { getInteger(key) }.getOrElse { runCatching { getFloat(key).toInt() }.getOrNull() }

private fun MediaFormat.longOrNull(key: String): Long? =
    if (!containsKey(key)) null else runCatching { getLong(key) }.getOrElse { runCatching { getInteger(key).toLong() }.getOrNull() }

/** Frame rate is stored as an int by some muxers and a float by others. */
private fun MediaFormat.floatOrNull(key: String): Float? =
    if (!containsKey(key)) null else runCatching { getFloat(key) }.getOrElse { runCatching { getInteger(key).toFloat() }.getOrNull() }

private fun MediaMetadataRetriever.int(key: Int): Int? = runCatching { extractMetadata(key)?.toIntOrNull() }.getOrNull()

private fun MediaMetadataRetriever.long(key: Int): Long? = runCatching { extractMetadata(key)?.toLongOrNull() }.getOrNull()
