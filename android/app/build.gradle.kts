import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The fixed release key lives outside the repo; android/key.properties (never
// committed) points at it. Every build machine with it signs the same app, so
// an APK from any of them installs over another. Without it, builds fall back
// to that machine's debug key.
val releaseKey = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

// android/maps.properties (not committed) holds MAPS_API_KEY, a Google Maps
// SDK key restricted to this app and its release certificate. Without it the
// app still builds; locations then show without a live map.
val mapsKey = Properties().apply {
    val file = rootProject.file("maps.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}.getProperty("MAPS_API_KEY") ?: ""

android {
    namespace = "com.telvox.chat"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications for Java API compatibility.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.telvox.chat"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["mapsApiKey"] = mapsKey
    }

    signingConfigs {
        if (releaseKey.getProperty("storeFile") != null) {
            create("release") {
                storeFile = file(releaseKey.getProperty("storeFile"))
                storePassword = releaseKey.getProperty("storePassword")
                keyAlias = releaseKey.getProperty("keyAlias")
                keyPassword = releaseKey.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
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
    // Videos re-encoded to fit WhatsApp's 16 MB (see VideoCompressor.kt).
    implementation("androidx.media3:media3-transformer:1.11.1")
    implementation("androidx.media3:media3-effect:1.11.1")
    implementation("androidx.media3:media3-common:1.11.1")
}
