#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP_VERSION=$(cat VERSION)
APP="$PWD/dist/URL Parser.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ "${1:-}" == "--universal" ]]; then
  swift build -c release -Xswiftc -Osize --arch arm64
  swift build -c release -Xswiftc -Osize --arch x86_64
  ARM_BIN=$(swift build -c release -Xswiftc -Osize --arch arm64 --show-bin-path)
  INTEL_BIN=$(swift build -c release -Xswiftc -Osize --arch x86_64 --show-bin-path)
  lipo -create "$ARM_BIN/URLParser" "$INTEL_BIN/URLParser" -output "$APP/Contents/MacOS/URLParser"
elif [[ -z "${1:-}" ]]; then
  swift build -c release -Xswiftc -Osize
  BIN=$(swift build -c release -Xswiftc -Osize --show-bin-path)
  cp "$BIN/URLParser" "$APP/Contents/MacOS/URLParser"
else
  printf 'Usage: %s [--universal]\n' "$0" >&2
  exit 1
fi
./scripts/build-icon.sh
cp .build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>URLParser</string>
<key>CFBundleIdentifier</key><string>dev.local.urlparser</string>
<key>CFBundleName</key><string>URL Parser</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${APP_VERSION}</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
strip -x "$APP/Contents/MacOS/URLParser"
codesign --force --sign - "$APP"
printf 'Built: %s\n' "$APP"
