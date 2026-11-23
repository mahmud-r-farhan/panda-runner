# Releasing Panda Runner

Releases are fully automated by GitHub Actions. A release publishes three
downloadable assets plus a browser build.

## What gets published

| Asset | Built by | Runs on |
| --- | --- | --- |
| `panda-runner-web.zip` | `release.yml` (ubuntu) | any static web server / modern browser |
| `PandaRunner-<version>-macOS-arm64.dmg` | `release.yml` (macos-14) | macOS 12+ on Apple silicon |
| `PandaRunner-<version>-macOS-arm64.zip` | `release.yml` (macos-14) | same, zipped `.app` for manual install |
| GitHub Pages site | `pages.yml` | `https://<owner>.github.io/panda-runner/` |

The web build is also deployed to GitHub Pages on every push to `main`, so the
playable link always tracks the latest `main`.

## Cut a release

1. Bump the version in `pubspec.yaml` (`version: 2.0.0+2` → `2.1.0+3`). The part
   before `+` is the user-visible version, the part after is the build number.
2. Update `CHANGELOG.md`.
3. Commit and merge to `main`.
4. Tag and push:

   ```bash
   git tag -a v2.1.0 -m "Panda Runner v2.1.0"
   git push origin v2.1.0
   ```

`release.yml` then:

1. Checks out the tag and installs the latest stable Flutter.
2. Runs `flutter analyze` and `flutter test` (a release never ships code that
   does not analyse or test clean).
3. Builds the web app and zips `build/web`.
4. Builds the macOS app, packages a `.dmg` (with an `Applications` shortcut) and
   a `.zip` of the `.app`.
5. Creates the GitHub Release for the tag, attaches the assets, and generates
   release notes from the commit history.

## Manual / dry run

`Actions → Release → Run workflow` builds and uploads the same artifacts to the
workflow run, but does **not** create a Release (it only publishes for `v*`
tags). Use it to validate the pipeline before tagging.

## Enabling GitHub Pages

`pages.yml` needs Pages configured once:

1. Repository **Settings → Pages → Build and deployment → Source: GitHub Actions**.
2. Push to `main` (or run the *Deploy web* workflow).

The workflow builds with `--base-href "/<repository-name>/"`, which is required
for project pages. If you fork under a different name the workflow derives the
base href from `github.event.repository.name`, so it keeps working.

## Signing notes

* **macOS**: the artifacts are unsigned and un-notarized (no Apple Developer
  account is wired into CI). Players must bypass Gatekeeper once:
  right-click → **Open**, or `xattr -dr com.apple.quarantine /Applications/PandaRunner.app`.
  To ship signed builds, add `MACOS_CERTIFICATE_*` secrets, import the
  certificate into a temporary keychain, pass `--codesign`/notarization steps and
  keep the same artifact names.
* **iOS**: App Store / TestFlight distribution requires your own team ID,
  provisioning profile and `--export-method`; that is intentionally out of scope
  for this workflow. Build locally with `flutter build ipa`.
* **Windows / Linux / Android**: this repository has no platform folders for
  them, so no native artifacts are produced. The web build is the
  platform-independent fallback and runs on all three.

## Local reproduction

```bash
flutter pub get

# web
flutter build web --release --base-href /
(cd build/web && zip -qr ../../panda-runner-web.zip .)

# macOS
flutter build macos --release
ditto -c -k --sequesterRsrc --keepParent \
  build/macos/Build/Products/Release/panda_runner.app \
  PandaRunner-macOS-arm64.zip
```

The macOS product name is `panda_runner`; the Finder display name is
`Panda Runner` (`CFBundleDisplayName`).
