# Phase 2: PJSIP Audio/Media Core - Research

**Researched:** 2026-08-04
**Domain:** PJSIP/PJSUA2 SIP signaling + media (SRTP/ICE/DTMF/codecs) integrated with CallKit (iOS) and androidx.core.telecom (Android), plus cross-repo Asterisk PJSIP TLS/SRTP test-extension provisioning
**Confidence:** MEDIUM-HIGH (PJSUA2 API surface and Asterisk pjsip.conf directives: HIGH, official docs verified live; version currency correction and Asterisk CLI correction: HIGH, verified against GitHub API / codebase; iOS/Android build-environment readiness in this sandbox: HIGH, directly probed)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### PJSIP-Build-Strategie
- **D-01:** PJSIP is built officially from source (not the community CocoaPod/AAR or third-party prebuilt binaries) — per STACK.md's recommendation.
- **D-02:** Matching Phase 1's pattern: iOS build runs on a GitHub Actions macOS runner; Android build runs here in the sandbox.

#### Test-SIP-Server
- **D-03:** Phase 2 develops and tests against the real HA-Phone box (`~/projects/Ha-Phone`, Asterisk 22 LTS), not a throwaway local Asterisk or a public SIP test service.
- **D-04:** A dedicated test extension is created on the HA-Phone box for Phase 2 (not one of the active 10-99 extensions) — avoids collisions with real household calls during unstable development.
- **D-05:** Test devices (iOS Simulator / Android emulator / sandbox) reach the HA-Phone box over the local network only during Phase 2 — no Tailscale, no port-forwarding. Matches the roadmap's sequencing (transport hardening is Phase 5's job, not Phase 2's).
- **D-06:** Existing HA-Phone extensions run plain UDP (`sip_tls_port=-1` in `extensions.py`, hardcoded `transport=udp` in the proxy/route headers) — but the new Phase 2 test extension will use **TLS/SRTP instead**, deviating from that default. **Cross-repo consequence:** this requires changes to the separate `Ha-Phone` repo (enabling `sip_tls_port`, provisioning a certificate, adding a `transport-tls` extension template) before the first PJSIP test call can happen — not just work inside `ha-phone-app`. Planner should scope this HA-Phone-side setup work explicitly, not assume it's a given.

#### Codec- & Netzwerk-Umgebung
- **D-07:** All three codecs named in CALL-01 (Opus, G.722, G.711) are verified for real against the HA-Phone box in Phase 2 — full coverage now, not phased within Phase 2.
- **D-08:** No STUN/TURN setup in Phase 2. Local-network-only testing (D-05) has no NAT to traverse, and ICE/STUN/TURN belongs to Phase 5 (Tailscale Transport Hardening), which will replace/subsume it. Avoids duplicate work.
- **D-09:** Mid-call network-switch handling (WiFi↔cellular, ICE restart per PITFALLS.md Pitfall 7) **is in scope for Phase 2**. Rationale: there's no later phase that would otherwise pick this up, and CALL-01 requires a "stable" two-way call, so network-switch resilience is treated as part of Phase 2's stability bar, not deferred.
- **D-10:** The transient SIP registration behavior (D-05/CALL-05 from Phase 1: registration only exists for the duration of a call, no persistent background registration) is verified manually via network sniff / Asterisk CLI (`sip show registry`) during test calls — not an automated test. Consistent with Phase 1's informal, qualitative acceptance style. **Research correction: `sip show registry` does not exist on this Asterisk 22 box (chan_sip removed) — see Common Pitfalls Pitfall 2 for the corrected command.**

#### Umfang Telefonie-UI
- **D-11:** Phase 2 builds real UI for exactly the 5 CALL-01..05 controls (mute, audio routing/speaker, DTMF keypad, hold, blind transfer, outgoing-call entry) — no more, no less.
- **D-12:** Outgoing call target entry (CALL-03) uses a classic numeric dialpad (not a plain text field).
- **D-13:** The same dialpad component is reused in-call for sending DTMF tones (CALL-02).
- **D-14:** The same dialpad component is also reused for entering the blind-transfer target (CALL-04).

