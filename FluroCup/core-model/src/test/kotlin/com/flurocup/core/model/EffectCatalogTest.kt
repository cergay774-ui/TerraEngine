package com.flurocup.core.model

import java.io.File
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Checks the catalog shipped in the engine's assets against its shader files. */
class EffectCatalogTest {

    private val dir = File("../core-engine/src/main/assets/effects")
    private val catalog = Json.decodeFromString(EffectCatalog.serializer(), File(dir, "catalog.json").readText())

    @Test
    fun everyEffectHasAShaderAndACategory() {
        val categories = catalog.categories.map { it.id }.toSet()
        assertTrue(catalog.effects.size >= 100)
        assertEquals(catalog.effects.size, catalog.effects.map { it.id }.toSet().size)
        catalog.effects.forEach { e ->
            assertTrue(e.id, e.category in categories)
            val shader = File(dir, "shaders/${e.shaderId}.glsl")
            assertTrue(e.id, shader.isFile)
            val used = Regex("""\bu_(\w+)""").findAll(shader.readText()).map { it.groupValues[1] }.toSet()
            assertTrue("${e.id} uses undeclared params", e.params.map { it.id }.containsAll(used))
        }
        assertTrue(catalog.categories.all { catalog.inCategory(it.id).isNotEmpty() })
    }

    @Test
    fun resolveFillsDefaultsAndClamps() {
        val def = catalog.definition("vhs")!!
        val values = def.resolve(mapOf("intensity" to 5f))
        assertEquals(1f, values.getValue("intensity"))
        assertEquals(def.params.first { it.id == "speed" }.default, values.getValue("speed"))
    }
}
