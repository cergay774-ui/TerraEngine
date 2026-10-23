package com.flurocup.app

import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.flurocup.app.crash.CrashReportDialog
import com.flurocup.app.navigation.FluroNavHost
import com.flurocup.core.ui.theme.FluroTheme
import com.flurocup.core.ui.theme.ThemeStore
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.DisposableEffect
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        val splash = installSplashScreen()
        // The system splash fades into the animated Compose splash, which draws the same mark.
        splash.setOnExitAnimationListener { provider ->
            provider.view.animate()
                .alpha(0f)
                .setDuration(SYSTEM_SPLASH_FADE_MS)
                .withEndAction { provider.remove() }
                .start()
        }
        super.onCreate(savedInstanceState)
        setContent {
            val settings = ThemeStore.settings
            val dark = settings.isDark(isSystemInDarkTheme())
            // Light themes need dark status and navigation bar icons.
            DisposableEffect(dark) {
                val style = if (dark) SystemBarStyle.dark(Color.TRANSPARENT) else SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT)
                enableEdgeToEdge(statusBarStyle = style, navigationBarStyle = style)
                onDispose { }
            }
            FluroTheme(settings) {
                FluroNavHost()
                CrashReportDialog()
            }
        }
    }

    private companion object {
        const val SYSTEM_SPLASH_FADE_MS = 220L
    }
}
