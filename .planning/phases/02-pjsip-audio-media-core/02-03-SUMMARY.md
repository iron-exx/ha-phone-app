---
phase: 02-pjsip-audio-media-core
plan: 03
subsystem: infra
tags: [pjsip, pjsua2, opus, ios, xcodegen, github-actions, ci]

# Dependency graph
requires:
  - phase: 02-pjsip-audio-media-core (plan 01)
    provides: cross-repo HA-Phone TLS/SRTP test-extension prerequisite (D-06)
provides:
  - PJSIP 2.17 from-source iOS build script (device + Simulator archs) with Opus compiled in
  - ios-ci.yml extended to build PJSIP before xcodegen generate
  - project.yml wired to link the resulting pjsua2.xcframework + Obj-C++ header search paths
affects: [02-pjsip-audio-media-core (plan 05 - iOS SIP call controller), 02-VALIDATION, 02-PHASE-SIGNOFF]

# Tech tracking
tech-stack:
  added: [PJSIP 2.17 (iOS, from source), xcodebuild -create-xcframework]
  removed: ["Opus codec (was added via Homebrew in the original Task 1-2 commits; dropped during Task 3's checkpoint resolution -- Homebrew's build is macOS-native and cannot link into iOS/iOS-Simulator. Deferred to a separate from-source iOS cross-compile task.)"]
  patterns: ["from-source iOS build gated to a GitHub Actions macOS runner only, never attempted in this Linux sandbox (D-02)", "gitignored vendored third_party/ + built Frameworks/ output, rebuilt deterministically from a pinned tag every CI run"]

key-files:
  created:
    - ios-app/scripts/build_pjsip_ios.sh
    - ios-app/HAPhoneTestApp/Sip/config_site.h
  modified:
    - .github/workflows/ios-ci.yml
    - ios-app/project.yml
    - .gitignore

key-decisions:
  - "Task 1/2 were executed and committed in a prior session (commits 5551283, 9a5c12b) but this SUMMARY was never generated at the time -- this execution session backfills it after re-verifying both commits against the plan's exact task specs, per STATE.md's tracked blocker."
  - "Task 3 (checkpoint:human-verify, gate=blocking) was NOT executed in this session -- this sandbox has no gh CLI and cannot push/trigger/poll GitHub Actions, matching Phase 1's D-11/01-PHASE-SIGNOFF.md precedent. The live CI run remains unconfirmed."

patterns-established:
  - "iOS PJSIP build step inserted between 'Install XcodeGen' and 'Generate Xcode project' in ios-ci.yml -- must run before xcodegen so the xcframework it produces exists when project.yml's dependencies: entry resolves it"
  - "Compile-time Obj-C++ smoke check (PjsuaSmokeCheck.h/.mm at the time of this plan) proves the xcframework actually links, structurally verified via grep/YAML parsing since xcodebuild cannot run in this sandbox"

requirements-completed: []

# Metrics
duration: unknown (backfilled)
completed: 2026-08-10
---

# Phase 2 Plan 03: PJSIP iOS Build + CI Wiring Summary

**PJSIP 2.17 from-source iOS build script (device + Simulator) authored and wired into `ios-ci.yml` ahead of `xcodegen generate`, with `project.yml` linking the resulting `pjsua2.xcframework` -- Task 3's live GitHub Actions checkpoint is now RESOLVED: `build-test` is green end-to-end (build + link + unit tests) as of commit `d6b623e`, run https://github.com/iron-exx/ha-phone-app/actions/runs/31588437266/job/94087580778.**

## Performance

- **Duration:** Not tracked at the time (Tasks 1-2 were committed in a prior session without a SUMMARY being generated; this session backfills documentation only, doing no new implementation work for Tasks 1-2)
- **Completed:** 2026-08-10 (backfill/verification session); original implementation commits dated 2026-08-08
- **Tasks:** 2 of 3 previously committed and now verified; Task 3 remains an open blocking checkpoint
- **Files modified:** 7 (2 created, 5 modified/extended across the two prior commits)

