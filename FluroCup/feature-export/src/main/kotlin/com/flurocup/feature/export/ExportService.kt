package com.flurocup.feature.export

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.flurocup.core.engine.export.ExportKind
import com.flurocup.core.engine.export.ExportManager
import com.flurocup.core.engine.export.ExportState
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Keeps the app running in the foreground while [ExportManager] exports, with a progress
 * notification and a cancel button. The export itself lives in ExportManager.
 */
@AndroidEntryPoint
class ExportService : Service() {

    @Inject lateinit var exports: ExportManager

    private val scope = MainScope()
    private var watcher: Job? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_CANCEL) {
            exports.cancel()
            return START_NOT_STICKY
        }
        createChannel(this)
        val state = exports.state.value
        ServiceCompat.startForeground(this, NOTIFICATION_ID, progressNotification(state as? ExportState.Running), foregroundType())
        if (state !is ExportState.Running) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (watcher == null) {
            watcher = scope.launch {
                exports.state.collect { current ->
                    when (current) {
                        is ExportState.Running -> notify(progressNotification(current))
                        else -> {
                            ServiceCompat.stopForeground(this@ExportService, ServiceCompat.STOP_FOREGROUND_REMOVE)
                            resultNotification(current)?.let { notify(it, RESULT_NOTIFICATION_ID) }
                            stopSelf()
                        }
                    }
                }
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun foregroundType(): Int = when {
        Build.VERSION.SDK_INT >= 35 -> ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        else -> 0
    }

    private fun progressNotification(state: ExportState.Running?) =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_export)
            .setContentTitle(getString(R.string.export_notification_title, state?.projectName.orEmpty()))
            .setContentText(
                state?.progress?.let { getString(R.string.export_running, (it * 100).toInt()) } ?: getString(R.string.export_preparing),
            )
            .setProgress(100, ((state?.progress ?: 0f) * 100).toInt(), state?.progress == null)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setContentIntent(openAppIntent())
            .addAction(0, getString(R.string.export_cancel), cancelIntent())
            .build()

    private fun resultNotification(state: ExportState) = when (state) {
        is ExportState.Done -> NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_export)
            .setContentTitle(
                getString(if (state.kind == ExportKind.AUDIO) R.string.export_notification_audio_done else R.string.export_notification_done),
            )
            .setContentIntent(
                PendingIntent.getActivity(
                    this,
                    2,
                    Intent(Intent.ACTION_VIEW).setDataAndType(state.uri, state.mimeType).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                ),
            )
            .setAutoCancel(true)
            .build()
        is ExportState.Failed -> NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_export)
            .setContentTitle(getString(R.string.export_notification_failed))
            .setContentText(state.code)
            .setContentIntent(openAppIntent())
            .setAutoCancel(true)
            .build()
        else -> null
    }

    private fun notify(notification: android.app.Notification, id: Int = NOTIFICATION_ID) {
        // Without the notification permission the export still runs; there is just nothing to show.
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        NotificationManagerCompat.from(this).notify(id, notification)
    }

    private fun openAppIntent(): PendingIntent? {
        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: return null
        launch.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(this, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    private fun cancelIntent(): PendingIntent = PendingIntent.getService(
        this,
        1,
        Intent(this, ExportService::class.java).setAction(ACTION_CANCEL),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    companion object {
        private const val CHANNEL_ID = "export"
        private const val NOTIFICATION_ID = 41
        private const val RESULT_NOTIFICATION_ID = 42
        private const val ACTION_CANCEL = "com.flurocup.export.CANCEL"

        /** Call right after starting an export in [ExportManager]. */
        fun start(context: Context) {
            ContextCompat.startForegroundService(context, Intent(context, ExportService::class.java))
        }

        private fun createChannel(context: Context) {
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                manager.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, context.getString(R.string.export_channel), NotificationManager.IMPORTANCE_LOW),
                )
            }
        }
    }
}
