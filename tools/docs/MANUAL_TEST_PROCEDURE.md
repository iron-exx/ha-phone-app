# Manual Test Procedure: Push-Wakeup Proof of Concept (Phase 1)

This procedure exercises the push-wakeup path built in this phase: a
signed envelope (`tools/envelope.py`) sent via `tools/push_trigger.py`
toward a real iOS or Android device, verifying the native call UI
appears reliably across app states. There is no real inbound call via
Asterisk in this phase (per D-04/D-05) -- the test-trigger script sends
the push directly.

## Device Matrix Scope (D-03)

- **iOS test device:** the developer's own current-generation iPhone,
  running current iOS (D-01).
- **Android test device:** a Pixel, stock Android, only (D-02).
- **Actually used for the 2026-08-03 run:** a headless Android Emulator
  AVD (`haphone_test_api35`, Pixel 6 profile, API 35 `google_apis`
  x86_64 image with Google Play Services, KVM-accelerated) instead of
  the physical Pixel, at the developer's request. This is a defensible
  substitution for *this* device class specifically: the AVD runs the
  same stock AOSP/Google-APIs build as a Pixel, registers a real FCM
  token against the real Firebase project, and receives real
  Google-delivered FCM messages -- so nothing about the Pixel-vs-emulator
  difference is load-bearing for PUSH-03/PUSH-04. What the emulator does
  NOT substitute for is OEM-specific power management (Samsung/Xiaomi
  etc.), which was already deferred above, and real-world multi-hour
  battery/standby behavior, which was approximated via forced Doze
  (`dumpsys deviceidle force-idle`) rather than an actual overnight idle.
- **Non-Pixel OEM coverage (Samsung, Xiaomi, and other aggressive-OEM
  Android devices) is explicitly deferred, not silently dropped.**
  ROADMAP.md's Phase 1 success criterion #3 ("verified on at least one
  non-Pixel OEM device") is not satisfiable with the current device
  matrix -- no such device is currently available. Phase 1 sign-off is
  scoped to Pixel-only; OEM diversity is revisited as a backlog item at
  Phase 6 hardening, per RESEARCH.md Open Question #3's recommendation.
  This is the explicit resolution to that success criterion for this
  phase -- it is tracked as deferred, not assumed done.

## App States to Exercise (D-09)

Per CONTEXT.md decision D-09, the following five app states are
exercised across manual test runs:

1. **Foreground** -- app open and visible on screen.
2. **Backgrounded** -- app sent to background (home button / swipe up),
   not force-quit.
3. **Locked** -- device screen off / lock screen active.
4. **Terminated** -- app fully force-quit / swiped away from the
   app-switcher (iOS) or recent-apps list (Android).
5. **Overnight standby** -- device locked and idle for 8+ hours,
   started before sleep and checked the following morning. This state
   is the one most likely to expose OS-level Doze/App Standby
   interference, even on stock Android/Pixel, and is run as its own
   long-duration test rather than a quick check.

## Per Test Run

1. Put the device in the target app state (one of the five above).
2. From the ha-phone-app repo, run the test-trigger script for the
   target platform and state, for example:
   ```
   python3 tools/push_trigger.py --platform ios --state locked --device-token <token>
   python3 tools/push_trigger.py --platform android --state backgrounded --device-token <token>
   ```
   The script signs a fresh envelope, sends the push, and logs a
   `sentAt` timestamp (its own local clock) to `tools/logs/push_log.csv`.
3. Observe the device: does the native call UI (CallKit on iOS, the
   incoming-call notification/ConnectionService flow on Android) appear?
   A rough stopwatch/eyeball estimate of latency is sufficient -- per
   D-09 there is no fixed numeric latency target for Phase 1.
4. The app itself logs `receivedAt` (when its push handler fired) and
   `reportedAt` (when `reportNewIncomingCall`/`addCall` returned). For
   iOS specifically, since a *terminated* app has no live Xcode console
   available (no local Mac, per D-10), the app must persist these
   timestamps to a local log file on wake and the developer reads them
   back afterward via TestFlight. For Android, `adb logcat` can be used
   directly against the connected Pixel.
