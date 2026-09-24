package de.haphone.app.test

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys

/**
 * The encrypted store for SIP credentials and the device secret (QR pairing).
 *
 * Created once and cached: opening EncryptedSharedPreferences loads the Keystore master
 * key and the Tink keysets, which is slow and ran on the main thread on every
 * hasValidCredentials() before.
 *
 * Self-healing: if the data cannot be decrypted (restored/transferred from another
 * device, Keystore key lost after a lock-screen reset, corrupted file:
 * AEADBadTagException / GeneralSecurityException / "Could not decrypt value"), the store
 * is wiped and recreated instead of crashing on every start. The user then has to pair
 * again, which is the only way to get valid credentials on this device anyway. Backup and
 * device transfer are also disabled for the whole app (manifest allowBackup=false +
 * data_extraction_rules.xml), so this should only happen after a Keystore loss.
 */
object SecurePrefs {
    private const val TAG = "SecurePrefs"
    private const val FILE = "haphone_prefs"

    @Volatile private var cached: SharedPreferences? = null

    fun get(context: Context): SharedPreferences {
        cached?.let { return it }
        return synchronized(this) {
            cached ?: open(context.applicationContext).also { cached = it }
        }
    }

    /** Runs [block] on the store; a decryption failure wipes it once and retries. */
    fun <T> read(context: Context, block: (SharedPreferences) -> T): T = try {
        block(get(context))
    } catch (e: SecurityException) {
        Log.e(TAG, "stored value undecryptable, resetting secure prefs", e)
        reset(context)
        block(get(context))
    }

    private fun open(context: Context): SharedPreferences = try {
        create(context)
    } catch (e: Exception) {
        // GeneralSecurityException (incl. AEADBadTagException), IOException, KeyStoreException...
        Log.e(TAG, "secure prefs unreadable (${e.javaClass.simpleName}), resetting", e)
        wipe(context)
        create(context)
    }

    private fun reset(context: Context) = synchronized(this) {
        cached = null
        wipe(context.applicationContext)
    }

    private fun wipe(context: Context) {
        runCatching { context.deleteSharedPreferences(FILE) }
            .onFailure { Log.w(TAG, "could not delete $FILE", it) }
    }

    private fun create(context: Context): SharedPreferences = EncryptedSharedPreferences.create(
        FILE,
        MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC),
        context,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )
}
