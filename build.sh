#!/bin/bash
# DisplayToggle.app（メニューバー）と displayctl（CLI）をビルドし、
# アプリを ~/Applications に入れる。
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build

swiftc -O -o build/displayctl DisplayCore.swift cli/main.swift

APP=build/DisplayToggle.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp app/Info.plist "$APP/Contents/"
cp icon/AppIcon.icns "$APP/Contents/Resources/"
swiftc -O -o "$APP/Contents/MacOS/DisplayToggle" DisplayCore.swift app/main.swift
codesign --force --sign - "$APP"

mkdir -p ~/Applications
pkill -x DisplayToggle 2>/dev/null && sleep 1 || true
rm -rf ~/Applications/DisplayToggle.app
cp -R "$APP" ~/Applications/
ln -sf "$PWD/build/displayctl" /opt/homebrew/bin/displayctl
echo "built: ~/Applications/DisplayToggle.app, /opt/homebrew/bin/displayctl"
