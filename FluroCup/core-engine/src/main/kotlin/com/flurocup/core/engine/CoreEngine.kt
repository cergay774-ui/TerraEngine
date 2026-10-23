package com.flurocup.core.engine

/**
 * Video engine of FluroCup: media analysis and proxies (stage 2), preview through Media3
 * CompositionPlayer (stage 3), export through Transformer (stage 4) and GLSL effects (stage 7).
 */
object CoreEngine {
    /** ABIs the app ships native code for. */
    val supportedAbis = listOf("arm64-v8a", "armeabi-v7a")
}
