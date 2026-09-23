import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("org.jetbrains.kotlin.plugin.compose")
    id("com.google.gms.google-services")
}

// Dev SIP test-extension credentials -- deliberately NOT android/local.properties
// (Flutter's tooling auto-writes/overwrites that file with sdk.dir/flutter.sdk
// on every `flutter pub get`/IDE sync; reusing it for secrets risks them
// being clobbered). Gitignored; sip-secrets.local.properties.example is the
// tracked template. Falls back to an empty string if unset so a fresh
// checkout still compiles -- HAPhoneTestApplication handles the empty case
// (SIP registration becomes a no-op until Settings/QR provisioning fills it in).
val sipSecrets = Properties().apply {
    val f = rootProject.file("app/sip-secrets.local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun sipTestProperty(key: String): String = sipSecrets.getProperty(key, "")

android {
    namespace = "de.haphone.app.test"
    compileSdk = 35

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "de.haphone.app.test"
        // Hard requirement, not the Flutter template's default floor:
        // androidx.core:core-telecom's self-managed ConnectionService +
        // MANAGE_OWN_CALLS need API 26+.
        minSdk = 26
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        buildConfigField("String", "SIP_TEST_HOST", "\"${sipTestProperty("sip.test.host")}\"")
        buildConfigField("String", "SIP_TEST_PORT", "\"${sipTestProperty("sip.test.port")}\"")
        buildConfigField("String", "SIP_TEST_USERNAME", "\"${sipTestProperty("sip.test.username")}\"")
        buildConfigField("String", "SIP_TEST_PASSWORD", "\"${sipTestProperty("sip.test.password")}\"")
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    buildTypes {
        release {
            // TODO before any real release build: a dedicated release
            // signing config. Debug signing is fine for the Phase 1
            // demo/dev-loop target this plan scopes to.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Reused native SIP/Telecom layer.
    implementation(project(":sip-core"))
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.core:core-telecom:1.0.0")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    implementation("com.google.firebase:firebase-messaging-ktx:24.0.1")
    implementation("com.google.crypto.tink:tink-android:1.14.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    // Compose stays, scoped to the one native screen that still uses it
    // (IncomingCallActivity) -- see that file's doc comment for why it's
    // deliberately not a FlutterActivity.
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation(platform("androidx.compose:compose-bom:2024.09.00"))
    implementation("androidx.compose.material3:material3")

    // Deliberately NOT carried over from android-app/app/build.gradle.kts:
    // CameraX, ML Kit barcode-scanning, Retrofit, Moshi, OkHttp
    // logging-interceptor -- all were added for the QR-provisioning
    // feature that was never implemented and is out of scope for this
    // phase. Re-add when that work is actually tackled.

    testImplementation("junit:junit:4.13.2")
}
