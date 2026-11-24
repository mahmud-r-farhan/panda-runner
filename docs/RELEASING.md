# Releasing Panda Runner

Releases are assembled by GitHub Actions. Tag `vX.Y.Z` after the change has been merged to `main`; the workflow
verifies the code, builds every supported downloadable target, and attaches each successful artifact to the GitHub
Release. Running the workflow manually is a dry run: it uploads build artifacts to the workflow run but does not
publish a Release.

## What gets published

| Asset | Built by | Runs on |
| --- | --- | --- |
| `panda-runner-web.zip` | `release.yml` (Ubuntu) | Any static web server / modern browser |
| `PandaRunner-<version>-Android-arm64-v8a.apk` | `release.yml` (Ubuntu) | ARM64 Android devices |
| `PandaRunner-<version>-Android-armeabi-v7a.apk` | `release.yml` (Ubuntu) | 32-bit ARM Android devices |
| `PandaRunner-<version>-Android-x86_64.apk` | `release.yml` (Ubuntu) | x86-64 Android devices/emulators |
| `PandaRunner-<version>-Android.aab` | `release.yml` (Ubuntu, only when signing is configured) | Google Play upload |
| `PandaRunner-<version>-Android-SHA256SUMS.txt` | `release.yml` (Ubuntu) | SHA-256 checksums for Android artifacts |
| `PandaRunner-<version>-Windows-x64.zip` | `release.yml` (`windows-latest`) | 64-bit Windows desktop |
| `PandaRunner-<version>-Windows-x64.zip.sha256` | `release.yml` (`windows-latest`) | SHA-256 checksum for the Windows ZIP |
| `PandaRunner-<version>-macOS-arm64.dmg` | `release.yml` (`macos-latest`) | macOS 12+ on Apple silicon |
| `PandaRunner-<version>-macOS-arm64.zip` | `release.yml` (`macos-latest`) | Same, zipped `.app` for manual install |
| `PandaRunner-<version>-macOS-arm64-SHA256SUMS.txt` | `release.yml` (`macos-latest`) | SHA-256 checksums for the macOS files |
| GitHub Pages site | `pages.yml` | `https://<owner>.github.io/panda-runner/` |

The web build is also deployed to GitHub Pages on every push to `main`, so the playable link tracks the latest `main`.

## Cut a release

1. Bump `version:` in `pubspec.yaml` (the part before `+` is the user-visible version; the part after `+` is the build
   number) and update `CHANGELOG.md`.
2. Open a pull request, let CI pass (including Android and Windows native builds), and merge it to `main`.
3. Tag and push the merged release commit:

   ```bash
   git tag -a v2.2.0 -m "Panda Runner v2.2.0"
   git push origin v2.2.0
   ```

`release.yml` then:

1. Checks out the tag and installs stable Flutter (3.47.1 or newer is required for the Windows Flutter GPU runner).
2. Runs `flutter analyze` and `flutter test`.
3. Builds the web app and packages `panda-runner-web.zip`.
4. Generates/configures the Android and Windows native runners, then builds per-ABI Android APKs and the Windows
   application directory. If Android signing is configured, it also builds a signed Android App Bundle.
5. Builds the macOS app and packages a `.dmg` (with an `Applications` shortcut) and a `.zip` of the `.app`.
6. Creates the GitHub Release for the tag and attaches the assets from every successful platform job.

The web artifact is the only required artifact for publishing. If a native runner fails or is unavailable, the web
release is still published and the missing platform asset is visible in the workflow run.

## Android signing

Android builds work without repository secrets: Flutter's generated Gradle configuration signs the APKs with the
runner's debug key so they can be sideloaded. This is **not** a Play Store signing key and is not stable across hosted
runners; installing an APK from a later unsigned-by-maintainer CI release may require uninstalling the previous app.

For production releases, configure all four repository Actions secrets:

* `ANDROID_KEYSTORE_BASE64` — base64-encoded upload keystore (`.jks`)
* `ANDROID_KEY_ALIAS`
* `ANDROID_KEY_PASSWORD`
* `ANDROID_STORE_PASSWORD`

When all four are present, the workflow signs the APKs with that key and also emits `PandaRunner-<version>-Android.aab`
for Play Console upload. Keep the key and passwords out of the repository; the workflow creates temporary files that
are covered by `.gitignore`. A missing/partial set is handled explicitly rather than silently producing a
mis-signed Play bundle.

## Manual / dry run

`Actions → Release → Run workflow` builds the same artifacts and uploads them to the workflow run, but does **not**
create a GitHub Release (publishing is tag-only). If Android signing secrets are configured, the dry run uses them too.

## Enabling GitHub Pages

`pages.yml` needs Pages configured once:

1. Repository **Settings → Pages → Build and deployment → Source: GitHub Actions**.
2. Push to `main` (or run the *Deploy web* workflow).

The Pages workflow builds with `--base-href "/<repository-name>/"`, which is required for project pages. If you fork
under a different name the workflow derives the base href from `github.event.repository.name`, so it keeps working.

## Signing notes

* **macOS**: the artifacts are unsigned and un-notarized (no Apple Developer account is wired into CI). Players must
  bypass Gatekeeper once: right-click → **Open**, or
  `xattr -dr com.apple.quarantine /Applications/PandaRunner.app`. To ship signed builds, add `MACOS_CERTIFICATE_*`
  secrets, import the certificate into a temporary keychain, pass `--codesign`/notarization steps and keep the same
  artifact names.
* **iOS**: App Store / TestFlight distribution requires your own team ID, provisioning profile and `--export-method`;
  that is intentionally out of scope for this workflow. Build locally with `flutter build ipa`.
* **Windows**: the ZIP is unsigned. Windows may show SmartScreen on first launch; extracting and running the app also
  requires the Microsoft Visual C++ runtime if it is not already installed.
* **Android**: see [Android signing](#android-signing). Play distribution requires the optional upload-key secrets.
* **Linux**: no native Linux artifact is currently built; the web build remains the cross-platform option.

The Android and Windows runner folders are generated from the installed Flutter SDK by `setup.sh` and in the
workflows, then configured by `scripts/configure_native_platforms.py`. This keeps generated Gradle/CMake boilerplate
aligned with Flutter while keeping the GPU flag, branding, and signing policy in one checked-in script. Flutter Scene
supports Android and Windows natively; Windows release builds require Flutter 3.47.1 or newer so the runner can enable
Flutter GPU explicitly.

## Local reproduction

Run `bash setup.sh` once to generate missing platform runners, configure Flutter GPU, fetch dependencies, and run the
tests. Then build on a machine with the relevant native toolchain:

```bash
# Web
flutter build web --release --base-href /
(cd build/web && zip -qr ../../panda-runner-web.zip .)

# Android (requires Android SDK/JDK; per-ABI sideload APKs)
flutter build apk --release --split-per-abi

# Windows (must run on Windows with Visual Studio C++ tools)
flutter build windows --release

# macOS
flutter build macos --release
ditto -c -k --sequesterRsrc --keepParent \
  build/macos/Build/Products/Release/panda_runner.app \
  PandaRunner-macOS-arm64.zip
```

The macOS product name is `panda_runner`; the Finder display name is `Panda Runner` (`CFBundleDisplayName`). The Windows
executable is `panda_runner.exe`; its window title and file description are `Panda Runner`.
