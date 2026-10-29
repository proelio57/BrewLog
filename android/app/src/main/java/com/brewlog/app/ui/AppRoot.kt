package com.brewlog.app.ui

import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ListAlt
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Eco
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.brewlog.app.LocalContainer
import com.brewlog.app.ui.screens.AiSettingsScreen
import com.brewlog.app.ui.screens.BeanAdviceScreen
import com.brewlog.app.ui.screens.BeanEditorScreen
import com.brewlog.app.ui.screens.BeanListScreen
import com.brewlog.app.ui.screens.BrewDetailScreen
import com.brewlog.app.ui.screens.ExtractionCalculatorScreen
import com.brewlog.app.ui.screens.GitBackupScreen
import com.brewlog.app.ui.screens.GrindConverterScreen
import com.brewlog.app.ui.screens.WaterCalculatorScreen
import com.brewlog.app.ui.screens.BrewEditorScreen
import com.brewlog.app.ui.screens.BrewSetupScreen
import com.brewlog.app.ui.screens.EquipmentEditorScreen
import com.brewlog.app.ui.screens.GearScreen
import com.brewlog.app.ui.screens.JournalScreen
import com.brewlog.app.ui.screens.LiveBrewScreen
import com.brewlog.app.ui.screens.OnboardingScreen
import com.brewlog.app.ui.screens.PresetPickerScreen
import com.brewlog.app.ui.screens.QuickWeighScreen
import com.brewlog.app.ui.screens.RecipeDetailScreen
import com.brewlog.app.ui.screens.RecipeEditorScreen
import com.brewlog.app.ui.screens.RecipeListScreen
import com.brewlog.app.ui.screens.RecipePickerScreen
import com.brewlog.app.ui.screens.SettingsScreen

object Routes {
    const val BREW = "brew"
    const val RECIPES = "recipes"
    const val JOURNAL = "journal"
    const val BEANS = "beans"
    const val GEAR = "gear"
    const val ONBOARDING = "onboarding"
    const val WEIGH = "weigh"
    const val LIVE = "live"
    const val RECIPE_PICKER = "recipePicker"
    const val PRESETS = "presets"
    const val SETTINGS = "settings"
    const val NEW = "new"
    const val TOOLS_EXTRACTION = "tools/extraction"
    const val TOOLS_WATER = "tools/water"
    const val TOOLS_GRIND = "tools/grind"
    const val GIT_BACKUP = "settings/git"
    const val AI = "settings/ai"

    fun brewDetail(id: String, isNew: Boolean = false) = "brewDetail/$id?isNew=$isNew"
    fun brewEditor(id: String) = "brewEditor/$id"
    fun recipe(id: String) = "recipe/$id"
    fun recipeEditor(id: String, duplicate: Boolean = false) = "recipeEditor/$id?duplicate=$duplicate"
    fun bean(id: String) = "bean/$id"
    fun equipment(id: String) = "equipment/$id"
    fun beanAdvice(id: String) = "beanAdvice/$id"
}

private data class Tab(val route: String, val label: String, val icon: ImageVector)

private val tabs = listOf(
    Tab(Routes.BREW, "Brew", Icons.Filled.WaterDrop),
    Tab(Routes.RECIPES, "Recipes", Icons.AutoMirrored.Filled.MenuBook),
    Tab(Routes.JOURNAL, "Journal", Icons.AutoMirrored.Filled.ListAlt),
    Tab(Routes.BEANS, "Beans", Icons.Filled.Eco),
    Tab(Routes.GEAR, "Gear", Icons.Filled.Build),
)

