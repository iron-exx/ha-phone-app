---
phase: 01-push-wakeup-proof-of-concept
plan: 04
subsystem: infra
tags: [github-actions, xcodegen, xcodebuild, ios-simulator, ci]

# Dependency graph
requires:
  - phase: 01-push-wakeup-proof-of-concept (plan 02)
    provides: "ios-app/project.yml (XcodeGen spec) with scheme HAPhoneTestApp, test target HAPhoneTestAppTests, and unit tests EnvelopeVerifierTests/PushHandlerTests/DiagnosticsLogTests"
provides:
  - "GitHub Actions workflow .github/workflows/ios-ci.yml: macOS runner builds the iOS app for the Simulator (unsigned, zero Apple accounts) and runs its unit test suite"
  - "Documented, explicit boundary between what Simulator CI proves (build + unit tests) and what it cannot prove (real VoIP push delivery on a physical device) per D-11"
affects: ["01-06 (phase sign-off must cite this gap as accepted/open, not silently resolved)"]

# Tech tracking
tech-stack:
  added: ["GitHub Actions (macos-14 runner)", "XcodeGen (via Homebrew in CI)"]
  patterns: ["Zero-secret, zero-account CI: unsigned iphonesimulator build via CODE_SIGNING_ALLOWED=NO", "push-to-main + workflow_dispatch trigger only (no pull_request from forks, to bound Actions-minutes exposure)"]

key-files:
  created: [".github/workflows/ios-ci.yml"]
  modified: []

key-decisions:
  - "Followed the plan's D-11 rescoping exactly: no Fastlane, match, App Store Connect API key, TestFlight, or code-signing secret material anywhere in the workflow"
  - "Used CODE_SIGNING_ALLOWED=NO on both the build and test xcodebuild invocations so the workflow needs no Apple ID, no provisioning profile, and no Developer Program membership at all"
  - "Scoped the push trigger to branches: [main] with paths: [\"ios-app/**\"] plus workflow_dispatch, deliberately excluding pull_request from forks to prevent external contributors from burning this repo's Actions minutes budget (documented as threat T-01-05 in the plan)"

patterns-established:
  - "Simulator-only CI as the free substitute for a paid, code-signed device pipeline until an Apple Developer Program membership is purchased"

requirements-completed: [PUSH-01, PUSH-02]

# Metrics
duration: 15min
completed: 2026-08-02
---

# Phase 01: Push Wake-up Proof of Concept — Plan 04 Summary

**Added a free GitHub Actions macOS CI workflow (`.github/workflows/ios-ci.yml`) that generates the Xcode project via XcodeGen, builds `HAPhoneTestApp` unsigned for the iOS Simulator, and runs `xcodebuild test` (EnvelopeVerifierTests, PushHandlerTests, DiagnosticsLogTests) — with zero Apple ID, code signing, App Store Connect account, or paid Developer Program membership required.**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-08-02T13:00Z (approx.)
- **Completed:** 2026-08-02T13:14:09Z
- **Tasks:** 1 of 2 fully completed (Task 2 is verification-only and was attempted but could not run to conclusion in this sandbox — see Issues Encountered)
- **Files modified:** 1 created

