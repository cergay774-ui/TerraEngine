package com.flurocup.core.data.db

import androidx.room.Entity
import androidx.room.PrimaryKey
import com.flurocup.core.model.Project
import com.flurocup.core.model.ProjectSummary

/** One row per project: what the project list shows. The project itself lives in its JSON file. */
@Entity(tableName = "projects")
data class ProjectEntity(
    @PrimaryKey val id: String,
    val name: String,
    val createdAt: Long,
    val modifiedAt: Long,
    val durationUs: Long,
    val sourceWidth: Int?,
    val sourceHeight: Int?,
    val sourceFrameRate: Float?,
    val thumbnailPath: String?,
)

fun ProjectEntity.toSummary() = ProjectSummary(
    id = id,
    name = name,
    createdAt = createdAt,
    modifiedAt = modifiedAt,
    durationUs = durationUs,
    sourceWidth = sourceWidth,
    sourceHeight = sourceHeight,
    sourceFrameRate = sourceFrameRate,
    thumbnailPath = thumbnailPath,
)

fun Project.toEntity(thumbnailPath: String?): ProjectEntity = toSummary(thumbnailPath).let {
    ProjectEntity(
        id = it.id,
        name = it.name,
        createdAt = it.createdAt,
        modifiedAt = it.modifiedAt,
        durationUs = it.durationUs,
        sourceWidth = it.sourceWidth,
        sourceHeight = it.sourceHeight,
        sourceFrameRate = it.sourceFrameRate,
        thumbnailPath = it.thumbnailPath,
    )
}
