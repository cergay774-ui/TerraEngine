package com.flurocup.feature.export

/** Export resolutions offered to the user, by the short side of the frame. Stage 4 filters them by encoder support. */
enum class ExportResolution(val shortSide: Int, val label: String) {
    SD_480(480, "480p"),
    HD_720(720, "720p"),
    FULL_HD_1080(1080, "1080p"),
    QHD_1440(1440, "2K"),
    UHD_2160(2160, "4K"),
    UHD_4320(4320, "8K"),
}
