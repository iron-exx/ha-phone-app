---
status: issues_found
files_reviewed: 56
findings:
  critical: 3
  warning: 1
  info: 2
  total: 6
---

# Code Review: Phase 02 (pjsip-audio-media-core)

## Findings

### CR-1: Live HA-Phone SIP extension password committed in plaintext to a public GitHub repo
**File:** tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md:22-26 (credential table), :28-41 (unresolved extension-range ambiguity), :43-47 ("accepted risk" framing)
**Severity:** Critical

The manual test doc records, in plaintext, a real working SIP account for the real HA-Phone box:

```
| Extension number | `13` |
| SIP password | `[REDACTED -- was plaintext here, confirmed live on the public GitHub remote; see Fix note below]` |
| Host | `192.168.7.10` |
```

This file is tracked (not gitignored — contrast with `android-app/local.properties`, `ios-app/Secrets.xcconfig`, and `tools/keys/*`, which the project's own `.gitignore` explicitly excludes for exactly this reason) and this repo's remote is `https://github.com/iron-exx/ha-phone-app.git`, a public repository. So this is a real, currently-valid credential for a live PBX, permanently in git history the moment it's pushed.

The risk is compounded by the same document's own admission (lines 28-41) that extension `13` falls **inside** the active 10-99 household range rather than the dedicated 80-99 test range specified by the plan (D-04), and that this discrepancy was never investigated or confirmed safe — i.e. there is a real chance this plaintext password belongs to (or collides with) an actual household extension, not a disposable test line.

The doc's own comment frames this as an "accepted risk... same tier as Phase 1's dev-only signing key" (lines 43-47), but a signing/verification *public* key (safe to embed by design) is not equivalent to a live *account password* for a real PBX with an unresolved question about whether it's actually in household use. Given the credential is already committed, it should be treated as compromised.

**Fix:** Rotate the SIP password for extension 13 on the live HA-Phone box immediately. Remove the plaintext password from this tracked file (replace with a placeholder + a pointer to a gitignored companion file, mirroring the `local.properties`/`Secrets.xcconfig` pattern already used elsewhere in this repo), and resolve the extension-range discrepancy before continuing to use extension 13 for testing.

### CR-2: Recursive `chmod -R 755` on every boot strips the 600 permissions this phase adds to the TLS private key, AMI secret, and session secret
**File:** /home/roto/projects/Ha-Phone/ha-phone/rootfs/etc/cont-init.d/10-asterisk-init.sh:25, :40, :68, :154 (real production Asterisk container init script)
**Severity:** Critical

This phase's commit `2f96ad5` ("feat(02-01): extend cont-init.d with self-signed TLS cert + [transport-tls]") adds:

```bash
[ -f /data/asterisk/tls/asterisk.key ] && chmod 600 /data/asterisk/tls/asterisk.key   # line 40
```

alongside the pre-existing:

```bash
chmod 600 /data/asterisk/ami_secret        # line 25
chmod 600 "$SESSION_SECRET_FILE"           # line 68
```

But later in the **same script, on every single boot**, an unconditional recursive chmod runs:

```bash
chmod -R 755 /data/voicemail /data/logs /data/asterisk   # line 154
```

`chmod -R` applies to every file under `/data/asterisk`, not just directories, so this line unconditionally resets `asterisk.key`, `ami_secret`, and `session_secret` from `rw-------` back to `rwxr-xr-x` (world-readable) at the end of every boot — undoing the protection the script itself just set moments earlier. It also leaves `/data/asterisk/pjsip_extensions.conf` world-readable; `backend/conf_templates/pjsip_extensions.conf.j2:60` renders `password = {{ ext.sip_password }}` in cleartext (confirmed by `backend/tests/test_api.py:1716`, which asserts the literal plaintext password string appears in that generated file), so every extension's SIP password ends up world-readable too.

Net effect after every boot: the Asterisk Manager Interface secret (full call-control API), the FastAPI session-signing secret (`SessionMiddleware` — exposure allows forging an authenticated admin session against the PBX web UI without the admin password), the newly-added TLS private key, and every extension's plaintext SIP password are all left with mode 755 on a live production box. This is a real, currently-live regression, not a hypothetical: the sequence of `chmod 600` followed unconditionally by `chmod -R 755` on the same file within one script run is not sandboxed by any later re-narrowing step.

**Fix:** Scope the recursive chmod to directories only (e.g. `find /data/voicemail /data/logs /data/asterisk -type d -exec chmod 755 {} +`) and re-apply `chmod 600` to the known secret files (`ami_secret`, `session_secret`, `tls/asterisk.key`, and ideally the generated `*.conf` files containing plaintext SIP passwords) after the broad chmod, or reorder the broad chmod to run before the secret-specific `chmod 600` calls.

### CR-3: Android's real incoming-call UI never triggers the SIP answer/hangup path — answering or declining a call through the app does not affect the underlying SIP dialog
**File:** android-app/app/src/main/java/de/haphone/app/test/IncomingCallActivity.kt:36-40
**Severity:** Critical

`IncomingCallActivity`'s Answer/Decline handlers are:

```kotlin
onAnswer = {
    startActivity(Intent(this, ActiveCallActivity::class.java))
    finish()
},
onDecline = { finish() },
```

Neither branch touches `SipCallController`/`CallControlScope` at all. The only place in the entire Android module that calls `sipCallController.answer(...)` is `CallRegistration.kt:88`, inside the `onAnswer` callback that is the **first lambda argument** passed to `callsManager.addCall(...)` (`CallRegistration.kt:71-92`) — and that callback is only invoked by `androidx.core.telecom` in response to a genuine Telecom-level answer action on the registered self-managed call (e.g. a system/Bluetooth answer action), never by an app `Activity` simply being launched.

The app's actual incoming-call surface — `CallNotificationBuilder.show()` — builds its `CallStyle` notification's Answer and Decline actions, and its full-screen intent, entirely from plain `PendingIntent.getActivity(..., IncomingCallActivity::class.java, ...)` (`CallNotificationBuilder.kt:16-30`). None of these `PendingIntent`s go through `CallsManager`/`Connection`, so tapping Answer on the notification, the full-screen intent, or `IncomingCallScreen`'s own Answer button can never fire Telecom's `onAnswer` callback, and therefore `SipCallController.answer()` (the only code path that sends the SIP `200 OK`) is never reached. `PjsuaEndpointHolder`'s `HAPhoneAccount.onIncomingCall` (PjsuaEndpointHolder.kt:190-196) only ever sends a provisional `180 Ringing`, so the concrete failure is: user taps "Answer" -> app shows the in-call UI locally -> the SIP dialog is still only at `180 Ringing` -> the caller/PBX keeps ringing until SIP timeout, with no way for the local user's answer to reach it. Declining is worse: `onDecline` just calls `finish()` with no `sipOps.hangup()` and no `CallControlScope.disconnect()`, so the call is not terminated at the Telecom layer or the SIP layer either — it keeps ringing indefinitely, which is exactly the "ring forever" failure mode the project's own CR-01 precedent (extensively referenced in comments across `CallRegistration.kt` and `SipCallController.kt`) was supposed to close off.

This was not a stale leftover the team forgot to update: `02-06-PLAN.md`/`02-06-SUMMARY.md`'s own acceptance criterion for this exact change is literally "`IncomingCallActivity.onAnswer` navigates to `ActiveCallActivity` instead of `finish()`" — the plan never specified wiring the notification/Activity path to the real `CallControlScope`, so the gap was baked into the plan and shipped exactly as specified.

**Fix:** Route the notification's answer/decline `PendingIntent`s (and `IncomingCallScreen`'s buttons) through the actual `CallControlScope` captured in `HAPhoneTestApplication.currentCallControlScope` — e.g. a `BroadcastReceiver`/deep-link that calls `sipCallController.answer(scope)` on answer and `scope.disconnect(...)` + `sipCallController.hangup()` on decline — so the real Telecom `onAnswer`/disconnect path in `CallRegistration.kt` is actually reachable from the UI a user interacts with.

