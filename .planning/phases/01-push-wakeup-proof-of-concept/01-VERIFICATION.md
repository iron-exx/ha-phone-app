---
phase: 01-push-wakeup-proof-of-concept
verified: 2026-08-03
status: passed
requirements_checked: [PUSH-01, PUSH-02, PUSH-03, PUSH-04]
plans_checked: [01-01, 01-02, 01-03, 01-04, 01-05, 01-06]
---

# Phase 1 Verification: Push-Wakeup Proof of Concept

## Verdict: PASSED

Phase 1's goal — "a platform push reliably wakes the app into native call UI on both iOS and Android, across real devices/OEMs/app states, proven before any other capability is built" — is achieved **to the extent the phase's own documented, user-approved zero-budget constraint allows**, and every place where that extent falls short of the original ROADMAP wording is written down explicitly rather than silently marked satisfied. Nothing found during this verification contradicts what the plans/summaries/sign-off/review claim. This is a `passed` verdict with clearly enumerated accepted exceptions, not a clean-sheet pass and not a `gaps_found`/`human_needed` verdict, for the reasons in §5.

## 1. Requirement Traceability

REQUIREMENTS.md maps PUSH-01..04 to Phase 1. All four appear, correctly and non-redundantly, across the six plans' frontmatter:

| Requirement | Covered by | Cross-check |
|---|---|---|
| PUSH-01 (iOS PushKit wake) | Plan 01 (envelope/CLI), Plan 02 (PushHandler), Plan 04 (CI), Plan 06 (sign-off) | ✓ present in REQUIREMENTS.md, ✓ ROADMAP.md criterion #1/#2 |
| PUSH-02 (CallKit synchronous report) | Plan 02, Plan 04, Plan 06 | ✓ |
| PUSH-03 (Android high-priority FCM wake) | Plan 01, Plan 03, Plan 05 | ✓ ROADMAP.md criterion #3 |
| PUSH-04 (Android self-managed ConnectionService + CallStyle + FSI) | Plan 03, Plan 05 | ✓ ROADMAP.md criterion #4 |

No orphaned or missing requirement IDs. `REQUIREMENTS.md`'s traceability table (lines 91–94), however, still shows all four as **"Pending"** with unchecked `- [ ]` boxes at the top of the file, even though ROADMAP.md's own progress table marks Phase 1 "Complete" (6/6 plans, completed 2026-08-03). This is a bookkeeping staleness gap (REQUIREMENTS.md and STATE.md were not updated when ROADMAP.md was), not a defect in the phase's actual work — noted in §6 as a carried-forward administrative item, not counted against the verdict.

## 2. Must-Haves vs. Actual Codebase (spot-checked, not just SUMMARY claims)

Read the real files for every plan rather than trusting summaries:

- **Plan 01** (`tools/envelope.py`, `tools/push_trigger.py`, `tools/tests/test_envelope.py`): confirmed `CANONICAL_FIELD_ORDER`, sign/verify/canonicalize/is_expired all present; 5 pytest cases exist (`grep -c "^def test_"` → 5, matching the SUMMARY's claim). Private key material confirmed gitignored (`tools/keys/*`).
- **Plan 02** (iOS): `PushHandler.swift` read in full. `reportNewIncomingCall` (line 82) fires unconditionally and synchronously *before* `EnvelopeVerifier.verify`/`isExpired` (lines 86–87); `callEnder.endCall` only runs afterward if invalid/expired (line 90–91) — exactly the "report first, verify after" pattern the plan and RESEARCH.md's Pitfall 1 require. Test files exist with the claimed counts: `EnvelopeVerifierTests.swift` (5), `PushHandlerTests.swift` (5), `DiagnosticsLogTests.swift` (4).
- **Plan 03** (Android): `TestFcmService.kt`, `CallRegistration.kt`, `CallNotificationBuilder.kt` all read in full — see §3 below, since this is also where the CR-01 finding/fix lives.
- **Plan 04** (`.github/workflows/ios-ci.yml`): read in full. Confirmed macOS runner, `xcodegen generate`, unsigned `iphonesimulator` build (`CODE_SIGNING_ALLOWED=NO`), `xcodebuild test` against the Simulator, zero Fastlane/match/TestFlight/ASC-API-key/`secrets.` references, and an inline comment explicitly stating the D-11 boundary (Simulator/unit-test proof only, no real-device VoIP capability).
- **Plan 05** (`tools/docs/MANUAL_TEST_PROCEDURE.md`): read in full — the Result Log Table contains 6 real dated rows (2026-08-03) with concrete `sentAt`/`receivedAt`/`reportedAt` timestamps, latencies, and pass verdicts across foreground/backgrounded/killed+screen-off/killed+Doze/killed+secure-keyguard/force-stop-false-negative. Both referenced screenshots exist on disk (`killed_locked_incoming_call.png`, `secure_locked_killed_incoming_call.png`, 48KB each, timestamped 2026-08-03).
- **Plan 06** (`01-PHASE-SIGNOFF.md`, MANUAL_TEST_PROCEDURE.md's iOS section): both exist, both contain the required "NOT TESTED" / "D-11" / "Simulator" language the plan's own acceptance grep demanded.

All artifacts declared in each plan's frontmatter exist on disk with the claimed content. No must-have was found to be falsely claimed complete.

## 3. Code Review Finding CR-01: Verified Fixed, Not Just Claimed Fixed

01-REVIEW.md's one CRITICAL finding (Android computed envelope `isValid`/`isExpired` but never enforced it — a forged/expired push would ring indefinitely) is the highest-risk claim in this phase's paper trail, since it's exactly the "a push must never unilaterally control a call" property ENTWICKLUNGSPLAN §11 and D-07 exist to guarantee. I read the current source directly rather than trusting the sign-off's narrative:

- `CallRegistration.kt`: `reportIncomingCall`'s callback signature is `CallControlScope.() -> Unit` (not a bare lambda), exposing `disconnect()` to the caller.
- `TestFcmService.kt`: `CallNotificationBuilder.show(...)` still runs unconditionally (correctly preserving Pitfall 2 — never silently drop a push), and *after* that, `if (!isValid || isExpired) { launch { disconnect(...) }; CallNotificationBuilder.cancel(...) }` runs.
- `CallNotificationBuilder.kt`: a new `cancel()` function exists and is what Async-disconnects the manually-posted notification (Telecom's own `disconnect()` doesn't remove it).
- Commit `a9898d0` (`git show --stat`) matches this exactly — same three files, same described mechanism, real diff (52 insertions across 3 files), correctly attributed and dated 2026-08-03.

This is a case where a critical finding was found, fixed, and the fix independently re-derivable from the code itself, not merely asserted in prose. Confidence in this phase's self-reported "fixed" claims is correspondingly high, and I extended that same read-the-code-don't-trust-the-doc discipline to the rest of the phase without finding a contradiction anywhere.

## 4. Deliberate Scope Reductions — Accepted, Not Silently Passed

Per the framing given for this verification, the two D-11/D-12 constraints are treated as documented, user-approved scope decisions, not defects:

- **iOS real-device push (ROADMAP criteria #1, #2):** Genuinely unverified on physical hardware — confirmed by reading `MANUAL_TEST_PROCEDURE.md`'s iOS row (`Not performed`) and its dedicated "iOS Status" section, `01-PHASE-SIGNOFF.md` §2, and Plan 04's SUMMARY. What *is* proven: `ios-ci.yml` is a real, correctly-structured, secrets-free Simulator+unit-test workflow; the report-first CallKit pattern is implemented correctly in `PushHandler.swift` (verified directly, §2 above). The workflow's live green run on GitHub's actual runners is **still unconfirmed** as of this verification — `gh` remains uninstalled in this sandbox and `git status`/`git log origin/main..HEAD` show no usable remote-tracking ref, consistent with the sign-off's own documented sub-gap. This sub-gap is exactly as described, not resolved, not worsened.
- **Non-Pixel OEM coverage (ROADMAP criterion #3):** Explicitly scoped to Pixel-only per D-03, deferred to a Phase 6 backlog item, documented in three separate places (CONTEXT.md, MANUAL_TEST_PROCEDURE.md, PHASE-SIGNOFF.md) with consistent wording. Not silently claimed satisfied anywhere I read.
- **Emulator-for-physical-Pixel substitution:** Also explicit and justified (same stock AOSP/Google-APIs build, real Firebase project, real FCM token) rather than glossed over; the sign-off is explicit about what this substitution does *not* cover (OEM power management, true multi-hour idle vs. forced Doze).
- **Play Console "calling app" declaration (ROADMAP criterion #4):** Skipped per D-12, tested empirically instead of assumed either way — the result (works without any declaration, for a sideloaded app) is a positive, evidence-backed finding with its scope limits (sideload-only) stated up front.

None of these read as an attempt to claim more than was actually done. Every instance I checked hedges correctly and points to the actual evidence or its absence.

## 5. Why `passed` and not `gaps_found` or `human_needed`

- `gaps_found` would fit if the phase's own documentation overclaimed relative to the code, or if the CR-01 fix turned out to be cosmetic. Neither happened — every cross-check in §2–4 confirmed the paper trail against the actual files.
- `human_needed` would fit if there were a live decision blocking further progress. There isn't one for Phase 1 itself: the zero-budget constraint was already the human's explicit decision (D-11/D-12), already acted on, already documented as accepted. The remaining action items (enroll in Apple Developer Program, push to GitHub to fire live CI, get a non-Pixel device) are all *future*, *optional*, and already correctly filed as "Carried Forward" rather than as blockers to Phase 2. Nothing about Phase 1's own scope is stuck waiting on a human right now.
- The phase's actual core value proposition — proving push→native-call-UI wake — is proven end-to-end for Android on a real device class (real Firebase project, real FCM tokens, real signed/tampered envelopes, 5 app states including killed+secure-keyguard, with screenshot evidence), and proven at the maximum level the zero-budget constraint allows for iOS (structural/unit-test level, with the actual CallKit report-first code independently verified correct by reading it). The one CRITICAL security-relevant gap the review process caught was fixed and the fix is verifiable in the current source, not just claimed.

## 6. Carried Forward (informational, not blocking Phase 2)

Restating 01-PHASE-SIGNOFF.md §6 plus two items this verification independently surfaced:

1. iOS real-device push verification — open, blocked on Apple Developer Program enrollment (D-11).
2. `ios-ci.yml` has still never executed on GitHub's runners as of this verification (`gh` absent, no usable remote tracking ref in this sandbox) — structural verification only.
3. `POST_NOTIFICATIONS` not requested at runtime on Android — cosmetic-breaking for a real first-time user, not a Phase 1 blocker.
4. Non-Pixel OEM coverage — deferred to Phase 6.
5. Single dev Ed25519 signing key — key distribution formalization deferred to Phase 6.
6. No retry/timeout logic — deferred to Phase 4/5 (by design, D-08).
7. Android full-screen-intent-without-Play-Console finding is sideload-only; would need re-verification if ever Play-distributed.
8. *(new)* 5 warnings + 4 info findings from 01-REVIEW.md remain open (canonical-JSON non-ASCII divergence WR-01, stale bundle-ID default WR-02, non-functional `--use-sandbox` flag WR-03, dev key file permissions WR-04, missing `POST_NOTIFICATIONS` request WR-05 — same as item 3 — plus 4 lower-severity info items). None block Phase 1's goal; WR-01 in particular is worth prioritizing early in Phase 2/3 since it will bite the first time a real German-language caller name is used.
9. *(new)* `.planning/REQUIREMENTS.md`'s traceability table and top-level checkboxes for PUSH-01..04 still read "Pending"/unchecked, and `.planning/STATE.md` still shows Phase 1 as 0% "executing", despite ROADMAP.md correctly showing Phase 1 complete. Purely an administrative sync gap — recommend updating both files to reflect the phase's actual completed status before or during Phase 2 planning.

---
*Verification performed: 2026-08-03*
*Method: read all 6 PLAN.md frontmatters + all 6 SUMMARY.md files + PHASE-SIGNOFF.md + REVIEW.md + CONTEXT.md + REQUIREMENTS.md + ROADMAP.md + MANUAL_TEST_PROCEDURE.md, then independently spot-checked claims against tools/envelope.py, ios-app/HAPhoneTestApp/PushHandler.swift, android-app's CallRegistration.kt/TestFcmService.kt/CallNotificationBuilder.kt, .github/workflows/ios-ci.yml, commit a9898d0, and the two screenshot files on disk.*
