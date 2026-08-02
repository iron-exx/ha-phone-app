# Phase 1: Push-Wakeup Proof of Concept - Research

**Researched:** 2026-08-01
**Domain:** iOS PushKit/CallKit VoIP wake, Android FCM/Telecom self-managed calling, minimal signed push-event envelope (ed25519), from-scratch test-trigger tooling
**Confidence:** MEDIUM-HIGH — iOS/Android platform contracts are HIGH confidence (official docs, Context7, cross-verified WebSearch); Play Console declaration mechanics and the Android `core-telecom` recommendation are MEDIUM/LOW confidence (see Assumptions Log) and need verification at execution time.

## Summary

Phase 1 has exactly one job: prove that a platform push can wake this app into native call UI on both iOS and Android, in every relevant app state, with nothing else built yet. The two platform contracts are well-documented and non-negotiable: iOS requires an unconditional, synchronous `CXProvider.reportNewIncomingCall` call inside the PushKit delegate method for every VoIP push (no exceptions, including malformed/expired ones), and Android requires that every high-priority data-only FCM message deterministically produce a visible notification (CallStyle + full-screen intent) tied to a registered self-managed calling app, or Google will silently downgrade future push priority for that install. Both of these are "day-one" invariants, not later hardening — this research confirms them with current official sources and gives concrete, minimal implementation patterns.

Two things are less mechanical and need explicit planner attention. First, **this research session ran inside a Linux sandbox with no Xcode/macOS available** — the iOS half of Phase 1 cannot be built or tested from this environment; a separate Mac with the physical iPhone tethered is a hard prerequisite that could not be verified here. Second, Android now has a newer Jetpack library, `androidx.core.telecom` (`CallsManager`), that wraps the raw `ConnectionService`/`PhoneAccount` registration STACK.md already recommended — it is real, currently stable at 1.0.0, and significantly reduces boilerplate, but its interaction with the Play Store "calling app" full-screen-intent auto-grant has not been independently confirmed in this session, so raw `ConnectionService` remains the documented fallback if `CallsManager` behavior is ambiguous at implementation time.

**Primary recommendation:** Build two throwaway single-screen native apps (no PJSIP, no HA-Phone integration) plus one Python CLI in `tools/`. iOS: minimal Xcode project with Push Notifications + Background Modes (Voice over IP) capabilities, `PKPushRegistry` + `CXProvider`, tested only on the real iPhone (VoIP push is not simulator-testable at all). Android: minimal Android Studio project with `androidx.core:core-telecom` (or raw `ConnectionService` as fallback) + `FirebaseMessagingService`, tested on the real Pixel. Python CLI signs a minimal versioned JSON envelope with Ed25519 (`cryptography` library, already a project dependency) and POSTs directly to APNs (`aioapns`, token-based `.p8` auth, `push_type=voip`) or FCM (`firebase-admin`, `AndroidConfig(priority='high')`, data-only). Both apps verify the signature client-side (CryptoKit on iOS, Tink or BouncyCastle on Android — do not rely on possibly-inconsistent native Android Ed25519 support) to prove the envelope round-trips end-to-end, even though no relay/PBX exists yet to consume it.

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Test-Geräte-Matrix**
- D-01: iOS testing device is the user's own current-generation iPhone on current iOS.
- D-02: Android testing device is a Pixel (stock Android) only — no Samsung/Xiaomi/other aggressive-OEM device currently available.
- D-03 (flagged concern): ROADMAP.md's Phase 1 success criterion #3 ("verified on at least one non-Pixel OEM device") is not satisfiable with the current device matrix. Planner should either scope the criterion down to "Pixel only, OEM diversity deferred" or flag it as blocked pending a borrowed/purchased test device — do not silently drop it.

**Test-Trigger-Mechanismus**
- D-04: Phase 1 does not touch HA-Phone (Asterisk/FastAPI) at all. A standalone test-trigger script/CLI, living in the ha-phone-app repo (e.g. `tools/`), sends VoIP push (APNs) / high-priority data push (FCM) directly to the test device.
- D-05: No real inbound call via Asterisk AMI/ARI in this phase — that end-to-end wiring is deferred to a later phase once the SIP core (Phase 2) and PBX-side call-state (Phase 4) exist.

**Inhalt der Anrufanzeige im Prototyp**
- D-06: The native call screen shows a fixed placeholder ("HA-Phone Testanruf") — no real caller-ID/name resolution in this phase (that's Phase 4's PBX-side phonebook lookup).
- D-07: The push payload is signed from the start (user chose to design/implement the signing scheme now, e.g. ed25519, rather than adding it retroactively in Phase 6 when the multi-tenant relay is formalized). Planner/researcher should treat "define and implement the push-event signing envelope" as in-scope for Phase 1, even though the full multi-tenant relay is out of scope until Phase 6.

**Umgang mit verspätetem/fehlgeschlagenem Push**
- D-08: No retry/timeout logic in Phase 1. Failed or late push delivery is logged (sent timestamp vs. received/reported timestamp) in the test script, not automatically retried. Retry/hardening is explicitly deferred to Phase 4/5.
- D-09: Acceptance is judged informally ("feels reliable" after manual test calls across app states: open, backgrounded, locked, overnight standby) — no fixed numeric test-count/success-rate target for Phase 1's Definition of Done.

### Claude's Discretion
None explicitly delegated beyond the above — CONTEXT.md's `<specifics>` section notes two implementation preferences (not full discretion, but non-binding guidance):
- Test-trigger tooling lives in the app repo itself (e.g. `tools/`), not in HA-Phone — keeps the repo boundary clean until the SIP/provisioning phases land.
- Push payload signing (D-07) should be designed with the eventual multi-tenant relay (Phase 6) in mind, even though only a single dev signing key is needed now — avoid a payload format that would require a breaking change later.

