package com.flurocup.feature.home

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.flurocup.core.ui.theme.AccentPalette
import com.flurocup.core.ui.theme.ThemeMode
import com.flurocup.core.ui.theme.ThemeStore

/** Theme choice: like the system, dark, light, or one's own background and accent colours. */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
internal fun AppearanceSheet(onDismiss: () -> Unit) {
    val settings = ThemeStore.settings
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = MaterialTheme.colorScheme.surfaceContainerHigh) {
        Column(
            Modifier
                .navigationBarsPadding()
                .padding(horizontal = 20.dp)
                .padding(bottom = 24.dp),
        ) {
            Text(stringResource(R.string.home_appearance), style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(12.dp))
            Text(stringResource(R.string.home_theme), style = MaterialTheme.typography.labelLarge)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(
                    ThemeMode.SYSTEM to R.string.home_theme_system,
                    ThemeMode.DARK to R.string.home_theme_dark,
                    ThemeMode.LIGHT to R.string.home_theme_light,
                    ThemeMode.CUSTOM to R.string.home_theme_custom,
                ).forEach { (mode, label) ->
                    Choice(stringResource(label), settings.mode == mode) { ThemeStore.update { it.copy(mode = mode) } }
                }
            }
            if (settings.mode == ThemeMode.CUSTOM) {
                Spacer(Modifier.height(16.dp))
                Text(stringResource(R.string.home_theme_background), style = MaterialTheme.typography.labelLarge)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Choice(stringResource(R.string.home_theme_dark), settings.customDark) { ThemeStore.update { it.copy(customDark = true) } }
                    Choice(stringResource(R.string.home_theme_light), !settings.customDark) { ThemeStore.update { it.copy(customDark = false) } }
                }
                Spacer(Modifier.height(16.dp))
                Text(stringResource(R.string.home_theme_accent), style = MaterialTheme.typography.labelLarge)
                Spacer(Modifier.height(8.dp))
                FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    AccentPalette.entries.forEach { accent ->
                        val selected = settings.accent == accent
                        Box(
                            modifier = Modifier
                                .size(44.dp)
                                .clip(CircleShape)
                                .background(Brush.linearGradient(listOf(accent.first, accent.second)))
                                .border(if (selected) 3.dp else 0.dp, MaterialTheme.colorScheme.onSurface, CircleShape)
                                .clickable { ThemeStore.update { it.copy(accent = accent) } },
                            contentAlignment = Alignment.Center,
                        ) {
                            if (selected) Icon(Icons.Rounded.Check, contentDescription = null, tint = accent.onAccent)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Choice(label: String, selected: Boolean, onClick: () -> Unit) {
    FilterChip(
        selected = selected,
        onClick = onClick,
        label = { Text(label) },
        colors = FilterChipDefaults.filterChipColors(
            selectedContainerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.18f),
            selectedLabelColor = MaterialTheme.colorScheme.primary,
        ),
    )
}
