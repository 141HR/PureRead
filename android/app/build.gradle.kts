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

    val keyPropertiesFile = rootProject.file("key.properties")
    val releaseSigningConfig = if (keyPropertiesFile.exists()) {
        val keyProperties = Properties().apply {
            keyPropertiesFile.inputStream().use { load(it) }
        }
        val storeFilePath = keyProperties.getProperty("storeFile")?.trim()
        val storePasswordValue = keyProperties.getProperty("storePassword")?.trim()
        val keyAliasValue = keyProperties.getProperty("keyAlias")?.trim()
        val keyPasswordValue = keyProperties.getProperty("keyPassword")?.trim()
        if (
            !storeFilePath.isNullOrEmpty() &&
            !storePasswordValue.isNullOrEmpty() &&
            !keyAliasValue.isNullOrEmpty() &&
            !keyPasswordValue.isNullOrEmpty()
        ) {
            signingConfigs.create("release") {
                storeFile = rootProject.file(storeFilePath)
                storePassword = storePasswordValue
                keyAlias = keyAliasValue
                keyPassword = keyPasswordValue
            }
        } else {
            null
        }
    } else {
        null
    }

    buildTypes {
        release {
            signingConfig = releaseSigningConfig ?: signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