#### iOS-Verifikationsgrenze
- **D-15:** iOS is built in parallel with Android in Phase 2, not deferred. Android gets full real-hardware verification; iOS stays structurally/Simulator-verified only.
- **D-16:** "iOS verified in Simulator" means structure/unit-test level only — PJSIP builds, SIP signaling/registration is checked — **not** real audio I/O through the Simulator's host-Mac microphone/speakers.
- **D-17:** Phase 2 produces its own `02-PHASE-SIGNOFF.md` (mirroring Phase 1's `01-PHASE-SIGNOFF.md` pattern) that explicitly documents the iOS real-device audio verification gap as an accepted, carried-forward item.
- **D-18:** The sign-off names a concrete resumption trigger: real iOS audio verification is picked back up specifically when the user enrolls in the Apple Developer Program ($99/yr).

### Claude's Discretion

Not explicitly separated in CONTEXT.md as a distinct section — all D-01..D-18 above are locked decisions. Areas left implicitly to implementation discretion (not raised as open questions by the user): exact PJSIP point-release pin within "build from source" (this research recommends 2.17 over the previously-assumed 2.16 — see Summary), exact Asterisk CLI command used to satisfy D-10's verification intent (this research recommends `pjsip show contacts`/`pjsip show aor`/`pjsip show endpoint` in place of the non-existent `sip show registry`), SDES vs DTLS-SRTP choice for the test extension's `media_encryption` (this research recommends SDES).

### Deferred Ideas (OUT OF SCOPE)

- STUN/TURN and full NAT traversal — explicitly deferred to Phase 5 (Tailscale Transport Hardening), which replaces/subsumes this rather than layering Tailscale on top of a separately-built STUN/TURN setup (D-08).
- Real iOS physical-device audio verification — deferred until the user enrolls in the Apple Developer Program (D-18); tracked via `02-PHASE-SIGNOFF.md`, not silently dropped.
- Full contacts/address book for dialing — belongs to Phase 3 (QR Provisioning & Device Management); Phase 2's dialpad (D-12) is a deliberate stand-in.
- Automated regression test for transient SIP registration — the manual verification in D-10 is accepted for Phase 2; no automated guard adopted now.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CALL-01 | Audio call functions stably (Opus/G.722/G.711, mic/speaker/Bluetooth routing) | Standard Stack (codec/version guidance), Architecture Patterns Pattern 2 (OS-owned audio routing), Code Examples (codec priority), Common Pitfalls 3 (Opus build gap), Validation Architecture (manual real-call verification) |
| CALL-02 | DTMF in an active call (RFC 2833/4733) | Code Examples (sendDtmf/CallSendDtmfParam), Standard Stack (RFC 4733 default match), Validation Architecture (DtmfControllerTest) |
| CALL-03 | Outgoing calls are possible | Code Examples (makeCall), Architectural Responsibility Map, Validation Architecture (DialpadTest) |
| CALL-04 | Hold a call and perform blind transfer | Code Examples (setHold/xfer), Architectural Responsibility Map, Validation Architecture (CallControlTest) |
| CALL-05 | After answer, the app builds the SIP connection transiently (no persistent background registration) | Architecture Patterns Pattern 1 (report-first, register-after), Common Pitfalls 2 (corrected verification command), Validation Architecture (manual CLI check) |
</phase_requirements>

## Summary

Phase 2 bolts PJSUA2 (SIP signaling + RTP/SRTP media engine) onto the two pieces of scaffolding Phase 1 already built — `CallProvider.swift` (CXProvider) and `CallRegistration.kt` (androidx.core.telecom `CallsManager`) — without touching how calls get reported to the OS. The work splits cleanly into three tracks: (1) build PJSIP 2.17 from source for iOS (static lib + Obj-C++ bridge) and Android (JNI module via SWIG), with Opus explicitly enabled; (2) wire PJSUA2's `Call`/`Account`/`Endpoint` API to each platform's call-lifecycle callbacks (CXProvider `didActivate`/`didDeactivate` for iOS audio session ownership, `CallControlScope` callbacks for Android) for the five CALL-01..05 controls; (3) a **cross-repo prerequisite** in `~/projects/Ha-Phone` — Asterisk currently has zero TLS transport defined and no per-extension transport/encryption field exists on the `Extension` model at all, so the dedicated TLS/SRTP test extension (D-04/D-06) cannot be provisioned without new backend work first.

Two corrections to locked assumptions surfaced during research, both important for planning:
1. **PJSIP 2.17 is now the current stable release** (GA 2026-04-22, verified via GitHub Releases API), not "2.16 stable / 2.17 dev" as STACK.md stated when it was researched on 2026-07-31. Recommend building 2.17, not 2.16, and flag the one backward-incompatible PJSUA2 C++ signature change it introduced (`Call::acc` is now `Account*`, was `Account&`).
2. **D-10's proposed verification command (`sip show registry`) does not exist on this Asterisk 22 box.** `pjsip.conf`'s own header comment confirms the legacy `chan_sip` driver was removed in Asterisk 21; only `chan_pjsip` is available. The equivalent commands are `pjsip show aor <ext>`, `pjsip show contacts`, and `pjsip show endpoint <ext>`. This does not change the *intent* of D-10 (manual CLI-based verification of transient registration), only the concrete command — the planner should update the acceptance-check task text accordingly.

**Primary recommendation:** Treat the HA-Phone-side TLS/SRTP test-extension provisioning (D-06) as a first-wave, blocking task — nothing in either app's PJSIP work can be end-to-end tested until it exists — and build it by extending the *existing* `cont-init.d/10-asterisk-init.sh` self-signed-cert-free pattern (it currently only writes `pjsip_local.conf`'s `externip`/`local_net` block) with a new self-signed certificate generation step and a `[transport-tls]` stanza, plus a new `transport`/`media_encryption` field pair on the `Extension` model mirroring the pattern the `Trunk` model already uses.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| SIP transient registration (CALL-05) | App (PJSUA2 `Account`) | PBX (Asterisk AOR/auth config) | App owns register/unregister lifecycle timing (tied to CallKit/Telecom callbacks); PBX just needs a matching AOR/auth pair to accept it |
| Codec negotiation (Opus/G.722/G.711) (CALL-01) | App (PJSUA2 `Endpoint.codecSetPriority`) | PBX (Asterisk endpoint `allow=` list) | Both sides must agree on the offered/accepted codec set — a mismatch silently drops to the lowest common codec or fails entirely |
| SRTP/TLS transport setup | PBX (Asterisk `pjsip.conf` transport + endpoint `media_encryption`) | App (PJSUA2 `TransportConfig`/`TlsConfig`) | The transport and cert must exist on the PBX before the app can even attempt a TLS REGISTER; app-side config is just "point at it, trust the cert" |
| Audio routing (mic/speaker/Bluetooth) (CALL-01) | OS Call framework (Telecom `CallEndpoint` on Android, `AVAudioSession` on iOS) | App (PJSUA2 `AudDevManager`, reactively) | Both platforms explicitly document that the OS call framework — not the app, not PJSIP directly — owns audio-route selection during an active call; PJSIP's own audio device layer must yield to it |
| DTMF sending (CALL-02) | App (PJSUA2 `Call.sendDtmf`) | — | Pure signaling operation, no OS or PBX-side code needed beyond Asterisk already accepting RFC 4733 (default) |
| Outgoing call (CALL-03) | App (PJSUA2 `Call` / `makeCall`, dialpad UI) | — | Client-initiated, no PBX-side change needed beyond the extension already existing |
| Hold + blind transfer (CALL-04) | App (PJSUA2 `Call.setHold` / `Call.xfer`) | PBX (Asterisk must accept re-INVITE hold and REFER) | Asterisk's default `chan_pjsip` behavior already supports both; no dialplan change expected, but must be verified live |
| Mid-call network-switch resilience (CALL-01 stability bar, D-09) | App (PJSUA2 `Endpoint.handleIpChange` + platform network-change callbacks) | — | Entirely a client-side reconnect/re-register/ICE-restart concern; PBX is a passive party once media renegotiates |
| Test-extension provisioning (D-04/D-06) | PBX/Backend (`~/projects/Ha-Phone` FastAPI: `models.py`, `extensions.py`, `pjsip_extensions.conf.j2`, `cont-init.d`) | — | Cross-repo prerequisite; nothing in this list works without it existing first |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| PJSIP / PJSUA2 | **2.17** (GA 2026-04-22) — corrects STACK.md's "2.16 stable/2.17-dev" [VERIFIED: GitHub Releases API, `pjsip/pjproject` tag `2.17`, `published_at: 2026-04-22T07:15:36Z`] | SIP signaling, SDP, RTP/SRTP, ICE, codec negotiation | Current stable; release notes list deadlock fixes (#4734/#4893/#4832/#4806/#4773/#4764/#4740/#4748/#4738/#4910) directly relevant to a mobile app holding long-lived native calls, and CMake build improvements. One breaking C++ change to account for: `Call::acc` is now `Account*` (was `Account&`) [VERIFIED: GitHub release body for tag 2.17]. |
| SWIG | 4.x (whatever `pjsip-apps/src/swig` targets for the current release — **not installed in this sandbox**, see Environment Availability) | Generates the Java/Kotlin (Android) and can assist the Obj-C++ (iOS uses a hand-written wrapper, not SWIG, per official iOS build docs) bindings from the PJSUA2 C++ headers | Required by the official Android build path (`cd pjsip-apps/src/swig && make` before Gradle module assembly) [CITED: docs.pjsip.org Android build_instructions.html] |
| libopus | dev headers (`libopus-dev` on Debian/Ubuntu) — **only the runtime lib (`libopus0`) is installed in this sandbox, dev headers are missing** | Opus codec implementation PJSIP links against | Opus is not bundled/compiled-in by default; must `#define PJMEDIA_HAS_OPUS_CODEC 1` in `config_site.h` and pass `--with-opus=<dir>` to configure, or the Android/iOS build will silently omit Opus and CALL-01's Opus requirement will fail at negotiation time, not at build time [CITED: docs.pjsip.org Opus Codec Family group docs] |

