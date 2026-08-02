---
phase: 01-push-wakeup-proof-of-concept
plan: 03
subsystem: mobile-android
tags: [android, kotlin, fcm, telecom, callstyle, tink, ed25519, gradle]

# Dependency graph
requires:
  - phase: 01-push-wakeup-proof-of-concept (plan 01)
    provides: "Signed push-event envelope contract (tools/envelope.py) and golden cross-language fixture that this plan's Kotlin EnvelopeVerifier must match byte-for-byte"
provides:
  - "Buildable Gradle Android project (android-app/) with Gradle Wrapper bootstrapped from scratch (no system gradle binary available)"
  - "EnvelopeVerifier.kt -- pure-JVM Ed25519 verify + canonical JSON builder (Tink's Ed25519Verify + java.util.Base64), passing all 5 golden-fixture unit tests against Plan 01's Python reference"
  - "TestFcmService -- FirebaseMessagingService that always registers a call and always shows a notification for any call-type data message, regardless of signature validity or expiry"
  - "CallRegistration -- androidx.core.telecom CallsManager self-managed registration wrapper, with the real addCall lambda shape confirmed via bytecode inspection"
  - "CallNotificationBuilder -- CallStyle notification + full-screen intent with canUseFullScreenIntent() runtime check and graceful fallback"
  - "IncomingCallActivity -- minimal placeholder call screen (D-05/D-06), lock-screen-capable"
affects: ["01-05-play-console-declaration"]

# Tech tracking
tech-stack:
  added: ["Gradle 8.9 (via wrapper)", "AGP 8.5.2", "Kotlin 2.0.20", "androidx.core:core-telecom:1.0.0", "com.google.firebase:firebase-messaging-ktx:24.0.1", "com.google.crypto.tink:tink-android:1.14.1", "androidx.compose (BOM 2024.09.00)"]
  patterns:
    - "EnvelopeVerifier uses java.util.Base64 (not android.util.Base64) so it is unit-testable on plain JVM without Robolectric/instrumentation"
    - "Verification result (isValid/isExpired) is logged but never gates whether a notification is shown -- TestFcmService always calls CallRegistration.reportIncomingCall -> CallNotificationBuilder.show, per RESEARCH.md Pitfall 2"
    - "CallsManager.addCall lambdas passed positionally, not by name, since the library's real parameter labels are not confirmed by the public API surface (decompiled from the cached AAR to confirm shape, not names)"

key-files:
  created:
    - android-app/settings.gradle.kts
    - android-app/build.gradle.kts
    - android-app/gradle.properties
    - android-app/gradle/wrapper/gradle-wrapper.properties
    - android-app/gradle/wrapper/gradle-wrapper.jar
    - android-app/gradlew
    - android-app/gradlew.bat
    - android-app/app/build.gradle.kts
    - android-app/app/src/main/AndroidManifest.xml
    - android-app/app/src/main/java/de/systemwerk/haphone/test/EnvelopeVerifier.kt
    - android-app/app/src/main/java/de/systemwerk/haphone/test/TestFcmService.kt
    - android-app/app/src/main/java/de/systemwerk/haphone/test/CallRegistration.kt
    - android-app/app/src/main/java/de/systemwerk/haphone/test/CallNotificationBuilder.kt
    - android-app/app/src/main/java/de/systemwerk/haphone/test/IncomingCallActivity.kt
    - android-app/app/src/main/java/de/systemwerk/haphone/test/HAPhoneTestApplication.kt
    - android-app/app/src/main/java/de/systemwerk/haphone/test/MainActivity.kt
    - android-app/app/src/test/java/de/systemwerk/haphone/test/EnvelopeVerifierTest.kt
  modified:
    - .gitignore
    - android-app/local.properties (gitignored, not committed)