### Deferred Ideas (OUT OF SCOPE)
- Non-Pixel Android OEM test coverage (Samsung/Xiaomi) — deferred until a suitable device is available; flagged as an open concern (D-03), not silently dropped.
- Retry/timeout handling for missed or late pushes — explicitly deferred to Phase 4/5 hardening (D-08).
- Real inbound-call-triggers-push wiring via Asterisk AMI/ARI — deferred until Phase 2 (SIP core) and Phase 4 (call-state orchestration) exist.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PUSH-01 | iOS VoIP push (PushKit) wakes the app reliably, even fully terminated | PushKit delegate pattern, Xcode entitlement/capability setup, real-device-only constraint (simulator unsupported), all documented below under "iOS Implementation Pattern" |
| PUSH-02 | iOS CallKit reports the incoming call immediately/natively (within Apple's deadline, every VoIP push reported) | Synchronous `reportNewIncomingCall` contract, token-revocation-on-repeat-failure pitfall, minimal `CXProviderConfiguration`, malformed/duplicate/expired push handling pattern — all under "iOS Implementation Pattern" and Common Pitfalls |
| PUSH-03 | Android high-priority FCM wakes the app reliably, backgrounded or locked | Data-only high-priority FCM contract, `FirebaseMessagingService.onMessageReceived` behavior/limits, silent priority-downgrade risk — under "Android Implementation Pattern" |
| PUSH-04 | Android shows the incoming call via self-managed ConnectionService/PhoneAccount + CallStyle + full-screen-intent, including the Play Console "calling app" declaration | `androidx.core.telecom` (CallsManager) vs. raw `ConnectionService`, CallStyle code pattern, full-screen-intent manifest/runtime check, Play Console declaration flow (flagged MEDIUM confidence) — under "Android Implementation Pattern" and "Play Console Declaration" |

## Architectural Responsibility Map

This is a native mobile proof-of-concept, not a web app, so tiers are adapted from the standard web-tier model to the mobile-push equivalent.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| VoIP push transport & OS wake (iOS) | Mobile OS / PushKit (system framework) | Native App Client | The OS owns delivery/wake guarantees; the app owns the mandatory synchronous-report contract that keeps that guarantee alive |
| CallKit incoming-call UI | Native App Client | — | Entirely client-owned system UI integration (`CXProvider`/`CXProviderConfiguration`) |
| High-priority FCM transport & OS wake (Android) | Mobile OS / Google Play Services (FCM client) | Native App Client | Transport is OS/GMS-owned; the app must react deterministically inside `onMessageReceived` or risk silent priority downgrade |
| Self-managed Telecom registration + CallStyle/full-screen UI | Native App Client | Android Telecom Framework (OS) | App registers the `PhoneAccount`/`CallsManager` capability; OS arbitrates call UI, audio focus, and the full-screen-intent auto-grant based on that registration |
| Push payload signing (Ed25519 envelope) | Test-Trigger Script (backend-equivalent sender) | Native App Client (verifies) | Signing authority belongs to whichever side originates the event (stand-in for the future relay/PBX); verification belongs to the receiver |
| Play Console "calling app" declaration | Distribution/Release tooling (Play Console, outside app code) | Native App Client (must implement Telecom capability to qualify) | An administrative declaration gates a client-side OS permission grant |
| Delivery timestamp logging (sent vs. received/reported) | Test-Trigger Script | Native App Client (echoes received/reported time to a local log/console) | D-09's qualitative reliability judgment needs both sides' timestamps compared by a human |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| PushKit (`PKPushRegistry`) | iOS SDK, system framework | Receive VoIP pushes, wake app when suspended/terminated | [CITED: developer.apple.com/documentation/pushkit] Only Apple-sanctioned mechanism for guaranteed background VoIP wake |
| CallKit (`CXProvider`, `CXProviderConfiguration`, `CXCallUpdate`) | iOS SDK, system framework | Native incoming-call UI; mandatory companion to PushKit | [CITED: developer.apple.com/documentation/callkit] Confirmed minimal-config code pattern below |
| Firebase Cloud Messaging (`firebase-messaging`) | Android SDK, current BoM | Receive high-priority data-only push to wake the app | [CITED: firebase.google.com/docs/cloud-messaging] Use data-only messages so `onMessageReceived` fires in every app state |
| `androidx.core:core-telecom` (`CallsManager`) | **1.0.0 stable** (1.1.0 still alpha as of March 2026 — adds unified call-log/callback features not needed here) | Simplified self-managed calling-app registration, wraps `ConnectionService` (API ≤33) / foreground-service-type (API 34+) internally | [VERIFIED via WebSearch cross-check: Jetpack Telecom blog + `androidx.core` release notes, MEDIUM confidence — see Assumptions Log A3] New since STACK.md's research; simplifies the exact "self-managed ConnectionService + PhoneAccount" pattern STACK.md already locked in. Raw `ConnectionService`/`PhoneAccount` remains the documented fallback. |
| `NotificationCompat.CallStyle` | AndroidX Core (current) | Visible incoming-call notification, API 31+ | [CITED: developer.android.com/develop/ui/compose/notifications/call-style] Code pattern confirmed below |
| Python 3.12 | already present in dev environment | Runtime for the standalone test-trigger CLI (`tools/`) | [VERIFIED: `python3 --version` in this session] |
| `aioapns` | **4.0** (verified current on PyPI; STACK.md cites 3.x — bump the number) | Async APNs HTTP/2 client, sends VoIP pushes (`push_type=voip`) | [VERIFIED: `pip index versions aioapns` → 4.0 latest] Confirmed VoIP example via Context7 `/fatal1ty/aioapns` docs |
| `firebase-admin` (Python) | **7.5.0** (verified current on PyPI; STACK.md cites 6.x — bump the number) | FCM HTTP v1 sending, `AndroidConfig(priority='high')` | [VERIFIED: `pip index versions firebase-admin` → 7.5.0 latest] |
| `cryptography` | 41.0.7 installed in this sandbox / 50.0.0 latest on PyPI | Ed25519 signing on the sender side (`cryptography.hazmat.primitives.asymmetric.ed25519`) | [VERIFIED: import works in this session] Already a project dependency per STACK.md (used for APNs JWT internals) — reuse it instead of adding PyNaCl as a second crypto dependency |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| CryptoKit (`Curve25519.Signing`) | iOS SDK, system framework (iOS 13+) | Client-side Ed25519 signature verification on iOS | Built-in, no dependency — use to verify the test-trigger script's signature after receiving a push, proving the envelope round-trips |
| Google Tink (`com.google.crypto.tink:tink-android`) or BouncyCastle | current stable | Client-side Ed25519 signature verification on Android | [ASSUMED — see Assumptions Log A4] Native Android Ed25519 support via Conscrypt/`java.security.Signature` could not be confirmed reliable across target API levels in this session; use a well-known library instead of relying on unverified platform support |
| `pytest` | current | Unit tests for the signing/verification logic in the Python test-trigger script | Not yet installed in this sandbox — install as part of Wave 0 (`pip install pytest`) |
| XCTest | bundled with Xcode | Unit tests for the Swift-side signature verification logic (pure crypto, runs fine in Simulator even though push/CallKit itself cannot) | Default Xcode "Include Tests" template option |
| JUnit4/5 (AndroidX Test) | bundled with Android Studio template | Unit tests for the Kotlin-side signature verification logic | Default Android Studio "app/src/test" source set |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `androidx.core.telecom` `CallsManager` | Raw `ConnectionService` + `PhoneAccount` (STACK.md's original recommendation) | Use raw `ConnectionService` if `CallsManager`'s interaction with the Play Store calling-app full-screen-intent grant can't be confirmed at implementation time, or if the project needs an API level below what `CallsManager` supports |
| `cryptography` (Ed25519) | PyNaCl (`nacl.signing`) | PyNaCl has a slightly simpler high-level API for Ed25519 specifically, but adds a second crypto dependency next to `cryptography` (already required for APNs JWT signing) — no reason to add it unless `cryptography`'s Ed25519 API proves awkward |
| Tink/BouncyCastle (Android Ed25519) | Native `java.security.Signature.getInstance("Ed25519")` (Conscrypt) | Only use native support if you explicitly verify it works on the project's minSdk floor during implementation — this session could not confirm consistent availability |

**Installation:**
```bash
# Python test-trigger CLI (tools/)
pip install aioapns firebase-admin cryptography pytest

# iOS: no package manager needed — PushKit/CallKit/CryptoKit are system frameworks.
# Create a new Xcode "App" template project (SwiftUI), no CocoaPods/SPM dependency required for Phase 1.

# Android: androidx.core:core-telecom added via Gradle
# build.gradle.kts (module):
#   implementation("androidx.core:core-telecom:1.0.0")
#   implementation("com.google.firebase:firebase-messaging-ktx")  // via Firebase BoM
#   implementation("com.google.crypto.tink:tink-android:<current>")  // Ed25519 verification
```

**Version verification:** `aioapns` and `firebase-admin` versions above were verified against PyPI in this session (`pip index versions <pkg>`) on 2026-08-01 — both are newer than STACK.md's prior figures (3.x / 6.x respectively); update STACK.md when convenient. `androidx.core:core-telecom` version was cross-checked via WebSearch against `developer.android.com/jetpack/androidx/releases/core` release notes and a March 2026 third-party changelog aggregator (commonsware.com) — confirm the exact current stable number directly in Android Studio's dependency picker at implementation time, since Jetpack artifacts ship frequently.

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────┐        ┌─────────────────────────┐
│  tools/push_trigger.py  │        │   Ed25519 dev keypair    │
│  (CLI, manual invoke)   │───────▶│   (private key: sender)  │
└───────────┬─────────────┘        └─────────────────────────┘
            │  1. build envelope {v, event_id, call_id, call_type,
            │     caller, expires_at}; sign with private key
            │  2. log sentAt timestamp
            ▼
   ┌────────────────┐              ┌────────────────┐
   │  aioapns client │             │ firebase-admin  │
   │  push_type=voip │             │ AndroidConfig   │
   │  apns-topic=    │             │ priority=high   │
   │  <bundle>.voip  │             │ data-only       │
   └───────┬────────┘              └────────┬────────┘
           ▼                                ▼
   ┌────────────────┐              ┌────────────────┐
   │      APNs       │              │      FCM        │
   └───────┬────────┘              └────────┬────────┘
           ▼                                ▼
   ┌────────────────────────┐     ┌──────────────────────────┐
   │ iOS: PKPushRegistry     │     │ Android: FirebaseMessaging│
   │ .didReceiveIncomingPush │     │ Service.onMessageReceived │
   │ with:for:completion:    │     │ (data-only, high prio)    │
   └───────────┬─────────────┘    └────────────┬──────────────┘
               ▼                                ▼
   ┌────────────────────────┐     ┌──────────────────────────┐
   │ Verify Ed25519 sig      │     │ Verify Ed25519 sig        │
   │ (CryptoKit)             │     │ (Tink/BouncyCastle)       │
   │ log receivedAt          │     │ log receivedAt            │
   └───────────┬─────────────┘    └────────────┬──────────────┘
               ▼                                ▼
   ┌────────────────────────┐     ┌──────────────────────────┐
   │ CXProvider              │     │ CallsManager.addCall /    │
   │ .reportNewIncomingCall  │     │ ConnectionService +        │
   │  (SYNCHRONOUS, always)  │     │ CallStyle notification +  │
   │  log reportedAt         │     │ full-screen intent         │
   └───────────┬─────────────┘    │ log reportedAt              │
               ▼                  └────────────┬──────────────┘
   ┌────────────────────────┐                   ▼
   │ Native call UI shows    │     ┌──────────────────────────┐
   │ "HA-Phone Testanruf"    │     │ Native call UI shows       │
   │ (placeholder, D-06)     │     │ "HA-Phone Testanruf"       │
   └────────────────────────┘     └──────────────────────────┘
```

### Recommended Project Structure
```
ha-phone-app/
├── tools/
│   ├── push_trigger.py       # CLI: sign + send one test push (APNs or FCM)
│   ├── envelope.py           # shared envelope build/sign/canonicalize logic
│   ├── keys/                 # dev Ed25519 keypair + APNs .p8 (gitignored)
│   └── tests/
│       └── test_envelope.py  # sign/verify roundtrip, tamper, expiry unit tests
├── ios-app/                  # throwaway Xcode project (no PJSIP)
│   ├── HAPhoneTestApp/
│   │   ├── AppDelegate.swift / App.swift
│   │   ├── PushHandler.swift      # PKPushRegistryDelegate
│   │   ├── CallProvider.swift     # CXProviderDelegate + CXProvider setup
│   │   └── EnvelopeVerifier.swift # CryptoKit Ed25519 verification
│   └── HAPhoneTestAppTests/
│       └── EnvelopeVerifierTests.swift
└── android-app/               # throwaway Android Studio project (no PJSIP)
    ├── app/src/main/java/.../
    │   ├── TestFcmService.kt      # FirebaseMessagingService
    │   ├── CallRegistration.kt    # CallsManager / ConnectionService setup
    │   └── EnvelopeVerifier.kt    # Tink/BouncyCastle Ed25519 verification
    └── app/src/test/java/.../
        └── EnvelopeVerifierTest.kt
```

### Pattern 1: iOS — Unconditional Synchronous CallKit Report

**What:** Every single VoIP push, with no exceptions (malformed, duplicate, expired, whatever), results in exactly one `reportNewIncomingCall` call before the delegate method returns.
**When to use:** Always — this is Apple's hard API contract since iOS 13, not a best practice.
**Example:**
```swift
// Source: Context7/WebSearch cross-verified against Apple PushKit docs + community examples
import PushKit
import CallKit

class PushHandler: NSObject, PKPushRegistryDelegate {
    let provider: CXProvider

    func pushRegistry(_ registry: PKPushRegistry,
                       didReceiveIncomingPushWith payload: PKPushPayload,
                       for type: PKPushType,
                       completion: @escaping () -> Void) {
        // 1. Parse whatever we can; fall back to a placeholder on any failure.
        let dict = payload.dictionaryPayload
        let callIdString = dict["callId"] as? String ?? UUID().uuidString
        let uuid = UUID(uuidString: callIdString) ?? UUID()

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: "HA-Phone Testanruf")
        update.localizedCallerName = "HA-Phone Testanruf"
        update.hasVideo = false

        // 2. Report FIRST, synchronously, no async work before this call.
        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            // 3. Only now, verify signature / fetch details / log timestamps.
            self.verifySignatureAndLog(dict)
            completion()  // Call completion in the reportNewIncomingCall callback, not before.
        }

        // If the payload is expired/invalid, end the just-reported call
        // immediately rather than skipping the report entirely.
        if isExpired(dict) {
            let controller = CXCallController()
            let endCallAction = CXEndCallAction(call: uuid)
            controller.request(CXTransaction(action: endCallAction), completion: { _ in })
        }
    }
}
```

### Pattern 2: iOS — Minimal CXProviderConfiguration

**What:** Smallest viable `CXProvider` setup for a single-placeholder-call POC.
**Example:**
```swift
// Source: Context7/WebSearch cross-verified against developer.apple.com/documentation/callkit
let configuration = CXProviderConfiguration(localizedName: "HA-Phone Test")
configuration.supportsVideo = false
configuration.maximumCallGroups = 1
configuration.maximumCallsPerCallGroup = 1
configuration.supportedHandleTypes = [.generic]
let provider = CXProvider(configuration: configuration)
```

### Pattern 3: Android — Self-Managed Registration via CallsManager (Jetpack Telecom)

**What:** Register the app as a calling app using the simplified Jetpack `CallsManager` API rather than hand-rolling `ConnectionService`/`PhoneAccount` boilerplate.
**When to use:** Recommended default for Phase 1; fall back to raw `ConnectionService` if `CallsManager` proves incompatible with the Play Store calling-app declaration at implementation time (see Assumptions Log A3).
**Example:**
```kotlin
// Source: WebFetch developer.android.com/develop/connectivity/telecom/selfManaged (androidx.core.telecom)
val callsManager = CallsManager(context)
val capabilities = CallsManager.CAPABILITY_BASELINE
callsManager.registerAppWithTelecom(capabilities)

