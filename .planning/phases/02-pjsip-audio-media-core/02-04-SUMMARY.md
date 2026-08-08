---
phase: 02-pjsip-audio-media-core
plan: 04
subsystem: telephony
tags: [pjsip, pjsua2, android, telecom, sip, dtmf, codec-priority, kotlin]

# Dependency graph
requires:
  - phase: 02-pjsip-audio-media-core (plan 01)
    provides: cross-repo HA-Phone TLS/SRTP test-extension prerequisite (D-06) -- NOTE, not yet live-verified, see Deviations
  - phase: 02-pjsip-audio-media-core (plan 02)
    provides: PJSIP 2.17 Android build (sip-core Gradle module, org.pjsip.pjsua2.* bindings)
provides:
  - SipCallController public API (makeCall/answer/hold/mute/transfer/sendDtmf/hangup) implementing CALL-01..05
  - PjsuaEndpointHolder -- real PJSUA2 Endpoint/Account/Call lifecycle owner, including inbound-call handle (HAPhoneAccount.onIncomingCall)
  - CallRegistration.reportOutgoingCall (DIRECTION_OUTGOING), mirroring reportIncomingCall
  - NetworkChangeHandler/IpChangeNotifier seam driving D-09 mid-call network-switch recovery
  - BuildConfig-based (not hardcoded) real HA-Phone test-extension config wiring
affects: [02-pjsip-audio-media-core (plan 06 - dialpad/call UI), 02-pjsip-audio-media-core (plan 08 - manual test procedure), 02-VALIDATION]

# Tech tracking
tech-stack:
  added: []
  patterns: ["local.properties -> BuildConfig for real per-environment test credentials (not tracked source)", "Report-First / Attach-SIP-After (CallRegistration onAnswer/onRegistered gating)"]

key-files:
  created:
    - android-app/app/src/main/java/de/haphone/app/test/sip/CodecPriorities.kt
    - android-app/app/src/main/java/de/haphone/app/test/sip/DialString.kt
    - android-app/app/src/main/java/de/haphone/app/test/sip/SipCallOperations.kt
    - android-app/app/src/main/java/de/haphone/app/test/sip/PjsuaEndpointHolder.kt
    - android-app/app/src/main/java/de/haphone/app/test/sip/NetworkChangeHandler.kt
    - android-app/app/src/main/java/de/haphone/app/test/sip/SipCallController.kt
    - android-app/app/src/test/java/de/haphone/app/test/sip/CodecConfigTest.kt
    - android-app/app/src/test/java/de/haphone/app/test/sip/DialpadSanitizeTest.kt
    - android-app/app/src/test/java/de/haphone/app/test/sip/CallControlTest.kt
    - android-app/app/src/test/java/de/haphone/app/test/sip/NetworkChangeHandlerTest.kt
    - android-app/app/src/test/java/de/haphone/app/test/sip/DtmfControllerTest.kt
  modified:
    - android-app/app/src/main/java/de/haphone/app/test/CallRegistration.kt
    - android-app/app/src/main/java/de/haphone/app/test/HAPhoneTestApplication.kt
    - android-app/app/src/main/java/de/haphone/app/test/TestFcmService.kt
    - android-app/app/build.gradle.kts
    - android-app/local.properties (gitignored, not committed)
    - .gitignore

key-decisions:
  - "Real HA-Phone test-extension host/port/username/password compiled into the app via BuildConfig fields sourced from the already-gitignored android-app/local.properties, instead of the plan's illustrative literal Kotlin string constants -- security-motivated deviation, see below"
  - "Deleted PjsuaAvailabilityCheck.kt (Plan 02 smoke check), superseded by PjsuaEndpointHolder's real Endpoint lifecycle"

requirements-completed: [CALL-01, CALL-02, CALL-03, CALL-04, CALL-05]

# Metrics
duration: ~30min
completed: 2026-08-08
---

# Phase 2 Plan 04: Android SIP Call Controller Summary

**PJSUA2-backed SipCallController implementing makeCall/answer/hold/mute/transfer/sendDtmf/hangup with digit sanitization, transient registration, and both-direction Telecom wiring (incoming + outgoing) into CallRegistration.kt.**

## Performance

- **Duration:** ~30 min
- **Completed:** 2026-08-08
- **Tasks:** 3
- **Files modified:** 17 (11 created, 5 modified, 1 gitignore update; local.properties updated but gitignored/not committed)