key-decisions:
  - "Added org.jetbrains.kotlin.plugin.compose to both build.gradle.kts files -- Kotlin 2.0+ requires the separate Compose Compiler Gradle plugin, which the plan's snippet omitted; without it the build fails at configuration time before any code even compiles"
  - "Fixed android.app.Person -> androidx.core.app.Person import in CallNotificationBuilder -- NotificationCompat.CallStyle.forIncomingCall requires the AndroidX Person type; the plan's sample imported the platform framework class, which does not compile against NotificationCompat.Builder.addPerson"
  - "Used positional (unnamed) arguments for CallsManager.addCall's 4 callback lambdas instead of the plan's suggested named parameters -- decompiled the cached androidx.core:core-telecom:1.0.0 AAR's classes.jar with javap to confirm the real method shape (suspend fun with (Int)->Unit, (DisconnectCause)->Unit, ()->Unit, ()->Unit + trailing (CallControlScope)->Unit block) since RESEARCH.md's Assumptions Log A3 flagged the exact parameter names as unconfirmed; positional args sidestep that ambiguity entirely without falling back to raw ConnectionService"
  - "Reworded a CallNotificationBuilder comment that explained the always-notify behavior, because the literal substrings \"isValid == false\" and \"skip\" (present in the plan's own suggested comment wording) tripped the plan's own grep-based no-skip acceptance check, even though no skip logic exists (same category of self-tripping check as Plan 01's SUMMARY)"
  - "Added android-app/local.properties (machine-specific SDK path), android-app/.gradle/, android-app/build/, android-app/app/build/, and .idea/ to .gitignore -- none were in the plan's files_modified list but committing them would leak a local machine path and bloat the repo with build artifacts"

requirements-completed: [PUSH-03, PUSH-04]

# Metrics
duration: 13min
completed: 2026-08-02
---

# Phase 1 Plan 03: Android FCM Wake + Telecom CallStyle Notification Summary

**Kotlin/Gradle Android app proving high-priority data-only FCM wakes the app and always produces a CallStyle + full-screen-intent notification via androidx.core.telecom self-managed registration, with an Ed25519 EnvelopeVerifier that reproduces tools/envelope.py's golden fixture byte-for-byte.**

## Performance

- **Duration:** ~13 min
- **Started:** 2026-08-02T09:51:32Z (approx., worktree base commit)
- **Completed:** 2026-08-02T10:04:17Z
- **Tasks:** 3 completed
- **Files modified:** 18 (17 created, 1 modified: .gitignore)

## Accomplishments

- Bootstrapped the Gradle Wrapper from scratch (no system `gradle` binary in this sandbox) by downloading `gradle-wrapper.jar`/`gradlew`/`gradlew.bat` directly from the Gradle 8.9.0 tag, then let the wrapper itself pull Gradle 8.9 on first invocation.
- `EnvelopeVerifier.kt` implements canonical JSON serialization + Tink `Ed25519Verify` verification using `java.util.Base64` (not `android.util.Base64`), making it testable on plain JVM. All 5 golden-fixture unit tests pass (`goldenCanonicalBytesMatchFixture`, `goldenSignatureVerifies`, `tamperedCallerFailsVerification`, `isExpiredTrueForPastTimestamp`, `isExpiredFalseForFutureTimestamp`), matching Plan 01's `tools/envelope.py` fixture exactly (203-byte canonical form, identical signature).
- `TestFcmService.onMessageReceived` always calls `CallRegistration.registerApp()` + `reportIncomingCall()` -> `CallNotificationBuilder.show()`, independent of `EnvelopeVerifier.verify()`/`isExpired()` outcome -- satisfying RESEARCH.md's Pitfall 2 (never silently drop a call-type FCM message).
- `CallRegistration` wraps `androidx.core.telecom.CallsManager` for self-managed calling-app registration (`registerAppWithTelecom` + `addCall`). Since RESEARCH.md flagged the library's exact `addCall` lambda parameter names as unconfirmed (Assumptions Log A3), I decompiled the cached `core-telecom-1.0.0.aar`'s `classes.jar` with `javap` to get ground truth: it's a suspend function taking 4 positional callback lambdas plus a trailing `CallControlScope` block. Used positional arguments to avoid depending on guessed names -- `compileDebugKotlin` confirms this matches the real API.
- `CallNotificationBuilder` builds a `NotificationCompat.CallStyle.forIncomingCall` notification with a runtime `canUseFullScreenIntent()` check (confirmed present on the resolved `androidx.core:core-1.13.1` via the same decompilation approach) and a graceful non-crashing fallback when the OS denies the full-screen-intent grant.
- `IncomingCallActivity` is a minimal Compose screen showing the "HA-Phone Testanruf" placeholder (D-05/D-06) with Answer/Decline buttons that `finish()` the activity; declared `showWhenLocked`/`turnScreenOn` in the manifest for lock-screen display.
- `HAPhoneTestApplication` registers the `haphone_test_calls` notification channel (`IMPORTANCE_HIGH`) at app startup, before any FCM message could arrive.
- `./gradlew testDebugUnitTest` and `./gradlew assembleDebug` both run for real in this sandbox (Java 17 + Android SDK platforms 33/34/35 already present) and both show `BUILD SUCCESSFUL`; `app-debug.apk` exists on disk.

