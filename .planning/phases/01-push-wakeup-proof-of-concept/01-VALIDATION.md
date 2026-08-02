---
phase: 1
slug: push-wakeup-proof-of-concept
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-01
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest (Python test-trigger logic) + XCTest (iOS signature/handler verification) + JUnit4/5 (Android signature verification) |
| **Config file** | none yet — Wave 0 gap (no `pytest.ini`/Xcode/Android Studio test targets exist until the projects are scaffolded) |
| **Quick run command** | `pytest tools/tests/ -x` (Python); `xcodebuild test -project ios-app/HAPhoneTestApp.xcodeproj -scheme HAPhoneTestApp -destination 'platform=iOS Simulator,name=iPhone 16'` (iOS logic-only); `./gradlew testDebugUnitTest` (Android) |
| **Full suite command** | Same three commands — Phase 1's test surface is small enough that "quick" and "full" are identical |
| **Estimated runtime** | ~30-60 seconds combined |

---

## Sampling Rate

- **After every task commit:** Run the relevant quick-run command for whichever side (Python/iOS/Android) was touched
- **After every plan wave:** Run all three quick-run commands (they are also the full suite for this phase)
- **Before `/gsd-verify-work`:** Full suite green, plus the manual test procedure (below) completed and logged
- **Max feedback latency:** ~60 seconds for automated checks; manual real-device checks are the actual bottleneck (CI round-trip for iOS, per D-10)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01 | 0 | cross-cutting (D-07) | T-01-01 | Ed25519 envelope sign/verify roundtrip, tamper rejection, expiry rejection | unit | `pytest tools/tests/test_envelope.py -x` | ❌ W0 | ⬜ pending |
| 01-01-02 | 01 | 0 | cross-cutting (D-07) | T-01-01 | Same envelope verification, iOS side | unit | `xcodebuild test ... -only-testing:HAPhoneTestAppTests/EnvelopeVerifierTests` | ❌ W0 | ⬜ pending |
| 01-01-03 | 01 | 0 | cross-cutting (D-07) | T-01-01 | Same envelope verification, Android side | unit | `./gradlew testDebugUnitTest --tests EnvelopeVerifierTest` | ❌ W0 | ⬜ pending |
| 01-02-01 | 02 | 1 | PUSH-02 | T-01-02 | `reportNewIncomingCall` invoked synchronously for well-formed, malformed, and expired payloads (mock CXProvider) | unit | `xcodebuild test ... -only-testing:HAPhoneTestAppTests/PushHandlerTests` | ❌ W0 | ⬜ pending |
| 01-02-02 | 02 | 1 | PUSH-01 | — | iOS VoIP push wakes app across app states | manual-only | N/A — manual test procedure below | ❌ W0 | ⬜ pending |
| 01-03-01 | 03 | 1 | PUSH-04 | T-01-02 | CallStyle/notification + envelope verification logic (Android) | unit | `./gradlew testDebugUnitTest --tests EnvelopeVerifierTest` | ❌ W0 | ⬜ pending |
| 01-03-02 | 03 | 1 | PUSH-03 | — | Android high-priority FCM wakes app while backgrounded/locked | manual-only | N/A — manual test procedure below | ❌ W0 | ⬜ pending |
| 01-04-01 | 04 | 2 | PUSH-01, PUSH-02 | — | **ERRATA (superseded by D-11):** Plan 04 no longer touches Android/Play Console — it is now an iOS-only Simulator build/test CI pipeline (unsigned, no Apple Developer Program). See row below for the actual verification. | automated | `xcodebuild build -sdk iphonesimulator` + `xcodebuild test` in CI | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tools/tests/test_envelope.py` — Ed25519 sign/verify roundtrip, tamper (flip one byte, expect failure), expiry rejection; framework install: `pip install pytest cryptography pynacl`
- [ ] `ios-app/HAPhoneTestAppTests/EnvelopeVerifierTests.swift` — same three cases using CryptoKit
- [ ] `ios-app/HAPhoneTestAppTests/PushHandlerTests.swift` — asserts `reportNewIncomingCall` is invoked for well-formed, malformed, and expired payload fixtures (mock/injected `CXProvider`); covers PUSH-02
- [ ] `android-app/app/src/test/.../EnvelopeVerifierTest.kt` — same three envelope cases using Tink/BouncyCastle
- [ ] Manual test procedure document (see below) — Wave 0 deliverable, not code, produced before real-device testing begins

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| VoIP push wakes app across app states (open/background/locked/terminated/overnight standby), iOS | PUSH-01 | **ERRATA (superseded by D-11):** PushKit is not simulator-testable under any circumstance (`xcrun simctl push` explicitly excludes VoIP), and real-device testing requires a paid Apple Developer Program membership ($99/yr) which the user has explicitly declined to purchase for Phase 1. **This behavior is UNVERIFIED and remains an accepted, open gap** — only Simulator build/unit-test-level verification exists (Plan 04). No TestFlight, no real-device row in the manual test log. | Not performed in Phase 1 — documented as an open gap in 01-PHASE-SIGNOFF.md, not a completed manual test |
| High-priority FCM wakes app while backgrounded/locked, Android | PUSH-03 | Locked-screen/backgrounded state cannot be meaningfully unit-tested; requires real Pixel device | See Manual Test Procedure below |
| Full-screen incoming-call UI display, Android | PUSH-04 | Full-screen intent rendering over lock screen requires a real device, not an emulator assertion | See Manual Test Procedure below |
| Play Console "calling app" declaration | PUSH-04 | **ERRATA (superseded by D-12):** Skipped entirely — requires a $25 Google Play Developer account the user has explicitly declined to purchase for Phase 1. Instead, Plan 05 empirically tests whether the Android 14+ full-screen-intent auto-grant works for a sideloaded, self-managed-ConnectionService app WITHOUT any Play Console declaration, and records the actual observed result (works/doesn't work) as a Phase 1 finding. | Sideload via `adb install`; observe and record actual full-screen-intent behavior on the real Pixel — no Play Console step |

### Manual Test Procedure (PUSH-01, PUSH-03 — not automatable)

**App states to exercise (per CONTEXT.md D-09):** app open (foreground), app backgrounded, device locked (screen off), app fully terminated (force-quit/swiped away), overnight standby (device locked & idle 8+ hours).

**Per test run:**
1. Put the device in the target app state.
2. Run `tools/push_trigger.py --platform ios|android --state <label>`; the script logs `sentAt` (its own clock).
3. Observe the device: does the native call UI appear? Rough stopwatch/eyeball estimate is enough (per D-09 — no fixed numeric target).
4. The app logs `receivedAt` (push handler fired) and `reportedAt` (`reportNewIncomingCall`/`addCall` returned) — for iOS, since a *terminated* app has no live Xcode console (no local Mac, per D-10), the app must persist this to a local log file on wake, read back afterward. For Android, `adb logcat` works directly.
5. Record pass/fail + rough latency in a simple table across at least a few repetitions per state — no fixed count required (D-09), but enough to form a qualitative "does this feel reliable" judgment.
6. Repeat overnight-standby specifically as its own long-duration test (start before sleep, trigger next morning) — most likely state to expose OS-level Doze/App Standby interference even on stock Android/Pixel.

This operationalizes D-09's informal acceptance approach while still producing a concrete, repeatable artifact (the sent/received/reported timestamp log).

---

## Validation Sign-Off

- [ ] All tasks have automated verify or are explicitly Wave 0 / manual-only / administrative
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify (manual-only tasks for PUSH-01/PUSH-03 are inherently exempt — device-dependent)
- [ ] Wave 0 covers all MISSING references (envelope tests, push handler test, manual test procedure doc)
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s for automated checks
- [ ] `nyquist_compliant: true` set in frontmatter once Wave 0 artifacts exist

**Approval:** pending
