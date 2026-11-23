#!/usr/bin/env bash
set -euo pipefail

echo "==> Generating iOS, macOS, and Web platform stubs..."
flutter create . --platforms=ios,macos,web --project-name neon_scramble

inject_flutter_gpu_plist() {
  local plist="$1"
  if [ -f "$plist" ]; then
    if grep -q "FLTEnableFlutterGPU" "$plist"; then
      echo "    FLTEnableFlutterGPU already present in $plist"
    else
      echo "    Enabling FLTEnableFlutterGPU in $plist"
      /usr/libexec/PlistBuddy -c "Add :FLTEnableFlutterGPU bool true" "$plist" 2>/dev/null || \
      python3 - "$plist" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
marker = "</dict>"
idx = text.rfind(marker)
if idx != -1:
    insert = "\t<key>FLTEnableFlutterGPU</key>\n\t<true/>\n"
    p.write_text(text[:idx] + insert + text[idx:])
PY
    fi
  fi
}

inject_flutter_gpu_plist "ios/Runner/Info.plist"
inject_flutter_gpu_plist "macos/Runner/Info.plist"

echo "==> Fetching dependencies..."
flutter pub get

echo ""
echo "Ready! Run Neon Scramble on any target:"
echo "  Web (WebGL2):   flutter run -d chrome"
echo "  Web (Skwasm):   flutter run -d chrome --wasm"
echo "  macOS (Metal):  flutter run -d macos --enable-flutter-gpu"
echo "  iOS (Metal):    flutter run -d ios --enable-flutter-gpu"
