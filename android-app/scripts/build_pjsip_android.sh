#!/usr/bin/env bash
set -euo pipefail

PJSIP_TAG="2.17"
NDK_VERSION="27.0.12077973"
# Override to build a single ABI, e.g. ANDROID_ABIS_OVERRIDE=arm64-v8a (real phones).
read -r -a ANDROID_ABIS <<< "${ANDROID_ABIS_OVERRIDE:-arm64-v8a x86_64}"
WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$WORKDIR/third_party/pjproject"
# Both copies of the sip-core module get the artifacts: the legacy native app
# and the Flutter app (app-flutter/android/sip-core), which is the one in use.
OUT_DIRS=("$WORKDIR/sip-core/src/main" "$WORKDIR/../app-flutter/android/sip-core/src/main")
OPUS_VERSION="1.5.2"
OPUS_BUILD_DIR="$WORKDIR/third_party/opus-src"
OPUS_TARBALL_URL="https://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz"
# OpenSSL is mandatory: the app only talks SIP over TLS (port 5061). Without
# --with-ssl, pjproject's configure silently disables SSL when cross-compiling,
# and every transportCreate(TLS) fails with PJSIP_EUNSUPTRANSPORT at runtime.
OPENSSL_VERSION="3.3.2"
OPENSSL_BUILD_DIR="$WORKDIR/third_party/openssl-src"

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

