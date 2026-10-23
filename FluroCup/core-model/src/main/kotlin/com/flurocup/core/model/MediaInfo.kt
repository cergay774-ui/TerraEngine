package com.flurocup.core.model

import kotlinx.serialization.Serializable

/** What was read from a media file when it was imported. */
@Serializable
data class MediaInfo(
    /** Encoded size, before rotation. */
    val width: Int,
    val height: Int,
    val rotationDegrees: Int = 0,
    val frameRate: Float = 0f,
    val isVariableFrameRate: Boolean = false,
    val bitrate: Int = 0,
    val videoMimeType: String? = null,
    val audioMimeType: String? = null,
    val hdr: HdrType = HdrType.NONE,
    val durationUs: Long = 0L,
    val audioTrackCount: Int = 0,
    val canDecodeInRealTime: Boolean = true,
) {
    private val isSideways: Boolean get() = rotationDegrees % 180 != 0

    /** Size as the picture is shown, after rotation. */
    val displayWidth: Int get() = if (isSideways) height else width
    val displayHeight: Int get() = if (isSideways) width else height
}

@Serializable
enum class HdrType { NONE, HDR10, HDR10_PLUS, HLG, DOLBY_VISION }