## Accomplishments
- `ios-app/scripts/build_pjsip_ios.sh` authored: clones pinned `pjproject` tag `2.17` (not a moving branch, mitigating T-2-06), installs Opus via Homebrew, runs `configure-iphone` for both device (arm64) and Simulator (`DEVICE=iPhoneSimulator`) passes, packages the resulting static libs into `pjsua2.xcframework`, and gates success on finding at least one compiled `*opus*.o` object file (Pitfall 3 guard)
- `ios-app/HAPhoneTestApp/Sip/config_site.h` created with `#define PJMEDIA_HAS_OPUS_CODEC 1`, copied into the vendored `pjproject` tree by the build script before `configure-iphone` runs
- `.github/workflows/ios-ci.yml` extended with a "Build PJSIP 2.17 for iOS (device + simulator)" step, inserted strictly between "Install XcodeGen" and "Generate Xcode project" (verified by line number: step at line 21, `xcodegen generate` at line 38)
- `ios-app/project.yml`'s `HAPhoneTestApp` target settings merged (not duplicated) to add `HEADER_SEARCH_PATHS` for the six PJSIP include dirs, `CLANG_CXX_LANGUAGE_STANDARD: gnu++17`, `CLANG_ENABLE_MODULES: NO`, and a `dependencies: [{framework: Frameworks/pjsua2.xcframework, embed: false}]` entry
- A compile-time Obj-C++ smoke check (`PjsuaSmokeCheck.h`/`PjsuaSmokeCheck.mm`, calling `pj::Endpoint::instance().libGetVersion()`) was added in the original Task 2 commit to prove the xcframework links; it was later superseded by the real `PjsuaBridge.h`/`.mm` wrapper in Plan 05 (documented inline in the smoke file's own header comment at the time) -- expected evolution, not a defect in this plan's work
- `.gitignore` extended with `ios-app/third_party/` and `ios-app/Frameworks/` (T-2-07: vendored source and build output are never committed, rebuilt deterministically from the pinned tag every CI run)

## Task Commits

Both task commits were made in a prior session (2026-08-08); re-verified against the plan spec in this session, not redone:

1. **Task 1: Build PJSIP 2.17 from source for iOS with Opus enabled (device + Simulator)** - `5551283` (feat) - 2026-08-08 12:30:08 +0200
2. **Task 2: Wire the PJSIP build into ios-ci.yml and project.yml** - `9a5c12b` (feat) - 2026-08-08 12:30:51 +0200

**Task 3: Confirm the extended iOS CI pipeline actually runs on GitHub** - RESOLVED in a later session (checkpoint:human-verify, gate=blocking) - `build-test` is green on commit `d6b623e`; see "Checkpoint: Task 3" below for the full fix trail.

**Plan metadata:** this commit (SUMMARY.md backfill only -- STATE.md/ROADMAP.md are intentionally left untouched per this execution's parallel-worktree instructions; the orchestrator updates those centrally after the wave completes)

## Files Created/Modified
- `ios-app/scripts/build_pjsip_ios.sh` - Reproducible from-source PJSIP 2.17 iOS build (device + Simulator), Opus-enabled, with a build-verification gate
- `ios-app/HAPhoneTestApp/Sip/config_site.h` - `PJMEDIA_HAS_OPUS_CODEC 1` override consumed by the build script
- `.github/workflows/ios-ci.yml` - New "Build PJSIP 2.17 for iOS" step ahead of `xcodegen generate` (note: the workflow file visible on disk today also contains a later Plan 02-05 addition, "Provision placeholder Secrets.xcconfig", which sits between the PJSIP step and project generation -- unrelated to this plan, confirmed by git blame/commit history, not part of this plan's scope)
- `ios-app/project.yml` - `HAPhoneTestApp` target settings merged (single `settings:` key, no duplication) with PJSIP header search paths + Obj-C++ flags, plus `dependencies:` linking `pjsua2.xcframework`
- `.gitignore` (root) - `ios-app/third_party/` and `ios-app/Frameworks/` added

## Decisions Made
- Confirmed (not re-decided): PJSIP 2.17 pinned tag, from-source build only, executed exclusively on a GitHub Actions macOS runner per D-01/D-02 -- this Linux sandbox never attempts the real build.
- This session's own decision: treat the missing SUMMARY as a backfill/verification task, not a re-execution. Task 1/2 file contents and both commits were diffed against the plan's exact task specs (script contents, config_site.h contents, YAML step ordering, project.yml settings merge) and found to match exactly -- no auto-fixes were needed, nothing was redone.

## Deviations from Plan

None for Tasks 1-2 -- both commits match the plan's task specs exactly (verified via `bash -n`, executable bit, `grep -c` pattern counts, and `python3 -c "import yaml"` parses, all matching the plan's stated acceptance criteria verbatim). No auto-fixes were applied in this session.

One process deviation is worth recording explicitly since it was the reason this session exists:

**1. [Process gap, not a Rule 1-4 deviation] 02-03-SUMMARY.md was never generated in the original execution session**
- **Found during:** Session start (flagged in STATE.md's "Blockers/Concerns" section: "02-03-SUMMARY.md is missing even though Plan 02-03's commits (5551283, 9a5c12b) already exist in git log")
- **Issue:** Tasks 1 and 2 were implemented and committed correctly, but the plan's summary/state-update step was skipped in that earlier session, leaving no documentation artifact and leaving Task 3's checkpoint status unrecorded.
- **Fix:** This session re-read the plan, re-verified both commits' contents against every acceptance criterion, and backfilled this SUMMARY.md. No code changes were made.
- **Files modified:** None (documentation only)
- **Verification:** All Task 1/2 acceptance-criteria commands re-run and passed (see Self-Check below).
- **Committed in:** This SUMMARY's own commit.

## Issues Encountered
None during this backfill/verification session. The working tree was clean at session start (no uncommitted drift from the two prior commits).

## User Setup Required

None remaining. Task 3 required the user to push each fix commit (this sandbox has no git push credentials); that loop is now closed -- see "Checkpoint: Task 3" below.

## Checkpoint: Task 3 (RESOLVED)

**What's built:** PJSIP-for-iOS build step, xcframework linkage, and the app's real Obj-C++ bridge (superseded from the original smoke file by Plan 05) are authored, committed, pushed, and now confirmed green on GitHub Actions -- build, link, AND unit tests, not just a structural YAML check.

**Resolution:** In a later session (2026-08-12), the user pushed each fix commit and pasted back the resulting GitHub Actions log/annotations for diagnosis, run after run, until `build-test` passed clean. The pipeline had never actually been exercised end-to-end before this session (Run #1 was the first real attempt), and it surfaced 8 real, previously-invisible defects across the PJSIP build, the Xcode project, and app runtime code -- none of which any prior sandboxed/structural check could have caught:

1. `pjsua2`'s C++11+ syntax needs an explicit `-std=gnu++17` (Apple clang++ defaults to gnu++98 bare) -- fixed in `build_pjsip_ios.sh`.
2. The Simulator `configure-iphone` pass never actually targeted the Simulator SDK (`DEVICE=iPhoneSimulator` isn't a real variable) -- fixed with `DEVPATH`/`MIN_IOS` pointing at `iPhoneSimulator.platform`.
3. XcodeGen's default project format (objectVersion 77) outpaced the runner's pinned Xcode 15.4 -- pinned via `options.projectFormat: xcode15_3` in `project.yml`.
4. The app's Swift/Obj-C++ bridging header was declared but never actually wired in (`CLANG_ENABLE_MODULES` was `NO`) -- flipped to `YES` to match the official PJSUA2 sample.
5. Pre-existing Phase-1 bug in `PushHandler.swift`: `PKPushPayload.dictionaryPayload` (`[AnyHashable: Any]`) passed directly where `[String: Any]` was expected -- only surfaced because this was the first time the app ever compiled in CI.
6. `AVRoutePickerView` (a UIKit view) used directly in a SwiftUI `ViewBuilder` without a `UIViewRepresentable` wrapper -- fixed in `ActiveCallView.swift`.
7. PJSIP's `pjlib/include/pj/config.h` hard-errors on ARM64 unless `PJ_IS_LITTLE_ENDIAN`/`PJ_IS_BIG_ENDIAN` are pre-defined; `configure-iphone`'s own autoconf script injects these into PJSIP's own build, but Xcode's separate compile of the app's bridge file never received them -- fixed via `GCC_PREPROCESSOR_DEFINITIONS` on the app target.
8. Homebrew's `opus` is a macOS-native build (dylib or static `.a` alike) and can never link into an iOS/iOS-Simulator binary regardless of CPU arch -- **Opus was dropped for this plan's scope** rather than cross-compiling a real iOS libopus (a separate, explicitly deferred task; user confirmed this tradeoff). `configure-iphone` no longer takes `--with-opus`, `config_site.h` sets `PJMEDIA_HAS_OPUS_CODEC 0`, and the app no longer links `-lopus` or sets `opus/48000` codec priority. PJSIP's own bundled codecs (G.711/PCMU/PCMA, GSM, iLBC, Speex) remain available.
9. (Runtime, not build) `NWPathMonitor`'s path-update callback fired on a private background queue and called straight into PJSUA2 (`handleIpChange`) without ever registering that thread with pjlib, crashing every test run on launch ("Calling pjlib from unknown/external thread") -- fixed by hopping back to `DispatchQueue.main` in `NetworkChangeMonitor.start()` before notifying.

**Final proof:** `build-test` completed=success on commit `d6b623e7` -- https://github.com/iron-exx/ha-phone-app/actions/runs/31588437266/job/94087580778 (all steps green: PJSIP build, XcodeGen, app build+link, unit tests).

**Deviation from this plan's original scope:** Opus (declared in this plan's `tech-stack.added` above) is temporarily disabled per item 8 -- tracked as a named, accepted gap for `02-PHASE-SIGNOFF.md`, not a silent regression. Re-enabling it requires a from-source iOS cross-compile of libopus, deferred as its own task.

## Next Phase Readiness
- Plan 05 (iOS SIP call controller) depends on this plan's xcframework/header-search-path wiring existing structurally -- confirmed at the strongest possible level now: it actually compiles, links, and runs unit tests green in CI, not just structurally.
- Task 3 is resolved. The one named, accepted gap carried forward into `02-PHASE-SIGNOFF.md` is Opus being disabled (see item 8 above) -- everything else that blocked a green CI run has been fixed.
- No blockers for continuing other Phase 2 plans -- CI is green.

---
*Phase: 02-pjsip-audio-media-core*
*Completed: 2026-08-12 (Task 3 checkpoint resolved -- CI green end-to-end)*

## Self-Check: PASSED

- FOUND: `ios-app/scripts/build_pjsip_ios.sh` (executable, `bash -n` exits 0, contains `PJSIP_TAG="2.17"`)
- FOUND: `ios-app/HAPhoneTestApp/Sip/config_site.h` (contains `PJMEDIA_HAS_OPUS_CODEC 0` -- Opus deferred, see Checkpoint: Task 3)
- FOUND: `.github/workflows/ios-ci.yml` (valid YAML, contains `build_pjsip_ios.sh`, PJSIP step precedes "Generate Xcode project")
- FOUND: `ios-app/project.yml` (valid YAML, single `settings:` key per target, contains `pjsua2.xcframework`)
- FOUND: commit `5551283` in `git log --all`
- FOUND: commit `9a5c12b` in `git log --all`
- FOUND: commit `d6b623e7` in `git log --all` (final green-CI fix)
- CONFIRMED: `build-test` check-run conclusion=`success` on commit `d6b623e7` via GitHub API
