package com.flurocup.core.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * An effect placed on an effect track: it applies to the whole frame (every layer under it)
 * from [startUs] for [durationUs]. [params] holds values by parameter id; missing ones use the
 * definition's defaults.
 */
@Serializable
@SerialName("effect")
data class EffectItem(
    override val id: String,
    override val startUs: Long,
    override val durationUs: Long,
    val effectId: String,
    val params: Map<String, Float> = emptyMap(),
) : TimelineItem

/** An effect applied to one clip for its whole length. */
@Serializable
data class ClipEffect(
    val id: String,
    val effectId: String,
    val params: Map<String, Float> = emptyMap(),
)

@Serializable
enum class EffectParamType { FLOAT, COLOR }

/**
 * One adjustable value of an effect. Colours are stored as 0xRRGGBB in a Float, which holds
 * any 24-bit integer exactly.
 */
@Serializable
data class EffectParam(
    val id: String,
    val name: String,
    val type: EffectParamType = EffectParamType.FLOAT,
    val min: Float = 0f,
    val max: Float = 1f,
    val default: Float = 0.5f,
)

/**
 * An effect as described in the catalog. Its GLSL lives in a file named after [shader], or
 * after [id] when it has none of its own (a variant reuses another effect's shader with other
 * defaults).
 */
@Serializable
data class EffectDefinition(
    val id: String,
    val name: String,
    val category: String,
    val params: List<EffectParam> = emptyList(),
    val shader: String? = null,
) {
    val shaderId: String get() = shader ?: id

    /** [values] completed with defaults and kept within each parameter's range. */
    fun resolve(values: Map<String, Float>): Map<String, Float> = params.associate { p ->
        val v = values[p.id] ?: p.default
        p.id to if (p.type == EffectParamType.COLOR) v else v.coerceIn(p.min, p.max)
    }
}

@Serializable
data class EffectCategory(val id: String, val name: String)

/** The effect catalog file. */
@Serializable
data class EffectCatalog(
    val categories: List<EffectCategory>,
    val effects: List<EffectDefinition>,
) {
    private val byId by lazy { effects.associateBy { it.id } }

    fun definition(id: String): EffectDefinition? = byId[id]

    fun inCategory(categoryId: String): List<EffectDefinition> = effects.filter { it.category == categoryId }

    companion object {
        const val DEFAULT_DURATION_US = 3_000_000L

        /** The uniform an effect's shader reads a parameter from. */
        fun uniformName(paramId: String) = "u_$paramId"
    }
}
