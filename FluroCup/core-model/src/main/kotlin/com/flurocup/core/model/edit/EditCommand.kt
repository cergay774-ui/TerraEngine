package com.flurocup.core.model.edit

import com.flurocup.core.model.AspectRatio
import com.flurocup.core.model.MediaClip
import com.flurocup.core.model.MediaSource
import com.flurocup.core.model.Project

/**
 * One undoable edit. Commands carry everything they need, including ids of clips they create, so
 * applying the same command again (redo) gives the same result.
 */
sealed interface EditCommand {
    /** The edited project, or null if the command changes nothing. */
    fun apply(project: Project): Project?

    data class AddClips(val clips: List<MediaClip>) : EditCommand {
        override fun apply(project: Project) = if (clips.isEmpty()) null else MainTrackEdits.append(project, clips)
    }

    data class Split(val clipId: String, val atUs: Long, val newClipId: String) : EditCommand {
        override fun apply(project: Project) = MainTrackEdits.split(project, clipId, atUs, newClipId)
    }

    data class Delete(val clipId: String) : EditCommand {
        override fun apply(project: Project) = MainTrackEdits.delete(project, clipId)
    }

    data class Duplicate(val clipId: String, val newClipId: String) : EditCommand {
        override fun apply(project: Project) = MainTrackEdits.duplicate(project, clipId, newClipId)
    }

    data class Move(val clipId: String, val toIndex: Int) : EditCommand {
        override fun apply(project: Project) = MainTrackEdits.move(project, clipId, toIndex)
    }

    data class Trim(val clipId: String, val trimStartUs: Long, val trimEndUs: Long) : EditCommand {
        override fun apply(project: Project) = MainTrackEdits.trim(project, clipId, trimStartUs, trimEndUs)
    }

    data class Replace(val clipId: String, val source: MediaSource) : EditCommand {
        override fun apply(project: Project) = MainTrackEdits.replace(project, clipId, source)
    }

    data class SetAspectRatio(val ratio: AspectRatio) : EditCommand {
        override fun apply(project: Project) =
            if (project.settings.aspectRatio == ratio) null
            else project.copy(settings = project.settings.copy(aspectRatio = ratio))
    }
}

/**
 * Unlimited undo/redo. Each entry keeps the command and the project before it: undo restores that
 * state exactly, redo applies the command again.
 */
class EditHistory {
    private data class Entry(val command: EditCommand, val before: Project)

    private val undoStack = ArrayDeque<Entry>()
    private val redoStack = ArrayDeque<EditCommand>()

    val canUndo: Boolean get() = undoStack.isNotEmpty()
    val canRedo: Boolean get() = redoStack.isNotEmpty()

    /** Applies [command] to [project] and records it; null if it changed nothing. */
    fun execute(project: Project, command: EditCommand): Project? {
        val result = command.apply(project) ?: return null
        undoStack.addLast(Entry(command, project))
        redoStack.clear()
        return result
    }

    /** The project as it was before the last command, or null if there is nothing to undo. */
    fun undo(): Project? {
        val entry = undoStack.removeLastOrNull() ?: return null
        redoStack.addLast(entry.command)
        return entry.before
    }

    /** Re-applies the last undone command to [project]. */
    fun redo(project: Project): Project? {
        val command = redoStack.removeLastOrNull() ?: return null
        val result = command.apply(project)
        if (result == null) {
            // The project changed in a way the command no longer fits; drop the rest of the redo chain.
            redoStack.clear()
            return null
        }
        undoStack.addLast(Entry(command, project))
        return result
    }

    fun clear() {
        undoStack.clear()
        redoStack.clear()
    }
}
