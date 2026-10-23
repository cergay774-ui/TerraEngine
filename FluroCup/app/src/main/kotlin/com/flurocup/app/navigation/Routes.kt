package com.flurocup.app.navigation

import kotlinx.serialization.Serializable

@Serializable
data object SplashRoute

@Serializable
data object HomeRoute

/** The property name must match [com.flurocup.feature.editor.EditorViewModel.PROJECT_ID_KEY]. */
@Serializable
data class EditorRoute(val projectId: String)
