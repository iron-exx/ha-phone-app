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

echo "== configure-iphone: Simulator (forced x86_64) =="
# Per docs.pjsip.org iOS build_instructions.html: DEVICE variable selects
# the Simulator SDK; re-run configure-iphone + make into a separate build
# products directory so device+simulator libs don't clash.
#
# ARCH is forced to x86_64 rather than the runner's native arm64. Run #3
# confirmed the reason: `xcodebuild -create-xcframework` derives each
# library's platform-variant identifier ("ios-arm64" vs
# "ios-arm64-simulator") from the compiled binary's embedded
# LC_BUILD_VERSION platform tag, not the filename. configure-iphone's
# DEVICE=iPhoneSimulator pass still emits `-miphoneos-version-min=` (the
# device flag) instead of a simulator-tagged target, so an arm64 simulator
# build ends up mislabeled as plain "ios-arm64" -- identical to the device
# pass -- and xcodebuild refuses with "A library with the identifier
# 'ios-arm64' already exists." x86_64 has never been ambiguous (no real
# iOS device ships x86_64), so it sidesteps the mistagging entirely --
# this is also why the very first version of this script assumed an
# x86_64-simulator filename, before either of us corrected it downstream.
#
# RISK: Homebrew's opus at $(brew --prefix opus) is arm64-only on this
# Apple Silicon runner (Homebrew does not ship universal binaries by
# default), so linking it into an x86_64 build may itself fail with an
# architecture-mismatch error. If so, cross-compile opus for x86_64 from
# source instead of relying on the Homebrew arm64 build -- mirroring
# exactly what build_pjsip_android.sh already does per-ABI (see its
# build_opus_for_abi() function) rather than improvising a new approach.
ARCH="-arch x86_64" DEVICE=iPhoneSimulator ./configure-iphone --with-opus="$(brew --prefix opus)"
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
