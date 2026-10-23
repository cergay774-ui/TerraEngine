package com.flurocup.feature.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.flurocup.core.data.project.PendingImports
import com.flurocup.core.data.project.ProjectRepository
import com.flurocup.core.model.ProjectSummary
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

sealed interface HomeUiState {
    data object Loading : HomeUiState
    data object Empty : HomeUiState
    data class Projects(val projects: List<ProjectSummary>) : HomeUiState
}

sealed interface HomeEvent {
    data class OpenProject(val id: String) : HomeEvent
}

@HiltViewModel
class HomeViewModel @Inject constructor(
    private val repository: ProjectRepository,
    private val pendingImports: PendingImports,
) : ViewModel() {

    val uiState: StateFlow<HomeUiState> = repository.observeProjects()
        .map { if (it.isEmpty()) HomeUiState.Empty else HomeUiState.Projects(it) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), HomeUiState.Loading)

    private val _events = Channel<HomeEvent>(Channel.BUFFERED)
    val events: Flow<HomeEvent> = _events.receiveAsFlow()

    private var creating = false

    /**
     * Creates "<namePrefix> N" with the picked files and opens it; the editor imports [mediaUris].
     * Ignores repeated taps while a project is being created.
     */
    fun createProject(namePrefix: String, mediaUris: List<String>) {
        if (creating) return
        creating = true
        viewModelScope.launch {
            try {
                val project = repository.createProject(repository.nextDefaultName(namePrefix))
                pendingImports.put(project.id, mediaUris)
                _events.send(HomeEvent.OpenProject(project.id))
            } finally {
                creating = false
            }
        }
    }

    fun rename(id: String, newName: String) {
        val name = newName.trim()
        if (name.isEmpty()) return
        viewModelScope.launch { repository.rename(id, name) }
    }

    fun duplicate(project: ProjectSummary, copySuffix: String) {
        viewModelScope.launch {
            repository.duplicate(project.id, repository.copyName(project.name, copySuffix))
        }
    }

    fun delete(id: String) {
        viewModelScope.launch { repository.delete(id) }
    }
}