## Task Commits

Each task was committed atomically:

1. **Task 1: Gradle project scaffold + Ed25519 EnvelopeVerifier (Tink, pure JVM)** - `5ce0f93` (feat)
2. **Task 2: FCM service + CallsManager self-managed registration** - `cafeaa6` (feat)
3. **Task 3: CallStyle notification + full-screen intent + incoming-call activity** - `1e94333` (feat)

**Plan metadata:** (this commit)

## Files Created/Modified

- `android-app/gradle/wrapper/gradle-wrapper.jar`, `gradlew`, `gradlew.bat`, `gradle-wrapper.properties` - Gradle Wrapper, bootstrapped from Gradle 8.9.0 (no system gradle binary was present)
- `android-app/settings.gradle.kts`, `android-app/build.gradle.kts`, `android-app/gradle.properties` - Root project config, plugin versions (AGP 8.5.2, Kotlin 2.0.20, Compose Compiler plugin, google-services)
- `android-app/app/build.gradle.kts` - App module: compileSdk 35, minSdk 26, core-telecom/firebase-messaging-ktx/tink-android/Compose dependencies
- `android-app/app/src/main/AndroidManifest.xml` - MANAGE_OWN_CALLS/USE_FULL_SCREEN_INTENT/POST_NOTIFICATIONS permissions, MainActivity/IncomingCallActivity/TestFcmService declarations, HAPhoneTestApplication
- `android-app/app/src/main/java/de/systemwerk/haphone/test/EnvelopeVerifier.kt` - Pure-JVM Ed25519 verify + canonical JSON builder matching tools/envelope.py
- `android-app/app/src/test/java/de/systemwerk/haphone/test/EnvelopeVerifierTest.kt` - 5 golden-fixture JUnit tests
- `android-app/app/src/main/java/de/systemwerk/haphone/test/TestFcmService.kt` - FirebaseMessagingService, always registers call + shows notification
- `android-app/app/src/main/java/de/systemwerk/haphone/test/CallRegistration.kt` - CallsManager self-managed registration wrapper
- `android-app/app/src/main/java/de/systemwerk/haphone/test/CallNotificationBuilder.kt` - CallStyle + full-screen-intent notification builder
- `android-app/app/src/main/java/de/systemwerk/haphone/test/IncomingCallActivity.kt` - Placeholder incoming-call screen
- `android-app/app/src/main/java/de/systemwerk/haphone/test/HAPhoneTestApplication.kt` - Notification channel registration at startup
- `android-app/app/src/main/java/de/systemwerk/haphone/test/MainActivity.kt` - Minimal launcher activity stub
- `.gitignore` - added `android-app/local.properties`, `android-app/.gradle/`, `android-app/build/`, `android-app/app/build/`, `android-app/.kotlin/`, `*.iml`, `.idea/`

## Decisions Made