fun placeholderIncomingCallAttributes(): CallAttributesCompat = CallAttributesCompat(
    displayName = "HA-Phone Testanruf",
    address = Uri.parse("haphone:test"),
    direction = CallAttributesCompat.DIRECTION_INCOMING,
    callType = CallAttributesCompat.CALL_TYPE_AUDIO_CALL,
)

// Inside FirebaseMessagingService.onMessageReceived, after verifying signature:
callsManager.addCall(
    placeholderIncomingCallAttributes(),
    onAnswerCall = { /* log reportedAt / accepted */ },
    onSetCallDisconnected = { /* end call */ },
    onSetCallActive = { },
    onSetCallInactive = { }
) {
    // Runs once the call is registered with Telecom — post the CallStyle
    // notification + full-screen intent from here.
}
```
**Manifest requirement:** `<uses-permission android:name="android.permission.MANAGE_OWN_CALLS" />`
**Critical timing:** a foreground notification must be posted within ~5 seconds of `addCall`, and all callback lambdas must complete within ~5 seconds or the call session may be torn down.

### Pattern 4: Android — CallStyle Notification + Full-Screen Intent

**What:** The visible incoming-call UI, always paired with the Telecom registration above.
**Example:**
```kotlin
// Source: WebFetch developer.android.com/develop/ui/compose/notifications/call-style
val caller = Person.Builder().setName("HA-Phone Testanruf").setImportant(true).build()
val fullScreenIntent = PendingIntent.getActivity(
    context, 0, Intent(context, IncomingCallActivity::class.java),
    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
)
val notification = NotificationCompat.Builder(context, CALL_CHANNEL_ID)
    .setStyle(NotificationCompat.CallStyle.forIncomingCall(caller, declineIntent, answerIntent))
    .setFullScreenIntent(fullScreenIntent, /* highPriority = */ true)
    .setCategory(NotificationCompat.CATEGORY_CALL)
    .setPriority(NotificationCompat.PRIORITY_MAX)
    .addPerson(caller)
    .build()

