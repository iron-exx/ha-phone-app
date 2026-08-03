---
phase: 01-push-wakeup-proof-of-concept
reviewed: 2026-08-03T06:23:05Z
depth: standard
files_reviewed: 35
files_reviewed_list:
  - android-app/app/build.gradle.kts
  - android-app/app/src/main/AndroidManifest.xml
  - android-app/app/src/main/java/de/haphone/app/test/CallNotificationBuilder.kt
  - android-app/app/src/main/java/de/haphone/app/test/CallRegistration.kt
  - android-app/app/src/main/java/de/haphone/app/test/EnvelopeVerifier.kt
  - android-app/app/src/main/java/de/haphone/app/test/HAPhoneTestApplication.kt
  - android-app/app/src/main/java/de/haphone/app/test/IncomingCallActivity.kt
  - android-app/app/src/main/java/de/haphone/app/test/MainActivity.kt
  - android-app/app/src/main/java/de/haphone/app/test/TestFcmService.kt
  - android-app/app/src/test/java/de/haphone/app/test/EnvelopeVerifierTest.kt
  - android-app/build.gradle.kts
  - android-app/gradle.properties
  - android-app/gradle/wrapper/gradle-wrapper.properties
  - android-app/settings.gradle.kts
  - .gitignore
  - ios-app/HAPhoneTestApp/CallProvider.swift
  - ios-app/HAPhoneTestApp/DiagnosticsLog.swift
  - ios-app/HAPhoneTestApp/DiagnosticsView.swift
  - ios-app/HAPhoneTestApp/EnvelopeVerifier.swift
  - ios-app/HAPhoneTestApp/HAPhoneTestAppApp.swift
  - ios-app/HAPhoneTestApp/HAPhoneTestApp.entitlements
  - ios-app/HAPhoneTestApp/Info.plist
  - ios-app/HAPhoneTestApp/PushHandler.swift
  - ios-app/HAPhoneTestAppTests/DiagnosticsLogTests.swift
  - ios-app/HAPhoneTestAppTests/EnvelopeVerifierTests.swift
  - ios-app/HAPhoneTestAppTests/PushHandlerTests.swift
  - ios-app/project.yml
  - tools/docs/MANUAL_TEST_PROCEDURE.md
  - tools/envelope.py
  - tools/keygen.py
  - tools/push_trigger.py
  - tools/requirements.txt
  - tools/tests/__init__.py
  - tools/tests/test_envelope.py
  - .github/workflows/ios-ci.yml
findings:
  critical: 1
  critical_resolved: 1
  warning: 5
  info: 4
  total: 10
status: issues_found
note: "CR-01 (the only critical finding) was fixed in commit a9898d0 and empirically re-verified; 5 warnings + 4 info items remain open, tracked as Phase 1 carried-forward items in 01-PHASE-SIGNOFF.md rather than blockers.
---

# Phase 1: Code Review Report

**Reviewed:** 2026-08-03T06:23:05Z
**Depth:** standard
**Files Reviewed:** 35
**Status:** issues_found

## Summary

Phase 1 delivers two throwaway single-screen native apps (iOS/Swift, Android/Kotlin) plus a Python CLI, all sharing one signed Ed25519 push-envelope contract. The individual pieces are well-structured for a PoC — the "report to CallKit first, verify after" pattern is implemented correctly on iOS with real test coverage (`PushHandlerTests.swift` explicitly asserts report-before-verify ordering), the crypto libraries used (CryptoKit, Tink, `cryptography`) are all industry-standard rather than hand-rolled, and secrets/keys are consistently kept out of git via `.gitignore`.

Two classes of finding stood out against the "signing/verification, pay close attention" brief:

