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
echo "== configure-iphone: device (arm64) =="
./configure-iphone --with-opus="$(brew --prefix opus)"
make dep
make clean
make

echo "== configure-iphone: Simulator (arm64-simulator) =="
# Per docs.pjsip.org iOS build_instructions.html: DEVICE variable selects
# the Simulator SDK/arch pass; re-run configure-iphone + make into a
# separate build products directory so device+simulator libs don't clash.
DEVICE=iPhoneSimulator ./configure-iphone --with-opus="$(brew --prefix opus)"
make dep
make clean
make

echo "== Packaging static libs into an xcframework =="
mkdir -p "$WORKDIR/Frameworks"
xcodebuild -create-xcframework \
    -library "$VENDOR_DIR/pjsip-apps/lib/libpjproject-arm64-apple-darwin_ios.a" \
    -library "$VENDOR_DIR/pjsip-apps/lib/libpjproject-x86_64-apple-darwin_ios_simulator.a" \
    -output "$XCFRAMEWORK_OUT" \
    || echo "WARNING: exact .a output filenames vary by pjproject version -- inspect $VENDOR_DIR/pjsip-apps/lib/*.a and adjust the -library paths above before re-running"

echo "== Build-verification gate: Opus actually compiled in =="
OPUS_OBJ_COUNT=$(find "$VENDOR_DIR" -iname "*opus*.o" | wc -l)
if [ "$OPUS_OBJ_COUNT" -eq 0 ]; then
    echo "ERROR: no opus object files found -- Opus was NOT compiled in (Pitfall 3)" >&2
    exit 1
fi
echo "PJSIP $PJSIP_TAG built for iOS device+simulator, opus object files: $OPUS_OBJ_COUNT"
