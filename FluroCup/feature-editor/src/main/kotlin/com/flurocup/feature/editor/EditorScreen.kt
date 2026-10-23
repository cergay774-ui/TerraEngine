package com.flurocup.feature.editor

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Check
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.flurocup.core.engine.media.MediaImportException
import com.flurocup.core.engine.media.MediaPermissions
import com.flurocup.core.ui.components.FluroLogoMark
import com.flurocup.core.ui.components.GradientButton

/** Editor, stage 2: import, preview of the main track, clip info and proxies. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditorScreen(
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    viewModel: EditorViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val isPlaying by viewModel.preview.isPlaying.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }
    val context = LocalContext.current

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia()) { uris ->
        if (uris.isNotEmpty()) {
            MediaPermissions.persist(context, uris)
            viewModel.import(uris)
        }
    }
    val pickMedia = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo)) }

    // Stop playback when the app goes to the background.
    LifecycleEventEffect(Lifecycle.Event.ON_PAUSE) { viewModel.preview.pause() }

    val reasonTexts = mapOf(
        MediaImportException.Reason.UNSUPPORTED_TYPE to stringResource(R.string.editor_reason_unsupported),
        MediaImportException.Reason.NO_VIDEO_TRACK to stringResource(R.string.editor_reason_no_video),
        MediaImportException.Reason.UNREADABLE to stringResource(R.string.editor_reason_unreadable),
        MediaImportException.Reason.CORRUPT to stringResource(R.string.editor_reason_corrupt),
    )
    val unknownFile = stringResource(R.string.editor_unknown_file)
    LaunchedEffect(viewModel) {
        viewModel.messages.collect { message ->
            when (message) {
                is EditorMessage.ImportFailed -> {
                    val first = message.failures.first()
                    val name = first.displayName ?: unknownFile
                    val reason = reasonTexts.getValue(first.reason)
                    val text = if (message.failures.size == 1) {
                        context.getString(R.string.editor_import_failed_one, name, reason)
                    } else {
                        context.getString(R.string.editor_import_failed_many, message.failures.size, name, reason)
                    }
                    snackbar.showSnackbar(text)
                }
            }
        }
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
                    PreviewSettingsMenu(
                        source = state.previewSource,
                        onSourceChange = viewModel::setPreviewSource,
                    )
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
                state.notFound -> Message(stringResource(R.string.editor_not_found), null)
                else -> EditorBody(
                    state = state,
                    isPlaying = isPlaying,
                    viewModel = viewModel,
                    onAddMedia = pickMedia,
                )
            }
        }
    }
}

@Composable
private fun EditorBody(
    state: EditorUiState,
    isPlaying: Boolean,
    viewModel: EditorViewModel,
    onAddMedia: () -> Unit,
) {
    Column(Modifier.fillMaxSize()) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .padding(horizontal = 12.dp),
            contentAlignment = Alignment.Center,
        ) {
            if (state.clips.isEmpty() && state.importing == null) {
                EmptyEditor(onAddMedia)
            } else {
                PreviewSurface(player = viewModel.preview.player, aspectRatio = state.previewAspect)
            }
        }
        PlaybackBar(
            isPlaying = isPlaying,
            preview = viewModel.preview,
            onTogglePlay = viewModel::togglePlay,
        )
        AnimatedVisibility(
            visible = state.importing != null,
            enter = expandVertically() + fadeIn(),
            exit = shrinkVertically() + fadeOut(),
        ) {
            val progress = state.importing
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
        AspectRatioRow(
            selected = state.project?.settings?.aspectRatio,
            onSelect = viewModel::setAspectRatio,
        )
        ClipStrip(
            clips = state.clips,
            loadThumbnail = viewModel::clipThumbnail,
            onAdd = onAddMedia,
            modifier = Modifier.navigationBarsPadding(),
        )
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
private fun Message(title: String, text: String?) {
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
        if (text != null) {
            Spacer(Modifier.height(8.dp))
            Text(
                text = text,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
    }
}