1. **The Android app computes signature validity and expiry but never acts on the result** (CR-01) — every FCM data message that looks like an envelope produces an identical full incoming-call UI regardless of whether it verifies, unlike iOS which explicitly ends the call for invalid/expired envelopes. This makes the Android-side authenticity check a no-op today.
2. **The three "byte-for-byte" canonical-serialization implementations (Python/Swift/Kotlin) actually diverge for non-ASCII input** (WR-01) — confirmed by direct reproduction of Python's `json.dumps(ensure_ascii=True)` default against the hand-rolled Swift/Kotlin escaping, which only handles `\` and `"`. This is latent today because every fixture and hardcoded caller string is pure ASCII, but the contract is explicitly meant to survive unchanged into later phases where real (German-language) caller names will appear.

Also found: a stale bundle-ID default in `push_trigger.py` left behind by an incomplete project-wide rename (confirmed via `git log`), a CLI flag that can structurally never be turned off, a dev private key written with default file permissions, and a few lower-impact quality/robustness notes. None of these block the phase's stated goal (proving the push→native-call-UI wake path, which the manual test log demonstrates working on Android); they matter for what carries forward into later phases.

## Critical Issues

### CR-01: Android push handler computes envelope validity/expiry but never enforces it — FIXED (commit `a9898d0`)

**Fix actually applied (differs from the suggested snippet below in two ways, both required for correctness):**

