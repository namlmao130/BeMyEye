#!/usr/bin/env python3
import os
import re

def configure():
    print(">>> [configure_android.py] Configuring Android files for Be My Eyes VN...")
    base_dir = os.path.dirname(os.path.abspath(__file__))
    android_dir = os.path.join(base_dir, "android")
    
    # 1. Update android/app/build.gradle
    build_gradle_path = os.path.join(android_dir, "app", "build.gradle")
    if os.path.exists(build_gradle_path):
        with open(build_gradle_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Set minSdk / minSdkVersion to 26 (Mandatory for tflite_flutter & modern Android)
        content = re.sub(r'minSdk\s*=\s*\S+', 'minSdk = 26', content)
        content = re.sub(r'minSdkVersion\s*\S+', 'minSdkVersion 26', content)

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

        with open(build_gradle_path, "w", encoding="utf-8") as f:
            f.write(content)
        print("  ✓ Updated android/app/build.gradle (minSdk=26, aaptOptions noCompress tflite)")
    else:
        print("  ! android/app/build.gradle not found!")

    # 2. Update AndroidManifest.xml
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

    # 3. Update gradle.properties
    props_path = os.path.join(android_dir, "gradle.properties")
    with open(props_path, "a", encoding="utf-8") as f:
        f.write("\norg.gradle.jvmargs=-Xmx4G -XX:MaxMetaspaceSize=2G\nandroid.useAndroidX=true\nandroid.enableJetifier=true\n")
    print("  ✓ Updated android/gradle.properties (JVM args 4G)")

    print(">>> [configure_android.py] Android configuration complete!")

if __name__ == "__main__":
    configure()
