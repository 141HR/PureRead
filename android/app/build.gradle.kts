import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.pureread.pureread"
    compileSdk = flutter.compileSdkVersion
    val androidSdkPath = System.getenv("ANDROID_HOME")
        ?: System.getenv("ANDROID_SDK_ROOT")
        ?: rootProject.file("local.properties").takeIf { it.exists() }?.let { propFile ->
            Properties().apply { propFile.inputStream().use { load(it) } }.getProperty("sdk.dir")
        }
    val installedNdks = androidSdkPath
        ?.let { File(it, "ndk").listFiles()?.filter { d -> d.isDirectory && File(d, "source.properties").exists() }?.map { d -> d.name }?.sorted() }
        .orEmpty()
    ndkVersion = if (installedNdks.isEmpty() || installedNdks.contains(flutter.ndkVersion)) {
        flutter.ndkVersion
    } else {
        installedNdks.last()
    }
    val installedBuildTools = androidSdkPath
        ?.let { File(it, "build-tools").listFiles()?.filter { d -> d.isDirectory && File(d, "source.properties").exists() }?.map { d -> d.name }?.sorted() }
        .orEmpty()
    val preferredBuildTools = installedBuildTools.lastOrNull { it.startsWith("${flutter.compileSdkVersion}.") }
    if (preferredBuildTools != null) {
        buildToolsVersion = preferredBuildTools
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.pureread.app"
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

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
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
