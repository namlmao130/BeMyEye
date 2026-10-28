#!/usr/bin/env python3
"""Validate native configuration; bootstrap missing Android template files only.

Never regenerate native source, rewrite Gradle files, or modify the pub cache.
The pinned Flutter SDK supplies launcher resources and the Gradle wrapper in a
temporary project. Existing files are always retained.
"""

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

FLUTTER_VERSION = "3.47.8"
APP_ID = "com.bemyeye.bemyeye_vn"
ACTIVITY = Path("app/src/main/kotlin/com/bemyeye/bemyeye_vn/MainActivity.kt")
ANDROID_NS = "{http://schemas.android.com/apk/res/android}"
SOUNDS = (
    "beep", "beep_left", "beep_center", "beep_right", "step_down",
    "beep_low", "beep_high",
)


def validate_project(project: Path) -> None:
    android = project / "android"
    activity = (android / ACTIVITY).read_text(encoding="utf-8")
    if f"package {APP_ID}" not in activity or '"com.bemyeye/device_health"' not in activity:
        raise RuntimeError("MainActivity package/device health channel is missing")
    manifest = ET.parse(android / "app/src/main/AndroidManifest.xml").getroot()
    activity_node = manifest.find("application/activity")
    if activity_node is None or activity_node.get(ANDROID_NS + "name") != ".MainActivity":
        raise RuntimeError("Manifest does not resolve the custom MainActivity")
    gradle = (android / "app/build.gradle").read_text(encoding="utf-8")
    if f'namespace "{APP_ID}"' not in gradle or f'applicationId "{APP_ID}"' not in gradle:
        raise RuntimeError("Android namespace/applicationId must match MainActivity")

    model = project / "assets/models/mobilenet_ssd.tflite"
    with model.open("rb") as stream:
        if stream.read(8)[4:8] != b"TFL3":
            raise RuntimeError("Model is missing a TensorFlow Lite FlatBuffer header")
    labels = (project / "assets/models/labelmap.txt").read_text(encoding="utf-8").splitlines()
    if len(labels) != 91 or labels[1] != "person" or labels[6] != "bus":
        raise RuntimeError("COCO label map no longer matches the bundled SSD model")
    for sound in SOUNDS:
        with (project / f"assets/sounds/{sound}.wav").open("rb") as stream:
            header = stream.read(12)
        if header[:4] != b"RIFF" or header[8:12] != b"WAVE":
            raise RuntimeError(f"Invalid WAV asset: {sound}")


def copy_missing_platform_files(source: Path, destination: Path) -> None:
    # Explicit allowlist: native Kotlin, manifests, Gradle files and signing
    # settings are owned by this repository, never by `flutter create`.
    files = [
        source / "gradlew", source / "gradlew.bat",
        source / "gradle/wrapper/gradle-wrapper.jar",
    ]
    files.extend((source / "app/src/main/res").rglob("*"))
    for file in files:
        if not file.is_file():
            continue
        target = destination / file.relative_to(source)
        if target.exists():
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(file, target)
        print(f"Added missing Android file: {target.relative_to(destination)}")


def bootstrap(project: Path, flutter: str) -> None:
    validate_project(project)
    result = subprocess.run(
        [flutter, "--version", "--machine"], check=True,
        capture_output=True, text=True,
    )
    version = json.loads(result.stdout)["frameworkVersion"]
    if version != FLUTTER_VERSION:
        raise RuntimeError(f"Use Flutter {FLUTTER_VERSION}; found {version}")

    # tempfile owns only its newly created directory; no checkout is deleted.
    with tempfile.TemporaryDirectory(prefix="bemyeye_android_") as temporary:
        scaffold = Path(temporary) / "scaffold"
        subprocess.run([
            flutter, "create", "--no-pub", "--platforms=android",
            "--org", "com.bemyeye", "--project-name", "bemyeye_vn",
            str(scaffold),
        ], check=True)
        copy_missing_platform_files(scaffold / "android", project / "android")

    required = (
        "gradlew", "gradlew.bat", "gradle/wrapper/gradle-wrapper.jar",
        "gradle/wrapper/gradle-wrapper.properties",
        "app/src/main/res/values/styles.xml",
        "app/src/main/res/mipmap-hdpi/ic_launcher.png",
    )
    for file in required:
        if not (project / "android" / file).is_file():
            raise RuntimeError(f"Missing Android bootstrap file: {file}")
    validate_project(project)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Validate source/assets without SDK or writes")
    parser.add_argument("--flutter", default="flutter", help="Flutter executable (or flutter.bat on Windows)")
    args = parser.parse_args()
    project = Path(__file__).resolve().parent
    if args.check:
        validate_project(project)
    else:
        bootstrap(project, args.flutter)
    print("Android source and bundled assets validated.")


if __name__ == "__main__":
    main()
