package com.flurocup.core.model

import kotlinx.serialization.json.Json

/** The one JSON configuration project files are read and written with. */
val ProjectJson: Json = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
    classDiscriminator = "type"
    coerceInputValues = true
}

fun Project.toJson(): String = ProjectJson.encodeToString(Project.serializer(), this)

fun projectFromJson(json: String): Project = ProjectJson.decodeFromString(Project.serializer(), json)
