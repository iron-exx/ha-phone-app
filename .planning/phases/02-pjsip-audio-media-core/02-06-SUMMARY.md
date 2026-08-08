---
phase: 02-pjsip-audio-media-core
plan: 06
subsystem: ui
tags: [android, jetpack-compose, telecom, sip, dialpad, dtmf, material3]

# Dependency graph
requires:
  - phase: 02-pjsip-audio-media-core (plan 04)
    provides: SipCallController (makeCall/answer/hold/mute/transfer/sendDtmf/hangup), CallRegistration.reportIncomingCall/reportOutgoingCall, HAPhoneTestApplication.currentCallControlScope
provides:
  - Reusable 3x4 DialpadComposable + DialedNumberState (one component, three call sites: dial/DTMF/transfer)
  - OutgoingCallActivity -- registers with Telecom via CallRegistration.reportOutgoingCall before makeCall, navigates to ActiveCallActivity only from inside onRegistered (race-condition-safe)
  - ActiveCallActivity -- real Mute/Hold/Audio-Routing/Keypad/Transfer/End-Call UI for CALL-01..05, Audio Routing bound to CallControlScope.availableEndpoints/requestEndpointChange, never AudioManager
  - IncomingCallActivity.onAnswer navigates to ActiveCallActivity instead of finish()
affects: [02-pjsip-audio-media-core (plan 08 - manual test procedure), 02-VALIDATION]

# Tech tracking
tech-stack:
  added: []
  patterns: ["Report-First-then-Navigate (reportOutgoingCall's onRegistered gates both makeCall and startActivity, closing the async-registration race)", "suspend-lambda-via-explicit-local-val (force suspend inference for a lambda literal passed as a named Composable argument)"]

key-files:
  created:
    - android-app/app/src/main/java/de/haphone/app/test/sip/DialedNumberState.kt
    - android-app/app/src/main/java/de/haphone/app/test/DialpadComposable.kt
    - android-app/app/src/main/java/de/haphone/app/test/OutgoingCallActivity.kt
    - android-app/app/src/main/java/de/haphone/app/test/ActiveCallActivity.kt
    - android-app/app/src/test/java/de/haphone/app/test/sip/DialpadTest.kt
  modified:
    - android-app/app/src/main/java/de/haphone/app/test/MainActivity.kt
    - android-app/app/src/main/java/de/haphone/app/test/IncomingCallActivity.kt
    - android-app/app/src/main/AndroidManifest.xml

key-decisions:
  - "Added a minimal ActiveCallActivity.kt stub in Task 2 (Rule 3, blocking-issue fix) so OutgoingCallActivity's reference to it compiles standalone before Task 3 builds the real screen -- Task 3 fully replaces it."
  - "CallControlScope.availableEndpoints is a plain Flow<List<CallEndpointCompat>> on the real compiled androidx.core.telecom 1.0.0 API, not StateFlow as the plan's illustrative snippet assumed -- ActiveCallScreen's parameter type and collectAsState call adjusted accordingly."
  - "A lambda literal passed directly as ActiveCallScreen's onRequestEndpointChange named argument was not inferred as suspend by the Kotlin compiler -- bound to an explicit suspend-typed local val first to force the expected type before the lambda body is analyzed."
  - "ModalBottomSheet/DropdownMenu require @OptIn(ExperimentalMaterial3Api::class) on ActiveCallScreen (Material3 BOM in use marks them experimental)."

requirements-completed: [CALL-01, CALL-02, CALL-03, CALL-04]

# Metrics
duration: ~7min
completed: 2026-08-08
---

# Phase 2 Plan 06: Android Dialpad + Outgoing/Active Call UI Summary

**Reusable 3x4 Jetpack Compose dialpad plus OutgoingCallActivity (Telecom-register-then-dial) and ActiveCallActivity (real Mute/Hold/Audio-Routing/Keypad/Transfer/End-Call), wired to Plan 04's SipCallController and CallControlScope for both incoming and outgoing calls.**

## Performance

- **Duration:** ~7 min
- **Started:** 2026-08-08T13:14:26Z
- **Completed:** 2026-08-08T13:21:20Z
- **Tasks:** 3
- **Files modified:** 8 (5 created, 3 modified)

