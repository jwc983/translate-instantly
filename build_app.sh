#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building release binary..."
swift build -c release

APP="TranslateInstantly.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp .build/release/TranslateInstantly "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/Info.plist"

echo "Signing app..."
# Signed with a stable local self-signed identity (not ad-hoc "-") so macOS
# recognizes it as the same app across rebuilds and Accessibility permission
# survives rebuilds instead of needing to be re-granted every time.
codesign --force --deep --sign "TranslateInstantly Local Dev" --identifier "com.jiangweicheng.translateinstantly" "$APP"

echo "Built $APP"
echo "Run: open $APP"
