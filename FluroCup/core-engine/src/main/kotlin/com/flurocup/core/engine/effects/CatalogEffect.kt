package com.flurocup.core.engine.effects

import com.flurocup.core.model.EffectCatalog
import com.flurocup.core.model.EffectDefinition
import com.flurocup.core.model.EffectParamType
import java.util.concurrent.atomic.AtomicReference

/**
 * One catalog effect in the render pipeline, covering [startUs] for [durationUs] on the
 * timeline; `uTime` counts seconds from the start and `uProgress` runs 0..1 over the range.
 * Parameters are read from [params] every frame, so they can be changed live.
 *
 * A track effect sees the whole frame and is switched off outside its range. A [clipEffect]
 * only ever gets its clip's frames, so it is always on; if the frame times it gets turn out
 * to be counted from the clip rather than the timeline, they are used as they are.
 */
class CatalogEffect(
    override val fragmentShader: String,
    private val definition: EffectDefinition,
    private val params: AtomicReference<Map<String, Float>>,
    private val startUs: Long,
    private val durationUs: Long,
    private val clipEffect: Boolean = false,
) : ShaderEffect() {

    override fun setUniforms(program: UniformSetter, presentationTimeUs: Long) {
        val inRange = presentationTimeUs >= startUs && presentationTimeUs - startUs < durationUs
        val local = when {
            inRange -> presentationTimeUs - startUs
            clipEffect -> presentationTimeUs.coerceIn(0L, durationUs)
            else -> -1L
        }
        val active = local >= 0
        program.float("uActive", if (active) 1f else 0f)
        if (!active) return
        program.float("uTime", local / 1_000_000f)
        program.float("uProgress", (local.toFloat() / durationUs.coerceAtLeast(1)).coerceIn(0f, 1f))
        val values = definition.resolve(params.get())
        definition.params.forEach { param ->
            val value = values.getValue(param.id)
            val name = EffectCatalog.uniformName(param.id)
            if (param.type == EffectParamType.COLOR) {
                val rgb = value.toInt()
                program.vec3(name, ((rgb shr 16) and 0xFF) / 255f, ((rgb shr 8) and 0xFF) / 255f, (rgb and 0xFF) / 255f)
            } else {
                program.float(name, value)
            }
        }
    }
}
