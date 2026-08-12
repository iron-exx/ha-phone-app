---
phase: 02-pjsip-audio-media-core
plan: 08
subsystem: testing
tags: [pjsip, asterisk, manual-test, sign-off, opus, ci]

# Dependency graph
requires:
  - phase: 02-pjsip-audio-media-core (plans 01-07)
    provides: PJSIP/PJSUA2 audio core on Android + iOS, TLS/SRTP test-extension provisioning, real HA-Phone test-extension credentials wired into both apps
provides:
  - "tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md -- corrected to cite the now-resolved Plan 03 iOS CI checkpoint (d6b623e7) as authoritative build+test proof, and to name the Opus-disabled-for-iOS gap explicitly"
  - "Re-confirmed automated suite results this session: Android 24/24 unit tests green, HA-Phone backend 93 passed/2 skipped/0 failed"
  - ".planning/phases/02-pjsip-audio-media-core/02-PHASE-SIGNOFF.md -- Phase 2's sign-off, documenting what was proven for real (Android unit tests, HA-Phone backend tests, iOS CI green on d6b623e7) versus what remains an accepted, named, resumable gap (Task 2's real-device matrix, Plan 01 Task 3's live TLS deploy, Opus-disabled-for-iOS, D-15/D-16/D-17/D-18's iOS real-device audio verification)"
affects: [02-PHASE-SIGNOFF, phase-2-verification, phase-2-complete]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Manual test procedure docs are corrected in-place when new information (e.g. a since-resolved CI checkpoint) makes an earlier section stale, rather than left as a point-in-time snapshot"
    - "A phase sign-off can be written honestly even when a prerequisite checkpoint (Task 2's real-device matrix) never ran -- by naming the gap explicitly, citing its concrete resumption trigger, and never fabricating the pass/fail data that gap would have produced (mirrors 01-PHASE-SIGNOFF.md's D-11 precedent)"

key-files:
  created:
    - .planning/phases/02-pjsip-audio-media-core/02-PHASE-SIGNOFF.md
  modified:
    - tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md

key-decisions:
  - "Task 1 (author the manual test procedure + run automated suites) was already committed in a prior session (e8c09ca, 2026-08-08); this session re-verified it was still accurate, found it stale (predated Plan 03 Task 3's CI resolution), and corrected it in a follow-up commit rather than leaving outdated iOS status information in a document Task 3's phase sign-off will cite as evidence"
  - "Task 2 (real-device manual verification matrix: real SIP calls, Bluetooth audio routing, physical WiFi-to-cellular network switch) cannot be executed from this Linux sandbox -- no real Android device, no real HA-Phone box reachable, no Bluetooth hardware. This is the plan's own explicitly-declared checkpoint:human-verify gate=blocking, not a skipped step."
  - "User explicitly decided how to proceed given Task 2's hardware blocker: carry it forward as a named, accepted gap and write the sign-off now ('Als akzeptierte Lucke weitertragen, Sign-off jetzt schreiben'), rather than leave the plan stuck indefinitely waiting on hardware this project's sandbox will never have. Task 3 is written on this explicit basis, not by silently reinterpreting the plan's own dependency on Task 2's results."
  - "Task 3 (write 02-PHASE-SIGNOFF.md) documents Task 2's non-execution as an explicit, named, resumable gap rather than inventing CALL-01/CALL-05/D-09 pass/fail data -- the sign-off's 'What Was Actually Proven' section is scoped strictly to what real execution (Android/backend/iOS-CI test runs, config-substitution grep gates) actually showed, matching 01-PHASE-SIGNOFF.md's precedent of only documenting what was actually proven."
  - "Independently re-verified (not just cited) the HA-Phone backend suite (93 passed/2 skipped/0 failed, exact match) and the iOS CI green-run (via the public GitHub REST API check-runs endpoint, not gh CLI which remains unavailable) before citing them in the sign-off; the Android suite's third re-run in this fresh worktree hit a gitignored-native-build-artifact gap (third_party/pjproject not rebuilt in this worktree) out of scope to fix here, so that figure is cited from two independently-verified prior sessions instead of fabricated or silently trusted."

patterns-established: []

