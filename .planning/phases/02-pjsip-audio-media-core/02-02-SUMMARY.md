---
phase: 02-pjsip-audio-media-core
plan: 02
subsystem: infra
tags: [pjsip, pjsua2, opus, android-ndk, gradle, jni, swig, sip]

# Dependency graph
requires:
  - phase: 02-pjsip-audio-media-core (plan 01)
    provides: cross-repo HA-Phone TLS/SRTP test-extension prerequisite (D-06)
provides:
  - PJSIP 2.17 built from official source for Android (arm64-v8a, x86_64) with Opus compiled in
  - Reproducible build_pjsip_android.sh script (idempotent, re-runnable)
  - sip-core local Gradle module wrapping PJSUA2 JNI/Java artifacts
  - :app compiles against org.pjsip.pjsua2.Endpoint via PjsuaAvailabilityCheck.kt smoke check
affects: [02-pjsip-audio-media-core (plan 04 - Android SIP call controller), 02-VALIDATION]

# Tech tracking
tech-stack:
  added: [PJSIP 2.17, libopus 1.5.2 (cross-built), Android NDK 27.0.12077973, SWIG 4.2.0, sip-core Gradle module]
  patterns: ["per-ABI cross-compile loop (opus + PJSIP + SWIG bindings all inside the same ABI iteration)", "gitignored vendored third-party source + generated JNI artifacts, rebuilt deterministically from a pinned tag"]

key-files:
  created:
    - android-app/scripts/build_pjsip_android.sh
    - android-app/.gitignore
    - android-app/sip-core/build.gradle.kts
    - android-app/app/src/main/java/de/haphone/app/test/sip/PjsuaAvailabilityCheck.kt
  modified:
    - android-app/settings.gradle.kts
    - android-app/app/build.gradle.kts
    - android-app/build.gradle.kts
    - .gitignore

key-decisions:
  - "Cross-compiled libopus from the official 1.5.2 source tarball per-ABI instead of relying on apt's libopus-dev, which only ships a host (x86_64) library unusable for Android cross-compilation"
  - "Moved SWIG's Java/JNI binding generation (`make java`) inside the per-ABI build loop instead of running it once after -- SWIG's Makefile links against whichever ABI's static libs the currently-active build.mak describes, so running it once only ever produces bindings for the last-configured ABI"

patterns-established:
  - "Per-ABI build loop: cross-build vendored native dependency (opus) -> configure-android -> make dep/clean/make -> SWIG java bindings, all within one iteration per ABI"
  - "TARGET_ABI must be an exported env var to configure-android, never a trailing CLI token (silently ignored otherwise)"

requirements-completed: [CALL-01]

# Metrics
duration: 35min
completed: 2026-08-08
---

# Phase 2 Plan 02: PJSIP Android Build Summary

**PJSIP 2.17 built from official source for Android (arm64-v8a + x86_64) with a from-source-cross-compiled Opus codec, wired into the app as a local `sip-core` Gradle module that `:app` successfully compiles against.**

## Performance

- **Duration:** ~35 min (includes multiple real from-source PJSIP/Opus builds after fixing build-script bugs)
- **Completed:** 2026-08-08
- **Tasks:** 2
- **Files modified:** 8 (4 created, 4 modified) plus vendored/generated build artifacts (gitignored)

## Accomplishments
- PJSIP 2.17 (pinned upstream tag) built from source for both `arm64-v8a` and `x86_64` Android ABIs using the NDK's per-API-level clang toolchain
- Opus 1.5.2 cross-compiled from source per-ABI (`libopus.a`) since the sandbox's only available `libopus-dev` package is host-architecture only; `PJMEDIA_HAS_OPUS_CODEC` enabled and verified via real `opus.o` object files in the build tree (2 found: one per ABI)
- SWIG-generated PJSUA2 Java/JNI bindings produced correctly for both ABIs (`libpjsua2.so` for `arm64-v8a` and `x86_64`, plus the Java package under `org.pjsip.pjsua2`)
- New `sip-core` Android library Gradle module wraps the generated artifacts; `:app` depends on it and `./gradlew :app:compileDebugKotlin` succeeds referencing `org.pjsip.pjsua2.Endpoint`

## Task Commits

1. **Task 1: Build PJSIP 2.17 from source for Android with Opus enabled** - `1634e2d` (feat)
2. **Task 2: Wire sip-core as a local Gradle module and prove :app can import PJSUA2** - `e8714cf` (feat)

**Plan metadata:** (pending — this commit)

