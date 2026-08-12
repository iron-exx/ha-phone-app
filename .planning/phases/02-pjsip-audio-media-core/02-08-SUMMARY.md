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
affects: [02-PHASE-SIGNOFF, phase-2-verification]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Manual test procedure docs are corrected in-place when new information (e.g. a since-resolved CI checkpoint) makes an earlier section stale, rather than left as a point-in-time snapshot"

key-files:
  created: []
  modified:
    - tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md

key-decisions:
  - "Task 1 (author the manual test procedure + run automated suites) was already committed in a prior session (e8c09ca, 2026-08-08); this session re-verified it was still accurate, found it stale (predated Plan 03 Task 3's CI resolution), and corrected it in a follow-up commit rather than leaving outdated iOS status information in a document Task 3's phase sign-off will cite as evidence"
  - "Task 2 (real-device manual verification matrix: real SIP calls, Bluetooth audio routing, physical WiFi-to-cellular network switch) cannot be executed from this Linux sandbox -- no real Android device, no real HA-Phone box reachable, no Bluetooth hardware. This is the plan's own explicitly-declared checkpoint:human-verify gate=blocking, not a skipped step."
  - "Task 3 (write 02-PHASE-SIGNOFF.md) was NOT started -- its own <action> block requires 'Task 2's reported results' as input, which do not exist yet. Writing it now would mean inventing pass/fail data for CALL-01/CALL-05/D-09, which the deviation rules and this plan's own design explicitly forbid (matches 01-PHASE-SIGNOFF.md's precedent of only documenting what was actually proven)."

patterns-established: []

requirements-completed: []  # CALL-01/CALL-05 remain open -- Task 2's real-device verification (and Task 3's sign-off built on it) has not run yet.

# Metrics
duration: 22min
completed: 2026-08-12
---

# Phase 2 Plan 08: Phase 2 Close-Out (Manual Test Procedure Correction) Summary

**Corrected `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md`'s stale iOS CI status (now cites the resolved, green `build-test` run on commit `d6b623e7` and names the Opus-disabled-for-iOS gap explicitly) and re-confirmed both automated suites green (Android 24/24, HA-Phone backend 93/2/0); Task 2's real-device manual verification matrix and Task 3's phase sign-off remain blocked pending that human-only verification.**

## Performance

- **Duration:** 22 min
- **Started:** 2026-08-12T10:45:00Z
- **Completed:** 2026-08-12T11:07:19Z
- **Tasks:** 1 of 3 fully complete this session (Task 1 was already committed in a prior session and is corrected here); Task 2 blocked on a checkpoint this sandbox cannot execute; Task 3 not reached (depends on Task 2)
- **Files modified:** 1

## Accomplishments

- Re-verified Task 1's already-committed work (`e8c09ca`, 2026-08-08): `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md` exists, mirrors Phase 1's `MANUAL_TEST_PROCEDURE.md` structure (Test Extension table, CALL-01 codec matrix, CALL-05 Asterisk CLI sequence, Result Log Table, iOS Status section), and still satisfies every one of the task's acceptance-criteria greps (`pjsip show contacts` count 2, `sip show registry` count 0).
- Re-ran both automated suites from scratch to reconfirm the doc's claims still hold:
  - Android: `cd android-app && ./gradlew testDebugUnitTest --console=plain` -> `BUILD SUCCESSFUL`; cross-checked the 7 test-result XML files directly (`CallControlTest` x5, `DialpadSanitizeTest` x4, `NetworkChangeHandlerTest` x1, `EnvelopeVerifierTest` x5, `DtmfControllerTest` x2, `CodecConfigTest` x2, `DialpadTest` x5 = 24 tests, 0 failures, 0 errors).
  - HA-Phone backend (cross-repo, `~/projects/Ha-Phone/ha-phone`): `python3 -m pytest backend/tests/test_api.py backend/tests/test_cont_init_tls.py -x` reproduces the known pre-existing `pydantic`/`sqlmodel` environment mismatch on the shared interpreter (documented since 02-01-SUMMARY.md, out of scope for this plan); worked around exactly as the prior session did, by prepending a scratch-installed current `pydantic` via `PYTHONPATH` (no shared-environment or repo files touched) -- result: 93 passed, 2 skipped, 0 failed, matching the doc's recorded figures exactly.
