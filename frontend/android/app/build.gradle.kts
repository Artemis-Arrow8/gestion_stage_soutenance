import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// La signature release provient d'un fichier local ignoré par Git.
val signingPropertiesFile = rootProject.file("key.properties")
val signingProperties = Properties()
if (signingPropertiesFile.exists()) {
    signingPropertiesFile.inputStream().use(signingProperties::load)
}

val releaseTaskRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
val signingPropertyNames = listOf(
    "storeFile",
    "keyAlias",
    "storePassword",
    "keyPassword",
)
val missingSigningProperties = signingPropertyNames.filter { name ->
    val value = signingProperties.getProperty(name)?.trim()
    value.isNullOrEmpty() || value.startsWith("REMPLACER")
}
val releaseKeystorePath = signingProperties.getProperty("storeFile")?.trim()
val releaseKeystore = releaseKeystorePath?.let(rootProject::file)

if (releaseTaskRequested && missingSigningProperties.isNotEmpty()) {
    throw GradleException(
        "Signature release manquante : compléter frontend/android/key.properties " +
            "à partir de key.properties.example."
    )
}
if (releaseTaskRequested && releaseKeystore?.exists() != true) {
    throw GradleException(
        "Keystore release introuvable. Vérifier la propriété storeFile dans key.properties."
    )
}

android {
    namespace = "com.artemisarrow8.sgsus"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Identifiant stable de l'application Android SGSUS.
        applicationId = "com.artemisarrow8.sgsus"
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
    }

    signingConfigs {
        if (missingSigningProperties.isEmpty() && releaseKeystore != null) {
            create("release") {
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
                storeFile = releaseKeystore
                storePassword = signingProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (missingSigningProperties.isEmpty() && releaseKeystore != null) {
                signingConfig = signingConfigs.getByName("release")
            }
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