## Accomplishments
- Created `.github/workflows/ios-ci.yml`: `push` (branches: main, paths: ios-app/**) + `workflow_dispatch` triggers, `macos-14` runner, `xcodegen generate --spec project.yml`, unsigned `xcodebuild build -sdk iphonesimulator` (`CODE_SIGNING_ALLOWED=NO`), then `xcodebuild test -destination 'platform=iOS Simulator,name=iPhone 16'` (`CODE_SIGNING_ALLOWED=NO`) against the `HAPhoneTestApp` scheme.
- Verified structurally (this sandbox has no macOS/Xcode toolchain, so `xcodebuild` itself cannot run here) via grep-based acceptance criteria and a YAML-validity check — all six plan-specified checks pass (see Task Commits / verification output below).
- Confirmed zero secrets, zero Fastlane/match/TestFlight/App-Store-Connect-API-key content anywhere in the workflow, satisfying the plan's `must_haves.truths` about no signing/distribution material.
- Inline comments in the workflow explicitly document the D-11 boundary: this CI proves build + unit-test correctness on the Simulator only, and explicitly cannot prove real VoIP push delivery on a physical device (PushKit/CallKit has no Simulator support for the VoIP push type).

## Task Commits

Each task was committed atomically:

1. **Task 1: GitHub Actions Simulator-only CI workflow** - `3f3aba2` (feat)
2. **Task 2: Trigger the workflow and confirm it runs green** - no commit (verification-only task; nothing to commit — see Issues Encountered for why the live run could not be confirmed from this sandbox)

_Note: no plan-metadata-only commit was needed beyond the SUMMARY.md commit that follows this file._

## Files Created/Modified
- `.github/workflows/ios-ci.yml` - GitHub Actions workflow: XcodeGen generate -> unsigned iphonesimulator build -> Simulator unit test run, zero secrets/accounts required

## Decisions Made
None beyond what the plan specified — implementation follows the plan's embedded workflow YAML verbatim (scheme/test-target names cross-checked live against `ios-app/project.yml`, which confirmed `HAPhoneTestApp` / `HAPhoneTestAppTests` exactly as the plan's `<interfaces>` section stated).

## Deviations from Plan

None - plan executed exactly as written for Task 1. Task 2 was attempted per the plan's instruction to try the CLI path first before falling back to documentation (see Issues Encountered).

## Issues Encountered

**Task 2 (workflow trigger + confirmation) could not be completed in this sandbox — environment limitation, not a task failure:**
- The `gh` CLI is not installed in this sandbox (`gh: Befehl nicht gefunden` / command not found), so `gh workflow run ios-ci.yml`, `gh run list`, and `gh run watch` could not be attempted at all.
- Separately, per this environment's established constraint (see project memory "Git Push Sandbox Workaround"), this sandbox cannot push commits to the external GitHub remote (`origin` is `https://github.com/iron-exx/ha-phone-app.git`) — the credential helper is not wired up here, so even a push-triggered run cannot be initiated from this worktree. The user runs `git push` themselves (token-in-URL) once commits land on their machine/CI environment.
- Consequence: the workflow's live "conclusion: success" run on GitHub Actions has NOT been confirmed as part of this plan's execution. This must happen after the user (or their environment) pushes this branch/commit to GitHub, either by merging to `main` (fires the `push` trigger automatically per `paths: ["ios-app/**"]`) or by running `gh workflow run ios-ci.yml` manually from an authenticated machine.
- This is flagged here explicitly so Plan 06's phase sign-off does not silently assume the CI has been proven green — that verification step remains outstanding until the workflow actually executes on GitHub's macOS runners, which requires network/GitHub access this sandbox does not have.
- What WAS verified in this sandbox: full structural/static verification of the workflow file — YAML validity (`python3 -c "import yaml..."` → `valid yaml`) and all 5 plan-specified grep-based acceptance criteria (macos runner present, `iphonesimulator` present, exactly one `xcodegen generate` command, zero fastlane/match/TestFlight/ASC references, zero `secrets.` references).

## User Setup Required

None for the workflow itself (zero secrets, zero accounts, zero code signing — that is the entire point of this plan). However:
**Action needed from the user:** push this branch (or merge to `main`) from an environment with GitHub access and an authenticated `gh` CLI (or use the GitHub web UI's Actions tab) to actually trigger `ios-ci.yml` and confirm it reports `conclusion: success`. This sandbox could not do so — see Issues Encountered above.

## Next Phase Readiness
- `.github/workflows/ios-ci.yml` is ready to fire automatically on the next `push` to `main` touching `ios-app/**`, or on-demand via `workflow_dispatch`, once this commit reaches GitHub.
- Plan 06 (phase sign-off) should record PUSH-01/PUSH-02's real-physical-device VoIP push verification as an accepted, open Phase 1 gap (per D-11) — this plan's CI can only prove Simulator build + unit-test correctness, never real backgrounded/terminated/locked-device push delivery.
- Blocker/concern for full closure of this plan's Task 2: the live "green run" confirmation is still outstanding and requires a networked environment with `gh` auth or GitHub UI access — not achievable from this air-gapped-from-GitHub sandbox.

---
*Phase: 01-push-wakeup-proof-of-concept*
*Completed: 2026-08-02*
