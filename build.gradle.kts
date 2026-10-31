plugins {
    id("com.android.application") version "8.13.0" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.2.20" apply false
    // Firebase Cloud Messaging (instant notifications): app/google-services.json, written by the build from a secret
    id("com.google.gms.google-services") version "4.4.4" apply false
}
