plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.arenaos.arena_os"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.arenaos.arena_os"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Three flavours, one per Supabase project (D34).
    //
    // Distinct application ids let development, staging, and production be
    // installed side by side on the same tablet, so a staff device being
    // tested against staging can never be confused with the one taking real
    // money. Supabase URL and anon key are NOT set here — they arrive via
    // --dart-define-from-file at build time and are never committed.
    flavorDimensions += "environment"

    productFlavors {
        create("development") {
            dimension = "environment"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            resValue("string", "app_name", "Arena OS dev")
        }
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".stg"
            versionNameSuffix = "-stg"
            resValue("string", "app_name", "Arena OS stg")
        }
        create("production") {
            dimension = "environment"
            // No suffix: this is the real application id.
            resValue("string", "app_name", "Arena OS")
        }
    }

    buildTypes {
        release {
            // TODO(M7): replace with the production upload keystore before the
            // pilot. Signing config must come from CI secrets, never a file in
            // this repository (D37).
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
