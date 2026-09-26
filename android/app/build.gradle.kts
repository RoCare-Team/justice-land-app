import java.io.FileInputStream
import java.util.Properties

// Upload-key details, kept out of the repository. `android/.gitignore` already
// covers key.properties and *.jks, so neither the passwords nor the keystore
// can be committed by accident. Without the file the release build falls back
// to the debug key, which keeps `flutter run --release` working on a machine
// that has no keystore — but Play rejects anything signed that way, so a real
// release needs the file.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}


val   = keystoreProperties.containsKey("storeFile")

// Firebase (push notifications — see lib/services/push_service.dart) reads its
// project config from this file, which is not committed (real credentials).
// Applying the plugin without it present fails the whole build, so it is
// applied further down only once the file has actually landed here — until
// then the app builds and runs exactly as it did before pushes were added,
// just without them.
val hasFirebaseConfig = file("google-services.json").exists()

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

if (hasFirebaseConfig) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.justiceland.care"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        if (hasUploadKey) {
            create("upload") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.justiceland.care"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // The upload key when key.properties is present, the debug key when
            // it is not. Play will not take a debug-signed upload, so check the
            // signer before you upload: apksigner verify --print-certs should
            // name you, not "CN=Android Debug".
            signingConfig = signingConfigs.getByName(if (hasUploadKey) "upload" else "debug")

            // Razorpay's WebView bridge and libwebrtc both break under an
            // unconfigured R8 pass — see proguard-rules.pro.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}