### Supporting Libraries — iOS

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Objective-C++ bridge (`.mm` files) | n/a | Wraps the C++ PJSUA2 `Endpoint`/`Account`/`Call` classes for Swift consumption | Required — PJSUA2 is a C++ API, Swift cannot call C++ directly; official sample lives at `pjsip-apps/src/pjsua2/ios-swift-pjsua2` in the pjproject source tree [CITED: docs.pjsip.org iOS build_instructions.html] |
| `AVAudioSession` (`.playAndRecord`, `.voiceChat`) | iOS SDK | Speaker/earpiece/Bluetooth output routing during the call | Configure **only** inside `CXProviderDelegate.provider(_:didActivate:)` / `didDeactivate:` — PJSIP's own sound-device wrapper deliberately does not touch the audio session to avoid fighting CallKit for ownership [CITED: PJSIP iOS push-notifications guide + Apple CallKit docs] |
| `AVRoutePickerView` | iOS SDK | User-facing Bluetooth/speaker output picker during a call | Preferred over a custom menu — keeps in sync with Control Center automatically [VERIFIED: Apple Developer Forums, cross-checked against multiple threads] |

### Supporting Libraries — Android

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `androidx.core:core-telecom` | **1.0.0** (already in `android-app/app/build.gradle.kts`, unchanged from Phase 1) | `CallControlScope.currentCallEndpoint` / `availableEndpoints` / `requestEndpointChange()` for audio routing | Do **not** call `AudioManager.setCommunicationDevice()` or `startBluetoothSco()` directly — Google's own docs warn this fights Telecom's routing and causes audio bugs; always go through `requestEndpointChange()` [VERIFIED: developer.android.com Core-Telecom docs] |
| PJSUA2 Android JNI module | matches PJSIP 2.17 | SIP core exposed to Kotlin | Built via `configure-android` + `pjsip-apps/src/swig` + Gradle module wiring generated `.so`/Java sources into `jniLibs` |
| NDK | r26+ per STACK.md, **r27+ recommended by current official docs for Android 15 support** [CITED: docs.pjsip.org Android build_instructions.html] — **not installed in this sandbox** (see Environment Availability) | Cross-compiles PJSIP native code for arm64/x86_64 | Set `ANDROID_NDK_ROOT` before `configure-android` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SDES SRTP keying (`media_encryption=sdes` on Asterisk) | DTLS-SRTP (`media_encryption=dtls`) | SDES puts the SRTP key material inside the SDP itself — safe only when the signaling channel is TLS-encrypted (which D-06 already gives us), so SDES is fine here. DTLS-SRTP is WebRTC-aligned and doesn't need TLS signaling for key safety, but Asterisk's chan_pjsip DTLS-SRTP path is primarily documented/tested for WebRTC endpoints, not classic SIP TLS clients — SDES is the lower-friction, better-precedented choice for a PJSUA2-to-Asterisk-over-TLS call [CITED: docs.asterisk.org Secure Calling Tutorial]. |
| PJSUA2's own `AudDevManager` for output routing | Platform call-framework audio routing (Telecom `CallEndpoint`, CallKit+`AVAudioSession`) | Never use PJSUA2's audio device selection as the primary routing mechanism during an active platform-reported call — both OS vendors explicitly reserve that role for their own call framework; use `AudDevManager.setNoDev()`/`setPlaybackDev()` only for interruption recovery (e.g., a transient audio-session loss), not for user-facing speaker/Bluetooth toggling. |

**Installation (illustrative — exact package names/paths depend on the CI runner image):**
```bash
# Ubuntu/Debian build host (Android build happens in this sandbox per D-02)
sudo apt-get install libopus-dev swig      # NOT currently present — see Environment Availability
# Android NDK: install via sdkmanager, NOT currently present
sdkmanager --install "ndk;27.0.12077973"
export ANDROID_NDK_ROOT=$HOME/android-sdk/ndk/27.0.12077973

# PJSIP source build (both platforms start here)
git clone --branch 2.17 --depth 1 https://github.com/pjsip/pjproject.git
```

**Version verification:**
```bash
curl -s https://api.github.com/repos/pjsip/pjproject/releases/latest | grep tag_name
# → "tag_name": "2.17"  (verified live 2026-08-04)
```

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│  Test dialer / dialpad UI (reused 3x: dial / DTMF / transfer target) │
└───────────────────────────────┬───────────────────────────────────────┘
                                 │ user action
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│  OS Call Framework layer  (owns call lifecycle + audio routing)      │
│  iOS: CXProvider / CXCallController / AVAudioSession                 │
│  Android: CallsManager / CallControlScope / CallEndpoint             │
└───────┬───────────────────────────────────────────────────┬─────────┘
        │ didActivate/didDeactivate                          │ onSetActive/onSetInactive
        │ (audio session ownership)                           │ (CallControlScope callbacks)
        ▼                                                     ▼
