package com.flurocup.feature.export

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.AudioFile
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.ErrorOutline
import androidx.compose.material.icons.rounded.Image
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.flurocup.core.engine.export.ExportKind
import com.flurocup.core.engine.export.ExportManager
import com.flurocup.core.engine.export.ExportState
import com.flurocup.core.model.HdrType
import com.flurocup.core.model.export.BitrateMode
import com.flurocup.core.model.export.formatFileSize
import com.flurocup.core.model.formatDuration
import com.flurocup.core.ui.components.GradientButton
import com.flurocup.core.ui.theme.FluroColors
import kotlin.math.roundToInt
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExportScreen(
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    viewModel: ExportViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val export by viewModel.exportState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val snackbar = remember { SnackbarHostState() }

    // Permissions are asked right before they are needed. Either answer continues the export:
    // without notifications it simply runs silently; without storage (Android 9-) saving fails
    // with a clear message.
    val scope = rememberCoroutineScope()
    val pendingAction = remember { mutableStateOf<(() -> Unit)?>(null) }
    val storageDenied = stringResource(R.string.export_storage_denied)
    val storagePermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) pendingAction.value?.invoke() else scope.launch { snackbar.showSnackbar(storageDenied) }
        pendingAction.value = null
    }
    val notificationPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        pendingAction.value?.invoke()
        pendingAction.value = null
    }
    fun withPermissions(action: () -> Unit) {
        pendingAction.value = action
        when {
            viewModel.needsStoragePermission -> storagePermission.launch(Manifest.permission.WRITE_EXTERNAL_STORAGE)
            Build.VERSION.SDK_INT >= 33 -> notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
            else -> action()
        }
    }

    val frameSaved = stringResource(R.string.export_frame_saved)
    val frameFailed = stringResource(R.string.export_frame_failed)
    val busy = stringResource(R.string.export_busy)
    LaunchedEffect(viewModel) {
        viewModel.messages.collect { message ->
            snackbar.showSnackbar(
                when (message) {
                    ExportMessage.FrameSaved -> frameSaved
                    ExportMessage.FrameFailed -> frameFailed
                    ExportMessage.Busy -> busy
                },
            )
        }
    }

    Scaffold(
        modifier = modifier,
        containerColor = MaterialTheme.colorScheme.background,
        snackbarHost = { SnackbarHost(snackbar) },
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text(stringResource(R.string.export_title)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = stringResource(R.string.export_back))
                    }
                },
                colors = TopAppBarDefaults.centerAlignedTopAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
    ) { padding ->
        Box(
            Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            AnimatedContent(
                targetState = export,
                contentKey = { it::class },
                transitionSpec = {
                    (fadeIn(spring(stiffness = Spring.StiffnessLow)) + scaleIn(spring(Spring.DampingRatioLowBouncy), initialScale = 0.94f))
                        .togetherWith(fadeOut(spring(stiffness = Spring.StiffnessMedium)))
                },
                label = "exportState",
            ) { current ->
                when (current) {
                    is ExportState.Running -> RunningView(current, onCancel = viewModel::cancel)
                    is ExportState.Done -> DoneView(
                        state = current,
                        onShare = { share(context, current.uri, current.mimeType) },
                        onOpen = { open(context, current.uri, current.mimeType) },
                        onFinish = {
                            viewModel.clearResult()
                            onBack()
                        },
                    )
                    is ExportState.Failed -> FailedView(
                        state = current,
                        onRetry = viewModel::clearResult,
                    )
                    ExportState.Idle, is ExportState.Cancelled -> SettingsView(
                        state = state,
                        cancelled = current is ExportState.Cancelled,
                        viewModel = viewModel,
                        onExport = { withPermissions(viewModel::exportVideo) },
                        onExportAudio = { withPermissions(viewModel::exportAudio) },
                        onExportFrame = {
                            if (viewModel.needsStoragePermission) withPermissions(viewModel::exportFrame) else viewModel.exportFrame()
                        },
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SettingsView(
    state: ExportUiState,
    cancelled: Boolean,
    viewModel: ExportViewModel,
    onExport: () -> Unit,
    onExportAudio: () -> Unit,
    onExportFrame: () -> Unit,
) {
    if (state.loading) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        return
    }
    if (state.durationUs <= 0L) {
        Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
            Text(stringResource(R.string.export_nothing), style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
        }
        return
    }
    val settings = state.settings
    val (width, height) = state.outputSize
    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .navigationBarsPadding(),
    ) {
        Text(
            text = state.project?.name.orEmpty(),
            style = MaterialTheme.typography.headlineSmall,
        )
        Text(
            text = formatDuration(state.durationUs) + " · " +
                stringResource(R.string.export_output, width, height, settings.frameRate, settings.codec.label),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.primary,
        )
        if (cancelled) {
            Spacer(Modifier.height(8.dp))
            Text(stringResource(R.string.export_cancelled), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }

        Section(stringResource(R.string.export_resolution)) {
            if (state.resolutions.isEmpty()) {
                Text(stringResource(R.string.export_no_resolutions), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }
            ChipRow(state.resolutions, settings.resolution, { it.label }, viewModel::setResolution)
        }
        Section(stringResource(R.string.export_frame_rate), hint = stringResource(R.string.export_frame_rate_hint)) {
            ChipRow(state.frameRates, settings.frameRate, { "$it" }, viewModel::setFrameRate)
        }
        Section(stringResource(R.string.export_codec)) {
            ChipRow(state.codecs, settings.codec, { it.label }, viewModel::setCodec)
        }
        Section(stringResource(R.string.export_bitrate)) {
            val labels = mapOf(
                BitrateMode.AUTO to stringResource(R.string.export_bitrate_auto),
                BitrateMode.LOW to stringResource(R.string.export_bitrate_low),
                BitrateMode.RECOMMENDED to stringResource(R.string.export_bitrate_recommended),
                BitrateMode.HIGH to stringResource(R.string.export_bitrate_high),
                BitrateMode.CUSTOM to stringResource(R.string.export_bitrate_custom),
            )
            ChipRow(BitrateMode.entries, settings.bitrateMode, { labels.getValue(it) }, viewModel::setBitrateMode)
            AnimatedVisibility(
                visible = settings.bitrateMode == BitrateMode.CUSTOM,
                enter = expandVertically() + fadeIn(),
                exit = shrinkVertically() + fadeOut(),
            ) {
                Column {
                    Text(stringResource(R.string.export_bitrate_value, settings.customBitrateMbps), style = MaterialTheme.typography.labelLarge)
                    Slider(
                        value = settings.customBitrateMbps.toFloat(),
                        onValueChange = { viewModel.setCustomBitrate(it.roundToInt()) },
                        valueRange = 1f..200f,
                    )
                }
            }
        }
        if (state.sourceHdr != HdrType.NONE) {
            val hdrName = hdrLabel(state.sourceHdr)
            Section(stringResource(R.string.export_hdr)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = if (state.hdrSupported) {
                            stringResource(R.string.export_hdr_hint, hdrName)
                        } else {
                            stringResource(R.string.export_hdr_unsupported, hdrName, settings.codec.label)
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.weight(1f),
                    )
                    Spacer(Modifier.width(12.dp))
                    Switch(checked = settings.keepHdr, onCheckedChange = viewModel::setKeepHdr, enabled = state.hdrSupported)
                }
            }
        }

        Spacer(Modifier.height(20.dp))
        Text(
            text = stringResource(
                R.string.export_estimate,
                formatFileSize(state.estimatedBytes, stringResource(R.string.export_size_mb), stringResource(R.string.export_size_gb)),
            ),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(12.dp))
        GradientButton(
            onClick = { if (state.canExport) onExport() },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { Text(stringResource(R.string.export_start)) }
        }
        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(onClick = onExportFrame, modifier = Modifier.weight(1f)) {
                Icon(Icons.Rounded.Image, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text(stringResource(R.string.export_frame_png))
            }
            OutlinedButton(onClick = onExportAudio, enabled = state.hasAudio, modifier = Modifier.weight(1f)) {
                Icon(Icons.Rounded.AudioFile, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text(stringResource(R.string.export_audio_only))
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun Section(title: String, hint: String? = null, content: @Composable () -> Unit) {
    Spacer(Modifier.height(20.dp))
    Text(title, style = MaterialTheme.typography.titleMedium)
    if (hint != null) {
        Text(hint, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    Spacer(Modifier.height(8.dp))
    content()
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun <T> ChipRow(options: List<T>, selected: T, label: (T) -> String, onSelect: (T) -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        options.forEach { option ->
            FilterChip(
                selected = option == selected,
                onClick = { onSelect(option) },
                label = { Text(label(option)) },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.18f),
                    selectedLabelColor = MaterialTheme.colorScheme.primary,
                ),
            )
        }
    }
}

@Composable
private fun RunningView(state: ExportState.Running, onCancel: () -> Unit) {
    val progress by animateFloatAsState(state.progress ?: 0f, spring(stiffness = Spring.StiffnessLow), label = "exportProgress")
    CenteredColumn {
        Box(contentAlignment = Alignment.Center) {
            if (state.progress == null) {
                CircularProgressIndicator(modifier = Modifier.size(140.dp), strokeWidth = 8.dp, strokeCap = StrokeCap.Round)
            } else {
                CircularProgressIndicator(
                    progress = { progress },
                    modifier = Modifier.size(140.dp),
                    strokeWidth = 8.dp,
                    strokeCap = StrokeCap.Round,
                    color = FluroColors.Teal,
                    trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                )
            }
            Text(
                text = "${(progress * 100).roundToInt()}%",
                style = MaterialTheme.typography.headlineSmall,
            )
        }
        Spacer(Modifier.height(24.dp))
        Text(
            text = if (state.kind == ExportKind.AUDIO) {
                stringResource(R.string.export_running_audio, (progress * 100).roundToInt())
            } else {
                stringResource(R.string.export_running, (progress * 100).roundToInt())
            },
            style = MaterialTheme.typography.titleMedium,
        )
        Spacer(Modifier.height(6.dp))
        Text(
            stringResource(R.string.export_keep_open),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(24.dp))
        TextButton(onClick = onCancel) { Text(stringResource(R.string.export_cancel), color = MaterialTheme.colorScheme.error) }
    }
}

@Composable
private fun DoneView(state: ExportState.Done, onShare: () -> Unit, onOpen: () -> Unit, onFinish: () -> Unit) {
    CenteredColumn {
        Icon(Icons.Rounded.CheckCircle, contentDescription = null, tint = FluroColors.Teal, modifier = Modifier.size(96.dp))
        Spacer(Modifier.height(16.dp))
        Text(stringResource(R.string.export_done), style = MaterialTheme.typography.headlineSmall)
        val size = formatFileSize(state.sizeBytes, stringResource(R.string.export_size_mb), stringResource(R.string.export_size_gb))
        Text(
            stringResource(if (state.kind == ExportKind.AUDIO) R.string.export_done_audio else R.string.export_done_video, size),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(28.dp))
        GradientButton(onClick = onShare) {
            Icon(Icons.Rounded.Share, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text(stringResource(R.string.export_share))
        }
        Spacer(Modifier.height(12.dp))
        Row {
            TextButton(onClick = onOpen) { Text(stringResource(R.string.export_open)) }
            TextButton(onClick = onFinish) { Text(stringResource(R.string.export_finish)) }
        }
    }
}

@Composable
private fun FailedView(state: ExportState.Failed, onRetry: () -> Unit) {
    CenteredColumn {
        Icon(Icons.Rounded.ErrorOutline, contentDescription = null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(80.dp))
        Spacer(Modifier.height(16.dp))
        val nothing = state.code == ExportManager.NOTHING_TO_EXPORT
        Text(
            text = when {
                nothing && state.kind == ExportKind.AUDIO -> stringResource(R.string.export_no_audio)
                nothing -> stringResource(R.string.export_nothing)
                else -> stringResource(R.string.export_failed)
            },
            style = MaterialTheme.typography.headlineSmall,
            textAlign = TextAlign.Center,
        )
        val code = state.code
        if (!nothing && code != null) {
            Spacer(Modifier.height(6.dp))
            Text(
                stringResource(R.string.export_failed_code, code),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            state.message?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
            }
        }
        Spacer(Modifier.height(24.dp))
        GradientButton(onClick = onRetry) { Text(stringResource(R.string.export_retry)) }
    }
}

@Composable
private fun CenteredColumn(content: @Composable () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) { content() }
}

private fun hdrLabel(hdr: HdrType): String = when (hdr) {
    HdrType.HDR10 -> "HDR10"
    HdrType.HDR10_PLUS -> "HDR10+"
    HdrType.HLG -> "HLG"
    HdrType.DOLBY_VISION -> "Dolby Vision"
    HdrType.NONE -> "SDR"
}

private fun share(context: android.content.Context, uri: Uri, mimeType: String) {
    val send = Intent(Intent.ACTION_SEND)
        .setType(mimeType)
        .putExtra(Intent.EXTRA_STREAM, uri)
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    context.startActivity(Intent.createChooser(send, null))
}

private fun open(context: android.content.Context, uri: Uri, mimeType: String) {
    runCatching {
        context.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, mimeType).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
    }
}
