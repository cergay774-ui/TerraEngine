package com.flurocup.feature.editor

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.Redo
import androidx.compose.material.icons.automirrored.rounded.Undo
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.AspectRatio
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.ContentCut
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material.icons.rounded.Fullscreen
import androidx.compose.material.icons.rounded.FullscreenExit
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.SwapHoriz
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.media3.common.Player
import com.flurocup.core.engine.media.MediaImportException
import com.flurocup.core.engine.media.MediaPermissions
import com.flurocup.core.model.formatDuration
import com.flurocup.core.ui.components.FluroLogoMark
import com.flurocup.core.ui.components.GradientButton
import com.flurocup.core.ui.components.GradientIconSurface
import com.flurocup.feature.editor.timeline.FilmstripLoader
import com.flurocup.feature.editor.timeline.Timeline
import com.flurocup.feature.editor.timeline.TimelineState

/** The editor: preview on top, the timeline in the middle, tools for the current selection below. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditorScreen(
    onBack: () -> Unit,
    onExport: (positionUs: Long) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: EditorViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val isPlaying by viewModel.preview.isPlaying.collectAsStateWithLifecycle()
    val player by viewModel.preview.player.collectAsStateWithLifecycle()
    val previewError by viewModel.preview.error.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }
    val context = LocalContext.current
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()

    val timeline = remember {
        with(density) { TimelineState(56.dp.toPx(), minPxPerSecond = 6.dp.toPx(), maxPxPerSecond = 900.dp.toPx()) }
    }
    LaunchedEffect(state.durationUs) {
        timeline.durationUs = state.durationUs
        timeline.scrollToUs(timeline.positionUs)
    }
    // While playing, the timeline follows the player frame by frame.
    LaunchedEffect(isPlaying) {
        if (isPlaying) {
            while (true) {
                withFrameNanos { }
                timeline.scrollToUs(viewModel.positionUs)
            }
        }
    }
    val frames = remember(viewModel) { FilmstripLoader(scope) { key -> viewModel.frame(key)?.asImageBitmap() } }

    val addPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia()) { uris ->
        if (uris.isNotEmpty()) {
            MediaPermissions.persist(context, uris)
            viewModel.import(uris)
        }
    }
    val replacePicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) {
            MediaPermissions.persist(context, listOf(uri))
            viewModel.replaceSelected(uri)
        }
    }
    val mediaRequest = PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo)
    val pickMedia = { addPicker.launch(mediaRequest) }

    var fullscreen by rememberSaveable { mutableStateOf(false) }
    var showFormat by remember { mutableStateOf(false) }
    BackHandler(enabled = fullscreen) { fullscreen = false }

    // Stop playback when the app goes to the background.
    LifecycleEventEffect(Lifecycle.Event.ON_PAUSE) { viewModel.pause() }

    val reasonTexts = mapOf(
        MediaImportException.Reason.UNSUPPORTED_TYPE to stringResource(R.string.editor_reason_unsupported),
        MediaImportException.Reason.NO_VIDEO_TRACK to stringResource(R.string.editor_reason_no_video),
        MediaImportException.Reason.UNREADABLE to stringResource(R.string.editor_reason_unreadable),
        MediaImportException.Reason.CORRUPT to stringResource(R.string.editor_reason_corrupt),
    )
    val unknownFile = stringResource(R.string.editor_unknown_file)
    LaunchedEffect(viewModel) {
        viewModel.messages.collect { message ->
            val text = when (message) {
                is EditorMessage.ImportFailed -> {
                    val first = message.failures.first()
                    val name = first.displayName ?: unknownFile
                    val reason = reasonTexts.getValue(first.reason)
                    if (message.failures.size == 1) {
                        context.getString(R.string.editor_import_failed_one, name, reason)
                    } else {
                        context.getString(R.string.editor_import_failed_many, message.failures.size, name, reason)
                    }
                }
                EditorMessage.CannotSplit -> context.getString(R.string.editor_cannot_split)
            }
            snackbar.showSnackbar(text)
        }
    }
    val previewErrorText = stringResource(R.string.editor_preview_error)
    LaunchedEffect(previewError) {
        if (previewError != null) snackbar.showSnackbar(previewErrorText)
    }

    if (fullscreen) {
        FullscreenPreview(
            player = player,
            aspectRatio = state.previewAspect,
            timeline = timeline,
            isPlaying = isPlaying,
            onTogglePlay = viewModel::togglePlay,
            onExit = { fullscreen = false },
        )
        return
    }

    Scaffold(
        modifier = modifier,
        containerColor = MaterialTheme.colorScheme.background,
        snackbarHost = { SnackbarHost(snackbar) },
        topBar = {
            CenterAlignedTopAppBar(
                title = {
                    Text(
                        text = state.project?.name.orEmpty(),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = stringResource(R.string.editor_back))
                    }
                },
                actions = {
                    IconButton(onClick = viewModel::undo, enabled = state.canUndo) {
                        Icon(Icons.AutoMirrored.Rounded.Undo, contentDescription = stringResource(R.string.editor_undo))
                    }
                    IconButton(onClick = viewModel::redo, enabled = state.canRedo) {
                        Icon(Icons.AutoMirrored.Rounded.Redo, contentDescription = stringResource(R.string.editor_redo))
                    }
                    PreviewSettingsMenu(source = state.previewSource, onSourceChange = viewModel::setPreviewSource)
                    GradientButton(
                        onClick = {
                            viewModel.pause()
                            onExport(timeline.positionUs)
                        },
                        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp),
                        modifier = Modifier.padding(end = 8.dp),
                    ) {
                        Text(stringResource(R.string.editor_export))
                    }
                },
                colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
    ) { padding ->
        Box(
            Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            when {
                state.loading -> CircularProgressIndicator(Modifier.align(Alignment.Center))
                state.notFound -> Message(stringResource(R.string.editor_not_found))
                else -> Column(Modifier.fillMaxSize()) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f)
                            .padding(horizontal = 16.dp, vertical = 4.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (state.clips.isEmpty() && state.importing == null) {
                            EmptyEditor(pickMedia)
                        } else {
                            PreviewSurface(player = player, aspectRatio = state.previewAspect)
                        }
                    }
                    PlaybackRow(
                        timeline = timeline,
                        isPlaying = isPlaying,
                        onTogglePlay = viewModel::togglePlay,
                        endIcon = Icons.Rounded.Fullscreen,
                        endDescription = stringResource(R.string.editor_fullscreen),
                        onEnd = { fullscreen = true },
                        contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    ImportProgressBar(state.importing)
                    Timeline(
                        state = timeline,
                        clips = state.clips,
                        selectedClipId = state.selectedClipId,
                        frames = frames,
                        onScrubStart = viewModel::pause,
                        onScrub = { viewModel.seekTo(it) },
                        onScrubEnd = { viewModel.seekTo(it, final = true) },
                        onSelect = viewModel::select,
                        onTrim = viewModel::trim,
                        onMove = viewModel::move,
                        onAdd = pickMedia,
                    )
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .height(22.dp)
                            .padding(horizontal = 16.dp),
                    ) {
                        val selected = state.selectedClip
                        Text(
                            text = if (selected != null) clipInfoLine(selected) else stringResource(R.string.editor_timeline_hint),
                            style = MaterialTheme.typography.labelSmall,
                            color = if (selected != null) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                    ToolPanel(
                        panelKey = state.selectedClipId != null,
                        tools = if (state.selectedClipId != null) {
                            listOf(
                                EditorTool(Icons.Rounded.ContentCut, stringResource(R.string.editor_tool_split)) { viewModel.split(timeline.positionUs) },
                                EditorTool(Icons.Rounded.ContentCopy, stringResource(R.string.editor_tool_duplicate)) { viewModel.duplicateSelected() },
                                EditorTool(Icons.Rounded.SwapHoriz, stringResource(R.string.editor_tool_replace)) { replacePicker.launch(mediaRequest) },
                                EditorTool(Icons.Rounded.DeleteOutline, stringResource(R.string.editor_tool_delete), destructive = true) {
                                    viewModel.deleteSelected()
                                },
                            )
                        } else {
                            listOf(
                                EditorTool(Icons.Rounded.Add, stringResource(R.string.editor_tool_add), onClick = pickMedia),
                                EditorTool(Icons.Rounded.ContentCut, stringResource(R.string.editor_tool_split), enabled = state.clips.isNotEmpty()) {
                                    viewModel.split(timeline.positionUs)
                                },
                                EditorTool(Icons.Rounded.AspectRatio, stringResource(R.string.editor_tool_format)) { showFormat = true },
                            )
                        },
                        modifier = Modifier
                            .navigationBarsPadding()
                            .padding(bottom = 4.dp),
                    )
                }
            }
        }
    }

    if (showFormat) {
        ModalBottomSheet(
            onDismissRequest = { showFormat = false },
            containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
        ) {
            Column(
                Modifier
                    .navigationBarsPadding()
                    .padding(bottom = 20.dp),
            ) {
                Text(
                    text = stringResource(R.string.editor_format_title),
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
                )
                AspectRatioRow(selected = state.project?.settings?.aspectRatio, onSelect = viewModel::setAspectRatio)
            }
        }
    }
}

/** Time on the left, play in the middle, one action (fullscreen on or off) on the right. */
@Composable
private fun PlaybackRow(
    timeline: TimelineState,
    isPlaying: Boolean,
    onTogglePlay: () -> Unit,
    endIcon: ImageVector,
    endDescription: String,
    onEnd: () -> Unit,
    contentColor: Color,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.weight(1f)) { TimeLabel(timeline, contentColor) }
        GradientIconSurface(onClick = onTogglePlay, modifier = Modifier.size(48.dp)) {
            Icon(
                imageVector = if (isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                contentDescription = stringResource(if (isPlaying) R.string.editor_pause else R.string.editor_play),
                modifier = Modifier.size(28.dp),
            )
        }
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) {
            IconButton(onClick = onEnd) {
                Icon(endIcon, contentDescription = endDescription, tint = contentColor)
            }
        }
    }
}

