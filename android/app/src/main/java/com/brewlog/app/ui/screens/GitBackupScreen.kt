package com.brewlog.app.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import com.brewlog.app.LocalContainer
import com.brewlog.app.sync.GitRemote
import com.brewlog.app.ui.components.BrewCard
import com.brewlog.app.ui.components.PillChip
import com.brewlog.app.ui.components.SectionHeader
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date

/** Settings → Git backup: journal, gear, beans and recipes as one JSON file in your own repository. Port of GitBackupView.swift. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun GitBackupScreen(nav: NavHostController) {
    val container = LocalContainer.current
    val sync = container.gitSync
    val saved by sync.remote.collectAsStateWithLifecycle()
    val status by sync.status.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    var provider by remember { mutableStateOf(saved.provider) }
    var host by remember { mutableStateOf(saved.host) }
    var repository by remember { mutableStateOf(saved.repository) }
    var branch by remember { mutableStateOf(saved.branch) }
    var path by remember { mutableStateOf(saved.path) }
    var token by remember { mutableStateOf("") }
    var hasToken by remember { mutableStateOf(sync.hasToken) }
    var autoSync by remember { mutableStateOf(sync.autoSync) }

    val draft = GitRemote(provider, host.trim(), repository.trim(), branch.trim(), path.trim())
    fun apply() {
        if (draft != saved) sync.setRemote(draft)
        if (token.isNotBlank()) {
            sync.setToken(token)
            token = ""
            hasToken = true
        }
    }

    // Keep a valid repository setting right away; the token is stored on Sync or when leaving.
    LaunchedEffect(draft) { if (draft.isValid && draft != saved) sync.setRemote(draft) }
    BackHandler { apply(); nav.popBackStack() }

    BrewScreen(title = "Git backup", onBack = { apply(); nav.popBackStack() }) { padding ->
        CardList(padding) {
            item {
                BrewCard {
                    Text("Keeps your journal, gear, beans and recipes as one JSON file in your own GitHub, GitLab or Gitea repository, " +
                        "one commit per change. Other devices merge it in: nothing is ever deleted.",
                        style = MaterialTheme.typography.bodyMedium)
                }
            }
            item {
                SectionHeader("Repository")
                Spacer(Modifier.height(8.dp))
                BrewCard {
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        GitRemote.Provider.entries.forEach { p -> PillChip(p.displayName, provider == p) { provider = p } }
                    }
                    Spacer(Modifier.height(8.dp))
                    OutlinedTextField(host, { host = it.take(253) }, Modifier.fillMaxWidth(), singleLine = true,
                        label = { Text(if (provider.defaultHost == null) "Server (e.g. git.example.com)" else "Server (empty = ${provider.defaultHost})") })
                    OutlinedTextField(repository, { repository = it.take(200) }, Modifier.fillMaxWidth(), singleLine = true, label = { Text("Repository (owner/name)") })
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedTextField(branch, { branch = it.take(100) }, Modifier.weight(1f), singleLine = true, label = { Text("Branch") })
                        OutlinedTextField(path, { path = it.take(200) }, Modifier.weight(1.6f), singleLine = true, label = { Text("File") })
                    }
                    draft.problem?.let {
                        if (repository.isNotBlank()) Text(it.message, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
            item {
                SectionHeader("Access token")
                Spacer(Modifier.height(8.dp))
                BrewCard {
                    OutlinedTextField(token, { token = it.take(500) }, Modifier.fillMaxWidth(), singleLine = true,
                        label = { Text(if (hasToken) "Token saved (enter a new one to replace it)" else "Token") },
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password))
                    Text("Needs read and write access to the repository's contents. Stored encrypted with a key that never leaves this phone.",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    if (hasToken) {
                        TextButton(onClick = { sync.setToken(null); hasToken = false }) { Text("Remove token", color = MaterialTheme.colorScheme.error) }
                    }
                }
            }
            item {
                BrewCard {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Sync automatically after brews", Modifier.weight(1f))
                        Switch(autoSync, { autoSync = it; sync.autoSync = it })
                    }
                    Spacer(Modifier.height(8.dp))
                    PrimaryButton(if (status.syncing) "Syncing…" else "Sync now", enabled = !status.syncing && draft.isValid && (hasToken || token.isNotBlank())) {
                        apply()
                        scope.launch { sync.sync() }
                    }
                    status.message?.let { Text(it, Modifier.padding(top = 8.dp), style = MaterialTheme.typography.bodyMedium) }
                    status.lastSync?.let {
                        Text("Last sync: " + DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(it)),
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}