## Files Created/Modified
- `android-app/scripts/build_pjsip_android.sh` - Reproducible from-source PJSIP 2.17 + per-ABI Opus cross-build + per-ABI SWIG binding generation
- `android-app/.gitignore` - Ignores vendored `third_party/pjproject` source and generated `jniLibs`/Java artifacts
- `android-app/sip-core/build.gradle.kts` - New Android library module wrapping the compiled JNI `.so`s and generated Java sources
- `android-app/app/src/main/java/de/haphone/app/test/sip/PjsuaAvailabilityCheck.kt` - Compile-time smoke check proving PJSUA2 bindings are visible to `:app`
- `android-app/settings.gradle.kts` - Added `include(":sip-core")`
- `android-app/app/build.gradle.kts` - Added `implementation(project(":sip-core"))`
- `android-app/build.gradle.kts` - Declared `com.android.library` plugin version (only `com.android.application` was declared before)
- `.gitignore` (root) - Added `android-app/sip-core/build/` alongside the existing per-module Gradle output ignore pattern

## Decisions Made
- Cross-built libopus from the official source tarball per-ABI rather than the plan's illustrative `--with-opus=/usr` (system package), since the system package is host-only and cannot satisfy an Android cross-compile — see Deviations.
- Ran SWIG's Java/JNI binding step inside the per-ABI loop rather than once after it, since it links against whatever the currently-active `build.mak` describes.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `sdkmanager` not on PATH**
- **Found during:** Task 1, first build attempt
- **Issue:** `configure-android`/NDK install step invoked bare `sdkmanager`, which isn't on `PATH` in this sandbox.
- **Fix:** Export `$HOME/android-sdk/cmdline-tools/latest/bin` onto `PATH` at the top of the NDK-install section.
- **Files modified:** `android-app/scripts/build_pjsip_android.sh`
- **Committed in:** `1634e2d`

**2. [Rule 1 - Bug] `yes | sdkmanager` + `pipefail` false failure**
- **Found during:** Task 1, first build attempt (exit 141)
- **Issue:** `yes` receives SIGPIPE (exit 141) once `sdkmanager` stops reading stdin after the license prompt; under `set -o pipefail` this failed the script even though the NDK install itself succeeded.
- **Fix:** Wrapped `yes` in a subshell with `|| true` so the harmless SIGPIPE doesn't propagate, while `sdkmanager`'s own exit code is still honored.
- **Files modified:** `android-app/scripts/build_pjsip_android.sh`
- **Committed in:** `1634e2d`

**3. [Rule 2 - Missing Critical] `libopus-dev` (apt) cannot satisfy Android cross-compilation**
- **Found during:** Task 1, second build attempt
- **Issue:** The plan's `--with-opus=/usr` pointed `configure-android` at the sandbox's system `libopus-dev`, which only ships a host x86_64 shared library. This also leaked `-I/usr/include` into the Android cross-compile flags, shadowing the NDK's own bionic sysroot headers and breaking the entire pjlib build (`bits/libc-header-start.h` not found), not just Opus.
- **Fix:** Added a `build_opus_for_abi()` function that cross-compiles libopus 1.5.2 from the official source tarball per-ABI using the NDK's per-API-level clang wrapper (`aarch64-linux-android23-clang`/`x86_64-linux-android23-clang`), installing to a per-ABI prefix passed to `--with-opus=`.
- **Files modified:** `android-app/scripts/build_pjsip_android.sh`
- **Committed in:** `1634e2d`

**4. [Rule 1 - Bug] Stale `.depend` files poisoning `make dep` across retries**
- **Found during:** Task 1, third build attempt
- **Issue:** GNU make `-include`s `.depend` files at Makefile-parse time (before any recipe runs). A malformed leftover `.depend` file from an earlier failed attempt broke every subsequent `make dep` with "missing separator" even after the root cause was fixed. (Confirmed as a known upstream gotcha per the vendored `pjproject/CLAUDE.md`.)
- **Fix:** Added `find . -iname "*.depend" -delete` before the ABI build loop.
- **Files modified:** `android-app/scripts/build_pjsip_android.sh`
- **Committed in:** `1634e2d`

**5. [Rule 1 - Bug] `TARGET_ABI=$ABI` as a trailing CLI token is silently ignored**
- **Found during:** Task 1, fourth build attempt — second ABI (`x86_64`) built using `arm64-v8a` settings
- **Issue:** `configure-android` reads `TARGET_ABI` purely as an inherited shell environment variable (`test "x$TARGET_ABI" = "x"`); it has no argument parser for a trailing `TARGET_ABI=value` token. The plan's illustrative invocation placed it after the command name, so it was silently ignored and every ABI after the first defaulted to `arm64-v8a`.
- **Fix:** Changed to `TARGET_ABI="$ABI" ./configure-android ...` (prefix env-var assignment).
- **Files modified:** `android-app/scripts/build_pjsip_android.sh`
- **Committed in:** `1634e2d`

