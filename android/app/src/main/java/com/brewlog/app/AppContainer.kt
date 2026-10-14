package com.brewlog.app

import android.app.Application
import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import com.brewlog.app.audio.Haptics
import com.brewlog.app.audio.SoundPlayer
import com.brewlog.app.brewing.BrewCue
import com.brewlog.app.brewing.BrewSession
import com.brewlog.app.data.BrewRepository
import com.brewlog.app.data.BrewSetupState
import com.brewlog.app.data.SettingsRepository
import com.brewlog.app.domain.Equipment
import com.brewlog.app.domain.Recipe
import com.brewlog.app.domain.RecipeLibrary
import com.brewlog.app.scale.ScaleManager
import com.brewlog.app.ui.AppRoot
import com.brewlog.app.ui.theme.BrewLogTheme
import kotlinx.coroutines.MainScope

/** Everything the brew needs, frozen when "Start brew" is pressed. */
data class BrewConfig(
    val recipe: Recipe,
    val dose: Double,
    val waterTemp: Double,
    val beanId: String?,
    val brewer: Equipment?,
    val grinder: Equipment?,
    val filter: Equipment?,
    val grindValue: Double?,
    val grindText: String,
)

/** Simple manual dependency container, created once per process. */
class AppContainer(context: Context) {
    val scope = MainScope()
    private val prefs = context.getSharedPreferences("brewlog", Context.MODE_PRIVATE)

    val settings = SettingsRepository(prefs)
    val presets: List<Recipe> = context.assets.open("recipes.json").bufferedReader().use { RecipeLibrary.parse(it.readText()) }
    val repository = BrewRepository(context.filesDir, scope)
    val scale = ScaleManager(context.applicationContext, prefs, scope)
    val sound = SoundPlayer { settings.current }
    val haptics = Haptics(context.applicationContext) { settings.current }
    val setup = BrewSetupState(prefs, presets).also { it.restoreCustom(repository.data.value.customRecipes) }

    /** The live brew survives configuration changes because it lives here, not in the UI. */
    var activeBrew: Pair<BrewConfig, BrewSession>? = null

    fun cue(cue: BrewCue) {
        sound.play(cue)
        haptics.play(cue)
    }

    fun allRecipes(): List<Recipe> = repository.data.value.customRecipes + presets
}

class BrewLogApplication : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }
}

val LocalContainer = staticCompositionLocalOf<AppContainer> { error("AppContainer not provided") }

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val container = (application as BrewLogApplication).container
        setContent {
            CompositionLocalProvider(LocalContainer provides container) {
                BrewLogTheme {
                    AppRoot()
                }
            }
        }
    }
}