// Always check the runtime grant before relying on full-screen display:
if (!notificationManager.canUseFullScreenIntent()) {
    // Fall back to a normal heads-up notification and prompt the user to
    // grant it via ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT.
}
NotificationManagerCompat.from(context).notify(CALL_NOTIFICATION_ID, notification)
```
**Requires:** API 31+ for `CallStyle` itself; `USE_FULL_SCREEN_INTENT` permission in the manifest; API 34+ additionally gates the *default grant* behind the Play Console declaration (see below).

### Pattern 5: Minimal Signed Push-Event Envelope (Ed25519)

**What:** A versioned, minimal JSON envelope the Python test script signs and both native apps verify — the same shape the future relay/PBX (Phase 6) will produce, so it survives without a breaking change.
**Fields:** `v` (schema version int), `event_id` (UUID, replay-protection nonce — not yet enforced server-side per D-08, but present so it can be later), `call_id` (UUID), `call_type` (fixed `"audio"` for Phase 1), `caller` (fixed `"HA-Phone Testanruf"` per D-06), `issued_at` / `expires_at` (unix seconds, short TTL e.g. `issued_at + 30`), `sig` (base64 Ed25519 signature over the canonical JSON of all preceding fields, sorted keys, `sig` excluded).

```python
# Source: cryptography library docs (VERIFIED available in this session: cryptography 41.0.7)
import json, time, base64, uuid
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

def build_and_sign(private_key: Ed25519PrivateKey) -> dict:
    now = int(time.time())
    envelope = {
        "v": 1,
        "event_id": str(uuid.uuid4()),
        "call_id": str(uuid.uuid4()),
        "call_type": "audio",
        "caller": "HA-Phone Testanruf",
        "issued_at": now,
        "expires_at": now + 30,
    }
    canonical = json.dumps(envelope, sort_keys=True, separators=(",", ":")).encode()
    signature = private_key.sign(canonical)
    envelope["sig"] = base64.b64encode(signature).decode()
    return envelope
```

```swift
// Source: CryptoKit (system framework, iOS 13+) — verification side
import CryptoKit

