import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// Optional release signing. Create android/keystore.properties (git-ignored) with:
//   storeFile=C:/dev/keys/brewlog.jks
//   storePassword=…
//   keyAlias=brewlog
//   keyPassword=…
val keystoreProperties = Properties().apply {
    val file = rootProject.file("keystore.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "com.brewlog.app"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.brewlog.app"
        minSdk = 26
        targetSdk = 36
        versionCode = System.getenv("VERSION_CODE")?.toIntOrNull() ?: 1
        versionName = System.getenv("VERSION_NAME") ?: "0.1"
        buildConfigField("String", "RELEASE_REPO", "\"${System.getenv("RELEASE_REPO") ?: "proelio57/BrewLog"}\"")
    }

    signingConfigs {
        if (!keystoreProperties.isEmpty) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            if (!keystoreProperties.isEmpty) signingConfig = signingConfigs.getByName("release")
        }
    }

    // The built-in recipes come straight from ../../Shared/recipes.json, the same file as iOS and web.
    sourceSets {
        getByName("main") {
            assets.srcDir("../../Shared")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material.icons.extended)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.kotlinx.serialization.json)
    // WebSocket to the espresso machine (GaggiMate) in the local network.
    implementation(libs.okhttp)
    // "Ask Claude" for a bean (opt-in, the user's own API key).
    implementation(libs.anthropic.java)
    debugImplementation(libs.androidx.ui.tooling)

    testImplementation(libs.junit)
}
