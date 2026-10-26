# Suppress all missing class warnings from R8 / ProGuard
-ignorewarnings
-dontwarn **

# Google Play Core & Play Store Split / Deferred Components
-dontwarn com.google.android.play.**
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.splitcompat.** { *; }
-keep class com.google.android.play.core.splitinstall.** { *; }

# TensorFlow Lite & tflite_flutter specific rules
-keep class org.tensorflow.lite.** { *; }
-keep class com.google.android.gms.tflite.** { *; }
-dontwarn org.tensorflow.lite.**

# Keep native methods and standard FFI/reflection structures
-keepclassmembers class * {
    native <methods>;
}

# General Flutter embedding rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.common.** { *; }
-keep class io.flutter.plugins.** { *; }
