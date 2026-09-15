package de.haphone.app.test

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys

class SettingsActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Surface {
                    SettingsScreen(onBack = { finish() })
                }
            }
        }
    }

    @Composable
    private fun SettingsScreen(onBack: () -> Unit) {
        val context = LocalContext.current
        val prefs = remember { getEncryptedPrefs(context) }

        val sipHost = remember { mutableStateOf(prefs.getString("sip_host", "") ?: "") }
        val sipPort = remember { mutableStateOf(prefs.getString("sip_port", "") ?: "") }
        val sipUsername = remember { mutableStateOf(prefs.getString("sip_username", "") ?: "") }
        val sipPassword = remember { mutableStateOf(prefs.getString("sip_password", "") ?: "") }
        val saved = remember { mutableStateOf(false) }
        val error = remember { mutableStateOf<String?>(null) }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("Einstellungen", style = MaterialTheme.typography.headlineMedium)
                Button(onClick = onBack) { Text("Fertig") }
            }

            // Info
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer
                )
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text("SIP-Zugangsdaten", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "Tragen Sie hier Ihre HA-Phone-Box-Zugangsdaten ein.\n" +
                        "Alternativ: QR-Code scannen für automatische Einrichtung.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            // SIP Fields
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                TextField(
                    label = { Text("SIP-Server (Host)") },
                    value = sipHost.value,
                    onValueChange = { sipHost.value = it },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )

                TextField(
                    label = { Text("SIP-Port (meist 5061 für TLS)") },
                    value = sipPort.value,
                    onValueChange = { sipPort.value = it },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )

                TextField(
                    label = { Text("Benutzername (Nebenstellennummer)") },
                    value = sipUsername.value,
                    onValueChange = { sipUsername.value = it },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )

                TextField(
                    label = { Text("SIP-Passwort") },
                    value = sipPassword.value,
                    onValueChange = { sipPassword.value = it },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation()
                )
            }

            // Save button
            Button(
                onClick = {
                    if (sipHost.value.isBlank() || sipPort.value.isBlank() || sipUsername.value.isBlank() || sipPassword.value.isBlank()) {
                        error.value = "Alle Felder ausfüllen!"
                    } else {
                        error.value = null
                        saveCredentials(context, sipHost.value, sipPort.value, sipUsername.value, sipPassword.value)
                        Log.i("HAPhoneTest", "SIP credentials saved")
                    }
                },
                modifier = Modifier.fillMaxWidth(),
                enabled = true
            ) {
                Text("Speichern")
            }

            error.value?.let { msg ->
                Text(msg, style = MaterialTheme.typography.bodyMedium, color = Color.Red)
            }

            // Danger zone
            androidx.compose.foundation.layout.Spacer(modifier = Modifier.padding(top = 32.dp))
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.errorContainer
                )
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text("Zurücksetzen", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onErrorContainer)
                    Text("Alle SIP-Daten und Geräte-Registrierungen löschen.", style = MaterialTheme.typography.bodySmall)
                    Button(onClick = { clearCredentials(context) }, modifier = Modifier.fillMaxWidth()) {
                        Text("Alles löschen", style = MaterialTheme.typography.labelLarge)
                    }
                }
            }
        }
    }

    private fun getEncryptedPrefs(context: Context): SharedPreferences {
        val masterKeyAlias = MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC)
        return EncryptedSharedPreferences.create(
            "haphone_prefs",
            masterKeyAlias,
            context,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    private fun saveCredentials(context: Context, host: String, port: String, username: String, password: String) {
        val prefs = getEncryptedPrefs(context)
        prefs.edit().apply {
            putString("sip_host", host)
            putString("sip_port", port)
            putString("sip_username", username)
            putString("sip_password", password)
            apply()
        }
    }

    private fun clearCredentials(context: Context) {
        val prefs = getEncryptedPrefs(context)
        prefs.edit().clear().apply()
    }
}