## Accomplishments
- `DialedNumberState` + `DialpadComposable` -- one 3x4 grid (digits + standard letter subtext), reused at 3 call sites (outgoing dial, in-call DTMF, blind-transfer target) per D-12/D-13/D-14
- `OutgoingCallActivity` implements the Blocker-fix Report-First pattern: `CallRegistration.reportOutgoingCall` registers with Telecom first; `SipCallController.makeCall` and the navigation to `ActiveCallActivity` both fire from inside that call's `onRegistered` lambda, closing the race condition where `currentCallControlScope` could be read before the async Telecom-registration coroutine finished
- `ActiveCallActivity` hosts exactly the 5 CALL-01..05 controls (Mute, Hold, Audio Routing, Keypad, Transfer, End Call) per 02-UI-SPEC.md's layout; Audio Routing renders a real `DropdownMenu` bound to `CallControlScope.availableEndpoints`, and tapping an entry launches a coroutine to call the suspend `requestEndpointChange` -- `AudioManager` is never referenced
- `IncomingCallActivity.onAnswer` now navigates to `ActiveCallActivity` instead of merely `finish()`-ing
- `MainActivity` gains a "Dial" nav entry button; manifest declares both new activities

## Task Commits

1. **Task 1: DialedNumberState + reusable DialpadComposable** - `414c388` (feat)
2. **Task 2: OutgoingCallActivity + MainActivity nav entry (CALL-03)** - `82ff5ee` (feat)
3. **Task 3: ActiveCallActivity + IncomingCallActivity wiring** - `f101357` (feat)

**Plan metadata:** (pending -- this commit)

## Files Created/Modified
- `android-app/app/src/main/java/de/haphone/app/test/sip/DialedNumberState.kt` - Digit-accumulator state, sanitizes via `DialString.sanitize` on every `append`
- `android-app/app/src/main/java/de/haphone/app/test/DialpadComposable.kt` - Shared 3x4 dialpad grid, 64dp keys
- `android-app/app/src/test/java/de/haphone/app/test/sip/DialpadTest.kt` - append/backspace/clear/toCallUri coverage
- `android-app/app/src/main/java/de/haphone/app/test/OutgoingCallActivity.kt` - CALL-03 entry screen; registers with Telecom before dialing, navigates only after registration completes
- `android-app/app/src/main/java/de/haphone/app/test/MainActivity.kt` - Added "Dial" button navigating to `OutgoingCallActivity`
- `android-app/app/src/main/java/de/haphone/app/test/ActiveCallActivity.kt` - Active Call screen hosting all 5 CALL-01..05 controls
- `android-app/app/src/main/java/de/haphone/app/test/IncomingCallActivity.kt` - `onAnswer` navigates to `ActiveCallActivity`
- `android-app/app/src/main/AndroidManifest.xml` - Declares `OutgoingCallActivity` and `ActiveCallActivity`

## Decisions Made
- See `key-decisions` in frontmatter -- all four were compile-driven fixes against the real compiled `androidx.core.telecom` API and Kotlin suspend-lambda inference behavior, not architectural changes.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Forward-reference stub for `ActiveCallActivity`**
- **Found during:** Task 2 (`OutgoingCallActivity` compile)
- **Issue:** Task 2's `OutgoingCallActivity` references `ActiveCallActivity::class.java`, which Task 3 creates later in the same plan -- compiling Task 2 standalone would fail without it.
- **Fix:** Added a minimal `ActiveCallActivity` stub (empty `ComponentActivity`) in Task 2's commit; Task 3 fully replaced it with the real 5-control screen.
- **Files modified:** `android-app/app/src/main/java/de/haphone/app/test/ActiveCallActivity.kt`
- **Verification:** `./gradlew :app:compileDebugKotlin` exits 0 after Task 2 and again after Task 3's full replacement
- **Committed in:** `82ff5ee` (stub), `f101357` (full replacement)

**2. [Rule 1 - Bug] `CallControlScope.availableEndpoints` is a `Flow`, not a `StateFlow`**
- **Found during:** Task 3, `:app:compileDebugKotlin`
- **Issue:** The plan's illustrative snippet typed `ActiveCallScreen`'s `availableEndpoints` parameter as `StateFlow<List<CallEndpointCompat>>?`. The real compiled `androidx.core.telecom 1.0.0` API exposes it as a plain `Flow<List<CallEndpointCompat>>`, so the assignment site (`callControlScope?.availableEndpoints`) failed type-checking.
- **Fix:** Changed the parameter type to `Flow<List<CallEndpointCompat>>?` and switched `collectAsState()` to `collectAsState(initial = emptyList())`, which works uniformly for both a plain `Flow` and the `MutableStateFlow` empty-fallback.
- **Files modified:** `android-app/app/src/main/java/de/haphone/app/test/ActiveCallActivity.kt`
- **Verification:** `./gradlew :app:compileDebugKotlin` exits 0
- **Committed in:** `f101357`