- **Found the doc stale and fixed it (Rule 1 -- factual bug, not a new feature):** Task 1's iOS Status / Automated Suite Status sections were authored 2026-08-08, before Plan 03's Task 3 checkpoint was resolved (2026-08-12, commit `d6b623e7`, CI run https://github.com/iron-exx/ha-phone-app/actions/runs/31588437266/job/94087580778). The doc still said iOS CI status was unconfirmed ("neither plan's iOS code has actually been confirmed green on that CI run yet"). Since this document is the evidence trail Task 3's `02-PHASE-SIGNOFF.md` will cite, leaving it stale would propagate outdated information into the sign-off. Corrected both sections to state plainly: `build-test` is green end-to-end (build+link+unit tests, not just structural checks) on `d6b623e7`, and that same session permanently disabled Opus for iOS (`PJMEDIA_HAS_OPUS_CODEC 0`) because Homebrew's build is macOS-native and cannot link into iOS/iOS-Simulator -- named as an explicit, accepted gap rather than silently omitted, per this session's explicit instructions.
- Confirmed the config-substitution grep gates from Plan 04 Task 3 / Plan 05 Task 3 (cited by Task 3's `<action>` block) both pass with zero leftover placeholders: `grep -Ec "<ha-phone-host>|TODO.*Plan 01" HAPhoneTestApplication.kt` = 0, same for `HAPhoneTestAppApp.swift` = 0.
- Did **not** attempt Task 2 (the real-device manual verification matrix: real SIP calls over 3 codecs, Bluetooth audio routing, physical WiFi-to-cellular network switch, Asterisk CLI registration-lifecycle check) -- this plan's own frontmatter marks it `type="checkpoint:human-verify" gate="blocking"`, and none of the required hardware (a real Android device, the live HA-Phone Asterisk box, Bluetooth audio hardware, a cellular radio to switch to) exists in this Linux sandbox. See "Checkpoint" section below.
- Did **not** start Task 3 (`02-PHASE-SIGNOFF.md`) -- its `<action>` block explicitly requires "Task 2's reported results" as input (codec pass/fail rows, the actual D-09 network-switch outcome). Writing the sign-off now would mean fabricating that evidence, which contradicts both the deviation rules and this plan's entire purpose (an honest, evidence-based close-out, mirroring `01-PHASE-SIGNOFF.md`'s explicit "not silently resolved" pattern).

## Task Commits

1. **Task 1: Run full automated suites + author the manual test procedure doc** - `e8c09ca` (docs, prior session, 2026-08-08) -- re-verified, not re-executed, this session.
2. **Task 1 correction: fix stale iOS CI status + Opus gap** - `9597db6` (fix, this session) -- see "Deviations from Plan" below.
3. **Task 2: Perform the real-device manual verification matrix** - NOT STARTED (blocking checkpoint:human-verify, no compatible hardware in this sandbox).
4. **Task 3: Write 02-PHASE-SIGNOFF.md** - NOT STARTED (depends on Task 2's results).

**Plan metadata:** this SUMMARY.md, committed per the task_commit_protocol immediately after this file was written (STATE.md/ROADMAP.md intentionally excluded -- orchestrator-owned in this worktree-parallel execution).

## Files Created/Modified

- `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md` - iOS Status and Automated Suite Status sections corrected to cite the resolved Plan 03 CI checkpoint (`d6b623e7`) and the Opus-disabled-for-iOS gap; re-confirmation note added recording this session's suite re-runs.

This repo (`ha-phone-app`):
- `.planning/phases/02-pjsip-audio-media-core/02-08-SUMMARY.md` - this file

## Decisions Made

- Corrected the already-committed manual test doc rather than leaving it as a stale point-in-time snapshot, since Task 3 (not yet reached) will treat it as its evidence source -- propagating outdated "CI unconfirmed" language into the phase sign-off would misrepresent what was actually proven.
- Did not fabricate or assume Task 2's real-device results to unblock Task 3 -- the plan's `<verification>`/`<success_criteria>` explicitly require the sign-off to document "the real D-09 network-switch outcome... not assumed," which structurally requires Task 2 to have actually run first.
- Reconfirmed (did not just trust the doc's recorded numbers) both automated suites by re-running them fresh this session, since re-verification is cheap and this plan's whole purpose is an honest evidence trail.

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

- **Cross-checkout path hazard (process note, not a plan deviation):** early in this session, several Read/Bash operations were run against `/home/roto/projects/ha-phone-app/...` (the shared main checkout, currently identical content to this worktree) rather than the `.claude/worktrees/agent-a462b748c3924c4ea/` prefixed path. The Edit tool correctly refused a shared-checkout write and forced the correct worktree path. Verified via `diff` that both checkouts held identical content for every file read this way (no drift occurred), and confirmed via `git worktree list` that both were at the same commit (`e7fa7e3`) at the time. All actual file mutations (Edit/Write/commit) in this session targeted the correct worktree path only.
- **Backend pytest environment mismatch (pre-existing, deferred, not fixed):** same `pydantic==2.5.3` vs `sqlmodel==0.0.38` `model_dump(context=...)` `TypeError` documented since 02-01-SUMMARY.md; worked around via a scratch-installed `pydantic` on `PYTHONPATH` (no shared environment or repo files touched), matching the prior session's approach.

## User Setup Required

**Task 2 is a blocking checkpoint:human-verify -- see "CHECKPOINT REACHED" below.** The user (or someone with access to a real Android device and the live HA-Phone box) must run the manual test procedure end to end and report back the completed Result Log Table before Task 3 can be written.

## Next Phase Readiness

- Task 1's manual test procedure doc is now accurate and ready to be followed for real; the extension-range discrepancy (extension `13` inside the active 10-99 household range, vs. Plan 01's D-04 intent of an 80-99 sub-range) is already flagged prominently in the doc itself and must be reconciled with the household PBX admin before running real test calls against it.
- Task 3 (`02-PHASE-SIGNOFF.md`) is fully specified and ready to write the moment Task 2's results come back -- nothing else blocks it.
- Phase 2 cannot be marked complete until both Task 2 and Task 3 finish; this plan's own frontmatter (`autonomous: false`) and this plan's `<verification>`/`<success_criteria>` make that explicit, not implicit.

---
*Phase: 02-pjsip-audio-media-core*
*Completed: 2026-08-12 (Task 1 verified + corrected; Task 2 blocked on human-only real-device verification; Task 3 not reached)*

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

## Self-Check: PASSED

- FOUND: `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md`
- FOUND: `.planning/phases/02-pjsip-audio-media-core/02-08-SUMMARY.md` (this file)
- FOUND: commit `e8c09ca` in `git log --all`
- FOUND: commit `9597db6` in `git log --all`
- CONFIRMED: `grep -c "pjsip show contacts"` returns 2 in the corrected doc
- CONFIRMED: `grep -c "sip show registry"` returns 0 in the corrected doc
- CONFIRMED: Android suite re-run this session -- 24 tests, 0 failures, 0 errors (cross-checked against `app/build/test-results/testDebugUnitTest/TEST-*.xml`)
- CONFIRMED: HA-Phone backend suite re-run this session -- 93 passed, 2 skipped, 0 failed