func verify(envelope: [String: Any], publicKeyBase64: String) -> Bool {
    guard let sigB64 = envelope["sig"] as? String,
          let signature = Data(base64Encoded: sigB64),
          let pubKeyData = Data(base64Encoded: publicKeyBase64),
          let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: pubKeyData)
    else { return false }
    var unsigned = envelope; unsigned.removeValue(forKey: "sig")
    let canonical = canonicalize(unsigned) // must match Python's sort_keys/separators exactly
    return publicKey.isValidSignature(signature, for: canonical)
}
```

APNs request (VoIP push type):
```jsonc
// aps dict may be empty for VoIP pushes — PushKit delivers the whole
// dictionary to the delegate regardless of "aps" contents.
{
  "aps": {},
  "v": 1, "event_id": "...", "call_id": "...", "call_type": "audio",
  "caller": "HA-Phone Testanruf", "issued_at": 1785600000, "expires_at": 1785600030,
  "sig": "base64..."
}
```
FCM data message (all values must be strings):
```jsonc
{
  "message": {
    "token": "<fcm-token>",
    "android": { "priority": "high", "ttl": "30s" },
    "data": {
      "v": "1", "event_id": "...", "call_id": "...", "call_type": "audio",
      "caller": "HA-Phone Testanruf", "issued_at": "1785600000",
      "expires_at": "1785600030", "sig": "base64..."
    }
  }
}
```

### Anti-Patterns to Avoid
- **Skipping `reportNewIncomingCall` on any code path** (malformed/expired/duplicate push): report first, then end the call via `CXEndCallAction` if it turns out to be stale — never silently drop it.
- **Doing async work (network calls, signature verification) before `reportNewIncomingCall`**: verify/fetch only inside or after the report's completion handler.
- **FCM `notification`-block messages for the wake path**: use data-only messages exclusively so `onMessageReceived` is guaranteed to fire.
- **Skipping the Play Console full-screen-intent declaration** because "it's just a prototype": Android 14+ devices will silently deny the permission without it, which defeats PUSH-04's own acceptance criterion.
- **Embedding the Ed25519 private key or the `.p8` APNs key inside the repo** — keep both under `tools/keys/` and gitignore them (per project security rules, no hardcoded secrets in source).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| VoIP wake mechanism on iOS | A custom background-fetch/silent-push polling scheme | PushKit + CallKit | Apple explicitly reserves guaranteed background wake for this pair; anything else is unreliable by design |
| Self-managed calling registration on Android | Hand-rolled `ConnectionService` + `PhoneAccount` boilerplate | `androidx.core.telecom` `CallsManager` (fallback: raw `ConnectionService`) | `CallsManager` is Google's own simplification of the exact pattern this project needs, actively maintained |
| Ed25519 signing/verification | Hand-written signature scheme or manual EdDSA math | `cryptography` (Python/sender), CryptoKit (iOS), Tink/BouncyCastle (Android) | Cryptographic primitives must never be hand-rolled; all three are audited, standard libraries |
| APNs token auth (JWT) | Manual ES256 JWT construction | `aioapns` (wraps this internally) | JWT signing has subtle correctness/security pitfalls; the library already does it |
| FCM message construction | Raw HTTP calls to the legacy FCM server-key API | `firebase-admin` HTTP v1 client | Legacy API is fully deprecated/shut down by Google |

**Key insight:** Everything in Phase 1 that touches OS-level call/push contracts (CallKit, PushKit, Telecom, FCM priority) is deliberately inflexible by platform design — the "custom" version of any of these is not a shortcut, it's a reliability regression waiting to happen.

## Common Pitfalls

### Pitfall 1: Not reporting every VoIP push to CallKit synchronously
**What goes wrong:** iOS kills the app ("failed to post an incoming call in time") on the first offense and permanently revokes the VoIP push token on the second, until reinstall.
**Why it happens:** Developers try to "check with the server first" before reporting, or silently skip reporting for malformed/expired/duplicate pushes.
**How to avoid:** Report first, unconditionally, for every VoIP push — including a synthetic malformed-payload test case exercised before every release. See Pattern 1 above.
**Warning signs:** Console log "Killing VoIP app...failed to post an incoming call"; app "just stops ringing" until reinstalled.
**Phase to address:** Phase 1 (this pitfall's prevention *is* the phase's core deliverable).

### Pitfall 2: FCM high-priority silent downgrade
**What goes wrong:** If a high-priority data-only FCM message doesn't result in a real, visible notification within the handler, Google silently demotes future high-priority messages for that install over a rolling ~7-day window — with no error returned to the sender.
**How to avoid:** Every call-type FCM message must deterministically produce a CallStyle/full-screen notification, even on error paths (show a "missed call" fallback rather than nothing).
**Warning signs:** Growing delay between push send and app wake for a specific install over days.
**Phase to address:** Phase 1, with an explicit rule: "no code path receives a call-type FCM message without producing a visible notification."

### Pitfall 3: USE_FULL_SCREEN_INTENT default-deny on Android 14+
**What goes wrong:** Without the Play Console "calling app" declaration, `USE_FULL_SCREEN_INTENT` is not auto-granted on Android 14+ devices; calls silently degrade to a normal heads-up notification (or the app crashes if it assumes the permission is always present).
**How to avoid:** Complete the Play Console declaration before relying on this (see below); always runtime-check `canUseFullScreenIntent()` and gracefully degrade.
**Phase to address:** Phase 1 implementation; Play Console declaration itself is an administrative prerequisite that should happen as early as possible in the phase since account/review turnaround time is unknown.

### Pitfall 4: VoIP push cannot be tested on the iOS Simulator at all
**What goes wrong:** Teams try `xcrun simctl push` to shortcut real-device setup and discover VoIP, unlike regular alert pushes, is not supported by the simulator's push-simulation command.
**How to avoid:** Budget real-device setup (provisioning profile, physical iPhone tethered to a Mac) as a Phase 1 day-one task, not an afterthought — this is confirmed to have zero simulator fallback.
**Phase to address:** Phase 1, immediately — this determines whether the phase can start at all on a given machine.

### Pitfall 5: Payload schema that would need a breaking change later
**What goes wrong:** A minimal ad-hoc payload (e.g. just `{"callId": "..."}`) works fine for the throwaway test but forces a breaking-change migration when the real relay (Phase 6) needs `event_id`/expiry/versioning.
**How to avoid:** Use the versioned envelope shape from Pattern 5 now, even though only `v=1` fields are populated and no server-side replay-dedup store exists yet.
**Phase to address:** Phase 1 (payload schema lock-in), per D-07/CONTEXT.md's explicit instruction.

## Runtime State Inventory

Not applicable — this is a greenfield phase (no existing code, no rename/refactor/migration in scope). Skipping this section per the greenfield exception.

## Code Examples

See Architecture Patterns section above (Patterns 1-5) for verified/cross-checked code: PushKit delegate + synchronous CallKit report, minimal `CXProviderConfiguration`, `CallsManager` self-managed registration, CallStyle + full-screen intent notification, and the signed envelope build/verify pair.

### APNs send via aioapns (VoIP)
```python
# Source: Context7 /fatal1ty/aioapns docs, verified in this session
import asyncio
from aioapns import APNs, NotificationRequest, PushType, PRIORITY_HIGH