### WR-1: PJSUA2 native calls dispatched from a `Dispatchers.Default` background thread pool, with no thread-safety guard against PJSIP's "unregistered thread" assertion
**File:** android-app/app/src/main/java/de/haphone/app/test/CallRegistration.kt:33, :61-92, :127-143
**Severity:** Warning

`CallRegistration` uses `private val scope = CoroutineScope(Dispatchers.Default)` (line 33) to launch `callsManager.addCall(...)`. Both the `onAnswer` callback (line 88, `sipCallController.answer(it)`) and `reportOutgoingCall`'s `onRegistered` block (invoked from `OutgoingCallActivity.kt:69`, `sipCallController.makeCall(digits)`) run inside that `Dispatchers.Default`-rooted coroutine context, and both ultimately call into PJSUA2 native code via `PjsuaEndpointHolder.asSipCallOperations(...)` (`Account.create()`, `Call.answer()`, `Call.makeCall()`).

`Endpoint.libCreate()`/`libInit()`/`libStart()` are called exactly once, from `HAPhoneTestApplication.onCreate()` (`HAPhoneTestApplication.kt:72`), which runs on the main thread. PJSIP requires any thread calling into pjlib to either be the thread that called `libCreate()` or to have called `pj_thread_register()` first; calling from any other, unregistered thread aborts with a native assertion. Nothing in `CallRegistration.kt`, `PjsuaEndpointHolder.kt`, or `SipCallController.kt` hops back to the main thread or registers the calling thread before invoking `sipOps` — confirmed by grep: there is no `Dispatchers.Main`/`withContext`/thread-registration call anywhere under `android-app/app/src/main/java/de/haphone/app/test/`.