requirements-completed: []  # CALL-01/CALL-05 remain open per 02-PHASE-SIGNOFF.md -- Task 2's real-device verification never ran (accepted, named, resumable gap); the sign-off documents this honestly rather than marking these requirements complete.

# Metrics
duration: 22min (Task 1 session) + ~35min (this continuation session, Task 3 + re-verification)
completed: 2026-08-12
---

# Phase 2 Plan 08: Phase 2 Close-Out (Manual Test Procedure Correction + Phase Sign-Off) Summary

**Corrected `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md`'s stale iOS CI status, re-confirmed both automated suites green (Android 24/24, HA-Phone backend 93/2/0) plus an independently re-verified iOS CI green run (`d6b623e7` via GitHub's public check-runs API), and wrote `02-PHASE-SIGNOFF.md` documenting what was proven for real versus four named, accepted, resumable gaps -- most notably Task 2's real-device matrix, which the user explicitly decided to carry forward rather than leave the plan permanently stuck on hardware this sandbox will never have.**

## Performance

- **Duration:** 22 min (Task 1 session, 2026-08-12) + ~35 min (this continuation session, Task 3 + independent re-verification)
- **Started:** 2026-08-12T10:45:00Z
- **Completed:** 2026-08-12T11:41:20Z
- **Tasks:** 3 of 3 accounted for -- Task 1 complete (prior session, corrected); Task 2 explicitly carried forward as an accepted, named, resumable gap per the user's decision (never executed -- no real hardware in this sandbox); Task 3 complete this session (`02-PHASE-SIGNOFF.md` written)
- **Files modified:** 1 (this session: 0 further edits to `PHASE2_MANUAL_TEST_PROCEDURE.md`, cited as-is); **Files created:** 1 (`02-PHASE-SIGNOFF.md`)

## Accomplishments

- Re-verified Task 1's already-committed work (`e8c09ca`, 2026-08-08): `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md` exists, mirrors Phase 1's `MANUAL_TEST_PROCEDURE.md` structure (Test Extension table, CALL-01 codec matrix, CALL-05 Asterisk CLI sequence, Result Log Table, iOS Status section), and still satisfies every one of the task's acceptance-criteria greps (`pjsip show contacts` count 2, `sip show registry` count 0).
- Re-ran both automated suites from scratch to reconfirm the doc's claims still hold:
  - Android: `cd android-app && ./gradlew testDebugUnitTest --console=plain` -> `BUILD SUCCESSFUL`; cross-checked the 7 test-result XML files directly (`CallControlTest` x5, `DialpadSanitizeTest` x4, `NetworkChangeHandlerTest` x1, `EnvelopeVerifierTest` x5, `DtmfControllerTest` x2, `CodecConfigTest` x2, `DialpadTest` x5 = 24 tests, 0 failures, 0 errors).
  - HA-Phone backend (cross-repo, `~/projects/Ha-Phone/ha-phone`): `python3 -m pytest backend/tests/test_api.py backend/tests/test_cont_init_tls.py -x` reproduces the known pre-existing `pydantic`/`sqlmodel` environment mismatch on the shared interpreter (documented since 02-01-SUMMARY.md, out of scope for this plan); worked around exactly as the prior session did, by prepending a scratch-installed current `pydantic` via `PYTHONPATH` (no shared-environment or repo files touched) -- result: 93 passed, 2 skipped, 0 failed, matching the doc's recorded figures exactly.