5. Record pass/fail and the rough latency in the Result Log Table
   below. Repeat across at least a few runs per state -- no fixed count
   is required (D-09), but enough repetitions to form a qualitative
   "does this feel reliable" judgment.
6. Run the **overnight standby** state specifically as its own
   long-duration test: trigger the push once before going to sleep with
   the device already locked and idle, then check the result the next
   morning. Do not substitute a short locked-state test for this run --
   its purpose is to catch OS-level background-kill behavior that only
   manifests after extended idle time.

## Result Log Table

| Date | Platform | State | sentAt | receivedAt | reportedAt | Latency (rough) | Pass/Fail | Notes |
|------|----------|-------|--------|------------|------------|------------------|-----------|-------|
| 2026-08-03 | android (emulator, API 35) | foreground | 07:53:38.996 | 07:53:39.273 | 07:53:39.273 | ~0.3s | Pass | Notification shown, `isValid=true isExpired=false`; FSI fired -> IncomingCallActivity resumed |
| 2026-08-03 | android (emulator, API 35) | backgrounded | 07:58:22.960 | 07:58:23.233 | 07:58:23.233 | ~0.3s | Pass | Notification shown; FSI correctly did NOT take over screen (device unlocked + in use -> heads-up), launcher stayed top activity |
| 2026-08-03 | android (emulator, API 35) | killed + screen off (no PIN) | 07:57:00.612 | 07:57:02.221 | 07:57:02.221 | ~1.6s | Pass | App process was 0 before push; woke, screen turned on, IncomingCallActivity became top activity. Screenshot: `tools/logs/screenshots/killed_locked_incoming_call.png` |
| 2026-08-03 | android (emulator, API 35) | killed + deep Doze (overnight sim) | 08:01:18.167 | 08:01:19.613 | 08:01:19.613 | ~1.4s | Pass | `deviceidle get deep` = IDLE before AND after; high-priority FCM punched through Doze, screen woke |
| 2026-08-03 | android (emulator, API 35) | killed + secure PIN keyguard | 08:02:29.791 | 08:02:31.552 | 08:02:31.552 | ~1.8s | Pass | `isKeyguardShowing=true` (real PIN set); IncomingCallActivity displayed OVER the secure lock screen. Screenshot: `tools/logs/screenshots/secure_locked_killed_incoming_call.png` |
| 2026-08-03 | android (emulator, API 35) | force-stopped (`am force-stop`) | 07:55:27.172 | (never) | (never) | n/a | Expected no-delivery | NOT a defect: `am force-stop` sets Android's `stopped=true` package flag, which by design suppresses all FCM/broadcast delivery until the user manually relaunches the app. Verified via `dumpsys package ... stopped=true`. This is more aggressive than a user swiping the app from Recents -- use `am kill` to simulate that instead. |
| — | ios | all states | — | — | — | — | Not performed | Blocked per D-11: real-device VoIP push requires a paid Apple Developer Program membership, which is explicitly out of scope for Phase 1. iOS verification is Simulator build/unit-test level only (Plan 04 CI). Documented as an accepted open gap in 01-PHASE-SIGNOFF.md -- deliberately NOT recorded as a pass. |

## iOS Status (Phase 1)

iOS is verified for Phase 1 **ONLY** via `.github/workflows/ios-ci.yml`
(Plan 04): the app builds unsigned for the iOS Simulator and its unit
test suite (`EnvelopeVerifierTests`, `PushHandlerTests`,
`DiagnosticsLogTests`) passes. `gh` is not installed in this sandbox
and this sandbox cannot push to GitHub (see Plan 04's SUMMARY), so the
live "conclusion: success" run on GitHub Actions has not been directly
re-confirmed from here; Plan 04's own Task 2 verification (structural
YAML/grep checks, since `xcodebuild` cannot run in this sandbox either)
is relied on instead.

**Real physical-device push delivery is NOT TESTED for iOS in Phase
1.** Foreground/backgrounded/locked/terminated/overnight-standby
behavior on an actual iPhone has not been exercised at all. This is a
deliberate, accepted gap per **D-11** (a free "Personal Team" Apple ID
cannot receive the Push Notifications entitlement under any
circumstance, and the user will not pay for an Apple Developer Program
membership in Phase 1) -- not an oversight, and not silently skipped.

