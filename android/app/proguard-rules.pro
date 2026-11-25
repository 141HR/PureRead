# PureRead Android R8 / ProGuard rules

# Preserve attributes and annotations needed by reflection, JNI, and Kotlin
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# PureRead app entry point, MethodChannel, and EventChannel handlers
-keep class com.pureread.pureread.** { *; }

# Flutter engine, embedding, and plugin registrant
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class dev.flutter.** { *; }

# Preserve all JNI native methods and bridge classes
-keepclasseswithmembernames class * {
    native <methods>;
}
-keep class com.github.dart_lang.jni.** { *; }
-keep class com.github.dart_lang.jni_flutter.** { *; }

# SQLite / native library bridge classes
-keep class eu.simonbinder.sqlite3_flutter_libs.** { *; }
-keep class org.sqlite.** { *; }

# Keep @Keep annotated classes and members
-keep @androidx.annotation.Keep class * { *; }
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}

# Kotlin metadata and runtime types used via reflection / JNI
-keep class kotlin.Metadata { *; }
-keep class kotlin.Unit { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.coroutines.** { *; }

# Optional Play Core deferred-component classes referenced by Flutter embedding
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