1. `CallRegistration.reportIncomingCall`'s trailing lambda became `CallControlScope.() -> Unit` — **not** `suspend CallControlScope.() -> Unit` as suggested below. `androidx.core.telecom.CallsManager.addCall`'s trailing block parameter is a plain (non-suspend) `Function1<CallControlScope, Unit>` per the compiled API (confirmed via `javap`); declaring it `suspend` fails to compile ("Suspension functions can only be called within coroutine body"). Since `CallControlScope` itself extends `CoroutineScope`, the caller wraps the actual `disconnect()` call in `launch { }` instead.
2. `notify()` still runs **unconditionally** for every push (kept, not skipped, per Pitfall 2 — a push must never be silently dropped from the user's view). The fix adds disconnect-and-cancel *after* showing the notification, rather than branching around `CallNotificationBuilder.show(...)` as the snippet below suggested — skipping the notify() call on invalid envelopes would itself violate Pitfall 2. `CallNotificationBuilder.cancel()` was added since Telecom's `disconnect()` ends the call session but does not, by itself, remove a notification the app posted manually.

**Verified empirically** on the API 35 emulator: a push signed with the real dev key, then tampered (`caller` field mutated after signing) via a one-off script, now results in the call disconnecting and notification 1001 being fully removed (`dumpsys notification` shows 0 records for the package immediately after). A subsequent valid push was re-sent as a regression check and still notifies/rings normally (1 record, unaffected).

<details>
<summary>Original finding (superseded by the fix above)</summary>

**File:** `android-app/app/src/main/java/de/haphone/app/test/TestFcmService.kt:13-24` (also `android-app/app/src/main/java/de/haphone/app/test/CallNotificationBuilder.kt:43-48`)

**Issue:** `isValid` and `isExpired` are computed via `EnvelopeVerifier.verify()`/`.isExpired()`, then passed only into `CallNotificationBuilder.show(...)`, where they are used solely to build a `Log.i(...)` line (`CallNotificationBuilder.kt:47`). No code path anywhere disconnects/rejects the Telecom call or suppresses the notification when the signature is invalid or the envelope has expired — `registration.registerApp()` and `registration.reportIncomingCall(callId) { CallNotificationBuilder.show(...) }` run unconditionally. The comment directly above the `notify()` call even documents this explicitly: *"This notify() call always runs, unconditionally, regardless of what isValid or isExpired evaluate to."*

Contrast with `ios-app/HAPhoneTestApp/PushHandler.swift:86-92`, which explicitly calls `self.callEnder.endCall(uuid: uuid)` when `isExpired || !isValid`, after reporting the call (matching Pitfall 1's "report first" requirement while still enforcing the check). The Android implementation reports and shows the full-screen incoming-call UI identically whether the push is a genuinely signed envelope or an arbitrary/tampered FCM data payload shaped like one. Since FCM data messages can be triggered by anything capable of addressing the device's registration token, the entire Ed25519 verification apparatus (`EnvelopeVerifier.kt`, wired up correctly on its own) currently has zero effect on Android runtime behavior — it is computed and then discarded.

**Fix:**
```kotlin
// TestFcmService.kt — thread the CallControlScope out of reportIncomingCall so an
// invalid/expired envelope can actually end the call, mirroring PushHandler.swift.
registration.reportIncomingCall(callId) {
    if (!isValid || isExpired) {
        disconnect(DisconnectCause(DisconnectCause.REJECTED)) // requires CallControlScope receiver
    } else {
        CallNotificationBuilder.show(applicationContext, callId, isValid, isExpired)
    }
}
```
This requires changing `CallRegistration.reportIncomingCall`'s trailing lambda from `onRegistered: () -> Unit` to a `suspend CallControlScope.() -> Unit` (the type `androidx.core.telecom`'s `addCall` already exposes on its own trailing block) so the caller can invoke `disconnect(...)`.

</details>

## Warnings

### WR-01: Canonical JSON serialization diverges between Python and Swift/Kotlin for non-ASCII characters

**File:** `tools/envelope.py:65-77`, `android-app/app/src/main/java/de/haphone/app/test/EnvelopeVerifier.kt:9-23`, `ios-app/HAPhoneTestApp/EnvelopeVerifier.swift:14-30`

**Issue:** `canonical_bytes()` in `envelope.py` calls `json.dumps(ordered, sort_keys=True, separators=(",", ":"))`, which defaults to `ensure_ascii=True` — every codepoint above ASCII (and JSON control characters) gets escaped as `\uXXXX`. Reproduced directly:
```
>>> json.dumps({'caller': 'Türsprechanlage'}, sort_keys=True, separators=(',',':'))
'{"caller":"T\\u00fcrsprechanlage"}'
```
The Swift (`EnvelopeVerifier.swift:21-24`) and Kotlin (`EnvelopeVerifier.kt:16-17`) implementations only escape `\` and `"` and pass every other byte through raw. All three docstrings/comments explicitly claim "byte-for-byte" parity ("Canonicalization contract ... must stay identical to the Python reference"), but that parity silently breaks for any `caller`/`call_type` value containing a non-ASCII character. This is invisible today only because every fixture and hardcoded caller string in the repo ("HA-Phone Testanruf", "audio") is pure ASCII. Given the project's German-language target audience and door-station use case, a real caller/device name (e.g. containing "ü", "ß") will produce a signature the mobile clients cannot verify, and — combined with CR-01's asymmetry — would cause iOS to actively reject/end a legitimately signed call.

**Fix:** Pick one escaping rule and implement it identically in all three languages: either keep Python's `ensure_ascii=True` and replicate `\uXXXX` escaping for non-ASCII/control characters in Swift/Kotlin, or set `ensure_ascii=False` on the Python side and add explicit control-character escaping to Swift/Kotlin (which already pass non-ASCII through unescaped). Add a non-ASCII caller fixture to `tools/tests/test_envelope.py`, `EnvelopeVerifierTest.kt`, and `EnvelopeVerifierTests.swift` to lock in the chosen rule — none of the current golden fixtures would have caught this.

### WR-02: `push_trigger.py`'s default APNs bundle ID is stale and doesn't match the app

**File:** `tools/push_trigger.py:173-176`

**Issue:** `--apns-bundle-id` defaults to `"de.systemwerk.haphone.test"`, but the app's actual bundle/package identifier everywhere else in the repo (`android-app/app/build.gradle.kts` `applicationId`, `ios-app/project.yml` `PRODUCT_BUNDLE_IDENTIFIER`, `bundleIdPrefix`) is `de.haphone.app.test`. Commit `11c9b9c` ("fix(01): replace de.systemwerk.haphone with de.haphone.app everywhere") was written specifically to remove this old identifier project-wide, but `push_trigger.py` was added by commit `490dd01` roughly one hour earlier in the same session and was missed by that sweep (confirmed via `git log --follow -- tools/push_trigger.py` and `git show 11c9b9c --stat`). Any invocation that doesn't explicitly pass `--apns-bundle-id`/`APNS_BUNDLE_ID` computes `topic = f"{apns_bundle_id}.voip"` = `de.systemwerk.haphone.test.voip`, which will not match the real app's VoIP topic — APNs would reject the push (`BadTopic`) the first time this is exercised against a real device. Currently masked only because iOS device testing is fully blocked by the zero-budget constraint (D-11), so this has never actually been run against real APNs.

**Fix:** `default=os.environ.get("APNS_BUNDLE_ID", "de.haphone.app.test")`.

### WR-03: `--use-sandbox` CLI flag can never be set to `False`

**File:** `tools/push_trigger.py:183-188`

**Issue:** `action="store_true"` combined with `default=True` means `args.use_sandbox` evaluates to `True` regardless of whether `--use-sandbox` is passed on the command line — `argparse`'s `store_true` action has no mechanism to produce `False` here. There is currently no way to select the production APNs endpoint from this script's CLI at all.

**Fix:** `parser.add_argument("--use-sandbox", action=argparse.BooleanOptionalAction, default=True, ...)`, which adds a real `--no-use-sandbox` counterpart.

### WR-04: Dev Ed25519 private key written to disk with default file permissions

**File:** `tools/keygen.py:54-55`

**Issue:** `open(private_path, "w")` creates `{out}_private.hex` with the process's default umask-derived permissions (typically `644` — world/group readable), so the raw private signing key is not restricted to the owning user. `envelope.py`'s module docstring states this signing contract is meant to "survive unchanged into the Phase 6 multi-tenant push-relay," where the equivalent production key becomes a much higher-value secret — worth establishing correct permissions now rather than retrofitting later.

**Fix:** `os.chmod(private_path, 0o600)` immediately after writing, or open via `os.open(private_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)`.

### WR-05: Android app never requests the runtime `POST_NOTIFICATIONS` permission

**File:** `android-app/app/src/main/AndroidManifest.xml:6`, `android-app/app/src/main/java/de/haphone/app/test/MainActivity.kt` (entire file — the only `Activity` that could host the request)

**Issue:** `POST_NOTIFICATIONS` is declared in the manifest but is a runtime (dangerous) permission since API 33; nothing in `MainActivity.onCreate` (or anywhere else) ever calls `ActivityCompat.requestPermissions`/registers a `RequestPermission` contract. On a fresh install the entire push-wake path silently produces no visible UI (FCM delivery, `EnvelopeVerifier`, and Telecom registration all still succeed, but `NotificationManagerCompat.notify()` is a no-op without the grant) — the app would appear completely broken to a first-time user. This exact gap is already self-documented as a known, accepted Phase-1 limitation in `tools/docs/MANUAL_TEST_PROCEDURE.md`'s "Additional Finding" section, so it is not a surprise to the project, but it remains present in the reviewed source and worth keeping flagged until fixed.

**Fix:** Request `POST_NOTIFICATIONS` from `MainActivity.onCreate` via `ActivityResultContracts.RequestPermission()` before/around the existing FCM token fetch.

## Info

### IN-01: Unvalidated hex-length assumption in `Data(hexEncoded:)` risks a crash on malformed input

**File:** `ios-app/HAPhoneTestApp/EnvelopeVerifier.swift:49-59`

**Issue:** The loop computes `let next = hex.index(index, offsetBy: 2)` without first checking that `hex.count` is even, so an odd-length hex string overruns `hex.endIndex` and triggers a precondition failure/crash rather than returning `nil`. Not reachable today — the only callers pass the hardcoded 64-character `verifierPublicKeyHex`/`devFixturePublicKeyHex` constants — but this is exactly the kind of string a developer will hand-copy from `keygen.py`'s printed output in a later phase, where a copy/paste truncation would crash the app instead of failing `verify()` safely. (Kotlin's `hexToBytes` in `EnvelopeVerifier.kt:41-47` has the analogous gap but fails differently — it silently truncates the last odd character rather than crashing.)

