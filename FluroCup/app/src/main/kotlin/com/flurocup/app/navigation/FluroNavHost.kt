package com.flurocup.app.navigation

import androidx.compose.animation.AnimatedContentTransitionScope.SlideDirection
import androidx.compose.animation.BoundsTransform
import androidx.compose.animation.ExperimentalSharedTransitionApi
import androidx.compose.animation.SharedTransitionLayout
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.flurocup.app.splash.FluroSplash
import com.flurocup.feature.editor.EditorScreen
import com.flurocup.feature.home.HomeScreen

private const val LOGO_KEY = "fluro-logo"

/** Springy, slightly overshooting flight of the logo from the splash into the home top bar. */
@OptIn(ExperimentalSharedTransitionApi::class)
private val LogoBoundsTransform = BoundsTransform { _, _ ->
    spring(dampingRatio = 0.78f, stiffness = Spring.StiffnessLow)
}

@OptIn(ExperimentalSharedTransitionApi::class)
@Composable
fun FluroNavHost() {
    val navController = rememberNavController()
    SharedTransitionLayout(
        Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
    ) {
        NavHost(
            navController = navController,
            startDestination = SplashRoute,
            enterTransition = { fadeIn(tween(350)) },
            exitTransition = { fadeOut(tween(350)) },
            popEnterTransition = { fadeIn(tween(350)) },
            popExitTransition = { fadeOut(tween(350)) },
        ) {
            composable<SplashRoute>(
                exitTransition = { fadeOut(tween(450)) },
            ) {
                FluroSplash(
                    markModifier = Modifier.sharedElement(
                        rememberSharedContentState(key = LOGO_KEY),
                        animatedVisibilityScope = this@composable,
                        boundsTransform = LogoBoundsTransform,
                    ),
                    onFinished = {
                        navController.navigate(HomeRoute) {
                            popUpTo<SplashRoute> { inclusive = true }
                        }
                    },
                )
            }
            composable<HomeRoute>(
                enterTransition = { fadeIn(tween(500, delayMillis = 100)) },
                exitTransition = {
                    fadeOut(tween(250)) + scaleOut(spring(stiffness = Spring.StiffnessMediumLow), targetScale = 0.96f)
                },
            ) {
                HomeScreen(
                    onOpenProject = { id -> navController.navigate(EditorRoute(id)) },
                    logoModifier = Modifier.sharedElement(
                        rememberSharedContentState(key = LOGO_KEY),
                        animatedVisibilityScope = this@composable,
                        boundsTransform = LogoBoundsTransform,
                    ),
                )
            }
            composable<EditorRoute>(
                enterTransition = {
                    slideIntoContainer(SlideDirection.Start, spring(stiffness = Spring.StiffnessMediumLow)) +
                        fadeIn(tween(250))
                },
                popExitTransition = {
                    slideOutOfContainer(SlideDirection.End, spring(stiffness = Spring.StiffnessMediumLow)) +
                        fadeOut(tween(250))
                },
            ) {
                EditorScreen(onBack = { navController.popBackStack() })
            }
        }
    }
}
