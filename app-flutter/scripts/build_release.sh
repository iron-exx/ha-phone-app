#!/usr/bin/env bash
# Release-APKs (pro ABI) + App Bundle. Aufruf auf CCsrv, nicht parallel zu schweren Builds.
set -euo pipefail
cd "$(dirname "$0")/.."
FLUTTER=/home/roto/flutter/flutter/bin/flutter
$FLUTTER build apk --release --split-per-abi --target-platform android-arm64,android-x64
$FLUTTER build appbundle --release --target-platform android-arm64,android-x64
ls -l build/app/outputs/flutter-apk/*-release.apk build/app/outputs/bundle/release/*.aab
grep -q "^storeFile=" android/key.properties 2>/dev/null \
  && echo "signiert mit Release-Key aus key.properties" || echo "WARNUNG: debug-signiert (kein key.properties)"
# Handy-APK mit Version im Namen ablegen (Freigabe Z:\ha-phone-app\no-git\apk).
# Flutter selbst braucht die festen Namen unter build/, darum eine Kopie.
VERSION=$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)
APK_DIR=../no-git/apk
mkdir -p "$APK_DIR"
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "$APK_DIR/HA-Phone-$VERSION-arm64.apk"
ls -l "$APK_DIR/HA-Phone-$VERSION-arm64.apk"