## Accomplishments
- Pure-Kotlin `CodecPriorities`/`DialString`/`SipCallOperations` contracts (CALL-01/D-07 codec order, T-2-08 digit sanitization mirroring server-side `_dial_string`)
- `PjsuaEndpointHolder` owns a real, process-lifetime PJSUA2 `Endpoint`, applies codec priorities, exposes `handleIpChange()` (D-09) and a real `asSipCallOperations()` wired to actual PJSUA2 `Account`/`Call`/`AudioMedia` objects (mute via `AudioMedia.adjustTxLevel`, never `AudioManager`, per D-11)
- `HAPhoneAccount.onIncomingCall` constructs the incoming `Call` wrapper and stores it as `activeCall` -- closes the previously-permanent null-activeCall gap for inbound calls (checker blocker fix, iteration 4)
- `SipCallController` implements all 5 CALL-01..05 operations against the `SipCallOperations` seam, with CR-01-style disconnect-on-answer-failure
- `CallRegistration.reportIncomingCall`'s real SIP answer now gated on Telecom's genuine `onAnswer` callback (captured `liveScope`), never fired unconditionally at registration-complete time
- New `CallRegistration.reportOutgoingCall` (`DIRECTION_OUTGOING`) so outgoing calls also register with Telecom and get a live `CallControlScope` for Audio Routing
- `TestFcmService.kt` updated to the new 2-arg `CallRegistration` constructor
- Full `sip.*` unit test suite green (`CodecConfigTest`, `DialpadSanitizeTest`, `CallControlTest`, `NetworkChangeHandlerTest`, `DtmfControllerTest`)

## Task Commits

1. **Task 1: Define shared contracts -- CodecPriorities, DialString, SipCallOperations** - `ec069f5` (feat)
2. **Task 2: PjsuaEndpointHolder -- Endpoint/Account lifecycle + transient registration (CALL-05)** - `a908611` (feat)
3. **Task 3: SipCallController -- makeCall/answer/hold/xfer/sendDtmf + CallRegistration wiring** - `2f800c4` (feat)

**Plan metadata:** (pending — this commit)

## Files Created/Modified
- `android-app/app/src/main/java/de/haphone/app/test/sip/CodecPriorities.kt` - Ordered codec-priority contract (opus/48000=255, g722/16000=200, pcma/pcmu=150)
- `android-app/app/src/main/java/de/haphone/app/test/sip/DialString.kt` - `sanitize`/`toSipUri`, shared by dial/DTMF/transfer
- `android-app/app/src/main/java/de/haphone/app/test/sip/SipCallOperations.kt` - Testable seam over PJSUA2 Call/Account
- `android-app/app/src/main/java/de/haphone/app/test/sip/PjsuaEndpointHolder.kt` - Real Endpoint/Account/Call lifecycle, `HAPhoneAccount.onIncomingCall`, `asSipCallOperations()`
- `android-app/app/src/main/java/de/haphone/app/test/sip/NetworkChangeHandler.kt` - D-09 testable seam (`IpChangeNotifier`)
- `android-app/app/src/main/java/de/haphone/app/test/sip/SipCallController.kt` - Public CALL-01..05 API
- `android-app/app/src/main/java/de/haphone/app/test/CallRegistration.kt` - `reportIncomingCall` real-answer gating fix + new `reportOutgoingCall`
- `android-app/app/src/main/java/de/haphone/app/test/HAPhoneTestApplication.kt` - Owns `PjsuaEndpointHolder`, `sipCallController`, `currentCallControlScope`, network-change observer
- `android-app/app/src/main/java/de/haphone/app/test/TestFcmService.kt` - Updated `CallRegistration` construction site
- `android-app/app/build.gradle.kts` - `buildConfig = true`, reads `local.properties` for `SIP_TEST_*` BuildConfig fields
- `android-app/local.properties` - (gitignored, not committed) real test-extension host/port/username/password
- `.gitignore` - Added `graphify-out/` (untracked generated knowledge-graph cache, unrelated housekeeping found during this plan)
- 5 new JUnit test files under `android-app/app/src/test/java/de/haphone/app/test/sip/`
- Deleted `android-app/app/src/main/java/de/haphone/app/test/sip/PjsuaAvailabilityCheck.kt` (superseded by `PjsuaEndpointHolder`)

