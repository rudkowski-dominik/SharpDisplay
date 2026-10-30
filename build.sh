#!/bin/zsh
# Builds build/SharpDisplay.app (Apple Silicon, ad-hoc signed) and a zip for GitHub Releases.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/SharpDisplay.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O \
  -target arm64-apple-macos14.0 \
  -o "$APP/Contents/MacOS/SharpDisplay" \
  Sources/SharpDisplay/*.swift

cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

ditto -c -k --keepParent "$APP" build/SharpDisplay.zip
echo "Built $APP"
