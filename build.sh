#!/bin/zsh
# Builds build/SharpDisplay.app (universal: Apple Silicon and Intel, ad-hoc signed) and a zip for GitHub Releases.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/SharpDisplay.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
  swiftc -O \
    -target $arch-apple-macos14.0 \
    -o build/SharpDisplay-$arch \
    Sources/SharpDisplay/*.swift
done
lipo -create -output "$APP/Contents/MacOS/SharpDisplay" build/SharpDisplay-arm64 build/SharpDisplay-x86_64
rm build/SharpDisplay-arm64 build/SharpDisplay-x86_64

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

ditto -c -k --keepParent "$APP" build/SharpDisplay.zip
echo "Built $APP"
