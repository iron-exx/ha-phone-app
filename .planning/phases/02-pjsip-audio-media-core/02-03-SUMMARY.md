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
  added: [PJSIP 2.17 (iOS, from source), Opus (via Homebrew on the macOS runner), xcodebuild -create-xcframework]
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

**PJSIP 2.17 from-source iOS build script (device + Simulator, Opus enabled) authored and wired into `ios-ci.yml` ahead of `xcodegen generate`, with `project.yml` linking the resulting `pjsua2.xcframework` -- structurally verified in this sandbox; live GitHub Actions confirmation remains an open checkpoint.**

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

**Task 3: Confirm the extended iOS CI pipeline actually runs on GitHub** - NOT executed (checkpoint:human-verify, gate=blocking) - requires the user to push and check GitHub Actions; see "Checkpoint: Task 3" below.

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

**Task 3 (checkpoint:human-verify, gate=blocking) requires action from the user -- see "Checkpoint: Task 3" below.** No environment variables or dashboard configuration are needed; the required action is purely "push and watch GitHub Actions."

## Checkpoint: Task 3 (BLOCKING, unresolved)

**What's built:** PJSIP-for-iOS build step, xcframework linkage, and the Obj-C++ smoke file (Tasks 1-2) are authored, committed, and structurally verified (YAML validity + grep checks) from this sandbox. The repo was pushed to GitHub (`iron-exx/ha-phone-app`) earlier in this same overall session, so `.github/workflows/ios-ci.yml`'s extended pipeline is live on GitHub -- but no one has yet confirmed the workflow run actually succeeded.

**Why this session cannot resolve it:** This sandbox has no `gh` CLI and cannot push, trigger, or poll GitHub Actions runs. Per the plan's Task 3 definition (`type="checkpoint:human-verify" gate="blocking"`) and Phase 1's `01-PHASE-SIGNOFF.md` precedent, live CI confirmation is a human-in-the-loop step, not an automatable one from here.

**Exact verification steps (from the plan):**
1. Push this branch (or merge to `main`) so `.github/workflows/ios-ci.yml`'s `paths: ["ios-app/**"]` trigger fires, or manually trigger via GitHub's Actions tab -> "iOS CI" -> "Run workflow".
2. Watch the run: confirm "Build PJSIP 2.17 for iOS (device + simulator)" completes successfully (the script's own `OPUS_OBJ_COUNT` gate fails the step if Opus wasn't compiled in), then confirm "Generate Xcode project" / "Build for iOS Simulator" / "Run unit tests on iOS Simulator" all stay green.
3. Report back pass/fail per step, and if it fails, paste the failing step's log output (most likely failure point per RESEARCH.md Open Question 3: the exact SWIG/`.a` output filenames in the xcframework packaging step may need adjusting for the actual pjproject 2.17 layout).

**Resume signal:** Paste the GitHub Actions run URL + pass/fail per step, or "not yet pushed" if deferring.

**This plan is NOT considered fully complete until Task 3 resolves.** Tasks 1-2 are done and verified; the overall plan-level `<verification>`/`<success_criteria>` explicitly require the live CI green run.

## Next Phase Readiness
- Plan 05 (iOS SIP call controller) depends on this plan's xcframework/header-search-path wiring existing structurally -- that dependency is satisfied regardless of Task 3's outcome, since Plan 05's own commits (already present in git log, per STATE.md) were built on top of exactly this project.yml/build script state.
- Task 3 remains open. Per D-17/D-18 (02-CONTEXT.md), this kind of "accepted, not-hidden gap" is expected to be carried forward into `02-PHASE-SIGNOFF.md` at phase close, with a concrete resumption trigger (user pushes + checks the Actions tab).
- No blockers for continuing other Phase 2 plans in this wave -- this gap is specific to live-CI confirmation for the iOS PJSIP build step, not to any downstream code dependency.

---
*Phase: 02-pjsip-audio-media-core*
*Completed: 2026-08-10 (Tasks 1-2 verified/backfilled; Task 3 checkpoint still open)*

## Self-Check: PASSED

- FOUND: `ios-app/scripts/build_pjsip_ios.sh` (executable, `bash -n` exits 0, contains `PJSIP_TAG="2.17"`)
- FOUND: `ios-app/HAPhoneTestApp/Sip/config_site.h` (contains `PJMEDIA_HAS_OPUS_CODEC 1`)
- FOUND: `.github/workflows/ios-ci.yml` (valid YAML, contains `build_pjsip_ios.sh`, PJSIP step at line 21 precedes "Generate Xcode project" at line 38)
- FOUND: `ios-app/project.yml` (valid YAML, single `settings:` key per target, contains `pjsua2.xcframework`)
- FOUND: commit `5551283` in `git log --all`
- FOUND: commit `9a5c12b` in `git log --all`
- Task 3 intentionally NOT executed (checkpoint boundary honored, no GitHub push/trigger/poll attempted from this sandbox)
