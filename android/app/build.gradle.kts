plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.cyto.outstagram"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
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
            manifestPlaceholders["authScheme"] = "com.cyto.outstagram.staging"
        }
        create("prod") {
            dimension = "env"
            resValue("string", "app_name", "Outstagram")
            manifestPlaceholders["authScheme"] = "com.cyto.outstagram"
        }
    }

    buildTypes {
        release {
            // TODO(P7): upload keystore via key.properties. Debug keys for now so release builds run.
            signingConfig = signingConfigs.getByName("debug")
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
