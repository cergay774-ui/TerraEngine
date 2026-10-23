package com.flurocup.app.crash

import android.content.Context
import android.os.Build
import com.flurocup.app.BuildConfig
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Keeps the stack trace of the last crash, so the next launch can show it and the user can send it
 * to the developer. Nothing leaves the device unless the user copies it.
 */
object CrashLog {
    private const val FILE_NAME = "last_crash.txt"

    fun install(context: Context) {
        val appContext = context.applicationContext
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            runCatching { File(appContext.filesDir, FILE_NAME).writeText(report(thread, error)) }
            previous?.uncaughtException(thread, error)
        }
    }

    /** The saved report, removed so it is shown only once; null if the app did not crash. */
    fun take(context: Context): String? {
        val file = File(context.filesDir, FILE_NAME)
        if (!file.isFile) return null
        return runCatching { file.readText() }.getOrNull().also { file.delete() }
    }

    private fun report(thread: Thread, error: Throwable): String = buildString {
        appendLine("FluroCup ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
        appendLine("${Build.MANUFACTURER} ${Build.MODEL}, Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
        appendLine(SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.ROOT).format(Date()))
        appendLine("Thread: ${thread.name}")
        appendLine()
        append(error.stackTraceToString())
    }
}