**6. [Rule 1 - Bug] SWIG binding generation only produced bindings for the last-configured ABI**
- **Found during:** Task 1, after full build completed — only `jniLibs/x86_64/libpjsua2.so` existed, not `arm64-v8a`
- **Issue:** SWIG's own Makefile links `libpjsua2.so` against whichever ABI's static libs the currently-active root `build.mak` (`TARGET_ARCH`) describes. Running `make java` once, after the whole ABI loop (as the plan's illustrative script did), only ever produces bindings for whichever ABI was configured last.
- **Fix:** Moved the SWIG `make java` step inside the per-ABI loop, immediately after `make` for that ABI, while `build.mak` still reflects it. (Applied by reconfiguring `arm64-v8a` and re-running `make java` for the already-built arm64 static libs, then updating the script for future re-runs.)
- **Files modified:** `android-app/scripts/build_pjsip_android.sh`
- **Committed in:** `1634e2d`

**7. [Rule 1 - Bug] Overly broad `find -iname pjsua2` copy pulled in unrelated SWIG scaffold dirs**
- **Found during:** Task 1, artifact-copy step
- **Issue:** `find "$SWIG_JAVA_DIR" -type d -iname pjsua2` matched both the actual generated Java package dir and the outer SWIG project scaffold dir (`android/pjsua2/`), copying unrelated sample-app dirs (`app/`, `app_kotlin/`) and a nested duplicate `src/main/{java,jniLibs}` tree into `sip-core/src/main/java`.
- **Fix:** Replaced the unconstrained `find` with a direct reference to the known generated package path (`android/pjsua2/src/main/java/org/pjsip/pjsua2`).
- **Files modified:** `android-app/scripts/build_pjsip_android.sh` (script); stray copy cleaned directly on disk before Task 2 verification
- **Committed in:** `1634e2d`

**8. [Rule 2 - Missing Critical] `com.android.library` plugin version not declared in root `build.gradle.kts`**
- **Found during:** Task 2
- **Issue:** Only `com.android.application` had a declared version in the root `plugins {}` block; the new `sip-core/build.gradle.kts`'s bare `id("com.android.library")` would fail to resolve a plugin version at sync time.
- **Fix:** Added `id("com.android.library") version "8.5.2" apply false` (matching the existing AGP version).
- **Files modified:** `android-app/build.gradle.kts`
- **Committed in:** `e8714cf`

**9. [Rule 2 - Missing Critical] `sip-core/build/` not gitignored**
- **Found during:** Task 2
- **Issue:** The root `.gitignore` already had an entry for `android-app/app/build/` but not for the newly-introduced `sip-core` module, which would have committed generated Gradle build output (compiled `.class`/`.jar` files, manifests, etc.).
- **Fix:** Added `android-app/sip-core/build/` alongside the existing per-module pattern.
- **Files modified:** `.gitignore` (root)
- **Committed in:** `e8714cf`

---

**Total deviations:** 9 auto-fixed (6 Rule 1 bugs, 3 Rule 2 missing-critical; all discovered by actually running the build to completion rather than skipping/mocking it)
**Impact on plan:** All fixes were necessary to get a genuinely working, reproducible from-source Android PJSIP build with real per-ABI Opus support — matching D-01's explicit requirement. No scope creep; every fix stayed inside `build_pjsip_android.sh` or minimal Gradle wiring.

## Issues Encountered
- The full PJSIP build (both ABIs, from scratch, twice due to the `TARGET_ABI` bug requiring a rebuild) took a genuinely long time in the sandbox — expected given the environment note; handled via background execution and log polling rather than shortcuts.
- `python3 -c "from graphify.watch import _rebuild_code..."` (per project CLAUDE.md) succeeded for the graph data but failed only its optional HTML visualization step ("Graph has 42961 nodes - too large for HTML viz") — almost certainly because the vendored `third_party/pjproject` C source tree (gitignored, but not excluded from graphify's scan) inflated the node count. `graphify-out/graph.json` and `GRAPH_REPORT.md` were written successfully; the HTML viz failure does not block this plan and was left as-is (out of this plan's scope to fix graphify's scan exclusions).

## User Setup Required
None - no external service configuration required. All build tooling (NDK, SWIG, libopus-dev) was installed autonomously in the sandbox per the plan's environment note.

## Next Phase Readiness
- `sip-core` module and its compiled PJSUA2 bindings are ready for Plan 04 (Android SIP call controller) to build `PjsuaEndpointHolder.kt`/`SipCallController.kt` against `org.pjsip.pjsua2.*` directly.
- `PjsuaAvailabilityCheck.kt` is a placeholder smoke check only — Plan 04's task list already documents that it supersedes/deletes this file once the real `Endpoint` lifecycle holder exists.
- No blockers for Plan 04. The iOS-side PJSIP build (GitHub Actions macOS runner, per D-02) is out of scope for this plan and remains a separate, not-yet-executed track.

---
*Phase: 02-pjsip-audio-media-core*
*Completed: 2026-08-08*

## Self-Check: PASSED

All created files verified present on disk; both task commits (`1634e2d`, `e8714cf`) verified in `git log`.
