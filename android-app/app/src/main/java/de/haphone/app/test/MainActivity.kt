package de.haphone.app.test

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys
import com.google.firebase.messaging.FirebaseMessaging

class MainActivity : ComponentActivity() {

    private val fcmTokenState = mutableStateOf("Fetching FCM token...")
    private var isProvisioned = false

    private val requestNotificationPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        checkProvisionedStatus()
        requestNotificationPermissionIfNeeded()

        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            if (task.isSuccessful) {
                val token = task.result
                Log.i("HAPhoneTest", "FCM token: $token")
                fcmTokenState.value = token
            } else {
                Log.w("HAPhoneTest", "FCM token fetch failed", task.exception)
                fcmTokenState.value = "FCM token fetch failed: ${task.exception?.message}"
            }
        }

        setContent {
            val fcmToken by fcmTokenState
            val provisioned = isProvisioned
            MaterialTheme {
                Surface {
                    MainScreen(
                        fcmToken = fcmToken,
                        isProvisioned = provisioned,
                        onScanQr = { /* TODO: QR Scanner */ },
                        onDial = { startActivity(Intent(this@MainActivity, OutgoingCallActivity::class.java)) },
                        onSettings = { startActivity(Intent(this@MainActivity, SettingsActivity::class.java)) }
                    )
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        checkProvisionedStatus()
    }

    private fun checkProvisionedStatus() {
        isProvisioned = hasValidCredentials(this)
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (!granted) {
            requestNotificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    private fun hasValidCredentials(context: Context): Boolean {
        val prefs = getEncryptedPrefs(context)
        return prefs.getString("sip_host", "")?.isNotBlank() == true &&
               prefs.getString("sip_port", "")?.isNotBlank() == true &&
               prefs.getString("sip_username", "")?.isNotBlank() == true &&
               prefs.getString("sip_password", "")?.isNotBlank() == true
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

    @Composable
    private fun MainScreen(
        fcmToken: String,
        isProvisioned: Boolean,
        onScanQr: () -> Unit,
        onDial: () -> Unit,
        onSettings: () -> Unit
    ) {
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
                Text("HA-Phone", style = MaterialTheme.typography.headlineMedium)
                Button(onClick = onSettings) {
                    Text("⚙️")
                }
            }

            if (!isProvisioned) {
                // Onboarding Card
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.primaryContainer
                    )
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text("Ersteinrichtung", style = MaterialTheme.typography.titleMedium)
                            Text("ℹ️")
                        }
                        Spacer(modifier = Modifier.padding(top = 8.dp))
                        Text(
                            "HA-Phone ist noch nicht eingerichtet. Wählen Sie eine Option:",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onPrimaryContainer
                        )
                        Spacer(modifier = Modifier.padding(top = 12.dp))
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Button(onClick = onScanQr, modifier = Modifier.weight(1f), enabled = false) {
                                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                    Text("🔍")
                                    Spacer(modifier = Modifier.padding(top = 4.dp))
                                    Text("QR-Code scannen")
                                    Text("(bald verfügbar)", style = MaterialTheme.typography.labelSmall)
                                }
                            }
                            Button(onClick = onSettings, modifier = Modifier.weight(1f)) {
                                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                    Text("⚙️")
                                    Spacer(modifier = Modifier.padding(top = 4.dp))
                                    Text("Manuell eingeben")
                                }
                            }
                        }
                    }
                }

                // Info Card
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.secondaryContainer
                    )
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text("So richten Sie HA-Phone ein", style = MaterialTheme.typography.labelLarge)
                        Spacer(modifier = Modifier.padding(top = 8.dp))
                        Text(
                            "1. Öffnen Sie \"SIP-Zugangsdaten eingeben\" oben\n" +
                            "2. Tragen Sie Server, Port, Nebenstelle und Passwort aus Ihrem " +
                            "HA-Phone-Dashboard ein\n" +
                            "3. Speichern – die App ist danach betriebsbereit\n\n" +
                            "Der FCM-Push-Token unten wird von der HA-Phone-Box benötigt, um Ihr " +
                            "Gerät bei eingehenden Anrufen aufzuwecken (nur für manuelle Tests " +
                            "relevant, z.B. tools/push_trigger.py).",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }

            // Status Card
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = if (isProvisioned)
                        MaterialTheme.colorScheme.primaryContainer
                        else MaterialTheme.colorScheme.surfaceContainerHighest
                )
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            if (isProvisioned) "✅ HA-Phone bereit" else "⚠️ Nicht eingerichtet",
                            style = MaterialTheme.typography.titleMedium,
                            color = if (isProvisioned)
                                MaterialTheme.colorScheme.onPrimaryContainer
                                else MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        if (isProvisioned) {
                            Text("✅")
                        }
                    }
                }
            }

            // FCM Token Card
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("FCM Push-Token", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text("📋")
                    }
                    SelectionContainer {
                        Text(
                            fcmToken,
                            style = MaterialTheme.typography.bodySmall,
                            maxLines = 3,
                            
                        )
                    }
                }
            }

            // Actions
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                if (!isProvisioned) {
                    Button(onClick = onSettings, modifier = Modifier.fillMaxWidth()) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.Center
                        ) {
                            Text("⚙️")
                            Spacer(modifier = Modifier.padding(end = 8.dp))
                            Text("SIP-Zugangsdaten eingeben")
                        }
                    }
                }

                Button(
                    onClick = onDial,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = isProvisioned,
                    colors = androidx.compose.material3.ButtonDefaults.buttonColors(
                        containerColor = if (isProvisioned)
                            MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.surfaceContainerHighest
                    )
                ) {
                    Text("Anrufen (Dialpad)", style = MaterialTheme.typography.titleMedium)
                }

                Button(onClick = onSettings, modifier = Modifier.fillMaxWidth()) {
                    Text("Einstellungen", style = MaterialTheme.typography.titleMedium)
                }
            }

            // Footer
            Spacer(modifier = Modifier.padding(top = 24.dp))
            Text(
                "HA-Phone Test v0.1 • BuildConfig: ${BuildConfig.SIP_TEST_HOST}:${BuildConfig.SIP_TEST_PORT}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
        }
    }
}