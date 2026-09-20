#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh --universal
APP_VERSION=$(cat VERSION)
ARCHIVE="URL-Parser-${APP_VERSION}-macOS-universal.zip"
codesign --verify --deep --strict 'dist/URL Parser.app'
lipo 'dist/URL Parser.app/Contents/MacOS/URLParser' -verify_arch arm64 x86_64
ditto -c -k --sequesterRsrc --keepParent 'dist/URL Parser.app' "dist/$ARCHIVE"
(cd dist && shasum -a 256 "$ARCHIVE" > SHA256SUMS.txt)
printf 'Release archive: dist/%s\n' "$ARCHIVE"
