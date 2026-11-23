#!/usr/bin/env bash
# Panda Runner — one-shot setup for a fresh checkout.
#
# Restores the iOS/macOS/web platform folders if they are missing, makes sure
# Flutter GPU is enabled in both Info.plist files, then fetches packages.
# Existing platform files (bundle ids, icons, entitlements) are left untouched.
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo "error: Flutter is not on PATH. Install Flutter 3.47+ stable first:" >&2
  echo "       https://docs.flutter.dev/get-started/install" >&2
  exit 1
fi

echo "==> Flutter $(flutter --version | head -n 1)"
echo "==> Ensuring iOS, macOS and Web platform folders exist..."
flutter create . \
  --platforms=ios,macos,web \
  --project-name panda_runner \
  --org dev.pandarunner >/dev/null

inject_flutter_gpu_plist() {
  local plist="$1"
  [ -f "$plist" ] || return 0
  if grep -q "FLTEnableFlutterGPU" "$plist"; then
    echo "    FLTEnableFlutterGPU already set in $plist"
    return 0
  fi
  echo "    Enabling FLTEnableFlutterGPU in $plist"
  if [ -x /usr/libexec/PlistBuddy ]; then
    /usr/libexec/PlistBuddy -c "Add :FLTEnableFlutterGPU bool true" "$plist"
  else
    python3 - "$plist" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
marker = "</dict>"
idx = text.rfind(marker)
if idx != -1:
    p.write_text(text[:idx] + "\t<key>FLTEnableFlutterGPU</key>\n\t<true/>\n" + text[idx:])
PY
  fi
}

echo "==> Enabling Flutter GPU (Impeller / Metal)..."
inject_flutter_gpu_plist "ios/Runner/Info.plist"
inject_flutter_gpu_plist "macos/Runner/Info.plist"

echo "==> Fetching packages..."
flutter pub get

echo "==> Running tests..."
flutter test

cat <<'EOF'

Ready. Panda Runner targets:

  Web (WebGL2):   flutter run -d chrome
  Web (Wasm):     flutter run -d chrome --wasm
  macOS (Metal):  flutter run -d macos --enable-flutter-gpu
  iOS (Metal):    flutter run -d ios --enable-flutter-gpu

Production builds:

  flutter build web --release --base-href /
  flutter build macos --release

Docs: README.md, docs/ARCHITECTURE.md, docs/RELEASING.md
EOF
