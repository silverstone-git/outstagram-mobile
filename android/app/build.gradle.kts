plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.cyto.outstagram"
    // 37: receive_sharing_intent 1.9 requires it (1.8.1 has a JVM-target mismatch). targetSdk is unchanged.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications needs java.time on older Android
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.cyto.outstagram"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // staging -> outsie-staging and installs next to prod. Build with --flavor <name> plus the
    // matching --dart-define-from-file=config/<name>.json
    buildFeatures {
        resValues = true // app_name per flavor
    }
    flavorDimensions += "env"
    productFlavors {
        create("staging") {
            dimension = "env"
            applicationIdSuffix = ".staging"
            resValue("string", "app_name", "Outstagram β")
            resValue("string", "application_id", "com.cyto.outstagram.staging")
            manifestPlaceholders["authScheme"] = "com.cyto.outstagram.staging"
            // Website for App Links (share links, email sign-in); must match WEB_BASE in config/staging.json
            manifestPlaceholders["webLinkHost"] = "aryan.cfd"
            manifestPlaceholders["webLinkBase"] = "/outstagram"
        }
        create("prod") {
            dimension = "env"
            resValue("string", "app_name", "Outstagram")
            resValue("string", "application_id", "com.cyto.outstagram")
            manifestPlaceholders["authScheme"] = "com.cyto.outstagram"
            // Website for App Links (share links, email sign-in); must match WEB_BASE in config/prod.json
            manifestPlaceholders["webLinkHost"] = "outstagram.aryan.cfd"
            manifestPlaceholders["webLinkBase"] = ""
        }
    }

    // TODO(P7): upload keystore via key.properties. Until then release builds use the user's debug key, named
    // by path: on CI, AGP ignored ~/.android/debug.keystore and signed with a fresh random key, so CI APKs
    // couldn't update each other or a local install (QA 2026-11-25). CI sets OUTSTAGRAM_KEYSTORE.
    val sharedKeystore = file(
        System.getenv("OUTSTAGRAM_KEYSTORE") ?: "${System.getProperty("user.home")}/.android/debug.keystore"
    )
    signingConfigs {
        create("shared") {
            storeFile = sharedKeystore
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (sharedKeystore.exists()) "shared" else "debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