- Added `org.jetbrains.kotlin.plugin.compose` Gradle plugin to both `build.gradle.kts` files -- Kotlin 2.0+ mandates the separate Compose Compiler plugin when Compose is enabled; the plan's snippet predates this requirement and omitted it, causing a configuration-time failure on first `./gradlew` invocation.
- Fixed `android.app.Person` -> `androidx.core.app.Person` in `CallNotificationBuilder.kt` -- the plan's sample code imported the platform framework `Person` class, but `NotificationCompat.CallStyle.forIncomingCall`/`addPerson` require the AndroidX `Person` type; this was a genuine compile-blocking bug in the plan text, caught by `compileDebugKotlin`.
- Used positional lambda arguments for `CallsManager.addCall` instead of the plan's named-parameter suggestion, after decompiling the cached `core-telecom-1.0.0.aar` to confirm the real method shape via `javap` (confirmed: suspend function, `(Int)->Unit`, `(android.telecom.DisconnectCause)->Unit`, `()->Unit`, `()->Unit`, trailing `(CallControlScope)->Unit` block) -- RESEARCH.md's Assumptions Log A3 explicitly flagged the named-parameter labels as unconfirmed at MEDIUM confidence, and positional args avoid that risk without the heavier fallback to raw `ConnectionService`.
- Reworded one comment in `CallNotificationBuilder.kt` because its literal wording (copied near-verbatim from the plan's own suggested code) contained the substrings `"isValid == false"` and `"skip"`, which tripped the plan's own `grep -c "isValid == false\|skip\|return@show"` acceptance check even though no skip logic exists in the code -- same category of self-tripping literal-text check documented in Plan 01's SUMMARY.
- Added Android-specific `.gitignore` entries (`local.properties`, `.gradle/`, `build/` directories, `.idea/`) since none were declared in the plan's `files_modified` list, but omitting them would have either leaked this machine's absolute SDK path (`local.properties`) or bloated the repo with generated build artifacts on the first commit.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Missing Kotlin Compose Compiler plugin broke Gradle configuration**
- **Found during:** Task 1, first `./gradlew testDebugUnitTest` invocation
- **Issue:** The plan's root/app `build.gradle.kts` snippets enabled `buildFeatures { compose = true }` under Kotlin 2.0.20 without declaring `org.jetbrains.kotlin.plugin.compose`, which Kotlin 2.0+ requires as a separate Gradle plugin when Compose is enabled. Gradle failed at the configuration phase before any compilation started.
- **Fix:** Added `id("org.jetbrains.kotlin.plugin.compose") version "2.0.20" apply false` to the root `build.gradle.kts` and `id("org.jetbrains.kotlin.plugin.compose")` to `app/build.gradle.kts`.
- **Files modified:** android-app/build.gradle.kts, android-app/app/build.gradle.kts
- **Verification:** `./gradlew testDebugUnitTest --tests "*.EnvelopeVerifierTest"` re-run, reached `BUILD SUCCESSFUL` with all 5 tests passing.
- **Committed in:** 5ce0f93 (Task 1 commit)

**2. [Rule 1 - Bug] `android.app.Person` import fails to compile against `NotificationCompat.CallStyle`**
- **Found during:** Task 3, first `./gradlew assembleDebug` invocation
- **Issue:** `CallNotificationBuilder.kt` imported `android.app.Person` (the plan's own sample code) instead of `androidx.core.app.Person`. `NotificationCompat.CallStyle.forIncomingCall(caller, ...)` and `Builder.addPerson(...)` both require the AndroidX `Person` type; passing the framework type is a type mismatch that fails `compileDebugKotlin` with 4 separate cascading errors (`addPerson`, `setFullScreenIntent`, `.build()` all unresolved as a result).
- **Fix:** Changed the import to `androidx.core.app.Person`.
- **Files modified:** android-app/app/src/main/java/de/systemwerk/haphone/test/CallNotificationBuilder.kt
- **Verification:** `./gradlew assembleDebug` re-run, reached `BUILD SUCCESSFUL`, produced `app-debug.apk`.
- **Committed in:** 1e94333 (Task 3 commit)

**3. [Rule 1 - Bug] Comment wording tripped the plan's own "no skip logic" grep acceptance check**
- **Found during:** Task 3, acceptance-criteria verification pass (before the Gradle build attempt)
- **Issue:** The plan's suggested comment text for `CallNotificationBuilder.show()` contained the literal substrings `"isValid == false"` and `"skip"`, both of which the plan's own acceptance criterion `grep -c "isValid == false\|skip\|return@show"` (expected: 0) matches against -- even though the actual code has no branch that skips `notify()`.
- **Fix:** Reworded the comment to describe the same unconditional-`notify()` guarantee without using those literal substrings.
- **Files modified:** android-app/app/src/main/java/de/systemwerk/haphone/test/CallNotificationBuilder.kt
- **Verification:** Re-ran the exact acceptance-criteria grep command, now returns 0.
- **Committed in:** 1e94333 (Task 3 commit)

**4. [Rule 2 - Missing Critical] Missing Android .gitignore entries would have leaked a local machine path and committed build artifacts**
- **Found during:** Task 1, before the first `git add`
- **Issue:** The plan's `files_modified` list did not include `.gitignore`, `local.properties`, or any `build/`/`.gradle/` exclusion, but `android-app/local.properties` contains this sandbox's absolute SDK path (`/home/roto/android-sdk`) and Gradle/AGP generate substantial build-artifact directories on every build.
- **Fix:** Added `android-app/local.properties`, `android-app/.gradle/`, `android-app/build/`, `android-app/app/build/`, `android-app/.kotlin/`, `*.iml`, `.idea/` to the repo's root `.gitignore`.
- **Files modified:** .gitignore
- **Verification:** `git status --short` after each task's `git add` confirmed only intended source files were staged, never `local.properties` or `build/` contents.
- **Committed in:** 5ce0f93 (Task 1 commit)

---

**Total deviations:** 4 auto-fixed (2 blocking build/compile bugs in the plan's own sample code, 1 self-tripping acceptance-check wording issue, 1 missing-critical `.gitignore` hygiene fix)
**Impact on plan:** All four were necessary for the plan to build/verify at all in this sandbox. No scope creep -- no additional features beyond what the plan specified were added; the CallsManager positional-argument choice and the two compile fixes are corrections to get the plan's own specified behavior working, not new behavior.

## Issues Encountered

None beyond the deviations documented above -- all were resolved within this plan's execution without needing to escalate or fall back to the plan's offered alternative (raw `ConnectionService`/`PhoneAccount`).

## User Setup Required

None - no external service configuration required. (Real Firebase project credentials / `google-services.json` and the Play Console "calling app" declaration are needed before this can receive real FCM pushes on a physical device or qualify for the Android 14+ full-screen-intent auto-grant, but that provisioning is explicitly Plan 05's responsibility, not this plan's -- the `com.google.gms.google-services` plugin is declared but not yet applied in `app/build.gradle.kts`, matching the plan's scope.)

## Next Phase Readiness

- The Android half of Phase 1's core value (PUSH-03 wake path, PUSH-04 code-side calling-app registration + CallStyle/full-screen-intent) is code-complete and verified inside this sandbox: both `./gradlew testDebugUnitTest` and `./gradlew assembleDebug` pass with `BUILD SUCCESSFUL`.
- `EnvelopeVerifier.kt` is confirmed byte-for-byte compatible with Plan 01's Python golden fixture, so the Kotlin verifier can be trusted against real signed envelopes once Plan 01's `tools/push_trigger.py` sends real FCM pushes to a physical device.
- Not yet exercised on a real device (no Firebase project/`google-services.json`, no physical Pixel test in this sandbox) -- that manual verification pass, per `tools/docs/MANUAL_TEST_PROCEDURE.md` (Plan 01), still needs to happen once Plan 05 provisions real Firebase credentials and the Play Console declaration.
- No blockers identified for Plan 05 (Play Console "calling app" declaration) -- the code-side `CallsManager` self-managed registration this plan built is exactly the capability that declaration depends on.

## Self-Check: PASSED

- `test -f android-app/app/src/main/java/de/systemwerk/haphone/test/EnvelopeVerifier.kt` etc. -- all key artifacts exist on disk (verified via Write/Read tool confirmations during execution).
- `git log --oneline --all --grep="01-03"` returns 3 task commits (5ce0f93, cafeaa6, 1e94333).
- All `<acceptance_criteria>` from every task re-verified: Task 1 (gradlew executable, 3 dependencies present, 0 android.util.Base64, 2 manifest permissions, 5/5 tests pass), Task 2 (class exists, both call sites present, manifest intent-filter present, compileDebugKotlin succeeds), Task 3 (CallStyle present, canUseFullScreenIntent present, 2 lock-screen manifest attributes, 0 skip-pattern matches after reword, assembleDebug succeeds) -- all PASS.
- Plan-level `<verification>` commands (`./gradlew testDebugUnitTest`, `./gradlew assembleDebug`) both re-run at the end of Task 3 and show `BUILD SUCCESSFUL`.

---
*Phase: 01-push-wakeup-proof-of-concept*
*Completed: 2026-08-02*
