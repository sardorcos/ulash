import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from CI environment variables (Codemagic sets CM_* when a
// keystore reference is attached) or a local, never-committed key.properties.
// When neither exists the release build FAILS (see below): the debug key is
// never used for a release artifact.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) FileInputStream(file).use { load(it) }
}
fun signingValue(env: String, property: String): String? =
    System.getenv(env)?.takeIf { it.isNotBlank() }
        ?: keyProperties.getProperty(property)?.takeIf { it.isNotBlank() }
val releaseStoreFile = signingValue("CM_KEYSTORE_PATH", "storeFile")
val releaseStorePassword = signingValue("CM_KEYSTORE_PASSWORD", "storePassword")
val releaseKeyAlias = signingValue("CM_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = signingValue("CM_KEY_PASSWORD", "keyPassword")
val hasReleaseSigning = listOf(
    releaseStoreFile, releaseStorePassword, releaseKeyAlias, releaseKeyPassword,
).all { it != null }
// A store build must never be produced unsigned by accident. Pass
// -PallowUnsignedRelease=true only for local experiments.
val allowUnsignedRelease = (findProperty("allowUnsignedRelease") as String?)?.toBoolean() == true
gradle.taskGraph.whenReady {
    val releasePackaging = allTasks.any { task ->
        (task.name.startsWith("assemble") || task.name.startsWith("bundle") ||
            task.name.startsWith("package")) && task.name.endsWith("Release")
    }
    if (releasePackaging && !hasReleaseSigning && !allowUnsignedRelease) {
        throw GradleException(
            "Release signing is not configured (CM_KEYSTORE_* or android/key.properties). " +
                "Refusing to build an unsigned release; use -PallowUnsignedRelease=true to override."
        )
    }
}

android {
    // The Kotlin package and method-channel names keep the historical
    // namespace; the store identity is the applicationId below.
    namespace = "uz.sardor.file_transfer"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Permanent store identity. It must match Google Play and never change.
        applicationId = "uz.ulash.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 29
        targetSdk = 37
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        getByName("debug") {
            // Side-by-side with the store build; debug data never mixes with it.
            applicationIdSuffix = ".debug"
        }
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
            // R8 code shrinking stays off until the release build is verified on
            // devices with every plugin (Keystore, ML Kit scanner, SAF). Turning
            // it on is a separate, tested change.
            isMinifyEnabled = false
            isShrinkResources = false
            // Native symbol tables in the bundle for Play Console crash reports.
            ndk {
                debugSymbolLevel = "SYMBOL_TABLE"
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
