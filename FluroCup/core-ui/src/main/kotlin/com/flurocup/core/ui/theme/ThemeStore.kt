package com.flurocup.core.ui.theme

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** The chosen theme, kept in the app's preferences; read in composition, so changes show at once. */
object ThemeStore {
    private const val PREFS = "flurocup_appearance"
    private const val KEY_MODE = "mode"
    private const val KEY_CUSTOM_DARK = "custom_dark"
    private const val KEY_ACCENT = "accent"

    private var prefs: SharedPreferences? = null

    var settings by mutableStateOf(ThemeSettings())
        private set

    fun init(context: Context) {
        val p = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs = p
        settings = ThemeSettings(
            mode = enumOrDefault(p.getString(KEY_MODE, null), ThemeMode.DARK),
            customDark = p.getBoolean(KEY_CUSTOM_DARK, true),
            accent = enumOrDefault(p.getString(KEY_ACCENT, null), AccentPalette.FLURO),
        )
    }

    fun update(transform: (ThemeSettings) -> ThemeSettings) {
        val next = transform(settings)
        settings = next
        prefs?.edit()
            ?.putString(KEY_MODE, next.mode.name)
            ?.putBoolean(KEY_CUSTOM_DARK, next.customDark)
            ?.putString(KEY_ACCENT, next.accent.name)
            ?.apply()
    }

    private inline fun <reified T : Enum<T>> enumOrDefault(name: String?, default: T): T =
        enumValues<T>().firstOrNull { it.name == name } ?: default
}
