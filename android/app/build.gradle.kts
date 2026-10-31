plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.mesh_messenger_test"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    defaultConfig {
        applicationId = "com.example.mesh_messenger_test"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = "NRN Mesh"
    }

    flavorDimensions += "distribution"
    productFlavors {
        create("nrnPilot") {
            dimension = "distribution"
            applicationIdSuffix = ".nrnpilot"
            manifestPlaceholders["appLabel"] = "NRN Mesh Pilot"
            ndk { abiFilters += setOf("armeabi-v7a", "arm64-v8a", "x86_64") }
        }
    }


    signingConfigs {
        getByName("debug") {
            val testStore = rootProject.file(".nrn-signing/debug.keystore")
            if (testStore.exists()) {
                storeFile = testStore
                storePassword = "android"
                keyAlias = "androiddebugkey"
                keyPassword = "android"
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    jvmToolchain(21)
}

flutter {
    source = "../.."
}