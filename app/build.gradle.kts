plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace="com.pitlanehq.android"
    compileSdk=36
    defaultConfig {
        applicationId="com.pitlanehq.android"
        minSdk=26
        targetSdk=36
        // one version for Pitlane HQ (PC, web, phones): version.txt; "beta" until 1.0.0
        versionCode=33
        versionName=rootProject.file("version.txt").readText().trim() + "-beta"
    }
    // release signing from GitHub secrets (never in the repository); without them CI signs with its debug key
    val ks = System.getenv("ANDROID_KEYSTORE_FILE")
    signingConfigs {
        if (ks != null && file(ks).exists()) create("release") {
            storeFile = file(ks)
            storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("ANDROID_KEY_ALIAS")
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
        }
    }
    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
    compileOptions { sourceCompatibility=JavaVersion.VERSION_17; targetCompatibility=JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget="17" }
    buildFeatures { compose=true; buildConfig=true }
    packaging { resources.excludes += "/META-INF/{AL2.0,LGPL2.1}" }
}

dependencies {
    val composeBom=platform("androidx.compose:compose-bom:2025.09.01")
    implementation(composeBom)
    androidTestImplementation(composeBom)
    implementation("androidx.core:core-ktx:1.17.0")
    implementation("androidx.activity:activity-compose:1.11.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.9.4")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.9.4")
    implementation("androidx.navigation:navigation-compose:2.9.5")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("com.squareup.okhttp3:okhttp:5.2.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    // the lap analysis and the coach of the PC and the web (pitwall-analysis.js), run on the phone
    implementation("androidx.javascriptengine:javascriptengine:1.0.0")
    // tests on the computer (gradle :app:testDebugUnitTest): org.json is Android's, so the tests bring the real one
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20250517")
}
