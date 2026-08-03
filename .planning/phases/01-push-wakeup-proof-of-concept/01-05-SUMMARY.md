---
phase: 01-push-wakeup-proof-of-concept
plan: 05
subsystem: mobile-android
tags: [firebase, fcm, android-emulator, doze, full-screen-intent, manual-test, d-12]

# Dependency graph
requires:
  - phase: 01-push-wakeup-proof-of-concept (plan 01)
    provides: "tools/push_trigger.py + Ed25519 envelope contract used to send the real signed test pushes"
  - phase: 01-push-wakeup-proof-of-concept (plan 03)
    provides: "Android app (TestFcmService, CallRegistration, CallNotificationBuilder, IncomingCallActivity) that this plan wires to a real Firebase project and tests on a device"
provides:
  - "Real Firebase project (haphone-e30ca) wired into the Android app via google-services plugin + google-services.json"
  - "FCM registration token surfaced in-app as selectable text for direct copy into push_trigger.py"
  - "Empirically measured Android push-wake results across 5 device states, recorded in tools/docs/MANUAL_TEST_PROCEDURE.md with screenshot evidence"
  - "Definitive D-12 answer: full-screen intent works for a sideloaded, self-managed-ConnectionService app with NO Play Console declaration"
affects: ["01-06 (phase sign-off cites the D-12 finding and the POST_NOTIFICATIONS gap)"]

# Tech tracking
tech-stack:
  added: ["Firebase project haphone-e30ca (Spark/free tier)", "com.google.gms.google-services Gradle plugin", "Android Emulator AVD haphone_test_api35 (Pixel 6, API 35 google_apis x86_64, KVM)"]
  patterns:
    - "KVM-accelerated headless emulator as the Android test device instead of a physical Pixel — same stock AOSP/Google-APIs build, real FCM token, real Google-delivered messages"
    - "Programmatic verification (dumpsys notification/package/power/window + logcat) rather than visual-only inspection, with screenshots as supporting evidence"

key-files:
  created:
    - tools/logs/screenshots/killed_locked_incoming_call.png
    - tools/logs/screenshots/secure_locked_killed_incoming_call.png
  modified:
    - android-app/app/build.gradle.kts
    - android-app/app/src/main/java/de/haphone/app/test/MainActivity.kt
    - tools/docs/MANUAL_TEST_PROCEDURE.md
    - .gitignore

key-decisions:
  - "Used a KVM-accelerated Android Emulator (API 35) instead of the physical Pixel at the user's request; justified in MANUAL_TEST_PROCEDURE.md because the AVD runs the same stock build and receives real FCM — the Pixel-vs-emulator difference is not load-bearing for PUSH-03/PUSH-04. OEM-specific power management remains deferred (D-03) and true multi-hour standby was approximated via forced Doze."
  - "Play Console declaration skipped entirely per D-12; verified empirically rather than assumed, and the limits of that finding (sideload-only, would need re-testing if ever Play-distributed) are documented rather than overstated."
  - "Granted POST_NOTIFICATIONS manually via adb to unblock the test matrix, and recorded the app's failure to request it at runtime as a real carried-forward gap rather than hiding it behind the manual grant."

patterns-established:
  - "Distinguish `am force-stop` (sets Android stopped-state, suppresses FCM by design) from `am kill` (simulates a real system kill / swipe-away) when testing push wake — using the wrong one produces a false negative"

requirements-completed: [PUSH-03, PUSH-04]

# Metrics
duration: ~35min
completed: 2026-08-03
---

# Phase 01: Push Wake-up Proof of Concept — Plan 05 Summary

**Wired the Android app to a real (free-tier) Firebase project and empirically proved, on API 35, that a high-priority data-only FCM push wakes a killed app and displays the incoming-call UI over a secure PIN lock screen — with no Google Play Developer account and no Play Console declaration anywhere.**

## Accomplishments

- Firebase project `haphone-e30ca` created (Spark/free tier), Android app registered for package `de.haphone.app.test`, `google-services.json` and an Admin SDK service-account key placed (both gitignored).
- `com.google.gms.google-services` plugin applied; `MainActivity` now fetches and displays the FCM registration token as selectable text (plus a logcat fallback) so it can be copied straight into `push_trigger.py`.
- Stood up a KVM-accelerated headless emulator (Pixel 6 profile, API 35 `google_apis`) which obtained a **real** FCM token and received **real** Google-delivered messages.
- Ran the full push-wake matrix end-to-end: signed Ed25519 envelope → FCM → app verifies signature → CallStyle notification + full-screen intent.

## Measured Results

| State | Latency | Result |
|---|---|---|
| foreground | ~0.3s | Pass — FSI fired, IncomingCallActivity resumed |
| backgrounded | ~0.3s | Pass — heads-up only, screen correctly not taken over |
| killed + screen off | ~1.6s | Pass — app woke from 0 processes, screen turned on |
| killed + deep Doze | ~1.4s | Pass — high-priority FCM punched through `deviceidle` IDLE |
| killed + secure PIN keyguard | ~1.8s | Pass — call UI shown **over** the secure lock screen |

Signature verification reported `isValid=true isExpired=false` on every delivery.

## D-12 Finding (the point of this plan)

Full-screen intent **works without any Play Console declaration** for a sideloaded app that registers a self-managed `ConnectionService`. Evidence: `USE_FULL_SCREEN_INTENT: granted=true`, app-op never denied, `fullscreenIntent=PendingIntent{...}` present and NMS-allowlisted, and `IncomingCallActivity` observed as `topResumedActivity` while `isKeyguardShowing=true`.

Scope limit recorded explicitly: this proves nothing about Play-Store-distributed builds, where the declaration governs the grant and would need re-testing.

## Deviations & Findings

- **`am force-stop` produces a false negative.** An initial "terminated" test showed no delivery. Root cause: `force-stop` sets the package's `stopped=true` flag, which by design suppresses FCM until manual relaunch — verified via `dumpsys package`. Re-ran with `am kill` (the correct simulation of a system kill / swipe-away) and it passed. Documented so this trap isn't re-hit.
- **A first Doze run also looked like a failure** but was a test-setup artifact (leftover activity state from the prior run). Re-run from a clean state passed. The failing run was not reported as a result.
- **`POST_NOTIFICATIONS` is never requested at runtime** (`granted=false` on fresh install). Since API 33 this suppresses *all* notifications, so the push path would appear broken to a real user despite working correctly underneath. Granted manually via `adb` to unblock testing; recorded as a real gap in the Plan 03 app to fix before any real user install. Not a Phase 1 blocker — the wake mechanism itself is proven.

## Deferred / Out of Scope

- Physical Pixel testing and non-Pixel OEM coverage (D-03) — still deferred.
- True multi-hour overnight standby — approximated with forced Doze.
- iOS side — blocked by D-11 (no paid Apple Developer Program), unchanged by this plan.
