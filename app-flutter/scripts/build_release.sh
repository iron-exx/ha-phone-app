#!/usr/bin/env bash
# Release-APKs (pro ABI) + App Bundle. Aufruf auf CCsrv, nicht parallel zu schweren Builds.
set -euo pipefail
cd "$(dirname "$0")/.."
FLUTTER=/home/roto/flutter/flutter/bin/flutter
$FLUTTER build apk --release --split-per-abi --target-platform android-arm64,android-x64
$FLUTTER build appbundle --release --target-platform android-arm64,android-x64
ls -l build/app/outputs/flutter-apk/*-release.apk build/app/outputs/bundle/release/*.aab
grep -q "no-git/release" android/key.properties 2>/dev/null \
  && echo "signiert mit Upload-Key" || echo "WARNUNG: debug-signiert (kein key.properties)"