┌─────────────────────────────────────────────────────────────────────┐
│  PJSUA2 SIP/Media Core (per-platform, same C++ core, different glue) │
│  Endpoint → Account (transient register/unregister) → Call           │
│  - makeCall() / answer() / hangup() / setHold() / xfer() / sendDtmf() │
│  - codecSetPriority(opus/48000, g722/16000, pcma/8000, pcmu/8000)     │
│  - handleIpChange() on network-change callback → ICE restart path    │
└───────────────────────────────┬───────────────────────────────────────┘
                                 │ SIP/TLS REGISTER + INVITE, SRTP media
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│  HA-Phone PBX (Asterisk 22, chan_pjsip only — chan_sip removed)       │
│  [transport-tls] (NEW — does not exist yet) ── self-signed cert       │
│  Dedicated test extension (NEW): media_encryption=sdes, allow=        │
│  opus,g722,alaw,ulaw                                                  │
└─────────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure

```
ios-app/HAPhoneTestApp/
├── CallProvider.swift          # EXISTS (Phase 1) — CXProvider/CXProviderDelegate
├── PushHandler.swift           # EXISTS (Phase 1) — unchanged
├── Sip/                        # NEW
│   ├── PjsuaBridge.mm/.h       # Obj-C++ wrapper around PJSUA2 Endpoint/Account/Call
│   ├── SipCallController.swift # Swift-facing API: register(), makeCall(), hold(), xfer(), sendDtmf()
│   └── AudioSessionCoordinator.swift  # Owns AVAudioSession config inside didActivate/didDeactivate
└── DialpadView.swift           # NEW — reused for dial / DTMF / transfer (D-12/D-13/D-14)

android-app/app/src/main/java/de/haphone/app/test/
├── CallRegistration.kt         # EXISTS (Phase 1) — extend onRegistered to attach SIP media
├── sip/                        # NEW
│   ├── PjsuaEndpointHolder.kt  # Owns Endpoint/Account lifecycle, tied to app process lifetime
│   └── SipCallController.kt    # register(), makeCall(), hold(), xfer(), sendDtmf()
└── DialpadComposable.kt        # NEW — reused for dial / DTMF / transfer

~/projects/Ha-Phone/ha-phone/backend/           (cross-repo, D-06 prerequisite)
├── models.py                  # ADD: Extension.transport, Extension.media_encryption fields
├── routers/extensions.py      # ADD: pass new fields through create/update
├── conf_templates/
│   └── pjsip_extensions.conf.j2  # ADD: conditional media_encryption= line per extension
└── rootfs/etc/cont-init.d/10-asterisk-init.sh  # EXTEND: generate self-signed cert +
                                                 # write [transport-tls] into pjsip_local.conf
```

### Pattern 1: Report-First, Register-After (carried over from Phase 1, now load-bearing for media)

