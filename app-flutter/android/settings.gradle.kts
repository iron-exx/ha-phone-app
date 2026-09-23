pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in android/local.properties" }
        flutterSdkPath
    }
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // Versions pinned to match android-app/build.gradle.kts, the baseline
    // sip-core and the rest of the dependency graph were built/verified
    // against.
    id("com.android.application") version "8.5.2" apply false
    id("com.android.library") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "2.0.20" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.20" apply false
    id("com.google.gms.google-services") version "4.4.2" apply false
}

// Dependency repositories are declared in build.gradle.kts's `allprojects`
// block, not here -- declaring dependencyResolutionManagement in BOTH
// places risks a Gradle repositoriesMode conflict.
rootProject.name = "app_flutter_android"
include(":app")
// PJSUA2 SIP core, physically copied from android-app/sip-core (its payload
// is gitignored there -- see app-flutter/android/sip-core/.gitignore --
// so there is no git-resolvable relative path back to the old module).
include(":sip-core")