- **Found the doc stale and fixed it (Rule 1 -- factual bug, not a new feature):** Task 1's iOS Status / Automated Suite Status sections were authored 2026-08-08, before Plan 03's Task 3 checkpoint was resolved (2026-08-12, commit `d6b623e7`, CI run https://github.com/iron-exx/ha-phone-app/actions/runs/31588437266/job/94087580778). The doc still said iOS CI status was unconfirmed ("neither plan's iOS code has actually been confirmed green on that CI run yet"). Since this document is the evidence trail Task 3's `02-PHASE-SIGNOFF.md` will cite, leaving it stale would propagate outdated information into the sign-off. Corrected both sections to state plainly: `build-test` is green end-to-end (build+link+unit tests, not just structural checks) on `d6b623e7`, and that same session permanently disabled Opus for iOS (`PJMEDIA_HAS_OPUS_CODEC 0`) because Homebrew's build is macOS-native and cannot link into iOS/iOS-Simulator -- named as an explicit, accepted gap rather than silently omitted, per this session's explicit instructions.
- Confirmed the config-substitution grep gates from Plan 04 Task 3 / Plan 05 Task 3 (cited by Task 3's `<action>` block) both pass with zero leftover placeholders: `grep -Ec "<ha-phone-host>|TODO.*Plan 01" HAPhoneTestApplication.kt` = 0, same for `HAPhoneTestAppApp.swift` = 0.
- Did **not** attempt Task 2 (the real-device manual verification matrix: real SIP calls over 3 codecs, Bluetooth audio routing, physical WiFi-to-cellular network switch, Asterisk CLI registration-lifecycle check) -- this plan's own frontmatter marks it `type="checkpoint:human-verify" gate="blocking"`, and none of the required hardware (a real Android device, the live HA-Phone Asterisk box, Bluetooth audio hardware, a cellular radio to switch to) exists in this Linux sandbox. This checkpoint was surfaced to the user, who explicitly chose to carry it forward as a named, accepted gap rather than leave the plan blocked indefinitely -- see "Checkpoint" section below and `02-PHASE-SIGNOFF.md` gap #1.

### Task 3 (this continuation session): Write `02-PHASE-SIGNOFF.md`

- **Independently re-verified every citation before writing them into the sign-off, rather than copying the prior session's numbers verbatim:**
  - HA-Phone backend suite re-run fresh from this worktree (scratch-installed `pydantic` on `PYTHONPATH`, same workaround as prior sessions, zero shared-environment/repo files touched): **93 passed, 2 skipped, 0 failed** -- exact match to the prior session's recorded figures.
  - iOS CI green-run re-confirmed via the public GitHub REST API (`GET /repos/iron-exx/ha-phone-app/commits/d6b623e7.../check-runs`, no `gh` CLI needed, no auth required for a public repo): `"name": "build-test"`, `"conclusion": "success"`, run URL matches the prior session's citation exactly.
  - Config-substitution grep gates (`HAPhoneTestApplication.kt` / `HAPhoneTestAppApp.swift`) and the manual test doc's own acceptance-criteria greps (`pjsip show contacts` count 2, no legacy `sip show registry`-style command present) all re-run and confirmed passing.
  - Attempted a third independent re-run of the Android suite from this fresh worktree; found it missing several gitignored, locally-built artifacts the main checkout has (`local.properties`, `google-services.json`, and critically the vendored/compiled `third_party/pjproject` native build output). Copied in the first two (confirmed gitignored via `git check-ignore`, no secret-in-git risk); did **not** attempt rebuilding the from-source NDK cross-compile (multi-hour, wildly out of scope for writing a sign-off document) -- documented this honestly in the sign-off's "Re-verification note" rather than silently citing an unverified number or spending hours reproducing a build pipeline this task doesn't require.
- **Wrote `.planning/phases/02-pjsip-audio-media-core/02-PHASE-SIGNOFF.md`**, mirroring `01-PHASE-SIGNOFF.md`'s exact structure (What Was Actually Proven / numbered gap sections with named resumption triggers / Carried Forward), per this plan's Task 3 `<action>` spec. Named four gaps explicitly, each with a concrete resumption trigger, none hidden or marked done:
  1. Plan 02-08 Task 2's real-device manual verification matrix (this session's own carried-forward gap, per the user's explicit decision).
  2. Plan 02-01 Task 3's live TLS/SRTP extension deployment on the real HA-Phone box (cited verbatim from `02-01-SUMMARY.md`'s "Checkpoint: Task 3" section, not re-derived).
  3. Opus disabled for iOS (`PJMEDIA_HAS_OPUS_CODEC 0`, cited from the `02-03-SUMMARY.md` fix-chain commits `89585ac`/`44b3dcd`, ancestors of `d6b623e7`).
  4. D-15/D-16/D-17/D-18's iOS real-device audio verification gap (quoted verbatim from `02-CONTEXT.md`, resumption trigger named verbatim per D-18: Apple Developer Program enrollment, $99/yr).
- Also documented the D-10 correction and the config-substitution gates as **closed**, not carried forward -- distinguishing genuinely resolved items from genuinely open ones rather than lumping everything into one undifferentiated "gaps" list.

## Task Commits

1. **Task 1: Run full automated suites + author the manual test procedure doc** - `e8c09ca` (docs, prior session, 2026-08-08) -- re-verified, not re-executed, this session.
2. **Task 1 correction: fix stale iOS CI status + Opus gap** - `9597db6` (fix, this session) -- see "Deviations from Plan" below.
3. **Task 2: Perform the real-device manual verification matrix** - CARRIED FORWARD AS AN ACCEPTED, NAMED, RESUMABLE GAP (blocking checkpoint:human-verify, no compatible hardware in this sandbox; user explicitly decided to proceed to sign-off rather than block indefinitely). No commit -- nothing was executed or fabricated for this task.
4. **Task 3: Write 02-PHASE-SIGNOFF.md** - `.planning/phases/02-pjsip-audio-media-core/02-PHASE-SIGNOFF.md` created this session (docs commit, see commit hash recorded at plan-completion time below).

**Plan metadata:** this SUMMARY.md, committed per the task_commit_protocol immediately after this file was written (STATE.md/ROADMAP.md intentionally excluded -- orchestrator-owned in this worktree-parallel execution).

## Files Created/Modified

- `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md` - iOS Status and Automated Suite Status sections corrected to cite the resolved Plan 03 CI checkpoint (`d6b623e7`) and the Opus-disabled-for-iOS gap; re-confirmation note added recording the prior session's suite re-runs. Not modified further this session (its citations were independently re-verified, not edited).
- `.planning/phases/02-pjsip-audio-media-core/02-PHASE-SIGNOFF.md` - **created this session.** Documents what was proven for real (Android 24/24 unit tests, HA-Phone backend 93/2/0, iOS CI green on `d6b623e7` independently re-confirmed via GitHub's API, config-substitution gates closed, D-10 correction closed) versus four named, accepted, resumable gaps (Task 2's real-device matrix, Plan 01 Task 3's live TLS deploy, Opus disabled for iOS, D-15/D-16/D-17/D-18's iOS real-device audio verification with D-18's Apple Developer Program resumption trigger named verbatim).

This repo (`ha-phone-app`):
- `.planning/phases/02-pjsip-audio-media-core/02-08-SUMMARY.md` - this file, updated this session to reflect Task 3's completion and the plan's overall state (Tasks 1 and 3 complete, Task 2 carried forward as an accepted gap -- not silently dropped)

## Decisions Made

- Corrected the already-committed manual test doc rather than leaving it as a stale point-in-time snapshot, since Task 3 (not yet reached at the time) would treat it as its evidence source -- propagating outdated "CI unconfirmed" language into the phase sign-off would misrepresent what was actually proven.
- Did not fabricate or assume Task 2's real-device results in Task 3's sign-off -- the plan's `<verification>`/`<success_criteria>` explicitly require the sign-off to document "the real D-09 network-switch outcome... not assumed." Since Task 2 never ran (blocked, then explicitly carried forward by the user rather than executed), `02-PHASE-SIGNOFF.md` records that outcome as not observed, not as pass/fail/partial.
- Reconfirmed (did not just trust the doc's recorded numbers) the automated suites this session too: independently re-ran the HA-Phone backend suite (exact match, 93/2/0) and independently re-confirmed the iOS CI green run via GitHub's public API (not the `gh` CLI, which remains unavailable in this sandbox) rather than simply citing the prior session's numbers unverified.
- **User's explicit resolution for Task 2's hardware blocker:** given this sandbox has no real Android device, no live HA-Phone box, no Bluetooth hardware, and no cellular radio, the user was asked how to proceed and explicitly chose "Als akzeptierte Lucke weitertragen, Sign-off jetzt schreiben" (carry it forward as an accepted gap, write the sign-off now) -- mirroring the precedent Phase 1's own `01-PHASE-SIGNOFF.md` set for its own zero-budget iOS real-device gap (D-11), and the same resolution the user separately chose in this session for Plan 02-01's Task 3 checkpoint (also carried forward as an accepted, still-open gap rather than blocked on). Task 3 was written on this explicit basis.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Manual test procedure doc had stale iOS CI status**
- **Found during:** Task 1 re-verification (session start)
- **Issue:** `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md`'s iOS Status and Automated Suite Status sections stated iOS CI status was unconfirmed ("neither plan's iOS code has actually been confirmed green on that CI run yet"). This was accurate when written (2026-08-08) but is now factually wrong -- Plan 03's Task 3 checkpoint resolved on 2026-08-12 (commit `d6b623e7`, CI run green end-to-end). The doc also never mentioned that Opus was disabled for iOS during that same resolution, an explicitly-named gap this plan's own instructions require to be documented in `02-PHASE-SIGNOFF.md` (not silently omitted) -- and this doc is the evidence source that sign-off cites.
- **Fix:** Rewrote both sections to state the CI resolution plainly (with commit hash + run URL) and to name the Opus gap explicitly, including its practical consequence (CALL-01's Opus row is Android-only in practice until a from-source iOS libopus cross-compile happens).
- **Files modified:** `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md`
- **Verification:** Re-ran the task's own acceptance-criteria greps after the edit (`pjsip show contacts` count 2, `sip show registry` count 0) -- both still pass; re-ran both automated suites fresh and confirmed the same pass/fail counts the doc now records.
- **Committed in:** `9597db6`

---

**Total deviations:** 1 auto-fixed (1 bug -- stale documentation)
**Impact on plan:** Necessary correction to keep the manual test doc accurate as the evidence source for Task 3's not-yet-written sign-off. No scope creep -- no code changes, no new features.

## Issues Encountered

- **Cross-checkout path hazard (process note, not a plan deviation):** early in the prior session, several Read/Bash operations were run against `/home/roto/projects/ha-phone-app/...` (the shared main checkout, currently identical content to that worktree) rather than the correct worktree-prefixed path. The Edit tool correctly refused a shared-checkout write and forced the correct worktree path. Verified via `diff` that both checkouts held identical content for every file read this way (no drift occurred). All actual file mutations (Edit/Write/commit) in that session targeted the correct worktree path only.
- **Backend pytest environment mismatch (pre-existing, deferred, not fixed):** same `pydantic==2.5.3` vs `sqlmodel==0.0.38` `model_dump(context=...)` `TypeError` documented since 02-01-SUMMARY.md; worked around via a scratch-installed `pydantic` on `PYTHONPATH` (no shared environment or repo files touched), matching the prior session's approach. Reproduced identically by this continuation session's independent re-run.
- **Fresh-worktree native build artifact gap (this session, environment-specific, not a code issue):** this continuation session's worktree lacked `local.properties`, `google-services.json`, and the compiled `third_party/pjproject` native build output present only in the main checkout -- all gitignored, locally-built artifacts never intended to be in git. Copied in the first two (safe, confirmed gitignored); did not rebuild the third (a multi-hour NDK cross-compile), so this session's own third re-run of the Android suite could not complete. Documented honestly in `02-PHASE-SIGNOFF.md`'s "Re-verification note" rather than silently trusting or re-deriving the 24/24 figure -- it is cited from two independently-verified prior real runs instead.

## User Setup Required

**None remaining for this plan.** Task 2's real-device manual verification matrix was surfaced to the user as a blocking checkpoint (see "CHECKPOINT REACHED" below, preserved as history); the user explicitly decided to carry it forward as a named, accepted gap rather than perform it now (no real Android device, live HA-Phone box, Bluetooth hardware, or cellular radio available to run it in this environment either). Task 3 proceeded on that explicit basis. Whoever eventually has access to the required hardware can resume via `02-PHASE-SIGNOFF.md` gap #1's resumption trigger (follow `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md` end-to-end and report the completed Result Log Table) -- and per gap #2, Plan 01 Task 3's live TLS transport deploy on the real HA-Phone box must happen first, since Task 2 cannot produce a single real pass/fail result until that transport is live.

## Next Phase Readiness

- Task 1's manual test procedure doc is accurate and ready to be followed for real once the box's TLS transport goes live; the extension-range discrepancy (extension `13` inside the active 10-99 household range, vs. Plan 01's D-04 intent of an 80-99 sub-range) is already flagged prominently in the doc itself and must be reconciled with the household PBX admin before running real test calls against it.
- Task 3 (`02-PHASE-SIGNOFF.md`) is written and committed. Phase 2 is closed out with an honest evidence trail: what was proven for real (Android/backend/iOS-CI automated suites, config-substitution gates, D-10 CLI correction) is clearly separated from what remains an accepted, named, resumable gap (Task 2's hardware-blocked matrix, Plan 01 Task 3's live deploy, Opus-disabled-for-iOS, D-15/D-16/D-17/D-18's iOS real-device audio verification).
- Phase 3 (QR provisioning) has no functional dependency on any of Phase 2's four carried-forward gaps -- none of them block starting Phase 3's own plans. They must each be revisited before either app is considered production-ready for real calls / any real iOS user install, per `02-PHASE-SIGNOFF.md`'s "Carried Forward" section.

---
*Phase: 02-pjsip-audio-media-core*
*Completed: 2026-08-12 (Task 1 verified + corrected; Task 2 carried forward as an accepted, named, resumable gap per explicit user decision; Task 3 complete -- 02-PHASE-SIGNOFF.md written)*

---

## CHECKPOINT REACHED

**Type:** human-verify
**Plan:** 02-08
**Progress:** 1/3 tasks complete (Task 1 verified + corrected this session; Task 2 blocked; Task 3 not reached)

### Completed Tasks

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 | Run full automated suites + author the manual test procedure doc | `e8c09ca` (prior session, 2026-08-08) | `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md` |
| 1 (correction) | Fix stale iOS CI status + name the Opus-disabled-for-iOS gap | `9597db6` (this session) | `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md` |

### Current Task

**Task 2:** Perform the real-device manual verification matrix
**Status:** blocked -- requires real hardware not available in this sandbox
**Blocked by:** This Linux sandbox has no real Android device, no reachable live HA-Phone/Asterisk box, no Bluetooth audio hardware, and no cellular radio to physically switch to -- all of which Task 2's matrix requires. This is the plan's own declared `type="checkpoint:human-verify" gate="blocking"`, not a sandbox limitation being worked around.

### Checkpoint Details

**What's built so far:** `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md` is authored, verified against every acceptance criterion, and corrected to reflect the current, accurate state of the project (Plan 03's iOS CI checkpoint resolved green on `d6b623e7`; Opus disabled for iOS as a named gap). Both automated suites that CAN run in this sandbox are reconfirmed green (Android 24/24 unit tests; HA-Phone backend 93 passed/2 skipped/0 failed). Nothing further can happen automatically -- placing real SIP calls, testing Bluetooth audio routing, and physically switching a phone from WiFi to cellular all require a real Android device and the real HA-Phone box.

**How to verify (from the plan's own `<how-to-verify>` block):**
Follow `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md` end to end on a real Android device (or the API 35 emulator used in Phase 1, if that substitution remains acceptable for this phase too -- note any substitution explicitly, same as Phase 1's sign-off did):
1. **First, resolve the extension-range discrepancy already flagged in the doc:** confirm with the household PBX admin that extension `13` is genuinely a safe, dedicated test extension and not an active household line, since Plan 01's original intent was an extension from the 80-99 sub-range (D-04), not `13` (inside the active 10-99 range).
2. Confirm the TLS transport is actually live on the box (`asterisk -rx "pjsip show transports"` should show a `transport-tls` row) -- per 02-01-SUMMARY.md's still-open Task 3 checkpoint, this may not have happened yet; if not, that must be resolved first (see 02-01-SUMMARY.md's "Checkpoint: Task 3" section for the exact resumption steps).
3. Run through the CALL-01 codec matrix (6 rows: 3 codecs x MO, plus MT where noted) on Android. Note: iOS cannot exercise the Opus row at all (codec disabled, see doc's iOS Status section) -- do not expect or wait on an iOS Opus result.
4. Test DTMF, hold+transfer, and mid-call network switch (WiFi to cellular) on Android.
5. Run the CALL-05 Asterisk CLI verification sequence (`pjsip show contacts`/`pjsip show aor 13`/`pjsip show endpoint 13`).
6. Fill in the Result Log Table in `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md` with actual dates/observations/pass-fail.

### Awaiting

Per the plan's `<resume-signal>`: paste the completed Result Log Table, or describe which rows failed and how. Once that's provided, a continuation agent can write Task 3's `02-PHASE-SIGNOFF.md` using those real results (codec-by-codec pass/fail, the actual D-09 network-switch outcome, and the CALL-05 registration-lifecycle confirmation), plus the already-established D-15/D-16/D-17/D-18 iOS gap documentation and the Opus-disabled-for-iOS gap from this session's correction.

## Checkpoint Resolution: Task 2 (CARRIED FORWARD -- ACCEPTED GAP, not executed)

**Resolution (this continuation session, 2026-08-12):** rather than wait indefinitely for real hardware this sandbox will never have, the user was asked how to proceed and explicitly chose: **"Als akzeptierte Lucke weitertragen, Sign-off jetzt schreiben"** -- carry Task 2 forward as a named, accepted gap and write the phase sign-off now. This is not a resolution in the sense of "the checkpoint's question was answered" (it was not -- no real-device testing occurred); it is a resolution in the sense of "the plan's execution path forward is now unblocked by explicit user decision," matching the same precedent `01-PHASE-SIGNOFF.md` set for Phase 1's own D-11 zero-budget gap, and the same resolution the user separately chose in this session for Plan 02-01's Task 3 checkpoint.

**What this means for Task 3:** `02-PHASE-SIGNOFF.md` (written this session, see below) documents Task 2's non-execution as its own named gap (gap #1) with a concrete resumption trigger, rather than inventing the CALL-01/CALL-05/D-09 pass/fail data Task 2 would have produced. Nothing in the plan's original `<how-to-verify>` block was performed -- it remains exactly as valid a procedure as before, waiting for whoever eventually has the required hardware.

## Task 3 Complete: 02-PHASE-SIGNOFF.md Written

**Progress: 3/3 tasks now accounted for** (Task 1 complete; Task 2 carried forward as an accepted, named, resumable gap per explicit user decision -- not executed, not fabricated; Task 3 complete).

`.planning/phases/02-pjsip-audio-media-core/02-PHASE-SIGNOFF.md` created this session, mirroring `01-PHASE-SIGNOFF.md`'s structure exactly (What Was Actually Proven / numbered gap sections with named resumption triggers / Carried Forward). All of the plan's own acceptance-criteria greps pass:
```
grep -c "D-18" 02-PHASE-SIGNOFF.md                        -> 3
grep -c "Apple Developer Program" 02-PHASE-SIGNOFF.md     -> 2
grep -c "sip show registry" 02-PHASE-SIGNOFF.md           -> 0
grep -c "Carried Forward" 02-PHASE-SIGNOFF.md             -> 1
grep -c "^## What Was Actually Proven" 02-PHASE-SIGNOFF.md -> 1
```

This plan (02-08) and Phase 2's Wave 4 are now DONE from the executor's side.

## Self-Check: PASSED

- FOUND: `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md`
- FOUND: `.planning/phases/02-pjsip-audio-media-core/02-08-SUMMARY.md` (this file)
- FOUND: `.planning/phases/02-pjsip-audio-media-core/02-PHASE-SIGNOFF.md`
- FOUND: commit `e8c09ca` in `git log --all`
- FOUND: commit `9597db6` in `git log --all`
- CONFIRMED: `grep -c "pjsip show contacts"` returns 2 in the corrected doc
- CONFIRMED: `grep -c "sip show registry"` returns 0 in the corrected doc, and 0 in `02-PHASE-SIGNOFF.md`
- CONFIRMED: Android suite figure (24 tests, 0 failures, 0 errors) cited from two independently-verified prior real runs (`e8c09ca`, `9597db6` sessions); this session's own third re-run attempt hit a fresh-worktree native-build-artifact gap (documented in `02-PHASE-SIGNOFF.md`'s "Re-verification note"), not a code regression
- CONFIRMED: HA-Phone backend suite independently re-run this session -- 93 passed, 2 skipped, 0 failed (exact match)
- CONFIRMED: iOS CI green run independently re-confirmed this session via GitHub's public REST API check-runs endpoint (`build-test`, `conclusion: success`, commit `d6b623e7ff59a16aa9243ac18a7e8664678da823`)
- CONFIRMED: `02-PHASE-SIGNOFF.md`'s acceptance-criteria greps all pass (`D-18` count 3, `Apple Developer Program` count 2, `sip show registry` count 0, `Carried Forward` count 1, `## What Was Actually Proven` count 1)
