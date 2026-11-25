#!/usr/bin/env python3
"""Configure Flutter-generated Android and Windows runners for Panda Runner.

The runner projects are generated with `flutter create` so their Gradle/CMake
boilerplate stays aligned with the installed stable Flutter SDK. This script
applies the small, intentional platform customizations that must survive each
regeneration: Flutter GPU, the app identity/icons, and optional Android release
signing support.
"""

from __future__ import annotations

import re
import shutil
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID_APP_ID = "dev.pandarunner.game"
APP_LABEL = "Panda Runner"
FLUTTER_GPU_METADATA = "io.flutter.embedding.android.EnableFlutterGPU"


def _fail(message: str) -> None:
    raise RuntimeError(message)


def _configure_android(root: Path) -> None:
    android = root / "android"
    manifest_path = android / "app/src/main/AndroidManifest.xml"
    gradle_path = android / "app/build.gradle.kts"
    if not manifest_path.is_file() or not gradle_path.is_file():
        _fail("Android runner is missing; run `flutter create . --platforms=android,windows` first.")

    manifest = manifest_path.read_text(encoding="utf-8")
    label_pattern = re.compile(r'android:label\s*=\s*"[^"]+"')
    manifest, label_count = label_pattern.subn(
        f'android:label="{APP_LABEL}"', manifest, count=1
    )
    if label_count != 1:
        _fail(f"Could not find the Android application label in {manifest_path}.")

    gpu_tag = re.search(
        rf'<meta-data\b(?=[^>]*android:name\s*=\s*"{re.escape(FLUTTER_GPU_METADATA)}")[^>]*/>',
        manifest,
        flags=re.DOTALL,
    )
    if gpu_tag:
        tag = gpu_tag.group(0)
        value_pattern = re.compile(r'android:value\s*=\s*"[^"]+"')
        if value_pattern.search(tag):
            tag = value_pattern.sub('android:value="true"', tag, count=1)
        else:
            tag = re.sub(r"\s*/>$", '\n            android:value="true" />', tag)
        manifest = manifest[: gpu_tag.start()] + tag + manifest[gpu_tag.end() :]
    else:
        application_tag = re.search(r"<application\b[^>]*>", manifest, flags=re.DOTALL)
        if not application_tag:
            _fail(f"Could not find the Android <application> element in {manifest_path}.")
        gpu_metadata = (
            '\n        <meta-data\n'
            f'            android:name="{FLUTTER_GPU_METADATA}"\n'
            '            android:value="true" />'
        )
        manifest = manifest[: application_tag.end()] + gpu_metadata + manifest[application_tag.end() :]

    # Catch malformed XML here rather than letting a native build fail later.
    try:
        ET.fromstring(manifest)
    except ET.ParseError as exc:
        _fail(f"The configured Android manifest is invalid: {exc}")
    manifest_path.write_text(manifest, encoding="utf-8")

    gradle = gradle_path.read_text(encoding="utf-8")
    for field in ("namespace", "applicationId"):
        pattern = re.compile(rf'(?m)^(\s*{field}\s*=\s*)"[^"]+"')
        gradle, count = pattern.subn(rf'\g<1>"{ANDROID_APP_ID}"', gradle, count=1)
        if count != 1:
            _fail(f"Could not set Android {field} in {gradle_path}.")

    # Keep CI/local sideload builds installable with Flutter's debug key. When
    # android/key.properties is present (as on an explicitly signed release),
    # use that private upload key instead. The private key is never committed.
    if "releaseSigningConfigured" not in gradle:
        if "import java.util.Properties" not in gradle:
            gradle = "import java.util.Properties\n\n" + gradle

        signing_values = '''val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties().apply {
    if (keyPropertiesFile.exists()) {
        keyPropertiesFile.inputStream().use { load(it) }
    }
}
val releaseSigningConfigured = keyPropertiesFile.exists()

'''
        android_block = re.search(r"(?m)^android\s*\{", gradle)
        if not android_block:
            _fail(f"Could not find the android block in {gradle_path}.")
        gradle = gradle[: android_block.start()] + signing_values + gradle[android_block.start() :]

        signing_configs = '''    signingConfigs {
        if (releaseSigningConfigured) {
            create("release") {
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
            }
        }
    }

'''
        build_types = re.search(r"(?m)^    buildTypes\s*\{", gradle)
        if not build_types:
            _fail(f"Could not find buildTypes in {gradle_path}.")
        gradle = gradle[: build_types.start()] + signing_configs + gradle[build_types.start() :]

        debug_signing = re.compile(
            r'(?m)^(?P<indent>[ \t]*)signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)\s*$'
        )
        replacement = (
            "{indent}if (releaseSigningConfigured) {{\n"
            "{indent}    signingConfig = signingConfigs.getByName(\"release\")\n"
            "{indent}}} else {{\n"
            "{indent}    signingConfig = signingConfigs.getByName(\"debug\")\n"
            "{indent}}}"
        )
        gradle, count = debug_signing.subn(
            lambda match: replacement.format(indent=match.group("indent")), gradle, count=1
        )
        if count != 1:
            _fail(
                f"Flutter's Android release signing block changed in {gradle_path}; "
                "update the platform configurator before building."
            )
        gradle = gradle.replace(
            "// Signing with the debug keys for now, so `flutter run --release` works.",
            "// Use a configured upload key for releases; otherwise debug-sign for sideload builds.",
        )
        gradle_path.write_text(gradle, encoding="utf-8")

    # Match the existing iOS/macOS application identifier.
    kotlin_roots = android / "app/src/main"
    activities = list(kotlin_roots.rglob("MainActivity.kt")) + list(
        kotlin_roots.rglob("MainActivity.java")
    )
    if not activities:
        _fail(f"Could not find MainActivity under {kotlin_roots}.")
    activity = activities[0]
    source = activity.read_text(encoding="utf-8")
    source, package_count = re.subn(
        r"(?m)^(\s*package\s+)[A-Za-z0-9_.]+(;?)$",
        rf"\g<1>{ANDROID_APP_ID}\2",
        source,
        count=1,
    )
    if package_count != 1:
        _fail(f"Could not update the package declaration in {activity}.")
    destination = kotlin_roots / "kotlin" / Path(*ANDROID_APP_ID.split(".")) / activity.name
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(source, encoding="utf-8")
    if activity.resolve() != destination.resolve():
        activity.unlink()

    icon_sources = root / "assets/branding/platform/android"
    resource_root = android / "app/src/main/res"
    for density in ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"):
        source_icon = icon_sources / f"mipmap-{density}.png"
        destination_icon = resource_root / f"mipmap-{density}/ic_launcher.png"
        if not source_icon.is_file() or not destination_icon.parent.is_dir():
            _fail(f"Android launcher icon resource is missing for {density}.")
        shutil.copyfile(source_icon, destination_icon)