**3. [Rule 1 - Bug] Suspend lambda literal not inferred as `suspend` at the Composable call site**
- **Found during:** Task 3, `:app:compileDebugKotlin`
- **Issue:** The plan's illustrative snippet passed `{ endpoint -> callControlScope?.requestEndpointChange(endpoint) }` directly as `ActiveCallScreen`'s `onRequestEndpointChange` named argument. The Kotlin compiler reported `Suspend function 'requestEndpointChange' should be called only from a coroutine or another suspend function` -- it did not infer the lambda literal as `suspend` from the target parameter's declared type at that call site.
- **Fix:** Bound the lambda to an explicitly `suspend`-typed local val (`val requestEndpointChange: suspend (CallEndpointCompat) -> Unit = { endpoint -> ... }`) before passing it, forcing the expected type ahead of body analysis.
- **Files modified:** `android-app/app/src/main/java/de/haphone/app/test/ActiveCallActivity.kt`
- **Verification:** `./gradlew :app:compileDebugKotlin` exits 0
- **Committed in:** `f101357`

**4. [Rule 1 - Bug] `ModalBottomSheet`/`DropdownMenu` require Material3 experimental opt-in**
- **Found during:** Task 3, `:app:compileDebugKotlin`
- **Issue:** `ModalBottomSheet` is annotated `@ExperimentalMaterial3Api` in the Material3 BOM version this project uses; the plan's snippet used it without an opt-in, causing a compile error (not merely a warning).
- **Fix:** Added `@OptIn(ExperimentalMaterial3Api::class)` to `ActiveCallScreen`.
- **Files modified:** `android-app/app/src/main/java/de/haphone/app/test/ActiveCallActivity.kt`
- **Verification:** `./gradlew :app:compileDebugKotlin` exits 0
- **Committed in:** `f101357`

---

**Total deviations:** 4 (1 Rule 3 blocking-issue forward-reference stub, 3 Rule 1 bugs against the real compiled Compose/Telecom API surface)
**Impact on plan:** All fixes were necessary for the code to compile correctly against the real `androidx.core.telecom` 1.0.0 API and the project's Material3 BOM version. No scope creep -- functional behavior matches the plan's intent (Audio Routing still binds exclusively to `CallControlScope`, never `AudioManager`; the Report-First/race-condition-safe navigation pattern is implemented exactly as specified).

## Issues Encountered

None beyond the deviations documented above -- all discovered and fixed while compiling against the real PJSUA2/Telecom/Compose bindings already established by Plan 04 and this project's Material3 BOM.

## User Setup Required

None for this plan. Carried forward from Plan 04/01 (unresolved, not blocking this plan): the real HA-Phone box's live TLS transport deploy is still pending user action before Plan 08's manual end-to-end test call can succeed; `android-app/local.properties` (gitignored) must still be populated on any fresh checkout for the real credentials this UI's underlying `SipCallController` depends on.

## Next Phase Readiness
- All 5 CALL-01..05 controls now have real, compile-verified UI on Android, for both incoming and outgoing calls -- ready for Plan 08's manual test procedure once the live TLS transport is confirmed on the real HA-Phone box.
- iOS equivalent (DialpadView/OutgoingCallView/ActiveCallView) is out of this plan's scope -- not yet built; Plan 06 as authored only covers Android (`android-app/...` files list in frontmatter). Should be confirmed against the phase's plan list whether a corresponding iOS UI plan exists or is deferred.
- Blocker carried forward (not new to this plan): Plan 01's live TLS transport deploy on the real HA-Phone box is still pending user action before any real call can succeed.

---
*Phase: 02-pjsip-audio-media-core*
*Completed: 2026-08-08*

## Self-Check: PASSED

All 5 created files verified present on disk; all 3 task commits (`414c388`, `82ff5ee`, `f101357`) verified in `git log`; `./gradlew :app:compileDebugKotlin` and `./gradlew testDebugUnitTest` both green as of the final commit.
