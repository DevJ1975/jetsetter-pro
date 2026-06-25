import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ksp)
    alias(libs.plugins.hilt)
}

// ── Secrets ──────────────────────────────────────────────────────────────────
// API keys are read from local.properties (git-ignored) or the environment and
// surfaced to code via BuildConfig. This mirrors the iOS Secrets.xcconfig flow.
// A missing key resolves to "" — services treat an empty key as "not configured"
// and fall back to mock data (see core/secrets/Secrets.kt).
val secretProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun secret(key: String): String = secretProps.getProperty(key) ?: System.getenv(key) ?: ""

val secretKeys = listOf(
    "API_FLIGHTAWARE", "API_ANTHROPIC", "API_GOOGLE_VISION",
    "API_EXPEDIA_CLIENT_ID", "API_EXPEDIA_CLIENT_SECRET",
    "API_AMADEUS_CLIENT_ID", "API_AMADEUS_CLIENT_SECRET", "API_DUFFEL",
    "API_SITA_WORLDTRACER", "API_UBER_SERVER_TOKEN",
    "API_LYFT_CLIENT_ID", "API_LYFT_CLIENT_SECRET",
    "API_ENTERPRISE", "API_HERTZ", "API_NATIONAL",
    "API_FIREBASE_PROJECT_ID", "API_FIREBASE_API_KEY",
    "API_EXPENSIFY_PARTNER_KEY", "API_RAMP_CLIENT_ID", "API_RAMP_CLIENT_SECRET",
    "API_BREX_CLIENT_ID", "API_DIVVY_CLIENT_ID",
)

android {
    namespace = "com.jetsetter.pro"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.jetsetter.pro"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables { useSupportLibrary = true }

        secretKeys.forEach { key ->
            buildConfigField("String", key, "\"${secret(key)}\"")
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            isDebuggable = true
        }
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    // Core + lifecycle
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.core.splashscreen)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.viewmodel.ktx)
    implementation(libs.androidx.activity.compose)

    // Compose (BOM-managed)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material.icons.extended)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.hilt.navigation.compose)

    // Dependency injection
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)

    // Local persistence
    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    ksp(libs.androidx.room.compiler)
    implementation(libs.androidx.datastore.preferences)

    // Networking
    implementation(libs.retrofit)
    implementation(libs.retrofit.converter.moshi)
    implementation(libs.okhttp)
    implementation(libs.okhttp.logging.interceptor)
    implementation(libs.moshi)
    implementation(libs.moshi.kotlin)

    // Async, images, background work
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.coil.compose)
    implementation(libs.androidx.work.runtime.ktx)

    // Test
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.ui.test.junit4)
    debugImplementation(libs.androidx.ui.tooling)
    debugImplementation(libs.androidx.ui.test.manifest)
}