def _configure_windows(root: Path) -> None:
    windows = root / "windows"
    main_path = windows / "runner/main.cpp"
    resource_path = windows / "runner/Runner.rc"
    icon_source = root / "assets/branding/platform/windows/app_icon.ico"
    if not main_path.is_file() or not resource_path.is_file():
        _fail("Windows runner is missing; run `flutter create . --platforms=android,windows` first.")
    if not icon_source.is_file():
        _fail(f"Windows app icon is missing: {icon_source}")

    main = main_path.read_text(encoding="utf-8")
    gpu_call = re.compile(r"(?m)^(\s*)project\.set_enable_flutter_gpu\((?:true|false)\);\s*$")
    if gpu_call.search(main):
        main = gpu_call.sub(r"\1project.set_enable_flutter_gpu(true);", main, count=1)
    else:
        project_line = re.search(
            r'(?m)^(?P<indent>\s*)flutter::DartProject project\(L"data"\);\s*$', main
        )
        if not project_line:
            _fail(f"Could not find the DartProject initialization in {main_path}.")
        insert = project_line.group(0) + "\n" + project_line.group("indent") + "project.set_enable_flutter_gpu(true);"
        main = main[: project_line.start()] + insert + main[project_line.end() :]

    main, title_count = re.subn(
        r'window\.Create\(L"[^"]+"',
        'window.Create(L"Panda Runner"',
        main,
        count=1,
    )
    if title_count != 1:
        _fail(f"Could not set the Windows window title in {main_path}.")
    main_path.write_text(main, encoding="utf-8")

    resources = resource_path.read_text(encoding="utf-8")
    for field in ("FileDescription", "ProductName"):
        resources, count = re.subn(
            rf'(?m)^(\s*VALUE "{field}",\s*)"[^"]+"',
            rf'\g<1>"{APP_LABEL}"',
            resources,
            count=1,
        )
        if count != 1:
            _fail(f"Could not set Windows {field} in {resource_path}.")
    resource_path.write_text(resources, encoding="utf-8")

    icon_destination = windows / "runner/resources/app_icon.ico"
    icon_destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(icon_source, icon_destination)


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    try:
        _configure_android(root)
        _configure_windows(root)
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    print("Configured Android and Windows runners (Flutter GPU, app identity, and icons).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