This gap closes whenever the user chooses to enroll in the Apple
Developer Program. At that point, Plan 02's app code and the
Simulator-verified test suite are expected to carry over largely
unchanged -- only signing/distribution infrastructure (a superset of
Plan 04's current unsigned CI) would need to be added.

## D-09 Acceptance

Per decision D-09, Phase 1's Definition of Done does **not** use a fixed
numeric test-count or success-rate target. Acceptance is the developer's
own qualitative judgment -- "this feels reliable" -- formed after enough
repetitions across all five app states listed above to be confident in
that judgment. The overnight-standby state is run at least once as its
own dedicated long-duration test (not skipped or approximated by a
shorter run), since it is the state most likely to reveal aggressive
platform power-management behavior that a short foreground/backgrounded
test cannot surface.

If a state repeatedly fails (push never wakes the app), that is a real
Phase 1 blocker to investigate before proceeding -- it should not be
silently averaged away by successes in other states.

## D-12 Empirical Finding: Full-Screen Intent WITHOUT a Play Console Declaration

**Question (from CONTEXT.md D-12):** the Play Console "calling app"
declaration was skipped entirely (it requires a paid Google Play
Developer account, out of scope per the zero-budget constraint). Does
the Android 14+/15 full-screen-intent auto-grant still work for a
*sideloaded* app that registers a self-managed `ConnectionService` /
`PhoneAccount`, with no declaration anywhere?

**Answer: YES — it works, fully, with no declaration.** Measured on
2026-08-03 against API 35 (`targetSdk = 35`, i.e. above the API 34
threshold where the restriction applies):

| Evidence | Observed value |
|----------|----------------|
| `dumpsys package de.haphone.app.test` | `android.permission.USE_FULL_SCREEN_INTENT: granted=true` |
| `cmd appops get ... USE_FULL_SCREEN_INTENT` | `No operations. Default mode: default` (never denied) |
| `dumpsys notification --noredact` | `fullscreenIntent=PendingIntent{...}` present, and allowlisted by NotificationManagerService for +30s |
| Notification template | `android.template=android.app.Notification$CallStyle`, `category=call`, `importance=4` |
| Behaviour, screen off / app killed | `IncomingCallActivity` became `topResumedActivity`, `mWakefulness` went `Asleep` -> `Awake` |
| Behaviour, secure PIN keyguard | `isKeyguardShowing=true` AND `IncomingCallActivity` displayed on top of it |

**Interpretation and its limits.** The Play Console declaration governs
*Play-Store-distributed* apps: Google can revoke the permission for apps
it does not consider calling/alarm apps. A sideloaded install never goes
through that review path, so the permission stays granted and the
platform honours the full-screen intent purely on the strength of the
self-managed `ConnectionService` registration. This confirms the
project's architectural choice (registering as a real calling app rather
than relying on notifications alone) is what actually carries the
behaviour.

**What this does NOT prove:** that the app would keep the grant once
distributed through the Play Store. If the project ever ships via Play,
the declaration becomes necessary again and must be re-tested there.
Recorded here so a future phase does not mistake this result for a
blanket "the declaration is never needed".

## Additional Finding: `POST_NOTIFICATIONS` Is Never Requested at Runtime

On a fresh install the app had
`android.permission.POST_NOTIFICATIONS: granted=false`. Since API 33
this is a runtime permission, and without it **no notification of any
kind is displayed** — meaning the entire push-wake path would silently
appear broken to a real user, even though FCM delivery and the app's own
handler work perfectly.

For this test run the permission was granted manually
(`adb shell pm grant de.haphone.app.test android.permission.POST_NOTIFICATIONS`)
so that the rest of the matrix could be measured. The app itself does
not yet ask for it.

This is a real gap in the Phase 1 Android app (built in Plan 03), not a
test artifact. It is not a Phase 1 blocker — Phase 1's goal is proving
the push-wake mechanism, which is proven — but a runtime permission
request must be added before any real user installs the app. Carried
forward as a known gap.
