package com.flurocup.core.engine.effects

import android.content.Context
import com.flurocup.core.model.EffectCatalog
import com.flurocup.core.model.EffectDefinition
import com.flurocup.core.model.EffectParamType
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.serialization.json.Json

/**
 * The effect catalog: `assets/effects/catalog.json` describes each effect and its parameters,
 * `assets/effects/shaders/<id>.glsl` holds its GLSL (a `vec4 effect(vec2 uv)` function), and
 * `assets/effects/common.glsl` shared helpers. A new effect is one entry and one shader file.
 */
@Singleton
class EffectLibrary @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    val catalog: EffectCatalog by lazy {
        val text = context.assets.open(CATALOG).bufferedReader().use { it.readText() }
        Json { ignoreUnknownKeys = true }.decodeFromString(EffectCatalog.serializer(), text)
    }

    private val common: String by lazy { read(COMMON) }
    private val shaders = ConcurrentHashMap<String, String>()

    fun definition(id: String): EffectDefinition? = catalog.definition(id)

    /** The full fragment shader for [definition]: shared header, its parameter uniforms, helpers and its code. */
    fun fragmentShader(definition: EffectDefinition): String = shaders.getOrPut(definition.id) {
        buildString {
            append(HEADER)
            definition.params.forEach { param ->
                val type = if (param.type == EffectParamType.COLOR) "vec3" else "float"
                append("uniform ").append(type).append(' ').append(EffectCatalog.uniformName(param.id)).append(";\n")
            }
            append(common).append('\n')
            append(read("$SHADERS/${definition.shaderId}.glsl")).append('\n')
            append(MAIN)
        }
    }

    private fun read(path: String) = context.assets.open(path).bufferedReader().use { it.readText() }

    companion object {
        const val CATALOG = "effects/catalog.json"
        const val COMMON = "effects/common.glsl"
        const val SHADERS = "effects/shaders"

        /** Declarations every effect shader can use. */
        const val HEADER = """precision highp float;
uniform sampler2D uTexSampler;
varying vec2 vTexSamplingCoord;
uniform vec2 uSize;
uniform float uTimeSec;
uniform float uTime;
uniform float uProgress;
uniform float uActive;
"""

        /** Outside its time range an effect passes the frame through untouched. */
        const val MAIN = """
void main() {
  if (uActive < 0.5) {
    gl_FragColor = texture2D(uTexSampler, vTexSamplingCoord);
  } else {
    gl_FragColor = effect(vTexSamplingCoord);
  }
}
"""
    }
}