@Composable
fun AppRoot() {
    val container = LocalContainer.current
    val nav = rememberNavController()
    val backStack by nav.currentBackStackEntryAsState()
    val currentRoute = backStack?.destination?.route
    val startDestination = remember { if (container.settings.current.onboardingDone) Routes.BREW else Routes.ONBOARDING }

    LaunchedEffect(Unit) { container.scale.start() }
    // Widgets open the app with brewlog://brew, …/weigh, …/journal or …/beans.
    val link by container.pendingLink.collectAsState()
    LaunchedEffect(link) {
        val target = link ?: return@LaunchedEffect
        container.pendingLink.value = null
        if (!container.settings.current.onboardingDone || container.activeBrew != null) return@LaunchedEffect
        when (target) {
            "brew" -> nav.switchTab(Routes.BREW)
            "journal" -> nav.switchTab(Routes.JOURNAL)
            "beans" -> nav.switchTab(Routes.BEANS)
            "weigh" -> { nav.switchTab(Routes.BREW); nav.navigate(Routes.WEIGH) }
        }
    }

    Scaffold(
        contentWindowInsets = WindowInsets(0),
        containerColor = MaterialTheme.colorScheme.background,
        bottomBar = {
            if (tabs.any { it.route == currentRoute }) {
                NavigationBar {
                    tabs.forEach { tab ->
                        NavigationBarItem(
                            selected = currentRoute == tab.route,
                            onClick = { nav.switchTab(tab.route) },
                            icon = { Icon(tab.icon, contentDescription = null) },
                            label = { Text(tab.label) },
                        )
                    }
                }
            }
        },
    ) { padding ->
        NavHost(nav, startDestination = startDestination, modifier = Modifier.padding(padding).consumeWindowInsets(padding)) {
            composable(Routes.ONBOARDING) {
                OnboardingScreen(
                    onFinish = { nav.navigate(Routes.BREW) { popUpTo(Routes.ONBOARDING) { inclusive = true } } },
                    onJustWeigh = {
                        nav.navigate(Routes.BREW) { popUpTo(Routes.ONBOARDING) { inclusive = true } }
                        nav.navigate(Routes.WEIGH)
                    },
                )
            }
            composable(Routes.BREW) { BrewSetupScreen(nav) }
            composable(Routes.RECIPES) { RecipeListScreen(nav) }
            composable(Routes.JOURNAL) { JournalScreen(nav) }
            composable(Routes.BEANS) { BeanListScreen(nav) }
            composable(Routes.GEAR) { GearScreen(nav) }
            composable(Routes.WEIGH) { QuickWeighScreen(onClose = { nav.popBackStack() }) }
            composable(Routes.LIVE) { LiveBrewScreen(nav) }
            composable(Routes.RECIPE_PICKER) { RecipePickerScreen(nav) }
            composable(Routes.PRESETS) { PresetPickerScreen(nav) }
            composable(Routes.SETTINGS) { SettingsScreen(nav) }
            composable(Routes.TOOLS_EXTRACTION) { ExtractionCalculatorScreen(nav) }
            composable(Routes.TOOLS_WATER) { WaterCalculatorScreen(nav) }
            composable(Routes.TOOLS_GRIND) { GrindConverterScreen(nav) }
            composable(Routes.GIT_BACKUP) { GitBackupScreen(nav) }
            composable(Routes.AI) { AiSettingsScreen(nav) }
            composable("beanAdvice/{id}") { entry -> BeanAdviceScreen(nav, entry.arguments?.getString("id").orEmpty()) }
            composable(
                "brewDetail/{id}?isNew={isNew}",
                arguments = listOf(navArgument("isNew") { type = NavType.BoolType; defaultValue = false }),
            ) { entry ->
                BrewDetailScreen(nav, entry.arguments?.getString("id").orEmpty(), entry.arguments?.getBoolean("isNew") ?: false)
            }
            composable("brewEditor/{id}") { entry ->
                BrewEditorScreen(nav, entry.arguments?.getString("id").orEmpty())
            }
            composable("recipe/{id}") { entry -> RecipeDetailScreen(nav, entry.arguments?.getString("id").orEmpty()) }
            composable(
                "recipeEditor/{id}?duplicate={duplicate}",
                arguments = listOf(navArgument("duplicate") { type = NavType.BoolType; defaultValue = false }),
            ) { entry ->
                RecipeEditorScreen(nav, entry.arguments?.getString("id").orEmpty(), entry.arguments?.getBoolean("duplicate") ?: false)
            }
            composable("bean/{id}") { entry -> BeanEditorScreen(nav, entry.arguments?.getString("id").orEmpty()) }
            composable("equipment/{id}") { entry -> EquipmentEditorScreen(nav, entry.arguments?.getString("id").orEmpty()) }
        }
    }
}

/** Bottom-tab navigation that keeps one copy of each tab on the back stack (Brew is always the root). */
fun NavHostController.switchTab(route: String) {
    navigate(route) {
        popUpTo(Routes.BREW) { saveState = true }
        launchSingleTop = true
        restoreState = true
    }
}