build_openssl_for_abi() {
    local ABI="$1"
    local TARGET
    case "$ABI" in
        arm64-v8a) TARGET="android-arm64" ;;
        x86_64)    TARGET="android-x86_64" ;;
        *) echo "ERROR: no OpenSSL cross-build recipe for ABI $ABI" >&2; exit 1 ;;
    esac
    local PREFIX="$WORKDIR/third_party/openssl-android/$ABI"
    if [ -f "$PREFIX/lib/libssl.a" ] && [ -f "$PREFIX/lib/libcrypto.a" ]; then
        echo "== OpenSSL already cross-built for $ABI, skipping =="
        return
    fi
    echo "== Cross-compiling OpenSSL $OPENSSL_VERSION for Android ABI $ABI =="
    rm -rf "$OPENSSL_BUILD_DIR"
    mkdir -p "$OPENSSL_BUILD_DIR"
    curl -sL "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz" \
        | tar xz -C "$OPENSSL_BUILD_DIR" --strip-components=1
    (
        cd "$OPENSSL_BUILD_DIR"
        # OpenSSL's android-* targets find clang via ANDROID_NDK_ROOT + PATH.
        export PATH="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"
        # Static only (no-shared): the libs get linked straight into libpjsua2.so,
        # so no extra libssl.so/libcrypto.so has to be packaged in jniLibs.
        ./Configure "$TARGET" -D__ANDROID_API__=26 --prefix="$PREFIX" --openssldir="$PREFIX" \
            no-shared no-tests no-engine no-docs
        make -j"$(nproc)"
        make install_sw
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
# PJ_DEBUG 0 = PJSIP's documented release setting: pj_assert() logs instead of
# abort()ing. With the default (1) an internal assertion inside pjsua_init()
# (pjsip_endpt_unregister_module) killed the whole app on the first call.
grep -q "PJ_DEBUG" pjlib/include/pj/config_site.h || \
    echo "#define PJ_DEBUG 0" >> pjlib/include/pj/config_site.h
# Video is off by default; needed for door-station early-media preview (H.264
# via Android MediaCodec, receive-only in the app).
grep -q "PJMEDIA_HAS_VIDEO" pjlib/include/pj/config_site.h || \
    echo "#define PJMEDIA_HAS_VIDEO 1" >> pjlib/include/pj/config_site.h

# Discard any stale/partial .depend files from an earlier interrupted or
# failed build attempt. GNU make `-include`s these at Makefile-parse time
# (before any recipe, including `rm -f`, runs), so a malformed leftover
# file from a previous failed run breaks every subsequent `make dep` with
# a "missing separator" parse error even after the actual root cause (the
# earlier Opus/cross-compile misconfiguration) has been fixed.
find . -iname "*.depend" -delete

for ABI in "${ANDROID_ABIS[@]}"; do
    build_opus_for_abi "$ABI"
    build_openssl_for_abi "$ABI"
    OPUS_PREFIX_FOR_ABI="$WORKDIR/third_party/opus-android/$ABI"
    SSL_PREFIX_FOR_ABI="$WORKDIR/third_party/openssl-android/$ABI"
    echo "== Building for ABI $ABI =="
    # NOTE: configure-android reads TARGET_ABI purely as an inherited shell
    # environment variable (`test "x$TARGET_ABI" = "x"`) -- it does NOT parse
    # a trailing `TARGET_ABI=value` command-line token. Passing it after the
    # command name (as originally written) is silently ignored, so every ABI
    # after the first would build using the arm64-v8a default. Exporting it
    # as a prefix assignment is required for the second/subsequent ABIs.
    TARGET_ABI="$ABI" ./configure-android --use-ndk-cflags --with-opus="$OPUS_PREFIX_FOR_ABI" \
        --with-ssl="$SSL_PREFIX_FOR_ABI"
    grep -q "define PJ_HAS_SSL_SOCK 1" pjlib/include/pj/compat/os_auto.h || {
        echo "ERROR: configure did not enable SSL (PJ_HAS_SSL_SOCK) for $ABI" >&2; exit 1; }
    make dep
    make clean
    # `make clean` leaves the srtp archive behind. After switching the crypto
    # backend (builtin -> OpenSSL) it then holds BOTH aes_icm.o and
    # aes_icm_ossl.o, and linking libpjsua2.so fails with duplicate symbols.
    rm -f third_party/lib/libsrtp-*.a
    make -j"$(nproc)"

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
    # The SWIG Makefile does not list the pj*.a static libs as prerequisites of
    # libpjsua2.so, so an existing .so is never relinked after a rebuild. Delete
    # the outputs to force a real link (verify: fresh timestamp on the .so).
    rm -f pjsip-apps/src/swig/java/output/pjsua2_wrap.* \
        "pjsip-apps/src/swig/java/android/pjsua2/src/main/jniLibs/$ABI/libpjsua2.so"
    (cd pjsip-apps/src/swig && make java)
done

echo "== Copying build artifacts into the sip-core modules =="
SWIG_JAVA_DIR="$VENDOR_DIR/pjsip-apps/src/swig/java"
for OUT_DIR in "${OUT_DIRS[@]}"; do
    [ -d "$(dirname "$OUT_DIR")" ] || { echo "skipping missing $OUT_DIR"; continue; }
    mkdir -p "$OUT_DIR/jniLibs" "$OUT_DIR/java/org/pjsip"
    for ABI in "${ANDROID_ABIS[@]}"; do
        mkdir -p "$OUT_DIR/jniLibs/$ABI"
        find "$SWIG_JAVA_DIR/android/pjsua2/src/main/jniLibs/$ABI" -name "*.so" \
            -exec cp {} "$OUT_DIR/jniLibs/$ABI/" \; || true
        chmod 755 "$OUT_DIR/jniLibs/$ABI/"*.so
    done
    # NOTE: `find -iname pjsua2` (as the illustrative plan text used) also
    # matches the outer SWIG project scaffold dir (android/pjsua2/), not just
    # the actual generated Java package dir -- copying that wholesale pulls in
    # unrelated sample-app dirs (app/, app_kotlin/) and a nested duplicate
    # src/main/{java,jniLibs} tree. Reference the exact known package path
    # instead of an unconstrained recursive find.
    rm -rf "$OUT_DIR/java/org/pjsip/pjsua2"
    cp -r "$SWIG_JAVA_DIR/android/pjsua2/src/main/java/org/pjsip/pjsua2" "$OUT_DIR/java/org/pjsip/"
    # PJSIP's Android camera driver looks these up via JNI when the video
    # subsystem initialises; missing classes crash libInit().
    cp -f "$SWIG_JAVA_DIR/android/pjsua2/src/main/java/org/pjsip/"PjCamera*.java "$OUT_DIR/java/org/pjsip/"
done

echo "== Build-verification gate: Opus actually compiled in (not just flag set) =="
OPUS_OBJ_COUNT=$(find "$VENDOR_DIR" -iname "*opus*.o" | wc -l)
if [ "$OPUS_OBJ_COUNT" -eq 0 ]; then
    echo "ERROR: no opus object files found -- Opus was NOT compiled in (Pitfall 3)" >&2
    exit 1
fi
echo "PJSIP $PJSIP_TAG built for: ${ANDROID_ABIS[*]}, opus object files: $OPUS_OBJ_COUNT"
