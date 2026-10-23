package com.flurocup.feature.home

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Palette
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.flurocup.core.engine.media.MediaPermissions
import com.flurocup.core.model.ProjectSummary
import com.flurocup.core.ui.components.FluroLogoMark
import com.flurocup.core.ui.components.FluroWordmark
import com.flurocup.core.ui.components.GradientFab

/**
 * The project list. [logoModifier] is applied to the logo mark in the top bar, so the app can
 * attach the shared-element transition from the splash screen to it.
 */
@Composable
fun HomeScreen(
    onOpenProject: (projectId: String) -> Unit,
    modifier: Modifier = Modifier,
    logoModifier: Modifier = Modifier,
    viewModel: HomeViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val openProject by rememberUpdatedState(onOpenProject)
    LaunchedEffect(viewModel) {
        viewModel.events.collect { event ->
            when (event) {
                is HomeEvent.OpenProject -> openProject(event.id)
            }
        }
    }

    val defaultName = stringResource(R.string.home_default_project_name)
    val copySuffix = stringResource(R.string.home_copy_suffix)
    val context = LocalContext.current
    // A project is created only once something is picked; backing out of the picker changes nothing.
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia()) { uris ->
        if (uris.isNotEmpty()) {
            MediaPermissions.persist(context, uris)
            viewModel.createProject(defaultName, uris.map { it.toString() })
        }
    }
    HomeContent(
        uiState = uiState,
        onCreate = {
            picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo))
        },
        onOpen = { openProject(it.id) },
        onRename = viewModel::rename,
        onDuplicate = { viewModel.duplicate(it, copySuffix) },
        onDelete = { viewModel.delete(it.id) },
        modifier = modifier,
        logoModifier = logoModifier,
    )
}

@Composable
private fun HomeContent(
    uiState: HomeUiState,
    onCreate: () -> Unit,
    onOpen: (ProjectSummary) -> Unit,
    onRename: (id: String, name: String) -> Unit,
    onDuplicate: (ProjectSummary) -> Unit,
    onDelete: (ProjectSummary) -> Unit,
    modifier: Modifier = Modifier,
    logoModifier: Modifier = Modifier,
) {
    // Ids, not summaries, so a dialog survives rotation and follows renames.
    var actionsFor by rememberSaveable { mutableStateOf<String?>(null) }
    var renameFor by rememberSaveable { mutableStateOf<String?>(null) }
    var deleteFor by rememberSaveable { mutableStateOf<String?>(null) }
    var showAppearance by rememberSaveable { mutableStateOf(false) }
    if (showAppearance) AppearanceSheet(onDismiss = { showAppearance = false })
    val projects = (uiState as? HomeUiState.Projects)?.projects.orEmpty()
    fun find(id: String?) = projects.firstOrNull { it.id == id }

    Scaffold(
        modifier = modifier,
        containerColor = MaterialTheme.colorScheme.background,
        topBar = { HomeTopBar(logoModifier, onAppearance = { showAppearance = true }) },
        floatingActionButton = {
            AnimatedVisibility(
                visible = uiState is HomeUiState.Projects,
                enter = scaleIn(spring(Spring.DampingRatioMediumBouncy, Spring.StiffnessLow)) + fadeIn(),
                exit = scaleOut(spring(stiffness = Spring.StiffnessMediumLow)) + fadeOut(),
            ) {
                GradientFab(
                    icon = Icons.Rounded.Add,
                    contentDescription = stringResource(R.string.home_new_project),
                    onClick = onCreate,
                )
            }
        },
    ) { padding ->
        AnimatedContent(
            targetState = uiState,
            contentKey = { it::class },
            transitionSpec = {
                (fadeIn(spring(stiffness = Spring.StiffnessLow)) +
                    scaleIn(spring(Spring.DampingRatioLowBouncy, Spring.StiffnessLow), initialScale = 0.92f))
                    .togetherWith(fadeOut(spring(stiffness = Spring.StiffnessMedium)))
            },
            label = "homeContent",
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) { state ->
            when (state) {
                HomeUiState.Loading -> Box(Modifier.fillMaxSize())
                HomeUiState.Empty -> EmptyState(onCreate = onCreate)
                is HomeUiState.Projects -> ProjectGrid(
                    projects = state.projects,
                    onOpen = onOpen,
                    onLongPress = { actionsFor = it.id },
                )
            }
        }
    }

    find(actionsFor)?.let { project ->
        ProjectActionsSheet(
            project = project,
            onDismiss = { actionsFor = null },
            onRename = { renameFor = project.id },
            onDuplicate = { onDuplicate(project) },
            onDelete = { deleteFor = project.id },
        )
    }
    find(renameFor)?.let { project ->
        RenameDialog(
            initialName = project.name,
            onDismiss = { renameFor = null },
            onConfirm = { name ->
                onRename(project.id, name)
                renameFor = null
            },
        )
    }
    find(deleteFor)?.let { project ->
        DeleteDialog(
            projectName = project.name,
            onDismiss = { deleteFor = null },
            onConfirm = {
                onDelete(project)
                deleteFor = null
            },
        )
    }
}

@Composable
private fun HomeTopBar(logoModifier: Modifier, onAppearance: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .windowInsetsPadding(WindowInsets.statusBars)
            .padding(horizontal = 20.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        FluroLogoMark(modifier = logoModifier, size = 36.dp, glow = 0.6f)
        Spacer(Modifier.width(10.dp))
        FluroWordmark(fontSize = MaterialTheme.typography.titleLarge.fontSize)
        Spacer(Modifier.weight(1f))
        IconButton(onClick = onAppearance) {
            Icon(Icons.Rounded.Palette, contentDescription = stringResource(R.string.home_appearance))
        }
    }
}

@Composable
private fun ProjectGrid(
    projects: List<ProjectSummary>,
    onOpen: (ProjectSummary) -> Unit,
    onLongPress: (ProjectSummary) -> Unit,
) {
    LazyVerticalGrid(
        columns = GridCells.Adaptive(minSize = 156.dp),
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 112.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        item(key = "header", span = { GridItemSpan(maxLineSpan) }) {
            Row(
                modifier = Modifier.padding(horizontal = 4.dp, vertical = 4.dp),
                verticalAlignment = Alignment.Bottom,
            ) {
                Text(
                    text = stringResource(R.string.home_my_projects),
                    style = MaterialTheme.typography.headlineSmall,
                )
                Spacer(Modifier.weight(1f))
                Text(
                    text = pluralStringResource(R.plurals.home_projects_count, projects.size, projects.size),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        items(projects, key = { it.id }) { project ->
            ProjectCard(
                project = project,
                onClick = { onOpen(project) },
                onLongClick = { onLongPress(project) },
                modifier = Modifier.animateItem(
                    fadeInSpec = spring(stiffness = Spring.StiffnessMediumLow),
                    placementSpec = spring(Spring.DampingRatioLowBouncy, Spring.StiffnessMediumLow),
                    fadeOutSpec = spring(stiffness = Spring.StiffnessMedium),
                ),
            )
        }
    }
}
