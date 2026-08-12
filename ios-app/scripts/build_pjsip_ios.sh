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

# pjsua2 (the C++ OO wrapper the app's Obj-C++ bridge links against) uses
# rvalue references, `auto`, and default member initializers -- all C++11+.
# Apple clang++ invoked bare (no -std= flag at all, confirmed in the actual
# failing command line) defaults to gnu++98 on this toolchain, so
# account.cpp fails with "expected ';' at end of declaration list" etc.
# (misleading syntax-error phrasing for what's really a missing-C++11 error).
# PJSIP's Makefiles fold the CXXFLAGS env var into every module's _CXXFLAGS,
# so exporting it before configure-iphone is enough -- no Makefile edits
# needed. gnu++17 matches project.yml's CLANG_CXX_LANGUAGE_STANDARD so the
# PJSIP libs and the app that links them agree on ABI-relevant language rules.
export CXXFLAGS="-std=gnu++17"

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

echo "== configure-iphone: Simulator (arm64) =="
# Run #4 traced the "A library with the identifier 'ios-arm64' already
# exists" failure to its real cause: `DEVICE=iPhoneSimulator` is not a
# variable configure-iphone reads at all -- grep confirms it never appears
# in the script. Both prior "device" and "simulator" passes were silently
# building against the SAME iPhoneOS SDK the whole time (configure-iphone
# unconditionally defaults DEVPATH to iPhoneOS.platform unless DEVPATH is
# pre-set), so of course xcodebuild saw two identically-tagged "ios-arm64"
# libraries -- there was never a real Simulator build happening at all.
# Run #3's ARCH=x86_64 workaround masked the collision by changing
# architecture, but treated the wrong root cause.
#
# The actual official recipe (docs.pjsip.org iOS build_instructions.html
# "Simulator" section) sets DEVPATH to the iPhoneSimulator.platform SDK
# and overrides MIN_IOS to `-mios-simulator-version-min=`, NOT the default
# `-miphoneos-version-min=` -- that's what correctly tags the resulting
# Mach-O with the Simulator platform (not device), so xcodebuild can tell
# the two libraries apart. Staying on arm64 (the runner's native arch,
# matching the device pass and avoiding any Homebrew-opus arch mismatch)
# is fine once DEVPATH+MIN_IOS are both right -- x86_64 was never required.
DEVPATH="/Applications/XCode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer" \
MIN_IOS="-mios-simulator-version-min=13.0" \
./configure-iphone --with-opus="$(brew --prefix opus)"
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