## Decisions Made
- Wired the real test-extension credentials through `local.properties` → `BuildConfig` rather than literal Kotlin string constants (see Deviations) -- this repo has a public GitHub remote (`github.com/iron-exx/ha-phone-app`), so committing a real LAN PBX password to git history would be effectively permanent exposure even after a later rotation.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Two `.swigValue()` calls against non-existent enum types**
- **Found during:** Task 2, first `:app:compileDebugKotlin`
- **Issue:** The plan's illustrative snippet called `.swigValue()` on `pjsua_call_flag.PJSUA_CALL_UNHOLD` and `info.lastStatusCode`. This project's actual SWIG 4.2.0-generated bindings (from Plan 02's real build) expose these as plain `public final static int` constants / `int` getters, not enum classes -- `.swigValue()` doesn't exist on them.
- **Fix:** `prm.opt.flag = pjsua_call_flag.PJSUA_CALL_UNHOLD.toLong()` (CallSetting.flag is a `long` setter); `info.lastStatusCode < 400` (already `int`).
- **Files modified:** `android-app/app/src/main/java/de/haphone/app/test/sip/PjsuaEndpointHolder.kt`
- **Verification:** `./gradlew :app:compileDebugKotlin` exits 0
- **Committed in:** `a908611`

**2. [Rule 1 - Bug] `CallControlScope.disconnect()` requires a `DisconnectCause` argument**
- **Found during:** Task 3, `:app:compileDebugKotlin`
- **Issue:** The plan's illustrative snippet called `callControlScope.disconnect()` with no arguments. The actual compiled `androidx.core.telecom 1.0.0` API (confirmed via `javap` against the cached AAR) declares `suspend fun disconnect(disconnectCause: DisconnectCause): CallControlResult` -- no no-arg overload exists.
- **Fix:** `callControlScope.disconnect(DisconnectCause(DisconnectCause.ERROR))`, mirroring `TestFcmService.kt`'s existing `DisconnectCause(DisconnectCause.REJECTED)` precedent for a different cause.
- **Files modified:** `android-app/app/src/main/java/de/haphone/app/test/sip/SipCallController.kt`
- **Verification:** `./gradlew :app:compileDebugKotlin` exits 0
- **Committed in:** `2f800c4`
- **Note:** This means the plan's literal acceptance-criteria grep (`grep -c "callControlScope.disconnect()"` expecting `1`) returns `0` against the corrected code. The underlying requirement -- CR-01-style disconnect-on-SIP-answer-failure -- is fully implemented and exercised; the plan's illustrative string just didn't match the real compiled API surface, the same class of gap Plan 02 already hit multiple times against real PJSUA2 bindings.

**3. [Rule 2 - Missing Critical / Security] Real test-extension credentials wired via `local.properties`/`BuildConfig`, not hardcoded Kotlin literals**
- **Found during:** Task 3, `HAPhoneTestApplication.kt` credential substitution step
- **Issue:** The plan's `must_haves` and acceptance criteria require the real HA-Phone test-extension host/extension/password (confirmed valid: host `192.168.7.10`, port `5061`, extension `13`) to be "compiled into the app config" with "no placeholder token" surviving. The plan's illustrative snippet showed this as literal Kotlin string constants directly in `HAPhoneTestApplication.kt`, a file tracked in git. This repo has a public GitHub remote already pushed to (`github.com/iron-exx/ha-phone-app`); committing a real password for the user's home Asterisk PBX to git history is a standing, essentially-permanent exposure regardless of later rotation, and directly contradicts the loaded `kotlin/security.md` rule ("Never hardcode API keys, tokens, or credentials in source code... use local.properties for local development secrets, BuildConfig fields generated from CI secrets for release builds" -- this project's exact scenario).
- **Fix:** Added `sip.test.host`/`sip.test.port`/`sip.test.username`/`sip.test.password` to `android-app/local.properties` (already gitignored since Phase 1, confirmed via `git check-ignore`), and wired `app/build.gradle.kts` to read it into `BuildConfig.SIP_TEST_HOST`/`_PORT`/`_USERNAME`/`_PASSWORD` fields (`buildFeatures.buildConfig = true`). `HAPhoneTestApplication.kt` now references `BuildConfig.SIP_TEST_*` instead of literal strings -- functionally still "compiled into the app config" at build time, and the file contains zero placeholder tokens (verified by the plan's own grep gate, which returns 0 as required) and zero real secret text.
- **Files modified:** `android-app/app/build.gradle.kts`, `android-app/app/src/main/java/de/haphone/app/test/HAPhoneTestApplication.kt`, `android-app/local.properties` (gitignored, not committed)
- **Verification:** `./gradlew :app:compileDebugKotlin` exits 0 with real values populated locally; `git status --short` confirms `local.properties` is never staged; `git check-ignore -v android-app/local.properties` confirms the ignore rule
- **Committed in:** `2f800c4` (build.gradle.kts, HAPhoneTestApplication.kt); `local.properties` itself is intentionally never committed

**4. [Housekeeping, unrelated to plan scope] Gitignored `graphify-out/`**
- **Found during:** Task 1, post-commit untracked-file check
- **Issue:** Project CLAUDE.md's mandatory post-edit `graphify` rebuild step produces a 159MB `graphify-out/` directory that was untracked and not yet gitignored.
- **Fix:** Added `graphify-out/` to root `.gitignore`.
- **Files modified:** `.gitignore`
- **Committed in:** `ec069f5`

---

**Total deviations:** 4 (2 Rule 1 bugs against real compiled/generated APIs, 1 Rule 2 security-motivated credential-handling change, 1 unrelated housekeeping gitignore fix)
**Impact on plan:** All fixes were necessary for the code to actually compile/run correctly and securely against the real PJSUA2 bindings and androidx.core.telecom API, and to avoid committing a live credential to a public repository. No scope creep -- functional behavior matches the plan's intent in every case.

## Issues Encountered

**Credential substitution / pending-deploy caveat (important for Plan 08):** The real host/extension/password used here (`192.168.7.10:5061`, extension `13`) were supplied directly as confirmed-valid values for this execution rather than read from a `02-01-SUMMARY.md`, because Plan 01 has not yet produced that summary -- `.planning/phases/02-pjsip-audio-media-core/02-01-SUMMARY.md` does not exist on disk. Per the execution brief: Plan 01 Task 3's human-action checkpoint (restarting the real HA-Phone box to activate the `[transport-tls]` Asterisk transport) has code-complete support but has **not yet been confirmed live** -- a git push to the real box is still pending from the user. This means:
- The Android app's SIP config code is complete and compiles against these real values (satisfying this plan's acceptance criteria).
- A real end-to-end call against the live box has **not** been verified yet -- that remains Plan 08's job (manual test procedure), and Plan 08 should not assume the TLS transport is confirmed live just because this plan's config wiring is done.
- Also worth flagging for Plan 08/01 reconciliation: Plan 01's own task text says the test extension should be picked from the 80-99 sub-range (D-04, to avoid colliding with active 10-99 household extensions), but the supplied extension number is `13` -- inside that active range. This discrepancy was not investigated further in this plan (out of scope for Android-app-side work) but should be checked before Plan 08's manual test to confirm extension `13` is genuinely the dedicated Phase 2 test extension and not an active household extension.

