#!/usr/bin/env bash
set -euo pipefail

PJSIP_TAG="2.17"
NDK_VERSION="27.0.12077973"
ANDROID_ABIS=(arm64-v8a x86_64)
WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$WORKDIR/third_party/pjproject"
OUT_DIR="$WORKDIR/sip-core/src/main"
OPUS_VERSION="1.5.2"
OPUS_BUILD_DIR="$WORKDIR/third_party/opus-src"
OPUS_TARBALL_URL="https://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz"

echo "== Installing system dependencies =="
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends libopus-dev swig

# NOTE: apt's libopus-dev only ships a *host* (x86_64) shared library --
# it cannot satisfy PJSIP's Opus support when cross-compiling for Android
# (arm64-v8a/x86_64-android are different target triples than the build
# host). Passing `--with-opus=/usr` to configure-android also leaks
# `-I/usr/include` into the Android cross-compile flags, which shadows the
# NDK's own bionic sysroot headers and breaks the entire pjlib build (not
# just Opus). Building a real per-ABI libopus.a from source with the NDK's
# own per-API-level clang wrapper avoids both problems.
build_opus_for_abi() {
    local ABI="$1"
    local HOST_TRIPLE CLANG_PREFIX
    case "$ABI" in
        arm64-v8a) HOST_TRIPLE="aarch64-linux-android"; CLANG_PREFIX="aarch64-linux-android23" ;;
        x86_64)    HOST_TRIPLE="x86_64-linux-android";  CLANG_PREFIX="x86_64-linux-android23" ;;
        *) echo "ERROR: no libopus cross-build recipe for ABI $ABI" >&2; exit 1 ;;
    esac
    local OPUS_PREFIX="$WORKDIR/third_party/opus-android/$ABI"
    if [ -f "$OPUS_PREFIX/lib/libopus.a" ]; then
        echo "== libopus already cross-built for $ABI, skipping =="
        return
    fi
    echo "== Cross-compiling libopus $OPUS_VERSION for Android ABI $ABI =="
    if [ ! -d "$OPUS_BUILD_DIR" ]; then
        mkdir -p "$OPUS_BUILD_DIR"
        # Official release tarball ships a pre-generated ./configure (unlike
        # a git clone of the tag), so no autoconf/automake/libtool needed.
        curl -sL "$OPUS_TARBALL_URL" | tar xz -C "$OPUS_BUILD_DIR" --strip-components=1
    fi
    local TOOLCHAIN_BIN="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin"
    (
        cd "$OPUS_BUILD_DIR"
        make distclean >/dev/null 2>&1 || true
        CC="$TOOLCHAIN_BIN/${CLANG_PREFIX}-clang" \
        AR="$TOOLCHAIN_BIN/llvm-ar" \
        RANLIB="$TOOLCHAIN_BIN/llvm-ar s" \
        ./configure --host="$HOST_TRIPLE" --prefix="$OPUS_PREFIX" \
            --disable-shared --enable-static --disable-doc --disable-extra-programs
        make -j"$(nproc)"
        make install
    )
}

echo "== Installing Android NDK $NDK_VERSION =="
export PATH="$HOME/android-sdk/cmdline-tools/latest/bin:$PATH"
if [ ! -d "$HOME/android-sdk/ndk/$NDK_VERSION" ]; then
    # NOTE: `yes` receives SIGPIPE (exit 141) once sdkmanager stops reading
    # stdin after the license prompt; under `pipefail` that would otherwise
    # fail this script even though the install itself succeeded. Wrapping
    # `yes` in `(... || true)` absorbs that harmless SIGPIPE without masking
    # a real sdkmanager failure (its own exit code is still the pipeline's).
    (yes || true) | sdkmanager --sdk_root="$HOME/android-sdk" --install "ndk;$NDK_VERSION"
fi
export ANDROID_NDK_ROOT="$HOME/android-sdk/ndk/$NDK_VERSION"

echo "== Cloning pjproject tag $PJSIP_TAG (pinned, not a moving branch) =="
if [ ! -d "$VENDOR_DIR" ]; then
    git clone --branch "$PJSIP_TAG" --depth 1 https://github.com/pjsip/pjproject.git "$VENDOR_DIR"
