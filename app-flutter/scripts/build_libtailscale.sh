#!/usr/bin/env bash
# Baut libtailscale (Go-Backend von tailscale-android) als gomobile-AAR und
# legt es in app-flutter/android/tailscale-core/libs/ ab.
#
# Go wird NICHT vorausgesetzt: tailscale-android bringt mit tool/go einen
# eigenen, gepinnten Go-Toolchain mit (Download nach ~/.cache/tailscale-go).
#
# Aufruf (auf CCsrv, nicht parallel zum Emulator):
#   bash app-flutter/scripts/build_libtailscale.sh
# Variablen:
#   TS_ANDROID_DIR   Checkout von tailscale-android (Standard ~/src/tailscale-android)
#   TS_ANDROID_REV   gepinnter Commit (Standard siehe unten)
#   ANDROID_HOME     Android SDK (Standard ~/android-sdk, NDK = höchste Version dort)
set -euo pipefail

TS_ANDROID_REV="${TS_ANDROID_REV:-803d93860da0652d501298883fcc61c70973290b}"
TS_ANDROID_DIR="${TS_ANDROID_DIR:-$HOME/src/tailscale-android}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)/android/tailscale-core/libs"

if [[ ! -d "$TS_ANDROID_DIR/.git" ]]; then
    git clone https://github.com/tailscale/tailscale-android.git "$TS_ANDROID_DIR"
fi
cd "$TS_ANDROID_DIR"
git fetch --quiet origin
git checkout --quiet "$TS_ANDROID_REV"

# Alte Artefakte weg, sonst hält make ein veraltetes AAR für aktuell.
rm -f android/libs/libtailscale.aar android/libs/libtailscale_unstripped.aar \
      libgojni.so.unstripped libgojni.so.stripped libgojni.so.debug
make libtailscale

# Das Makefile strippt nur arm64. Wir strippen auch x86_64 (Emulator) und werfen die
# 32-Bit-ABIs raus, für die es ohnehin kein PJSIP gibt.
NDK_ROOT="$(ls -1d "$ANDROID_HOME"/ndk/* | sort -V | tail -n 1)"
OBJCOPY="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-objcopy"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
unzip -q android/libs/libtailscale.aar -d "$WORK/aar"
rm -rf "$WORK/aar/jni/armeabi-v7a" "$WORK/aar/jni/x86"
"$OBJCOPY" --strip-debug "$WORK/aar/jni/x86_64/libgojni.so"
mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR/libtailscale.aar"
(cd "$WORK/aar" && zip -qr "$OUT_DIR/libtailscale.aar" .)
echo "$TS_ANDROID_REV" > "$OUT_DIR/REVISION"
ls -l "$OUT_DIR"
unzip -l "$OUT_DIR/libtailscale.aar" | grep libgojni.so
