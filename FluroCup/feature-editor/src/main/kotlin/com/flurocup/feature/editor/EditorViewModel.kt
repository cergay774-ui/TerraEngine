package com.flurocup.feature.editor

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.flurocup.core.data.project.ProjectRepository
import com.flurocup.core.model.Project
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface EditorUiState {
    data object Loading : EditorUiState
    data object NotFound : EditorUiState
    data class Ready(val project: Project) : EditorUiState
}

@HiltViewModel
class EditorViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val repository: ProjectRepository,
) : ViewModel() {

    /** Navigation puts the route's `projectId` argument into the saved state. */
    private val projectId: String = checkNotNull(savedStateHandle[PROJECT_ID_KEY])

    private val _uiState = MutableStateFlow<EditorUiState>(EditorUiState.Loading)
    val uiState: StateFlow<EditorUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            _uiState.value = repository.load(projectId)?.let(EditorUiState::Ready) ?: EditorUiState.NotFound
        }
    }

    companion object {
        const val PROJECT_ID_KEY = "projectId"
    }
}
