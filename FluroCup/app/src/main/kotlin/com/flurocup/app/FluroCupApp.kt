package com.flurocup.app

import com.flurocup.core.ui.theme.ThemeStore
import android.app.Application
import com.flurocup.app.crash.CrashLog
import dagger.hilt.android.HiltAndroidApp

@HiltAndroidApp
class FluroCupApp : Application() {
    override fun onCreate() {
        super.onCreate()
        CrashLog.install(this)
        ThemeStore.init(this)
    }
}
