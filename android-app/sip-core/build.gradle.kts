plugins {
    id("com.android.library")
}
android {
    namespace = "org.pjsip.pjsua2"
    compileSdk = 35
    defaultConfig { minSdk = 26 }
    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/java")
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
