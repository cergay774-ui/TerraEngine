package com.flurocup.core.engine.media

import android.content.Context
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Runs one Transformer export to [outputPath] and suspends until it finishes. Cancelling the
 * coroutine cancels the export. Must be called on the main thread: Transformer runs on the
 * thread it is built on.
 */
@OptIn(UnstableApi::class)
internal suspend fun runTransformer(
    context: Context,
    composition: Composition,
    outputPath: String,
    configure: Transformer.Builder.() -> Unit,
    onProgress: (Float) -> Unit,
): ExportResult {
    val done = CompletableDeferred<ExportResult>()
    val transformer = Transformer.Builder(context)
        .apply(configure)
        .addListener(object : Transformer.Listener {
            override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                done.complete(exportResult)
            }

            override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                done.completeExceptionally(exportException)
            }
        })
        .build()
    transformer.start(composition, outputPath)
    try {
        return coroutineScope {
            val poller = launch {
                val holder = ProgressHolder()
                while (true) {
                    if (transformer.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) {
                        onProgress(holder.progress / 100f)
                    }
                    delay(PROGRESS_POLL_MS)
                }
            }
            val result = done.await()
            poller.cancel()
            result
        }
    } catch (e: CancellationException) {
        transformer.cancel()
        throw e
    }
}

private const val PROGRESS_POLL_MS = 250L
