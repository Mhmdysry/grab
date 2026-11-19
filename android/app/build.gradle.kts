import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.grab.grab"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "app.grab.grab.expressive"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release signing comes from android/key.properties if present, otherwise
    // uses the committed android/app/expressive-release.jks so every CI and local
    // build shares the exact same certificate and can update in place on Android.
    val keyProps = Properties().apply {
        val f = rootProject.file("key.properties")
        if (f.exists()) f.inputStream().use { load(it) }
    }
    signingConfigs {
        create("release") {
            if (keyProps.getProperty("storeFile") != null) {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            } else {
                storeFile = file("expressive-release.jks")
                storePassword = "grabexpressive"
                keyAlias = "grab_expressive"
                keyPassword = "grabexpressive"
            }
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            // youtubedl-android ships zip archives named *.so; they are not ELF files, so don't strip them.
            keepDebugSymbols += listOf("**/*.zip.so")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // youtubedl-android uses reflection (Jackson); shrinking would break it.
            isMinifyEnabled = false
            isShrinkResources = false
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

val youtubedlAndroid = "0.18.1"

dependencies {
    implementation("io.github.junkfood02.youtubedl-android:library:$youtubedlAndroid")
    implementation("io.github.junkfood02.youtubedl-android:ffmpeg:$youtubedlAndroid")
    implementation("androidx.core:core-ktx:1.13.1")
}
