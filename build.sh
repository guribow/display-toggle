#!/bin/bash
# DisplayToggle.app（メニューバー）と displayctl（CLI）を、macOS 13 以降・Apple シリコンと Intel の両対応でビルドし、
# アプリを ~/Applications に入れる。
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build

# macOS 13 以降で動く、Apple シリコンと Intel の両方に対応したユニバーサル形式にする
MIN_OS=13.0
universal() {   # $1 = 出力先、残り = ソース
    local out=$1; shift
    for ARCH in arm64 x86_64; do
        swiftc -O -target "$ARCH-apple-macos$MIN_OS" -o "$out-$ARCH" "$@"
    done
    lipo -create -output "$out" "$out-arm64" "$out-x86_64"
    rm -f "$out-arm64" "$out-x86_64"
}

universal build/displayctl DisplayCore.swift cli/main.swift
codesign --force --sign - build/displayctl

APP=build/DisplayToggle.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp app/Info.plist "$APP/Contents/"
cp icon/AppIcon.icns "$APP/Contents/Resources/"
universal "$APP/Contents/MacOS/DisplayToggle" DisplayCore.swift app/main.swift
codesign --force --sign - "$APP"

mkdir -p ~/Applications
pkill -x DisplayToggle 2>/dev/null && sleep 1 || true
rm -rf ~/Applications/DisplayToggle.app
cp -R "$APP" ~/Applications/
ln -sf "$PWD/build/displayctl" /opt/homebrew/bin/displayctl
echo "built: ~/Applications/DisplayToggle.app, /opt/homebrew/bin/displayctl"
