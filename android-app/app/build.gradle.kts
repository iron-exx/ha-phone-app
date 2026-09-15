import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("com.google.gms.google-services")
}

// Phase 2 (02-04): the real HA-Phone test-extension host/port/username/password
// (Plan 01's checkpoint output) is read from the already-gitignored
// local.properties (see root .gitignore's existing "android-app/local.properties"
// entry, established in Phase 1) and compiled into BuildConfig fields --
// NOT hardcoded as Kotlin string literals in tracked source. Kotlin security
// rule ("Never hardcode API keys, tokens, or credentials in source code...
// use local.properties for local development secrets, BuildConfig fields
// generated from CI secrets for release builds") applies directly here: this
// repo has a public GitHub remote, and a real LAN PBX password committed to
// git history is effectively permanent exposure even after rotation. Falls
// back to an empty string (not a placeholder token) if unset, so a fresh
// checkout still compiles; HAPhoneTestApplication.kt handles the empty case
// explicitly at runtime (SIP registration is a no-op until configured).
val localProperties = Properties().apply {
    val localPropsFile = rootProject.file("local.properties")
    if (localPropsFile.exists()) {
        localPropsFile.inputStream().use { load(it) }
    }
}
fun sipTestProperty(key: String): String = localProperties.getProperty(key, "")

android {
    namespace = "de.haphone.app.test"
    compileSdk = 35
    defaultConfig {
        applicationId = "de.haphone.app.test"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
        multiDexEnabled = true
        buildConfigField("String", "SIP_TEST_HOST", "\"${sipTestProperty("sip.test.host")}\"")
        buildConfigField("String", "SIP_TEST_PORT", "\"${sipTestProperty("sip.test.port")}\"")
        buildConfigField("String", "SIP_TEST_USERNAME", "\"${sipTestProperty("sip.test.username")}\"")
        buildConfigField("String", "SIP_TEST_PASSWORD", "\"${sipTestProperty("sip.test.password")}\"")
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    dexOptions {
        javaMaxHeapSize = "2g"
    }
}
dependencies {
    implementation(project(":sip-core"))
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.core:core-telecom:1.0.0")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation(platform("androidx.compose:compose-bom:2024.09.00"))
    implementation("androidx.compose.material3:material3")
    implementation("com.google.firebase:firebase-messaging-ktx:24.0.1")
    implementation("com.google.crypto.tink:tink-android:1.14.1")

    // Multidex for large dependency count
    implementation("androidx.multidex:multidex:2.0.1")

    // QR Code Scanning (CameraX + ML Kit)
    implementation("androidx.camera:camera-core:1.4.0")
    implementation("androidx.camera:camera-camera2:1.4.0")
    implementation("androidx.camera:camera-view:1.4.0")
    implementation("androidx.camera:camera-lifecycle:1.4.0")
    implementation("com.google.mlkit:barcode-scanning:17.2.0")

    // Networking (for provisioning API calls)
    implementation("com.squareup.retrofit2:retrofit:2.11.0")
    implementation("com.squareup.retrofit2:converter-moshi:2.11.0")
    implementation("com.squareup.moshi:moshi-kotlin:1.15.1")
    implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    // Secure storage
    implementation("androidx.security:security-crypto:1.1.0-alpha06")

    testImplementation("junit:junit:4.13.2")
}
