#!/usr/bin/env python3
import os
import re

PROGUARD_RULES = """# Suppress all missing class warnings from R8 / ProGuard
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
"""

def configure():
    print(">>> [configure_android.py] Configuring Android files for Be My Eyes VN...")
    base_dir = os.path.dirname(os.path.abspath(__file__))
    android_dir = os.path.join(base_dir, "android")
    
    # 1. Update android/app/build.gradle
    build_gradle_path = os.path.join(android_dir, "app", "build.gradle")
    if os.path.exists(build_gradle_path):
        with open(build_gradle_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Set compileSdk / targetSdk to 36 (Mandatory for flutter_tts & audioplayers)
        content = re.sub(r'compileSdk\s*=\s*\S+', 'compileSdk = 36', content)
        content = re.sub(r'compileSdkVersion\s*\S+', 'compileSdkVersion 36', content)
        content = re.sub(r'targetSdk\s*=\s*\S+', 'targetSdk = 36', content)
        content = re.sub(r'targetSdkVersion\s*\S+', 'targetSdkVersion 36', content)

        # Set minSdk / minSdkVersion to 26 (Mandatory for tflite_flutter & modern Android)
        content = re.sub(r'minSdk\s*=\s*\S+', 'minSdk = 26', content)
        content = re.sub(r'minSdkVersion\s*\S+', 'minSdkVersion 26', content)

        # Force Java 17 and Kotlin JVM Target 17
        content = content.replace("JavaVersion.VERSION_1_8", "JavaVersion.VERSION_17")
        content = content.replace("jvmTarget = '1.8'", "jvmTarget = '17'")
        content = content.replace('jvmTarget = "1.8"', 'jvmTarget = "17"')

        # Ensure aaptOptions noCompress for .tflite
        if "aaptOptions" not in content and "noCompress" not in content:
            aapt_block = """
    aaptOptions {
        noCompress 'tflite'
        noCompress 'lite'
    }
"""
            if "buildTypes {" in content:
                content = content.replace("buildTypes {", aapt_block + "\n    buildTypes {", 1)
            else:
                content = content.replace("android {", "android {\n" + aapt_block, 1)

        # Configure release build to use debug signing and link proguard-rules.pro
        release_block = """    buildTypes {
        release {
            signingConfig signingConfigs.debug
            minifyEnabled false
            shrinkResources false
            proguardFiles getDefaultProguardFile('proguard-android.txt'), 'proguard-rules.pro'
        }
    }"""
        if "buildTypes {" in content:
            content = re.sub(r'buildTypes\s*\{.*?\n    \}', release_block, content, flags=re.DOTALL)
            if "proguardFiles" not in content:
                content = content.replace("buildTypes {", release_block + "\n    /* original: buildTypes */", 1)

        with open(build_gradle_path, "w", encoding="utf-8") as f:
            f.write(content)
        print("  ✓ Updated android/app/build.gradle (compileSdk=36, targetSdk=36, minSdk=26, Java/Kotlin=17, aaptOptions, proguardFiles)")
    else:
        print("  ! android/app/build.gradle not found!")

    # 2. Update root android/build.gradle to force Java 17 and compileSdkVersion 36 on all subprojects (tflite_flutter, etc.)
    root_gradle_path = os.path.join(android_dir, "build.gradle")
    if os.path.exists(root_gradle_path):
        with open(root_gradle_path, "r", encoding="utf-8") as f:
            root_content = f.read()

        subprojects_block = """
// Force Java 17 and compileSdkVersion 36 across all plugins and subprojects
subprojects {
    afterEvaluate { project ->
        if (project.hasProperty('android')) {
            project.android {
                compileSdkVersion 36
                compileOptions {
                    sourceCompatibility JavaVersion.VERSION_17
                    targetCompatibility JavaVersion.VERSION_17
                }
            }
        }
        tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile).configureEach {
            kotlinOptions {
                jvmTarget = '17'
            }
        }
    }
}
"""
        if "jvmTarget = '17'" not in root_content:
            root_content += "\n" + subprojects_block
            with open(root_gradle_path, "w", encoding="utf-8") as f:
                f.write(root_content)
            print("  ✓ Updated android/build.gradle (enforced Java 17 across all subprojects)")
    else:
        print("  ! android/build.gradle not found!")

    # 3. Write proguard-rules.pro
    proguard_path = os.path.join(android_dir, "app", "proguard-rules.pro")
    with open(proguard_path, "w", encoding="utf-8") as f:
        f.write(PROGUARD_RULES)
    print("  ✓ Created android/app/proguard-rules.pro")

    # 4. Update AndroidManifest.xml
    manifest_path = os.path.join(android_dir, "app", "src", "main", "AndroidManifest.xml")
    if os.path.exists(manifest_path):
        with open(manifest_path, "r", encoding="utf-8") as f:
            manifest = f.read()

        permissions = """
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.VIBRATE" />
    <uses-feature android:name="android.hardware.camera" android:required="false" />
    <uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />
"""
        if "android.permission.CAMERA" not in manifest:
            manifest = manifest.replace("<application", permissions.strip() + "\n\n    <application", 1)
            with open(manifest_path, "w", encoding="utf-8") as f:
                f.write(manifest)
            print("  ✓ Injected permissions into AndroidManifest.xml")
        else:
            print("  ✓ Permissions already present in AndroidManifest.xml")
    else:
        print("  ! AndroidManifest.xml not found!")

    # 5. Update gradle.properties
    props_path = os.path.join(android_dir, "gradle.properties")
    props_content = ""
    if os.path.exists(props_path):
        with open(props_path, "r", encoding="utf-8") as f:
            props_content = f.read()
    if "uniquePackageNames" not in props_content:
        with open(props_path, "a", encoding="utf-8") as f:
            f.write("\norg.gradle.jvmargs=-Xmx4G -XX:MaxMetaspaceSize=2G\nandroid.useAndroidX=true\nandroid.enableJetifier=true\nkotlin.jvm.target.validation.mode=warning\nandroid.suppressUnsupportedCompileSdk=36\nandroid.uniquePackageNames=false\n")
        print("  ✓ Updated android/gradle.properties (JVM args 4G, uniquePackageNames=false)")
    else:
        print("  ✓ android/gradle.properties already configured")

    print(">>> [configure_android.py] Android configuration complete!")

if __name__ == "__main__":
    configure()