**Fix:** `guard hex.count.isMultiple(of: 2) else { return nil }` before the loop.

### IN-02: Notification's Answer/Decline actions don't distinguish from opening the app

**File:** `android-app/app/src/main/java/de/haphone/app/test/CallNotificationBuilder.kt:16-30`

**Issue:** `fullScreenIntent`, `answerIntent`, and `declineIntent` are three distinct `PendingIntent`s (different request codes) but all three launch the identical `IncomingCallActivity` with the identical `callId` extra — nothing distinguishes "the user tapped Decline" from "the user tapped the notification body" or "Answer." `NotificationCompat.CallStyle.forIncomingCall(caller, declineIntent, answerIntent)` is designed around the decline action actually ending the call. This is consistent with the documented Phase 1 scope ("No real call/SIP logic exists"), so it isn't a defect against the stated goal, but the CallStyle decline button is currently indistinguishable from any other tap.

**Fix:** Pass a differentiating extra (e.g. `putExtra("action", "decline")`) that `IncomingCallActivity` reads to `finish()`/disconnect immediately rather than showing the screen, ahead of any real Telecom-integrated answer/decline logic in a later phase.

### IN-03: `is_expired()` fails open (raises) on a missing field where the mobile clients fail closed

**File:** `tools/envelope.py:106-112` vs. `android-app/app/src/main/java/de/haphone/app/test/EnvelopeVerifier.kt:36-39`, `ios-app/HAPhoneTestApp/EnvelopeVerifier.swift:42-45`