/** Reads the playhead on its own, so only this text recomposes every frame. */
@Composable
private fun TimeLabel(timeline: TimelineState, color: Color) {
    Text(
        text = "${formatDuration(timeline.positionUs)} / ${formatDuration(timeline.durationUs)}",
        style = MaterialTheme.typography.labelLarge,
        color = color,
    )
}

@Composable
private fun FullscreenPreview(
    player: Player?,
    aspectRatio: Float,
    timeline: TimelineState,
    isPlaying: Boolean,
    onTogglePlay: () -> Unit,
    onExit: () -> Unit,
) {
    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .systemBarsPadding(),
    ) {
        PreviewSurface(player = player, aspectRatio = aspectRatio, modifier = Modifier.align(Alignment.Center))
        PlaybackRow(
            timeline = timeline,
            isPlaying = isPlaying,
            onTogglePlay = onTogglePlay,
            endIcon = Icons.Rounded.FullscreenExit,
            endDescription = stringResource(R.string.editor_exit_fullscreen),
            onEnd = onExit,
            contentColor = Color.White,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 8.dp),
        )
    }
}

@Composable
private fun ImportProgressBar(progress: ImportProgress?) {
    AnimatedVisibility(
        visible = progress != null,
        enter = expandVertically() + fadeIn(),
        exit = shrinkVertically() + fadeOut(),
    ) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) {
            if (progress != null) {
                Text(
                    text = stringResource(R.string.editor_importing, progress.done, progress.total),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(4.dp))
                LinearProgressIndicator(
                    progress = { if (progress.total == 0) 0f else progress.done.toFloat() / progress.total },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

@Composable
private fun EmptyEditor(onAddMedia: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        FluroLogoMark(size = 72.dp, glow = 0.5f)
        Spacer(Modifier.height(16.dp))
        Text(stringResource(R.string.editor_empty_title), style = MaterialTheme.typography.titleLarge)
        Spacer(Modifier.height(6.dp))
        Text(
            stringResource(R.string.editor_empty_text),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(20.dp))
        GradientButton(onClick = onAddMedia) { Text(stringResource(R.string.editor_add_media)) }
    }
}

@Composable
private fun PreviewSettingsMenu(source: PreviewSource, onSourceChange: (PreviewSource) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { open = true }) {
            Icon(Icons.Rounded.Tune, contentDescription = stringResource(R.string.editor_preview_settings))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            listOf(
                Triple(PreviewSource.PROXY, R.string.editor_preview_proxy, R.string.editor_preview_proxy_hint),
                Triple(PreviewSource.ORIGINAL, R.string.editor_preview_original, R.string.editor_preview_original_hint),
            ).forEach { (option, title, hint) ->
                DropdownMenuItem(
                    text = {
                        Column {
                            Text(stringResource(title))
                            Text(
                                stringResource(hint),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    },
                    leadingIcon = {
                        if (option == source) {
                            Icon(Icons.Rounded.Check, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                        } else {
                            Spacer(Modifier.width(24.dp))
                        }
                    },
                    onClick = {
                        onSourceChange(option)
                        open = false
                    },
                )
            }
        }
    }
}

@Composable
private fun Message(title: String) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        FluroLogoMark(size = 72.dp, glow = 0.5f)
        Spacer(Modifier.height(20.dp))
        Text(title, style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
    }
}
