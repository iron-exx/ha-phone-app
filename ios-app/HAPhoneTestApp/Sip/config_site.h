// PJSIP config_site.h override for HA-Phone. Copied over pjproject's own
// pjlib/include/pj/config_site.h by scripts/build_pjsip_ios.sh before
// configure-iphone runs -- not part of the app's own compiled sources.
//
// Opus is OFF for now. It cannot be enabled without an Opus library that
// was itself cross-compiled for iOS: Homebrew's opus is a macOS-native
// build and the linker rejects it outright ("building for 'iOS-simulator',
// but linking in dylib ... built for 'macOS'"), independent of CPU arch.
// pjmedia-codec/opus.c wraps its whole body in this flag, so 0 makes it a
// no-op translation unit that never reaches `#include <opus/opus.h>`; with
// it at 1 but no --with-opus include path, the PJSIP build dies with
// "'opus/opus.h' file not found". Flip back to 1 in the same change that
// adds a real from-source iOS Opus build (arm64-ios + arm64-ios-simulator)
// to build_pjsip_ios.sh, and re-add the opus codec priority in
// PjsuaBridge.mm's -start.
#define PJMEDIA_HAS_OPUS_CODEC 0