**Issue:** Python's `is_expired()` does `current > envelope["expires_at"]`, which raises `KeyError` if `expires_at` is absent. Both mobile implementations' `isExpired()` explicitly default to "expired" (`true`)/"already expired" when the field is missing or the wrong type — a fail-closed default. `verify_envelope()` in the same Python module guards this exact class of error (`except (InvalidSignature, KeyError, ValueError, TypeError)`), but `is_expired()` — described by the same docstring as part of the shared cross-language contract — doesn't. Low practical impact today since `is_expired()` is only exercised by `tools/tests/test_envelope.py`, not by any runtime path in `push_trigger.py`.

**Fix:** `return current > envelope.get("expires_at", -1)` (or otherwise fail closed) to match the Swift/Kotlin behavior, or document the divergence as intentional if it should stay.

### IN-04: `ios-ci.yml` won't catch cross-language drift in the shared envelope contract, and doesn't pin an Xcode version

**File:** `.github/workflows/ios-ci.yml:4-7, 43`

**Issue:** The workflow's trigger (`paths: ["ios-app/**"]`) means a change to `tools/envelope.py` — whose golden fixture `EnvelopeVerifierTests.swift` must match byte-for-byte, per WR-01 above — never re-runs this CI, so a fix applied only on the Python side wouldn't be automatically checked against the Swift side (or vice versa). Separately, `-destination 'platform=iOS Simulator,name=iPhone 16'` (line 43) hardcodes a specific simulator device without pinning an Xcode version anywhere in the workflow (no `xcode-select`/`actions/setup-xcode` step) — the build depends entirely on whichever Xcode version `macos-14` defaults to at run time, which is outside this repo's control and can change without warning.

**Fix:** Widen the path trigger to also cover `tools/envelope.py` (or add a small explicit cross-language contract-check job), and pin a specific Xcode version (e.g. `sudo xcode-select -s /Applications/Xcode_16.x.app`) instead of relying on the runner image's floating default.

---

_Reviewed: 2026-08-03T06:23:05Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
