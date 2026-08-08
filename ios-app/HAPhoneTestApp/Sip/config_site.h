// PJSIP config_site.h override for HA-Phone -- enables Opus (RESEARCH.md
// Pitfall 3: silently omitted otherwise). Included via the build script's
// configure-iphone step, not part of the app's own compiled sources.
#define PJMEDIA_HAS_OPUS_CODEC 1