async def send_test_voip_push(device_token: str, envelope: dict):
    with open("tools/keys/AuthKey_XXXX.p8") as f:
        auth_key = f.read()
    client = APNs(
        key=auth_key, key_id="<KEY_ID>", team_id="<TEAM_ID>",
        topic="de.haphone.app",   # bare bundle id; aioapns appends nothing —
        use_sandbox=True,                 # set apns_topic explicitly to "<bundle>.voip" below
    )
    request = NotificationRequest(
        device_token=device_token,
        message=envelope,
        push_type=PushType.VOIP,
        priority=PRIORITY_HIGH,
        apns_topic="de.haphone.app.voip",
    )
    result = await client.send_notification(request)
    print(result.status, result.is_successful)
```

### FCM send via firebase-admin (data-only, high priority)
```python
# Source: Context7 /firebase/firebase-admin-python docs, adapted for data-only (no `notification` block)
from firebase_admin import messaging

def send_test_fcm_push(fcm_token: str, envelope: dict):
    message = messaging.Message(
        data={k: str(v) for k, v in envelope.items()},  # FCM data values must be strings
        android=messaging.AndroidConfig(priority="high", ttl=30),
        token=fcm_token,
    )
    return messaging.send(message)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| Raw `ConnectionService` + `PhoneAccount` registration boilerplate | `androidx.core.telecom` `CallsManager` (stable 1.0.0) | Introduced as a Jetpack library, actively evolving (1.1.0 alpha as of March 2026 per WebSearch) | Less boilerplate for the same self-managed calling registration; verify at implementation time whether it satisfies the Play Console calling-app declaration identically to raw `ConnectionService` |
| Certificate-based (.p12) APNs auth | Token-based (.p8) auth, valid for VoIP push type too (not just alert/background) | Ongoing Apple deprecation of cert-based auth | One key, no renewal, works for VoIP — already STACK.md's recommendation, reconfirmed here via `aioapns`'s own VoIP example |
| `aioapns` 3.x / `firebase-admin` 6.x (STACK.md's prior figures) | `aioapns` 4.0 / `firebase-admin` 7.5.0 | Between STACK.md's research (2026-07-31) and this session (2026-08-01) — likely just prior imprecision, not literally a one-day jump | Bump the pinned versions when implementing; no breaking API changes expected for this phase's minimal usage but confirm changelogs |

**Deprecated/outdated:**
- FCM legacy server-key API — fully shut down, `firebase-admin` only targets HTTP v1.
- Certificate-based (.p12) APNs auth for new integrations — actively discouraged by Apple.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The Play Console "calling app" full-screen-intent declaration can be completed on a draft/internal-testing-only app that hasn't had a public release yet | Play Console Declaration / Environment Availability | If untrue, PUSH-04's declaration step is blocked until a closed/internal test track release exists — adds a sequencing dependency the planner should surface explicitly |
| A2 | A single token-based APNs `.p8` Auth Key is sufficient for VoIP push type (`push_type=voip`) without a separate legacy VoIP Services Certificate | Standard Stack, Code Examples | If untrue, an extra one-time cert-generation step is needed in Apple Developer portal before any VoIP push can be sent; low implementation cost either way, but changes the setup checklist |
| A3 | `androidx.core.telecom`'s `CallsManager` (1.0.0 stable) is a safe substitute for hand-rolled `ConnectionService`/`PhoneAccount` and still qualifies the app as a "calling app" for the Play Store full-screen-intent auto-grant | Standard Stack, Pattern 3 | If untrue, must fall back to raw `ConnectionService`/`PhoneAccount` registration (STACK.md's original recommendation) — same outcome, more boilerplate, no schedule risk if caught early |
| A4 | Native Android Ed25519 support (Conscrypt / `java.security.Signature`) is available and reliable on the project's eventual target API levels | Standard Stack (Supporting) | If assumed-available and actually inconsistent across devices, signature verification silently fails on some Android versions — mitigated by recommending Tink/BouncyCastle explicitly instead |
| A5 | An active Apple Developer Program membership ($99/yr) and an active Google Play Console developer account ($25 one-time) already exist for this project | Environment Availability | **ERRATA (superseded by CONTEXT.md D-11/D-12):** This assumption was WRONG — the user has explicitly rejected both paid accounts for Phase 1 (zero-budget constraint). Neither exists nor will be created for this phase. Consequence: iOS is Simulator/unit-test-only (no real-device push verification), Android skips Play Console entirely (Firebase-only + `adb install`, full-screen-intent grant tested empirically without a declaration). See D-11/D-12 for the authoritative scoping. |

**If this table is empty:** N/A — see entries above; all should be confirmed by the developer before/at the start of Phase 1 execution.

## Open Questions (RESOLVED)

1. **Is a Mac with the physical iPhone available for the iOS half of this phase?**
   - What we know: This research session ran in a Linux sandbox with no Xcode/macOS detected at all.
   - What's unclear: Whether the developer has separate Apple hardware to build/run/debug the iOS app — CONTEXT.md confirms a real iPhone is the test device (D-01), but says nothing about the build machine.
   - Recommendation: Planner should add an explicit Wave 0 checklist item confirming Mac + Xcode + Apple Developer Program membership availability before scheduling any iOS tasks.
   - RESOLVED (ERRATA, superseded by D-11): iOS build/test is routed through Plan 04's GitHub Actions macOS runner, but as an UNSIGNED SIMULATOR-ONLY build/test pipeline, not Fastlane/TestFlight — the user rejected the paid Apple Developer Program membership that TestFlight/match/signing require. Consequence: no local Mac is needed, but the physical iPhone is NOT used for real-device manual testing in Plan 06 either; real-device VoIP push verification is an accepted, open gap until the user chooses to pay for Program membership.

2. **Exact Play Console full-screen-intent declaration UI wording/click-path**
   - What we know: The declaration lives on the "App content" page (Monitor and improve > App content), became mandatory May 2024, and Google enforces default-deny for non-declared apps since January 22, 2025 on Android 14+ targets.
   - What's unclear: Sources disagree on the exact click-path/labels (one thread references selecting "Other" under "About your app", which doesn't obviously match a "calling app" declaration — likely describes a different, adjacent declaration flow that got conflated in search results).
   - Recommendation: Do not trust the exact UI copy from this research; have the developer navigate Play Console directly at execution time and screenshot the actual flow for the plan's verification step.
   - RESOLVED (ERRATA, superseded by D-12): Play Console is skipped entirely — the user rejected the $25 Google Play Developer account requirement. Plan 05 installs via `adb install` instead, and empirically tests (rather than assumes) whether the Android 14+ full-screen-intent auto-grant works for a sideloaded, self-managed-ConnectionService app without any Play Console declaration.

