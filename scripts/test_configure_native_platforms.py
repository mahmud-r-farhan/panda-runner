from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from configure_native_platforms import _configure_android, _configure_windows  # noqa: E402


class ConfigureNativePlatformsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self._write(
            "android/app/src/main/AndroidManifest.xml",
            '''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="panda_runner"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity android:name=".MainActivity" android:exported="true" />
    </application>
</manifest>
''',
        )
        self._write(
            "android/app/build.gradle.kts",
            '''plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.pandarunner.panda_runner"
    defaultConfig {
        applicationId = "dev.pandarunner.panda_runner"
    }
    buildTypes {
        release {
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
''',
        )
        self._write(
            "android/app/src/main/kotlin/dev/pandarunner/panda_runner/MainActivity.kt",
            "package dev.pandarunner.panda_runner\n\nimport io.flutter.embedding.android.FlutterActivity\n\nclass MainActivity : FlutterActivity()\n",
        )
        for density in ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"):
            (self.root / f"android/app/src/main/res/mipmap-{density}").mkdir(parents=True)
            self._write(f"assets/branding/platform/android/mipmap-{density}.png", f"{density} icon")
        self._write(
            "windows/runner/main.cpp",
            '''#include <flutter/dart_project.h>

int APIENTRY wWinMain() {
  flutter::DartProject project(L"data");
  FlutterWindow window(project);
  if (!window.Create(L"panda_runner", origin, size)) {
    return EXIT_FAILURE;
  }
}
''',
        )
        self._write(
            "windows/runner/Runner.rc",
            '''VALUE "FileDescription", "panda_runner" "\\0"
VALUE "ProductName", "panda_runner" "\\0"
''',
        )
        self._write("assets/branding/platform/windows/app_icon.ico", "windows icon")

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def _write(self, relative_path: str, text: str) -> Path:
        path = self.root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def test_native_runner_configuration_is_idempotent(self) -> None:
        _configure_android(self.root)
        _configure_windows(self.root)
        _configure_android(self.root)
        _configure_windows(self.root)

        manifest = (self.root / "android/app/src/main/AndroidManifest.xml").read_text()
        self.assertIn('android:label="Panda Runner"', manifest)
        self.assertIn('android:name="io.flutter.embedding.android.EnableFlutterGPU"', manifest)
        self.assertIn('android:value="true"', manifest)
        self.assertEqual(manifest.count("EnableFlutterGPU"), 1)

        gradle = (self.root / "android/app/build.gradle.kts").read_text()
        self.assertIn('namespace = "dev.pandarunner.game"', gradle)
        self.assertIn('applicationId = "dev.pandarunner.game"', gradle)
        self.assertIn("releaseSigningConfigured", gradle)
        self.assertIn('signingConfig = signingConfigs.getByName("debug")', gradle)
        self.assertEqual(gradle.count("signingConfigs {"), 1)

        activity = self.root / "android/app/src/main/kotlin/dev/pandarunner/game/MainActivity.kt"
        self.assertTrue(activity.is_file())
        self.assertIn("package dev.pandarunner.game", activity.read_text())
        self.assertFalse(
            (self.root / "android/app/src/main/kotlin/dev/pandarunner/panda_runner/MainActivity.kt").exists()
        )
        for density in ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"):
            icon = self.root / f"android/app/src/main/res/mipmap-{density}/ic_launcher.png"
            self.assertEqual(icon.read_text(), f"{density} icon")

        main = (self.root / "windows/runner/main.cpp").read_text()
        self.assertIn("project.set_enable_flutter_gpu(true);", main)
        self.assertEqual(main.count("set_enable_flutter_gpu"), 1)
        self.assertIn('window.Create(L"Panda Runner"', main)
        resources = (self.root / "windows/runner/Runner.rc").read_text()
        self.assertIn('VALUE "FileDescription", "Panda Runner"', resources)
        self.assertIn('VALUE "ProductName", "Panda Runner"', resources)
        self.assertEqual(
            (self.root / "windows/runner/resources/app_icon.ico").read_text(), "windows icon"
        )


if __name__ == "__main__":
    unittest.main()