**What:** The call is already reported to CallKit/Telecom (Phase 1's job) before any SIP signaling starts. Phase 2's SIP registration and INVITE/answer only begin inside the `onRegistered`/`didActivate` callbacks Phase 1 already wired.
**When to use:** Always — this is the seam Phase 2 plugs into, not a new decision.
**Example:**
```kotlin
// Source: android-app CallRegistration.kt (Phase 1, existing) — Phase 2 extends onRegistered
callRegistration.reportIncomingCall(callId) {
    // `this` is CallControlScope — Phase 2 adds: sipCallController.answer(callId)
    // disconnect() remains available if SIP negotiation fails (existing CR-01 fix)
}
```

### Pattern 2: OS Owns Audio Routing, PJSIP Reacts

**What:** Speaker/earpiece/Bluetooth selection happens through the platform call framework (`CallEndpoint`/`AVAudioSession`), never directly through PJSUA2's `AudDevManager` for user-facing routing.
**When to use:** Always for CALL-01's routing requirement.
**Example:**
```kotlin
// Source: developer.android.com Core-Telecom docs (CITED)
callControlScope.availableEndpoints.collect { endpoints -> /* update UI */ }
callControlScope.requestEndpointChange(selectedEndpoint) // NOT AudioManager.setCommunicationDevice()
```
```swift
// Source: Apple CallKit + AVAudioSession docs (VERIFIED, cross-checked forum threads)
func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    try? audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
    // Speaker toggle: audioSession.overrideOutputAudioPort(.speaker) — transient,
    // reverts on next route change/interruption, unlike .defaultToSpeaker category option
}
```

### Pattern 3: ICE Restart Driven by Platform Network Callbacks, Not PJSIP Polling

**What:** PJSIP does not detect network changes on its own [CITED: docs.pjsip.org ip_change.html]. The app observes `NWPathMonitor` (iOS) / `ConnectivityManager.NetworkCallback` (Android) and calls `Endpoint.handleIpChange()` only after the new network has a usable IP — not on old-interface teardown.
**When to use:** D-09's in-scope mid-call network-switch requirement.
**Example:**
```cpp
// Source: docs.pjsip.org ip_change.html (CITED)
IpChangeParam param;
param.restartListener = true;
param.shutdownTransport = true;
// AccountConfig tuning for faster/cleaner mobile handoff:
// acc_cfg.ipChangeConfig.reinvUseUpdate = true;      // prefer UPDATE over re-INVITE
// acc_cfg.regConfig.disableRegOnModify = true;       // don't re-REGISTER on a dead transport
endpoint.handleIpChange(param);
```
**Caveat:** Official docs explicitly do not detail ICE-restart-specific mechanics beyond transport/registration refresh — treat "does the media path (SRTP/ICE) actually recover, not just the SIP dialog" as something to verify empirically against the real Asterisk box, not assume from docs alone (see Open Questions).

### Anti-Patterns to Avoid

- **Setting `transport=transport-tls` explicitly on the Asterisk endpoint config:** [CITED: docs.asterisk.org Secure Calling Tutorial] — this is documented to cause connection issues with some pjproject versions; let Asterisk auto-select the transport the REGISTER arrived on instead. The existing `pjsip_extensions.conf.j2` template already has no `transport=` line for any endpoint — preserve that, don't add one when adding the TLS test extension.
- **Configuring `AVAudioSession` outside CallKit's `didActivate`/`didDeactivate`:** causes audio session ownership conflicts (STACK.md already flags this; reconfirmed by this research).
- **Calling `AudioManager.setCommunicationDevice()`/`startBluetoothSco()` directly on Android while a Telecom call is active:** explicitly warned against by Google's own Core-Telecom docs.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SRTP/DTMF/ICE/codec negotiation | Custom RTP stack or hand-rolled RFC 2833 packetizer | PJSUA2's built-in `Call.sendDtmf`/media engine | This is exactly what PJSIP already ships and what STACK.md already locked in; re-deriving any of it duplicates a decade of interop edge-case fixes |
| Speaker/Bluetooth audio routing UI | Custom audio-route picker | `AVRoutePickerView` (iOS) / Telecom `CallEndpoint` list (Android) | Both are the platform-blessed, OS-synced mechanisms; a custom picker desyncs from Control Center / system Bluetooth state |
| Self-signed TLS cert generation for the Asterisk test transport | A new bespoke cert tool/dependency | Plain `openssl req -x509 ...` invoked from `cont-init.d`, mirroring the existing idempotent generation pattern already used there for the AMI secret and session secret | Matches an established, reviewed pattern in the same file already; no new dependency needed |
| Per-extension transport/encryption modeling | A new bespoke config table | A `transport`/`media_encryption` field pair on `Extension`, mirroring the `transport: str = "udp" # udp\|tcp\|tls` field that already exists on `Trunk` in `models.py` | Same repo already solved this exact modeling problem for trunks; don't invent a second pattern |

**Key insight:** Every piece of this phase that looks like "we need custom code" either already has a first-party PJSUA2 API (client side) or an already-established sibling pattern in the same codebase (`Trunk.transport`, `cont-init.d` secret generation) — the risk in this phase is wiring/glue code and cross-repo sequencing, not algorithmic novelty.

## Common Pitfalls

### Pitfall 1: Building against PJSIP 2.16 per STACK.md's now-stale version note

**What goes wrong:** STACK.md (researched 2026-07-31) says "2.16 stable (2.17 is dev/trunk as of April 2026)." As of this research date (2026-08-04), PJSIP 2.17 has been the GA release since 2026-04-22 [VERIFIED: GitHub Releases API]. Building against 2.16 means missing the deadlock fixes and async-auth improvements in 2.17, and the plan/tasks may reference version-specific paths that assume 2.16.
**Why it happens:** STACK.md was accurate at the time it was written; the release happened between then and now.
**How to avoid:** Pin the build to tag `2.17`, and update any task text that says "2.16" to "2.17." Account for the one breaking PJSUA2 change: `Call::acc` is `Account*` now, not `Account&` — any C++/Obj-C++ glue code written from older sample code (which will show `.acc.` member access) needs `->`.
**Warning signs:** Compile errors on `call.getInfo().acc.` or similar dot-access on `acc`; build scripts hardcoding a `2.16` tag/branch name.

### Pitfall 2: Assuming `sip show registry` works to verify D-05/D-10's transient-registration behavior

**What goes wrong:** CONTEXT.md's D-10 names `sip show registry` as the Asterisk CLI verification command. This is a legacy `chan_sip` command. The HA-Phone box's own `pjsip.conf` states in its header comment: "legacy SIP channel driver was removed in Asterisk 21" [VERIFIED: `~/projects/Ha-Phone/ha-phone/rootfs/etc/asterisk/pjsip.conf` line 3] — so this command does not exist and the verification step as literally written will fail with "No such command."
**Why it happens:** `sip show registry` is a very commonly-cited legacy Asterisk command in older tutorials/muscle memory; the codebase's own PJSIP-only status wasn't cross-checked against the command name when D-10 was decided.
**How to avoid:** Use `pjsip show contacts`, `pjsip show aor <extension-number>`, or `pjsip show endpoint <extension-number>` instead — any of these shows whether a contact/registration currently exists for the test extension, which is what D-10 actually needs.
**Warning signs:** `asterisk -rx "sip show registry"` returning "No such command."

### Pitfall 3: Opus silently missing from the build

**What goes wrong:** PJSIP does not include Opus by default; without `PJMEDIA_HAS_OPUS_CODEC 1` in `config_site.h` and `--with-opus=<dir>` at configure time (plus the `libopus` dev headers actually present on the build machine), the resulting binary builds successfully but Opus never appears in the codec list — CALL-01's "Opus verified for real" (D-07) requirement then fails at the SDP-negotiation stage, not at build time, making it a late, confusing discovery.
**Why it happens:** The build succeeds either way; there's no build-time error for a codec quietly not being compiled in.
**How to avoid:** After each PJSIP build (iOS and Android), explicitly assert the codec list PJSUA2 reports includes `opus/48000` before doing anything else — treat this as a build-verification gate, not something to discover during the first real test call. This sandbox currently has only `libopus0` (runtime) installed, not `libopus-dev` — installing the dev package is a required first step for the Android build track (see Environment Availability).
**Warning signs:** SDP offers from the app never list Opus; Asterisk logs show negotiation falling straight to ulaw/alaw.

### Pitfall 4: Adding `transport=transport-tls` to the new test extension's endpoint block

**What goes wrong:** Following the natural instinct to be explicit ("this extension uses TLS, so set `transport=`"), a `transport=transport-tls` line gets added to the endpoint stanza in `pjsip_extensions.conf.j2` for the new test extension. Asterisk's own secure-calling documentation explicitly warns this can cause connection issues with certain pjproject versions [CITED: docs.asterisk.org Secure Calling Tutorial] — and it's also an unprecedented pattern in this specific codebase (the existing template has zero `transport=` lines for any current UDP extension either).
**Why it happens:** Looks like the "obviously correct, explicit" thing to do when adding a new transport type alongside an existing one.
**How to avoid:** Do not set `transport=` on the endpoint. Only the `[transport-tls]` global stanza needs to exist; Asterisk selects the transport based on which one the incoming REGISTER/INVITE actually arrived on.
**Warning signs:** REGISTER succeeds over the wrong transport, or TLS REGISTER attempts get rejected/mismatched against the endpoint.

### Pitfall 5: Trusting a self-signed cert on iOS/Android by disabling TLS verification everywhere, not just for this dev transport

**What goes wrong:** The straightforward fix for "PJSUA2 rejects the self-signed cert" is to set `TlsConfig.verifyServer = false` globally in shared SIP-core init code. If that code path is later reused unmodified for a real, publicly-trusted-cert deployment (e.g. once Phase 5's Tailscale/production transport work begins), verification stays silently disabled.
**Why it happens:** The fastest fix during dev is a global flag flip, and it's easy to forget to scope it.
**How to avoid:** Set `verifyServer=false`/`verifyClient=false` in a config path that is explicitly labeled/scoped as "Phase 2 local-dev-only, self-signed cert" (e.g. a build flag or a clearly named dev config object), not the account's default/shared config path, so it's easy to find and remove later. [VERIFIED: PJSUA2 `TlsConfig` docs — default `verifyServer=false`, so this is an explicit relaxation being deliberately kept, not merely "leaving a default alone."]
**Warning signs:** Any code review finding `verifyServer = false` outside a clearly-dev-scoped block once later phases touch transport.

## Code Examples

### Making an outgoing call (CALL-03)
```cpp
// Source: docs.pjsip.org PJSUA2_CALL group docs (CITED)
CallOpParam prm(true /* useDefaultCallSetting */);
Call *call = new Call(*account);
call->makeCall("sip:50@pbx.local:5061;transport=tls", prm);
```

### Hold / unhold (CALL-04)
```cpp
// Source: docs.pjsip.org PJSUA2_CALL group docs (CITED)
CallOpParam prm;
call->setHold(prm);              // places call on hold
// to release:
prm.opt.flag = PJSUA_CALL_UNHOLD;
call->reinvite(prm);
```

### Blind transfer (CALL-04)
```cpp
// Source: docs.pjsip.org PJSUA2_CALL group docs (CITED)
CallOpParam prm;
call->xfer("sip:60@pbx.local:5061;transport=tls", prm);
// monitor via Call::onCallTransferStatus() callback override
```

### DTMF (CALL-02)
```cpp
// Source: docs.pjsip.org dtmf.html (CITED)
CallSendDtmfParam dtmfParam;
dtmfParam.method = PJSUA_DTMF_METHOD_RFC2833; // Asterisk default; matches CALL-02's stated RFC
dtmfParam.digits = "5";
call->sendDtmf(dtmfParam);
```

### Codec priority (CALL-01)
```cpp
// Source: docs.pjsip.org pjmedia_codec_config group docs (CITED)
endpoint.codecSetPriority("opus/48000", 255);
endpoint.codecSetPriority("g722/16000", 200);
endpoint.codecSetPriority("pcma/8000", 150);
endpoint.codecSetPriority("pcmu/8000", 150);
```

### Asterisk-side: new [transport-tls] stanza (cross-repo, D-06)
```ini
; Illustrative — to be generated by cont-init.d, mirroring the existing
; pjsip_local.conf externip-generation pattern (self-signed cert, dev-only)
[transport-tls]
type       = transport
protocol   = tls
bind       = 0.0.0.0:5061
cert_file  = /data/asterisk/tls/asterisk.crt
priv_key_file = /data/asterisk/tls/asterisk.key
method     = tlsv1_2
```
```ini
; Test extension endpoint addition — media_encryption only, NO transport= line
; (Pitfall 4)
media_encryption = sdes
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| PJSIP 2.16 as "current stable" | PJSIP 2.17 as current stable | 2026-04-22 (GA) | Plan/task text should say 2.17; account for `Call::acc` becoming `Account*` |
| `sip show registry` for registration status (legacy chan_sip) | `pjsip show contacts` / `pjsip show aor` / `pjsip show endpoint` (chan_pjsip only) | Asterisk 21 removed chan_sip (already true on this box, per pjsip.conf's own comment) | D-10's literal verification command needs correcting |

**Deprecated/outdated:**
- Legacy `chan_sip` CLI commands (`sip show registry`, `sip show peers`, etc.) — not available at all on this Asterisk 22 install.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Asterisk's default chan_pjsip DTLS-SRTP support is primarily tuned for WebRTC endpoints rather than classic SIP-over-TLS clients, making SDES the lower-friction choice here | Standard Stack — Alternatives Considered | If wrong, DTLS-SRTP might actually interop fine with PJSUA2 over TLS and would avoid SDES's "keys travel in the SDP" caveat — worth a quick empirical check once the TLS transport exists, since it only changes one endpoint config line (`media_encryption=dtls` vs `sdes`) |
| A2 | ICE restart of the *media* path (not just SIP re-registration) is not explicitly detailed in PJSIP's official `handleIpChange` docs, so full mid-call audio recovery on network switch needs empirical verification rather than doc-level confidence | Architecture Patterns — Pattern 3 | If PJSIP's ICE restart on network change doesn't fully recover audio in both directions, D-09's "mid-call network-switch is in-scope" acceptance bar may need a fallback design (e.g., forced call-restart) that isn't currently planned |
| A3 | The exact SWIG version required for PJSIP 2.17's Android Java-binding generation step isn't pinned in the docs fetched during this research | Standard Stack | If the sandbox's eventual SWIG install is too old/new for 2.17's SWIG interface files, the Android binding-generation step may fail or produce subtly wrong bindings — verify SWIG version compatibility during the actual build task, not just install "any SWIG" |

**If this table is empty:** N/A — see entries above.

## Open Questions

1. **Does Asterisk 22's default chan_pjsip hold/blind-transfer behavior need any dialplan change, or does it work out of the box against a plain endpoint?**
   - What we know: `chan_pjsip` supports re-INVITE-based hold and REFER-based blind transfer natively for any endpoint by default; no dialplan feature code was found in the existing `extensions_routing.conf.j2`/`extensions.conf` that would block either.
   - What's unclear: whether any existing dialplan context (`from-internal`, `from-internal-restricted`) that the test extension will use has transfer explicitly disabled or redirected somewhere.
   - Recommendation: Verify empirically during the first real test call rather than assuming; if blocked, the fix is a dialplan/context tweak, not an app-side change.

2. **Does DTLS-SRTP interoperate cleanly with PJSUA2 over a classic (non-WebRTC) TLS transport on this Asterisk version, as a potential alternative to SDES?**
   - What we know: Both are documented as supported by Asterisk; SDES is the safer default given D-06 already provides TLS signaling.
   - What's unclear: whether DTLS-SRTP would actually work with zero extra Asterisk config (it's more commonly documented paired with `webrtc=yes` shortcuts).
   - Recommendation: Ship with SDES (A1 above); revisit only if a specific reason to prefer DTLS-SRTP emerges later (e.g., Phase 5's Tailscale/production hardening).

3. **What SWIG version does PJSIP 2.17's Android binding generation actually require, and does it need to be built from source or is a packaged version sufficient?**
   - What we know: the official docs reference `pjsip-apps/src/swig && make` with no version pin found during this research pass.
   - What's unclear: whether Ubuntu 24.04's packaged `swig` (not currently installed) is new/old enough.
   - Recommendation: Install `swig` from the distro package first (`apt-get install swig`); only build SWIG from source if the packaged version demonstrably fails against pjproject's `.i` interface files.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Java (JDK) | Android Gradle build | ✓ | OpenJDK 17.0.19 | — |
| Android SDK / platform-tools | Android build, emulator | ✓ | present at `~/android-sdk` | — |
| Android NDK | PJSIP native cross-compile for Android | ✗ | — | Install via `sdkmanager --install "ndk;27.0.12077973"` before the PJSIP build task starts |
| SWIG | Android Java/Kotlin binding generation | ✗ | — | `apt-get install swig` (see Open Question 3 on version fit) |
| libopus dev headers (`libopus-dev`) | Opus codec compiled into PJSIP | ✗ (only runtime `libopus0` present) | 1.4-1build1 (runtime only) | `apt-get install libopus-dev` |
| OpenSSL (dev + runtime) | PJSIP TLS/SRTP support, cert generation for the test transport | ✓ | 3.0.13 | — |
| Xcode / `xcodebuild` | iOS build + Simulator verification | ✗ (this sandbox is Linux; per D-02, iOS build runs on GitHub Actions macOS runner, not here) | — | Confirmed by design (D-02) — not a gap, just noting it's out-of-sandbox |
| `gh` CLI | Confirming the GitHub Actions iOS CI run actually executes | ✗ (already noted as a Phase 1 carried-forward gap in `01-PHASE-SIGNOFF.md` §2/§6) | — | Same limitation persists into Phase 2 — structural verification only from this sandbox |

**Missing dependencies with no fallback:**
- None — every missing dependency above has a concrete install command available.

**Missing dependencies with fallback:**
- Android NDK, SWIG, `libopus-dev` — all installable via standard package managers before the PJSIP build task; none require anything exotic.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework (iOS) | XCTest (`import XCTest`, confirmed in `PushHandlerTests.swift`/`EnvelopeVerifierTests.swift`/`DiagnosticsLogTests.swift`) |
| Framework (Android) | JUnit 4 (`junit:junit:4.13.2`, confirmed in `EnvelopeVerifierTest.kt`) |
| Config file (iOS) | `ios-app/project.yml` (xcodegen-managed, no CocoaPods/Podfile — consistent with D-01) |
| Config file (Android) | `android-app/app/build.gradle.kts` |
| Quick run command (Android) | `./gradlew testDebugUnitTest` |
| Quick run command (iOS) | `xcodebuild test -scheme HAPhoneTestApp -destination 'platform=iOS Simulator,name=iPhone 16'` (Simulator-only per D-15/D-16 — no device destination) |
| Full suite command | Same commands — this project has no separate "full" vs "quick" suite split yet |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CALL-01 | Codec priority list includes opus/g722/pcma/pcmu after PJSIP init | unit | `./gradlew testDebugUnitTest --tests "*CodecConfigTest*"` | ❌ Wave 0 |
| CALL-01 | Audio routing changes propagate to `CallControlScope.currentCallEndpoint` | unit (fake CallControlScope) | `./gradlew testDebugUnitTest --tests "*AudioRoutingTest*"` | ❌ Wave 0 |
| CALL-01 | Real two-way audio over Opus/G.722/G.711 against the HA-Phone box | manual-only (real device, real PBX — no automated audio-quality harness in this project) | manual test procedure, mirroring `tools/docs/MANUAL_TEST_PROCEDURE.md`'s Phase 1 pattern | manual doc: ❌ Wave 0 |
| CALL-02 | `sendDtmf` invoked with correct digit/method on keypad press | unit | `./gradlew testDebugUnitTest --tests "*DtmfControllerTest*"` | ❌ Wave 0 |
| CALL-03 | Dialpad-entered number produces correct `sip:` URI passed to `makeCall` | unit | `./gradlew testDebugUnitTest --tests "*DialpadTest*"` | ❌ Wave 0 |
| CALL-04 | Hold/unhold and blind-transfer target parsing produce correct `CallOpParam`/URI | unit | `./gradlew testDebugUnitTest --tests "*CallControlTest*"` | ❌ Wave 0 |
| CALL-05 | Registration only exists during call lifetime (register-on-call-start, unregister-on-call-end) | manual-only (per D-10, corrected command: `pjsip show contacts`/`pjsip show aor`) | manual CLI check against Asterisk, not automated | manual doc: ❌ Wave 0 |
| Cross-repo | New `[transport-tls]` stanza + test extension provisioned and Asterisk starts cleanly | integration (HA-Phone repo) | `asterisk -rx "pjsip show transports"` after `cont-init.d` runs | ❌ Wave 0 (new script logic) |

### Sampling Rate
- **Per task commit:** `./gradlew testDebugUnitTest` (Android); `xcodebuild test` (iOS, Simulator)
- **Per wave merge:** Same commands (no separate full-suite split exists yet) plus the manual CLI/real-call checks for CALL-01/CALL-05 at the end of each wave that touches SIP signaling
- **Phase gate:** All automated unit tests green + manual verification of CALL-01 (three codecs, real audio both directions) and CALL-05 (transient registration, corrected CLI command) recorded in `02-PHASE-SIGNOFF.md`, matching Phase 1's evidence-trail style

### Wave 0 Gaps
- [ ] `android-app/app/src/test/java/de/haphone/app/test/sip/CodecConfigTest.kt` — covers CALL-01 codec priority list
- [ ] `android-app/app/src/test/java/de/haphone/app/test/sip/DtmfControllerTest.kt` — covers CALL-02
- [ ] `android-app/app/src/test/java/de/haphone/app/test/sip/DialpadTest.kt` — covers CALL-03 (shared dialpad component, reused for D-13/D-14 too)
- [ ] `android-app/app/src/test/java/de/haphone/app/test/sip/CallControlTest.kt` — covers CALL-04
- [ ] `ios-app/HAPhoneTestAppTests/SipCallControllerTests.swift` — iOS-side equivalents of the above, Simulator-only per D-16
- [ ] A new `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md` (mirroring Phase 1's `tools/docs/MANUAL_TEST_PROCEDURE.md`) for the CALL-01/CALL-05 manual verification steps, including the corrected `pjsip show contacts`/`pjsip show aor`/`pjsip show endpoint` commands (not `sip show registry`)
- [ ] Cross-repo: no test currently exists in `~/projects/Ha-Phone` for the new TLS transport / test-extension provisioning path — needs at least a smoke check that `pjsip.conf` parses and `[transport-tls]` binds

*(Framework install: none needed — XCTest and JUnit 4 are already wired into both projects from Phase 1.)*

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-------------------|
| V2 Authentication | yes | SIP digest auth (existing `auth_type=userpass` pattern already used for all extensions/trunks) — no new mechanism needed for the test extension |
| V3 Session Management | yes (SIP registration as the analog) | Transient registration lifecycle already the whole point of CALL-05; no persistent session token involved |
| V4 Access Control | no (new surface) | Test extension is a normal Asterisk extension within the existing per-extension access model; no new authorization logic introduced |
| V5 Input Validation | yes | Dialpad-entered numbers (dial/DTMF/transfer target) must be validated/sanitized before being embedded in a SIP URI — reuse the existing `_dial_string()`-style stripping pattern already used server-side in `extensions.py` (`re.sub(r"[^0-9+*#]", "", value)`) on the client side too, so a malformed dialpad string can't inject SIP header/URI syntax |
| V6 Cryptography | yes | TLS transport (new) + SRTP (new) for the test extension — use Asterisk's own `cert_file`/`priv_key_file` TLS handling and PJSUA2's built-in SRTP, never hand-rolled crypto; self-signed cert is acceptable **only** because D-05 scopes this to local-network-only dev testing, not for any later production transport |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|----------------------|
| SIP URI/header injection via unsanitized dialpad input (e.g., a transfer target containing SIP syntax) | Tampering | Client-side digit-only sanitization mirroring the existing server-side `_dial_string()` pattern before constructing any `sip:` URI passed to `makeCall`/`xfer`/`sendDtmf` |
| Leaving `verifyServer=false` (self-signed cert acceptance) in a code path that later gets reused for a real deployment | Spoofing | Scope the relaxed-verification config to an explicitly-dev-labeled config path (Pitfall 5); revisit before any Phase 5 production-transport work |
| SDES SRTP key material exposed if TLS signaling is ever accidentally downgraded/misconfigured for this transport | Information Disclosure | `srtpSecureSignaling` should be set to require TLS (value `1`) on the account config so SDES keys are never sent over an unencrypted channel even by misconfiguration |

## Sources

### Primary (HIGH confidence)
- https://docs.pjsip.org/en/latest/api/generated/pjsip/group/group__PJSUA2__CALL.html — Call class methods (answer/hangup/setHold/reinvite/xfer/sendDtmf) [CITED]
- https://docs.pjsip.org/en/latest/specific-guides/sip/dtmf.html — DTMF methods, CallSendDtmfParam, RFC 4733 vs SIP INFO tradeoffs [CITED]
- https://docs.pjsip.org/en/latest/specific-guides/network_nat/ip_change.html — handleIpChange, IpChangeParam, platform-side detection responsibility [CITED]
- https://docs.pjsip.org/en/latest/specific-guides/security/srtp.html — SDES vs DTLS-SRTP, srtpUse/srtpSecureSignaling config [CITED]
- https://docs.pjsip.org/en/latest/get-started/android/build_instructions.html — NDK/SWIG/gradle build steps [CITED]
- https://docs.pjsip.org/en/latest/get-started/ios/build_instructions.html — configure-iphone, xcframework, Obj-C++ bridging [CITED]
- https://docs.pjsip.org/en/latest/api/generated/pjmedia/group/group__PJMED__OPUS.html and pjmedia-codec docs — Opus enablement requirements [CITED]
- https://api.github.com/repos/pjsip/pjproject/releases — 2.17 GA date and release notes, incl. `Call::acc` breaking change [VERIFIED live 2026-08-04]
- https://docs.asterisk.org/Deployment/Secure-Calling/Secure-Calling-Tutorial/ — transport-tls stanza fields, `media_encryption=sdes`, "don't set endpoint transport=" warning [CITED]
- `~/projects/Ha-Phone/ha-phone/rootfs/etc/asterisk/pjsip.conf`, `pjsip_local.conf.j2`, `pjsip_extensions.conf.j2`, `backend/models.py`, `backend/routers/extensions.py`, `rootfs/etc/cont-init.d/10-asterisk-init.sh` — direct codebase inspection confirming no TLS transport, no per-extension transport field, and the existing cert/secret-generation pattern to extend [VERIFIED: direct file read]
- Direct sandbox environment probes (`java -version`, `swig -version`, `pkg-config`, `dpkg -l`, NDK path search) [VERIFIED: direct command execution]

### Secondary (MEDIUM confidence)
- https://developer.android.com/develop/connectivity/telecom/voip-app/telecom — CallControlScope audio routing, "don't call AudioManager directly" warning [VERIFIED via WebSearch, consistent with official domain]
- Apple Developer Forums threads on `AVAudioSession.overrideOutputAudioPort` vs `.defaultToSpeaker` category option, `AVRoutePickerView` recommendation [MEDIUM — forum-sourced but consistent across multiple independent threads, same pattern STACK.md/PITFALLS.md already treat as MEDIUM elsewhere in this project]

### Tertiary (LOW confidence)
- None flagged — all findings in this research were either verified live or cited to an official doc; no pure-single-source WebSearch-only claims remain unqualified.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — PJSIP version verified live via GitHub API; build requirements cited from current official docs
- Architecture: HIGH — PJSUA2 API surface and platform audio-routing ownership model verified against official docs on both platforms
- Pitfalls: HIGH — the two most consequential corrections (PJSIP version, Asterisk CLI command) are both independently verified against a live API and the actual codebase, not inferred

**Research date:** 2026-08-04
**Valid until:** 2026-09-03 (30 days — PJSIP/Asterisk are stable-cadence projects, but re-check the GitHub Releases API before starting the build task in case another point release lands)
