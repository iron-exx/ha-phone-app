#!/usr/bin/env bash
set -euo pipefail

PJSIP_TAG="2.17"
WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$WORKDIR/third_party/pjproject"
CONFIG_SITE="$WORKDIR/HAPhoneTestApp/Sip/config_site.h"
XCFRAMEWORK_OUT="$WORKDIR/Frameworks/pjsua2.xcframework"

echo "== Cloning pjproject tag $PJSIP_TAG (pinned, not a moving branch) =="
if [ ! -d "$VENDOR_DIR" ]; then
    git clone --branch "$PJSIP_TAG" --depth 1 https://github.com/pjsip/pjproject.git "$VENDOR_DIR"
fi
cp "$CONFIG_SITE" "$VENDOR_DIR/pjlib/include/pj/config_site.h"

echo "== Installing Opus via Homebrew (macOS runner) =="
brew install opus

cd "$VENDOR_DIR"
# Merges every static lib PJSIP produced for the pass that just finished
# (pjlib, pjlib-util, pjnath, pjmedia + its codec/audiodev/videodev
# sub-libs, pjsip + its ua/simple/pjsua/pjsua2 sub-libs, third_party codecs)
# into a single combined archive. There is no "libpjproject.a" in upstream
# PJSIP's own build output -- the official ios-swift-pjsua2 sample Xcode
# project links ~17 separate .a files directly (confirmed against
# pjsip-apps/src/pjsua2/ios-swift-pjsua2/*.xcodeproj/project.pbxproj at tag
# 2.17). `-create-xcframework` packages ONE logical library per platform
# slice, so we pre-merge with `libtool -static` rather than guess a
# combined-archive filename that pjproject's Makefiles never produce.
merge_pass_libs() {
    local out="$1"
    local libs=()
    while IFS= read -r -d '' f; do libs+=("$f"); done < <(find \
        pjlib/lib pjlib-util/lib pjnath/lib pjmedia/lib pjsip/lib third_party/lib \
        -name '*.a' -print0 2>/dev/null)
    if [ "${#libs[@]}" -eq 0 ]; then
        echo "ERROR: no .a files found under pjlib/pjlib-util/pjnath/pjmedia/pjsip/third_party -- build did not produce libraries" >&2
        exit 1
    fi
    libtool -static -o "$out" "${libs[@]}"
    echo "Merged ${#libs[@]} static libs -> $out"
}

echo "== configure-iphone: device (arm64) =="
./configure-iphone --with-opus="$(brew --prefix opus)"
make dep
make clean
# `make lib` (not plain `make`/`all`) -- the top-level Makefile's `all` target
# also builds each module's test/demo executables (e.g. pjmedia/build's
# pjmedia-test), which link against opus symbols without ever receiving
# -lopus (that flag only reaches the library build, not the test binaries'
# link line). We only need the static libraries for the xcframework, so
# `lib` skips those test executables entirely and avoids the resulting
# "Undefined symbols ... _opus_encode" link failure.
make lib
mkdir -p "$WORKDIR/Frameworks/device"
merge_pass_libs "$WORKDIR/Frameworks/device/libpjproject.a"

echo "== configure-iphone: Simulator =="
# Per docs.pjsip.org iOS build_instructions.html: DEVICE variable selects
# the Simulator SDK/arch pass; re-run configure-iphone + make into a
# separate build products directory so device+simulator libs don't clash.
# NOTE: on Apple Silicon (arm64) GitHub macos-14 runners this produces an
# arm64 simulator slice, not x86_64 -- do not assume Intel-simulator naming.
DEVICE=iPhoneSimulator ./configure-iphone --with-opus="$(brew --prefix opus)"
make dep
make clean
make lib
mkdir -p "$WORKDIR/Frameworks/simulator"
merge_pass_libs "$WORKDIR/Frameworks/simulator/libpjproject.a"

echo "== Packaging merged static libs into an xcframework =="
mkdir -p "$WORKDIR/Frameworks"
rm -rf "$XCFRAMEWORK_OUT"
xcodebuild -create-xcframework \
    -library "$WORKDIR/Frameworks/device/libpjproject.a" \
    -library "$WORKDIR/Frameworks/simulator/libpjproject.a" \
    -output "$XCFRAMEWORK_OUT"

echo "== Build-verification gate: Opus actually compiled in =="
OPUS_OBJ_COUNT=$(find "$VENDOR_DIR" -iname "*opus*.o" | wc -l)
if [ "$OPUS_OBJ_COUNT" -eq 0 ]; then
    echo "ERROR: no opus object files found -- Opus was NOT compiled in (Pitfall 3)" >&2
    exit 1
fi
echo "PJSIP $PJSIP_TAG built for iOS device+simulator, opus object files: $OPUS_OBJ_COUNT"