No other issues -- all builds/tests ran cleanly in the sandbox against the real `sip-core` PJSUA2 bindings from Plan 02.

## User Setup Required

None for this plan directly. Carried forward from Plan 01 (unresolved): the real HA-Phone box still needs the pending git push + container restart to activate the `[transport-tls]` Asterisk transport before Plan 08's manual test call can succeed. This plan's code is ready and waiting for that; it does not block Plan 04's own completion.

## Next Phase Readiness
- `SipCallController`/`CallRegistration` are ready for Plan 06 (dialpad + Active/Outgoing Call UI) to bind against `HAPhoneTestApplication.sipCallController`/`currentCallControlScope`.
- Plan 08's manual test procedure needs the real credentials to exercise a live call -- they are in `android-app/local.properties` (gitignored) on this machine; whoever runs Plan 08 must ensure that file is present and populated (not committed, so a fresh clone will need it re-added).
- Blocker carried forward (not new to this plan): Plan 01's live TLS transport deploy on the real HA-Phone box is still pending user action before any real call can succeed.

---
*Phase: 02-pjsip-audio-media-core*
*Completed: 2026-08-08*

## Self-Check: PASSED

All 11 created files verified present on disk; `PjsuaAvailabilityCheck.kt` confirmed deleted; all 3 task commits (`ec069f5`, `a908611`, `2f800c4`) verified in `git log`.