3. **Non-Pixel Android OEM coverage (already flagged as D-03)**
   - What we know: No non-Pixel device is currently available; ROADMAP.md's success criterion #3 explicitly requires OEM diversity.
   - What's unclear: Whether to formally descope criterion #3 to "Pixel only" for Phase 1's Definition of Done, or mark it "blocked, pending device."
   - Recommendation: Planner should make an explicit choice here (not leave it ambiguous) — recommend scoping down to Pixel-only for Phase 1 sign-off, with a tracked backlog item for OEM coverage revisited at Phase 6 hardening (per PITFALLS.md's own phase mapping).
   - RESOLVED: CONTEXT.md D-03 explicitly scopes Phase 1 to Pixel-only device coverage; non-Pixel OEM verification is deferred to Phase 6 hardening. This is reflected in Plans 01, 05, and 06 (Plan 06 Task 3's sign-off note names the deferral explicitly).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode / macOS | iOS build, run, debug (PUSH-01, PUSH-02) | ✗ (not present on this Linux sandbox) | — | None found — Xcode requires macOS; must use separate Apple hardware with the physical iPhone tethered. No cloud-Mac fallback investigated for Phase 1 (that's a Phase 6/CI concern per STACK.md, not a substitute for interactive debugging here) |
| Android SDK (build-tools, platforms, adb) | Android build, run, debug (PUSH-03, PUSH-04) | ✓ | `platforms`: android-33/34/35; `adb` 1.0.41 (37.0.0-14910828) at `~/android-sdk/platform-tools` | — |
| Gradle | Android project build | ✗ (no system-wide `gradle`, no wrapper found yet — none exists since no Android project has been scaffolded) | — | Gradle Wrapper (`gradlew`), auto-generated by Android Studio project creation; requires one-time internet access to download the Gradle distribution |
| Apple Developer Program membership | APNs Auth Key generation, VoIP entitlement, real-device signing | ? unverifiable in this session | — | Must be confirmed active before Phase 1 iOS work starts (see Assumptions Log A5) |
| Google Play Console developer account | PUSH-04 "calling app" declaration | ? unverifiable in this session | — | Must be confirmed active before Phase 1 Android declaration step (see Assumptions Log A5) |
| Python 3 + pip | test-trigger CLI runtime | ✓ | Python 3.12.3, pip 24.0 | — |
| `cryptography` (Ed25519 signing) | test-trigger signing | ✓ | 41.0.7 installed (50.0.0 latest on PyPI) | — |
| `pynacl` | alternative Ed25519 lib | ✓ (already installed, not required if using `cryptography`) | 1.6.2 | — |
| `aioapns`, `firebase-admin` | sending real pushes from the test script | ✗ (not yet installed in this sandbox) | — | `pip install aioapns firebase-admin` — trivial, no blocking risk |
| Internet/HTTPS reachability | doc lookups during research; APNs/FCM API calls at runtime | ✓ | 200 OK to developer.apple.com and firebase.google.com in this session | — |

**Missing dependencies with no fallback:**
- Xcode/macOS — blocks all iOS-side implementation and testing from this specific machine; requires separate Apple hardware.

**Missing dependencies with fallback:**
- System-wide Gradle — use the Gradle Wrapper generated by Android Studio's project template instead.
- `aioapns`/`firebase-admin` not yet installed — trivial `pip install`, not a real gap.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | pytest (Python test-trigger logic) + XCTest (iOS signature verification) + JUnit4/5 (Android signature verification) |
| Config file | none yet — Wave 0 gap (no `pytest.ini`/`pyproject.toml` test section exists; Xcode/Android Studio test targets don't exist until the projects are scaffolded) |
| Quick run command | `pytest tools/tests/ -x` (Python); `xcodebuild test -project ios-app/HAPhoneTestApp.xcodeproj -scheme HAPhoneTestApp -destination 'platform=iOS Simulator,name=iPhone 16'` (iOS, logic-only tests); `./gradlew testDebugUnitTest` (Android) |
| Full suite command | Same three commands — Phase 1's test surface is small enough that "quick" and "full" are identical |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PUSH-01 | iOS VoIP push wakes app across app states (open/background/locked/terminated) | manual-only (real device required; PushKit is not simulator-testable at all — confirmed no `simctl push` support for VoIP) | N/A — manual test procedure (see below) | ❌ Wave 0: write the manual test checklist |
| PUSH-02 | CallKit reports every VoIP push synchronously, including malformed/expired/duplicate pushes | unit (regression-testable at the code-path level) + manual (real-device confirmation) | `xcodebuild test ... -only-testing:HAPhoneTestAppTests/PushHandlerTests` (assert `reportNewIncomingCall` invoked for a set of malformed-payload fixtures via a mock/injected `CXProvider`) | ❌ Wave 0: `PushHandlerTests.swift` |
| PUSH-03 | Android high-priority FCM wakes app while backgrounded/locked | manual-only (real device, locked-screen state cannot be meaningfully unit-tested) | N/A — manual test procedure | ❌ Wave 0: write the manual test checklist |
| PUSH-04 | Self-managed Telecom + CallStyle + full-screen intent shown; Play Console declaration completed | unit (CallStyle/notification construction logic) + manual (real-device full-screen display) + administrative (Play Console screenshot) | `./gradlew testDebugUnitTest --tests EnvelopeVerifierTest` (signature logic only — CallStyle/Telecom itself needs instrumentation or manual test) | ❌ Wave 0: `EnvelopeVerifierTest.kt` |
| (cross-cutting, D-07) | Ed25519 envelope: sign/verify roundtrip, tamper detection, expiry rejection | unit (fully automatable, no device needed) | `pytest tools/tests/test_envelope.py -x`; `xcodebuild test ... -only-testing:HAPhoneTestAppTests/EnvelopeVerifierTests`; `./gradlew testDebugUnitTest --tests EnvelopeVerifierTest` | ❌ Wave 0: all three test files |

### Sampling Rate
- **Per task commit:** run the relevant quick-run command for whichever side (Python/iOS/Android) was touched.
- **Per wave merge:** run all three quick-run commands (they are also the full suite for this phase).
- **Phase gate:** full suite green, plus the manual test procedure below completed and logged, before `/gsd-verify-work`.

### Wave 0 Gaps
- [ ] `tools/tests/test_envelope.py` — sign/verify roundtrip, tamper (flip one byte, expect failure), expiry rejection; framework install: `pip install pytest`
- [ ] `ios-app/HAPhoneTestAppTests/EnvelopeVerifierTests.swift` — same three cases using CryptoKit; covers the cross-cutting envelope requirement
- [ ] `ios-app/HAPhoneTestAppTests/PushHandlerTests.swift` — asserts `reportNewIncomingCall` is invoked for well-formed, malformed, and expired payload fixtures (inject a mock `CXProvider`); covers PUSH-02
- [ ] `android-app/app/src/test/.../EnvelopeVerifierTest.kt` — same three envelope cases using Tink/BouncyCastle
- [ ] Manual test procedure document (see below) — not a code file, but a Wave 0 deliverable the plan should produce before real-device testing begins

### Manual Test Procedure (PUSH-01, PUSH-03 — not automatable)

Concrete, minimal, hand-executable procedure for a solo developer, per app state × per platform:

**App states to exercise (per CONTEXT.md D-09):** app open (foreground), app backgrounded, device locked (screen off), app fully terminated (force-quit / swiped away), overnight standby (device locked & idle 8+ hours).

**Per test run:**
1. Put the device in the target app state.
2. Run `tools/push_trigger.py --platform ios|android --state <label>`; the script logs `sentAt` (its own clock).
3. Observe the device: does the native call UI appear? How long does it take (rough stopwatch/eyeball estimate is enough per D-09 — no fixed numeric target)?
4. The app itself logs `receivedAt` (when the push handler fired) and `reportedAt` (when `reportNewIncomingCall`/`addCall` returned) to on-device console/log (visible via `adb logcat` for Android, Xcode console or Console.app for iOS while tethered — note that a *terminated* app has no live Xcode console, so for that specific state rely on a persisted local log file the app writes on wake, read back afterward).
5. Record pass/fail + rough latency in a simple table (spreadsheet or markdown) across at least a few repetitions per state — no fixed count required (D-09), but enough to develop a qualitative sense of "does this feel reliable."
6. Repeat overnight-standby specifically as its own long-duration test (start before sleep, trigger next morning) since this is the state most likely to expose OS-level Doze/App Standby interference even on stock Android/Pixel.

This procedure directly operationalizes D-09's "informal, qualitative" acceptance approach while still producing a concrete, repeatable artifact (the sent/received/reported timestamp log) that the developer can point to as evidence.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|----------------|---------|-------------------|
| V2 Authentication | No | Out of scope for Phase 1 — no user login exists yet; device/user auth arrives with QR provisioning (Phase 3) |
| V3 Session Management | No | No session concept exists in this phase |
| V4 Access Control | No | Single dev device, single dev signing key; multi-tenant access control is Phase 6 |
| V5 Input Validation | Yes | Strictly typed parsing of the push envelope on both clients (Swift `Codable`/Kotlin data class); reject malformed fields safely, but **still always call `reportNewIncomingCall`** regardless of validation outcome (Pitfall 1 overrides normal "reject bad input" instinct here) |
| V6 Cryptography | Yes | Ed25519 signing/verification via `cryptography` (sender), CryptoKit (iOS), Tink/BouncyCastle (Android) — never hand-roll |

### Known Threat Patterns for this Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|----------------------|
| Forged/spoofed push payload | Spoofing, Tampering | Ed25519 signature verification on the client before trusting any payload field beyond "a call exists" |
| Replayed captured push event | Tampering | `event_id` + `expires_at` fields present in the envelope now (per D-07/Pattern 5) even though server-side dedup enforcement is deferred to Phase 6 (D-08) — client should treat an expired envelope as stale (end the call immediately after the mandatory CallKit report, per Pitfall 1's own guidance) |
| Push payload leakage via device notification history/logs | Information Disclosure | Low residual risk in Phase 1 since the payload carries only a placeholder string (D-06) — but the schema itself (Pattern 5) is designed to never carry sensitive data, per PITFALLS.md's Pitfall 5, so this discipline survives into later phases without a payload redesign |
| Signing key compromise | Elevation of Privilege | Single dev Ed25519 keypair is acceptable for Phase 1 (per D-07's own scope), but the private key and the APNs `.p8` file must never be committed to git — store under `tools/keys/` with that path gitignored |

## Sources

### Primary (HIGH confidence)
- Context7 `/fatal1ty/aioapns` — VoIP `NotificationRequest`, `PushType`, token-based client init (code examples verified in this session)
- Context7 `/firebase/firebase-admin-python` — `messaging.Message`, `AndroidConfig(priority='high')` (code examples verified in this session)
- `pip index versions aioapns` / `firebase-admin` / `cryptography` / `pynacl` — verified current PyPI versions in this session (2026-08-01)
- WebFetch `developer.android.com/develop/ui/compose/notifications/call-style` — CallStyle code pattern
- WebFetch `developer.android.com/develop/connectivity/telecom/selfManaged` — `CallsManager` registration pattern
- WebFetch `firebase.google.com/docs/cloud-messaging/android/message-priority` — high-priority data-only message behavior
- WebSearch confirming VoIP push is unsupported by `xcrun simctl push` (multiple independent sources agree)

### Secondary (MEDIUM confidence)
- WebSearch cross-verification of `androidx.core.telecom` `CallsManager` 1.0.0 stable status and 1.1.0 alpha timeline (commonsware.com changelog aggregator + `developer.android.com/jetpack/androidx/releases/core` release notes)
- WebSearch summary of Apple's token-based-auth documentation confirming `.p8` keys are valid for VoIP push notifications (Apple's own doc page could not be directly rendered via WebFetch in this session — title-only; relying on a WebSearch summary quoting it)
- WebSearch summary of Play Console's full-screen-intent declaration flow (App content page, mandatory since May 2024, default-deny since Jan 22 2025) — general mechanics MEDIUM confidence, exact click-path/labels LOW confidence (see Open Questions #2)
- Existing project research: `.planning/research/STACK.md`, `.planning/research/PITFALLS.md`, `.planning/research/ARCHITECTURE.md` (all dated 2026-07-31, HIGH confidence per their own sourcing, reused here as canonical project baseline)

### Tertiary (LOW confidence)
- Individual forum/blog threads on Apple VoIP token revocation behavior (consistent across multiple threads, but forum-sourced, not primary Apple documentation) — already flagged as MEDIUM in PITFALLS.md, carried forward at the same confidence here
- WebSearch-summarized claim that the Play Console declaration can be completed on an app not yet publicly released (Assumptions Log A1) — recommend direct verification in Play Console UI

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH for iOS/Android system frameworks and the Python push-sending libraries (Context7 + PyPI verified); MEDIUM for `androidx.core.telecom` (new library, WebSearch-only verification) and Android-side Ed25519 library choice (no definitive native-support confirmation)
- Architecture: HIGH — payload envelope design directly extends the already-locked project ARCHITECTURE.md pattern ("push is minimal and non-actionable alone"), no new architectural risk introduced
- Pitfalls: HIGH — both core iOS and Android pitfalls (synchronous CallKit report, FCM priority downgrade, full-screen-intent default-deny) are already documented at HIGH/MEDIUM-HIGH confidence in the project's own PITFALLS.md and reconfirmed against current official docs in this session

**Research date:** 2026-08-01
**Valid until:** 2026-08-15 (fast-moving: Android Jetpack Telecom is mid-evolution, and Play Console policy/UI details shift without notice — re-verify before executing if more than two weeks elapse)

---
*Phase 1 research for: Push-Wakeup Proof of Concept*
*Researched: 2026-08-01*
