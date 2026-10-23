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
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)
        setContent {
            FluroTheme {
                FluroNavHost()
                CrashReportDialog()
            }
        }
    }

    private companion object {
        const val SYSTEM_SPLASH_FADE_MS = 220L
    }
}