fi
cd "$VENDOR_DIR"

echo "== Enabling Opus (Pitfall 3 -- silently omitted otherwise) =="
grep -q "PJMEDIA_HAS_OPUS_CODEC" pjlib/include/pj/config_site.h 2>/dev/null || \
    echo "#define PJMEDIA_HAS_OPUS_CODEC 1" >> pjlib/include/pj/config_site.h

# Discard any stale/partial .depend files from an earlier interrupted or
# failed build attempt. GNU make `-include`s these at Makefile-parse time
# (before any recipe, including `rm -f`, runs), so a malformed leftover
# file from a previous failed run breaks every subsequent `make dep` with
# a "missing separator" parse error even after the actual root cause (the
# earlier Opus/cross-compile misconfiguration) has been fixed.
find . -iname "*.depend" -delete

for ABI in "${ANDROID_ABIS[@]}"; do
    build_opus_for_abi "$ABI"
    OPUS_PREFIX_FOR_ABI="$WORKDIR/third_party/opus-android/$ABI"
    echo "== Building for ABI $ABI =="
    # NOTE: configure-android reads TARGET_ABI purely as an inherited shell
    # environment variable (`test "x$TARGET_ABI" = "x"`) -- it does NOT parse
    # a trailing `TARGET_ABI=value` command-line token. Passing it after the
    # command name (as originally written) is silently ignored, so every ABI
    # after the first would build using the arm64-v8a default. Exporting it
    # as a prefix assignment is required for the second/subsequent ABIs.
    TARGET_ABI="$ABI" ./configure-android --use-ndk-cflags --with-opus="$OPUS_PREFIX_FOR_ABI"
    make dep
    make clean
    make

    # NOTE: SWIG's own Makefile links libpjsua2.so against whichever ABI's
    # static libs are described by the *currently active* build.mak
    # (TARGET_ARCH). Running this once after the whole ABI loop -- as the
    # plan's illustrative script does -- silently only ever produces
    # bindings for the last-configured ABI. Running it here, per-ABI, while
    # build.mak still reflects $ABI, is required to get a real libpjsua2.so
    # under jniLibs/ for every target ABI. Restricting to the `java` target
    # also skips the unused csharp/xamarin/maui outputs this Makefile
    # otherwise builds by default.
    echo "== Generating SWIG Java/JNI bindings for $ABI =="
    (cd pjsip-apps/src/swig && make java)
done

echo "== Copying build artifacts into sip-core module =="
SWIG_JAVA_DIR="$VENDOR_DIR/pjsip-apps/src/swig/java"
mkdir -p "$OUT_DIR/jniLibs" "$OUT_DIR/java/org/pjsip"
for ABI in "${ANDROID_ABIS[@]}"; do
    mkdir -p "$OUT_DIR/jniLibs/$ABI"
    find "$SWIG_JAVA_DIR/android/pjsua2/src/main/jniLibs/$ABI" -name "*.so" \
        -exec cp {} "$OUT_DIR/jniLibs/$ABI/" \; || true
done
# NOTE: `find -iname pjsua2` (as the illustrative plan text used) also
# matches the outer SWIG project scaffold dir (android/pjsua2/), not just
# the actual generated Java package dir -- copying that wholesale pulls in
# unrelated sample-app dirs (app/, app_kotlin/) and a nested duplicate
# src/main/{java,jniLibs} tree. Reference the exact known package path
# instead of an unconstrained recursive find.
rm -rf "$OUT_DIR/java/org/pjsip/pjsua2"
cp -r "$SWIG_JAVA_DIR/android/pjsua2/src/main/java/org/pjsip/pjsua2" "$OUT_DIR/java/org/pjsip/"

echo "== Build-verification gate: Opus actually compiled in (not just flag set) =="
OPUS_OBJ_COUNT=$(find "$VENDOR_DIR" -iname "*opus*.o" | wc -l)
if [ "$OPUS_OBJ_COUNT" -eq 0 ]; then
    echo "ERROR: no opus object files found -- Opus was NOT compiled in (Pitfall 3)" >&2
    exit 1
fi
echo "PJSIP $PJSIP_TAG built for: ${ANDROID_ABIS[*]}, opus object files: $OPUS_OBJ_COUNT"