This is the exact failure class the project's own iOS code identifies and fixes for a different code path: `NetworkChangeMonitor.swift:38-49` explicitly hops back with `DispatchQueue.main.async` before calling `PjsuaBridge.handleIpChange()`, with a comment naming the precise PJSIP assertion ("Calling pjlib from unknown/external thread"). Android's own network-change path is safe only because `ConnectivityManager.registerDefaultNetworkCallback` (no explicit `Handler`) happens to deliver callbacks on the same thread it was registered from (main, since `HAPhoneTestApplication.onCreate()` runs there) — but `CallRegistration`'s explicit opt-in to `Dispatchers.Default` is the one deliberate departure from that safety net, and it sits directly on the path that performs the real SIP answer/dial.

Whether `androidx.core.telecom`'s `addCall` internally marshals its callbacks back to the main thread is not something this code relies on or documents — it should not be left to an unconfirmed assumption about a third-party library's internals, especially given the project's own precedent of treating this exact scenario as a crash risk on the other platform.

**Fix:** Explicitly dispatch every `sipOps` call reached from `CallRegistration`'s callbacks onto the same thread that called `Endpoint.libCreate()` (e.g. `withContext(Dispatchers.Main) { sipCallController.answer(it) }`), or register each calling thread with PJSIP before use.

### IN-1: TLS server-certificate verification disabled on both platforms
**File:** android-app/app/src/main/java/de/haphone/app/test/sip/PjsuaEndpointHolder.kt:87; ios-app/HAPhoneTestApp/Sip/PjsuaBridge.mm:79
**Severity:** Info

Both platforms set `tlsConfig.verifyServer = false` for the self-signed Phase-2 test transport. This is already flagged in-code as dev-only, scoped to local-network testing, with an explicit note to remove it before a production transport phase — no action needed now, but since it's a bare literal rather than gated behind a build flag, a future refactor could carry it forward silently. Consider gating it behind `BuildConfig.DEBUG`/`#if DEBUG` so shipping it enabled requires an explicit, reviewable code change rather than just forgetting to flip one line.

### IN-2: Identical hardcoded dev/test verification public keys on both platforms with no build-time enforcement of replacement
**File:** android-app/app/src/main/java/de/haphone/app/test/TestFcmService.kt:9; ios-app/HAPhoneTestApp/HAPhoneTestAppApp.swift:28
**Severity:** Info

Both platforms hardcode the same dev-fixture Ed25519-style verification *public* key (`8a88e3dd...`), explicitly commented as a throwaway key to be replaced via `keygen.py` before real-device testing. Embedding a public verification key in source is not itself a vulnerability, but nothing currently prevents a release build from shipping with this placeholder key still in place (which would let anyone who can generate a matching signature forge push envelopes). Consider a lint/build check that fails a release build if this specific placeholder hex string is still present.

## Review Summary

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 3     | block  |
| WARNING  | 1     | warn   |
| INFO     | 2     | note   |

Verdict: BLOCK — 3 CRITICAL issues found (a live PBX credential committed to a public repo, a permission regression that exposes the AMI/session secrets and the new TLS private key on every boot of the real HA-Phone box, and an Android incoming-call UI that never actually answers or hangs up the underlying SIP call). All three should be fixed before this phase is considered complete; the credential in CR-1 should be rotated regardless of when/whether the doc itself is fixed.
