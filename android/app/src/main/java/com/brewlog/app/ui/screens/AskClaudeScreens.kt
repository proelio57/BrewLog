package com.brewlog.app.ui.screens

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import com.brewlog.app.AppContainer
import com.brewlog.app.LocalContainer
import com.brewlog.app.ai.BeanAdvisor
import com.brewlog.app.domain.Bean
import com.brewlog.app.domain.EquipmentType
import com.brewlog.app.ui.components.BrewCard
import com.brewlog.app.ui.components.SectionHeader
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.util.Locale

private const val PREF_WEB_SEARCH = "ai.webSearch"

/** Settings → Ask Claude: the user's own Anthropic API key (encrypted on the device) and web search. */
@Composable
fun AiSettingsScreen(nav: NavHostController) {
    val container = LocalContainer.current
    val prefs = remember { container.preferences }
    var key by remember { mutableStateOf("") }
    var hasKey by remember { mutableStateOf(container.secrets.get(BeanAdvisor.KEY_ACCOUNT) != null) }
    var webSearch by remember { mutableStateOf(prefs.getBoolean(PREF_WEB_SEARCH, true)) }

    BrewScreen(title = "Ask Claude", onBack = { nav.popBackStack() }) { padding ->
        CardList(padding) {
            item {
                BrewCard {
                    if (hasKey) {
                        Text("API key saved (encrypted on this phone).")
                        TextButton(onClick = { container.secrets.set(BeanAdvisor.KEY_ACCOUNT, null); hasKey = false }) {
                            Text("Remove key", color = MaterialTheme.colorScheme.error)
                        }
                    } else {
                        OutlinedTextField(key, { key = it.take(300) }, Modifier.fillMaxWidth(), singleLine = true,
                            label = { Text("Anthropic API key (sk-ant-…)") }, visualTransformation = PasswordVisualTransformation(),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password))
                        TextButton(onClick = {
                            container.secrets.set(BeanAdvisor.KEY_ACCOUNT, key)
                            key = ""
                            hasKey = container.secrets.get(BeanAdvisor.KEY_ACCOUNT) != null
                        }, enabled = key.isNotBlank()) { Text("Save key") }
                    }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Search the web", Modifier.weight(1f))
                        Switch(webSearch, { webSearch = it; prefs.edit().putBoolean(PREF_WEB_SEARCH, it).apply() })
                    }
                    Text("\"Ask Claude\" on a bean sends that bean, your gear and your brews of it to Anthropic, using your own API key " +
                        "from console.anthropic.com (billed to you). With web search, Claude also looks for the roaster's notes and " +
                        "community posts about the coffee. Nothing is sent unless you tap Ask Claude.",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

/** "Ask Claude" for a bean: best way to brew it with your gear, and what others say about it. */
@Composable
fun BeanAdviceScreen(nav: NavHostController, beanId: String) {
    val container = LocalContainer.current
    val context = LocalContext.current
    val bean = remember(beanId) { container.repository.data.value.beans.firstOrNull { it.id == beanId } }
    val webSearch = remember { container.preferences.getBoolean(PREF_WEB_SEARCH, true) }
    var answer by remember { mutableStateOf<BeanAdvisor.Answer?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun ask() {
        if (bean == null || loading) return
        loading = true
        error = null
        scope.launch {
            val language = Locale.getDefault().getDisplayLanguage(Locale.ENGLISH).ifEmpty { "English" }
            val key = container.secrets.get(BeanAdvisor.KEY_ACCOUNT) ?: ""
            try {
                answer = withContext(Dispatchers.IO) { BeanAdvisor.ask(adviceContext(container, bean), key, language, webSearch) }
            } catch (e: BeanAdvisor.AdvisorException) {
                error = e.message
            } catch (e: Exception) {
                error = "Something went wrong. Try again."
            } finally {
                loading = false
            }
        }
    }
    LaunchedEffect(beanId) { if (answer == null && error == null) ask() }

    BrewScreen(title = "Ask Claude", onBack = { nav.popBackStack() }) { padding ->
        CardList(padding) {
            item {
                Column {
                    Text(bean?.name ?: "", style = MaterialTheme.typography.titleMedium)
                    val subtitle = listOfNotNull(bean?.roaster, bean?.origin).filter { it.isNotEmpty() }.joinToString(" · ")
                    if (subtitle.isNotEmpty()) Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            when {
                loading -> item {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.width(10.dp))
                        Text(if (webSearch) "Searching the web and thinking… this can take a minute." else "Thinking…",
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                error != null -> item {
                    BrewCard {
                        Text(error!!, color = MaterialTheme.colorScheme.error)
                        TextButton(onClick = { ask() }) { Text("Try again") }
                        if (container.secrets.get(BeanAdvisor.KEY_ACCOUNT) == null) {
                            TextButton(onClick = { nav.navigate(com.brewlog.app.ui.Routes.AI) }) { Text("Add API key") }
                        }
                    }
                }
                answer != null -> {
                    item { BrewCard { SelectionContainer { Text(answer!!.text, style = MaterialTheme.typography.bodyMedium) } } }
                    if (answer!!.sources.isNotEmpty()) {
                        item {
                            SectionHeader("Sources")
                            Spacer(Modifier.height(8.dp))
                            BrewCard {
                                answer!!.sources.forEach { source ->
                                    Column(Modifier.fillMaxWidth().clickable {
                                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(source.url)))
                                    }.padding(vertical = 6.dp)) {
                                        Text(source.title, maxLines = 2, overflow = TextOverflow.Ellipsis, color = MaterialTheme.colorScheme.primary)
                                        Text(Uri.parse(source.url).host ?: source.url, style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                }
                            }
                        }
                    }
                    item {
                        Text("AI answers can be wrong. Taste and adjust.", style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

/** Only this bean, the brewing gear and this bean's brews are sent. */
private fun adviceContext(container: AppContainer, bean: Bean): BeanAdvisor.Context {
    val data = container.repository.data.value
    val gearTypes = setOf(EquipmentType.BREWER, EquipmentType.GRINDER, EquipmentType.FILTER, EquipmentType.WATER)
    val brews = data.brews.filter { it.beanId == bean.id }.sortedByDescending { it.date }.take(BeanAdvisor.MAX_BREWS)
    return BeanAdvisor.Context(
        name = bean.name, roaster = bean.roaster, origin = bean.origin, varietal = bean.varietal,
        process = bean.process.displayName, roastLevel = bean.roastLevel.displayName, daysOffRoast = bean.daysOffRoast(),
        tastingNotes = bean.tastingNotes,
        gear = data.equipment.filter { it.type in gearTypes }.map { item ->
            if (item.type == EquipmentType.GRINDER) "${item.name} (grinder, ${item.grinder.unit.displayName.lowercase()})"
            else "${item.name} (${item.type.name.lowercase()})"
        },
        brews = brews.map { brew ->
            BeanAdvisor.BrewSummary(
                date = Instant.ofEpochMilli(brew.date), recipe = brew.recipeName, method = brew.recipe?.method?.displayName ?: "",
                dose = brew.dose, water = brew.finalWeight, temperature = brew.waterTemp, time = brew.totalTime,
                grind = brew.grindDisplay, rating = brew.rating, feedback = brew.feedback.sortedBy { it.name }.map { it.title },
                notes = brew.notes,
            )
        },
    )
}
