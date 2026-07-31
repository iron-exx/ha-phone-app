# Feature Research

**Domain:** VoIP softphone / PBX companion mobile app (self-hosted Asterisk PBX, "HA-Phone")
**Researched:** 2026-07-31
**Confidence:** MEDIUM (WebSearch-verified across multiple vendors; no Context7 entries exist for these consumer VoIP apps — this is a product/UX domain, not a library API)

## Feature Landscape

### Table Stakes (Users Expect These)

Features every credible softphone / PBX companion app has. Missing these makes the app feel broken relative to Linphone, Zoiper, 3CX, or a regular phone.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Answer / reject / hangup | Baseline telephony | LOW | Must map to native CallKit (iOS) / ConnectionService (Android) actions, not custom UI |
| Mute / unmute | Baseline telephony | LOW | AVAudioSession (iOS) / AudioManager (Android) |
| Speaker toggle | Used constantly for hands-free | LOW | Route via CallKit `CXSetMutedCallAction`/audio session category |
| Bluetooth headset routing | Common in cars, offices | MEDIUM | OS handles most of it if CallKit/Telecom integration is correct; still needs explicit route-picker UI |
| DTMF (in-call keypad) | IVR/voicemail/PBX menus require it | LOW-MEDIUM | RFC 2833/4733 out-of-band DTMF via PJSIP; UI keypad during call |
| Hold / resume | Reception-desk-style transfers, "please hold" | MEDIUM | Needs SIP re-INVITE handling; server (Asterisk) must support hold music/state |
| Call transfer (blind + attended) | Small-office receptionist use case is common for PBX users | MEDIUM-HIGH | Attended transfer (consult then transfer) is notably more complex than blind transfer; requires multi-call SIP session juggling |
| Call history (incoming/outgoing/missed) | Expected on any phone app | LOW | Store locally; optionally sync from PBX CDR |
| Caller ID display with PBX-side name resolution | Users expect the PBX directory name, not just a raw number | LOW-MEDIUM | Requires HA-Phone to expose a phonebook/CNAM lookup endpoint |
| Native system call UI integration (CallKit / Telecom framework) | Users expect calls to look and feel like normal phone calls, integrate with Do Not Disturb, other-call-in-progress, car displays | HIGH | This *is* the product's core value proposition per PROJECT.md — not optional |
| Reliable ringing when app is closed or device locked | The #1 complaint category for every softphone reviewed (3CX, Zoiper, Linphone) | HIGH | See dedicated section below — this is the single hardest table-stakes item |
| Outgoing calls | Basic reciprocity of a phone app | LOW-MEDIUM | Standard PJSIP INVITE flow |
| Contacts integration (device contacts lookup for caller ID / dialing) | Users expect to tap a contact and call, and expect incoming numbers matched against contacts | LOW-MEDIUM | Read-only access to system contacts; no write-back needed |
| Network-change resilience (Wi-Fi ↔ cellular handover) | Mobile users switch networks mid-call or between calls constantly | MEDIUM-HIGH | PJSIP transport re-registration; must not require the user to notice/reconnect manually |
| Push/registration diagnostics screen | Users of self-hosted systems (no vendor support line) need to self-diagnose | LOW-MEDIUM | Already scoped in PROJECT.md as "Diagnose-Statusseite" — correctly identified as table stakes for this audience, not a differentiator |

### Differentiators (Competitive Advantage)

Features that set HA-Phone's app apart from generic softphones (Zoiper, Linphone) and even from commercial PBX apps (3CX, Yeastar Linkus).

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Zero-touch QR provisioning with no SIP credentials ever shown to the user | Removes the single biggest onboarding failure mode of generic softphones (users mistyping server/port/password) | MEDIUM | 3CX and Yeastar Linkus both already do this — it's becoming table stakes among *commercial* PBX apps, but is a strong differentiator vs. the DIY/self-hosted-PBX + Linphone/Zoiper status quo this project explicitly targets (see PROJECT.md: "Mobile Nutzung aktuell nur via Linphone + Tailscale-VPN") |
| Door-station video preview before answering (Akuvox integration) | Directly matches dedicated intercom apps (Akuvox SmartPlus, DoorBird, 2N) — no generic softphone (Zoiper, Linphone, 3CX, Linkus) does this out of the box | HIGH | This is the single feature most likely to make users choose this app over Linphone+VPN; requires PBX-side call-type detection and a short-lived signed preview-stream URL (see Architecture notes below) |
| Door-opener action with biometric confirmation, directly from the incoming-call/preview screen | Turns the phone into a real intercom handset, not just a phone | MEDIUM | DTMF/SIP-INFO/HTTP-webhook to Home Assistant; Face ID/Touch ID/biometric gate before opening is a differentiator vs. most PBX apps, which either don't support door relays at all or do so without a confirmation step |
| No permanent SIP registration / no VPN required for reachability | Directly attacks the stated status-quo pain (Tailscale VPN + always-on Linphone) | HIGH | Push-then-register pattern; battery and "always reachable without a tunnel" story is the architectural thesis of the whole project |
| Multi-device-per-extension with race-to-answer + push cancel-out | Handles the "whole household/family has a phone" case cleanly, more elegantly than most consumer softphones which either don't support multi-registration well or don't actively cancel other devices | MEDIUM-HIGH | Needs authoritative call-state tracking in HA-Phone backend; the "loser" devices need a fast cancel push, not just a timeout |
| Self-hosted/privacy-first posture: no cloud SIP account, no vendor telemetry, own push relay | Directly appeals to the Home Assistant / self-hosting audience already running HA-Phone | LOW-MEDIUM (mostly a policy/architecture stance, not a feature per se) | This is a positioning differentiator more than a checkbox feature — should be reflected in privacy copy, not just code |
| Central device management view mirroring what commercial PBX admin consoles offer (3CX, Yeastar), but for a self-hosted single-tenant box | Small-business/home-office admins get "enterprise-grade" device oversight (list, revoke, re-provision, last-seen, push status) without needing a hosted PBX subscription | MEDIUM | PROJECT.md already scopes this fully — correctly treated as differentiator against unmanaged Linphone deployments, not against 3CX/Linkus which already have it |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|------------------|-------------|
| Generic "enter any SIP server" mode | Power users/tinkerers expect softphones to support arbitrary providers | Directly contradicts the project's architecture: reliable push-wake, QR provisioning, and device revocation all depend on the app being tightly coupled to HA-Phone's own backend and push relay. A generic SIP mode reintroduces exactly the "always registered / unreliable wake" problem the project exists to solve, and multiplies QA/testing surface (arbitrary SIP servers behave differently) | Explicitly out of scope per PROJECT.md; if users want a generic softphone, point them at Linphone/Zoiper |
| WebRTC/browser-based calling | Seems simpler ("just open a link") | Cannot deliver reliable background wake, native CallKit/Telecom integration, or equivalent battery behavior — this is a proven dead end already ruled out by ENTWICKLUNGSPLAN.md §9 | Native app with PJSIP + platform push is the only path to the core value proposition |
| Multi-tenant / multi-PBX-account switching in one app install (i.e., "connect to several different HA-Phone boxes and hop between them") | Some users run multiple PBXes (home + business) | Adds real complexity to push registration, credential storage, and the "which box is this call from" UI — while the actual target audience (PROJECT.md) is "small self-hosted installs," not people juggling several PBXes in one app | Support one active provisioned identity per app install; if a user runs two boxes, install-and-reprovision or (later) explicit account-switcher as a deliberate v2+ feature, not default behavior |
| Enterprise call-center features (queues with wallboard, call recording/monitoring, CRM/ticketing integrations, presence federation, hot-desking) | These exist in 3CX/Yeastar/enterprise UC and might seem like "parity" targets | Irrelevant to the stated audience (home office / small business, self-hosted); large complexity for near-zero value to this project's users; also raises consent/privacy issues (recording) the project's privacy-first positioning wants to avoid | Leave to HA-Phone's own PBX-side roadmap if ever needed — not part of the mobile companion app |
| Video calling / SIP video as a general feature (distinct from the door-station preview) | "Every modern app has video calls" | HA-Phone's own PBX roadmap has explicitly deferred WebRTC/video (per PROJECT.md context) — building general SIP video in the app ahead of PBX-side readiness creates a feature nobody can actually use end-to-end, and adds real codec/bandwidth/UI complexity | Defer general video calling; door-station preview is a narrower, PBX-coordinated feature and should NOT be generalized into full peer-to-peer video calling prematurely |
| Full call recording / cloud transcript / AI call summaries | Popular in commercial UC apps as a selling point | Legal/consent complexity (recording laws vary by jurisdiction), plus contradicts explicit privacy stance ("keine Audioaufzeichnung ohne ausdrückliche Funktion" in ENTWICKLUNGSPLAN.md §11) | If ever requested, make it an explicit, off-by-default, clearly-consented feature — not default behavior, and not a v1 feature |
| Screen-based (non-QR) manual SIP credential entry as a fallback "advanced mode" | Feels like a reasonable escape hatch for power users or when QR scanning fails | Reintroduces exactly the manual-entry failure mode and credential-exposure risk the QR flow exists to eliminate; also complicates the security model (per-device credentials, no full credentials in QR, no credentials in logs) | If QR scanning fails, provide a short numeric/backup code entry (still a token, not raw SIP credentials) tied to the same time-limited provisioning flow — not a raw SIP settings form |
| Push notification carrying full call/media payload or long-lived camera/RTSP URLs | Simpler to implement — "just put the info in the push" | Security risk: pushes traverse Apple/Google infrastructure; a push must never itself be able to open a door or grant standing access to a camera stream (explicitly flagged in ENTWICKLUNGSPLAN.md §11 "Ein Push darf allein keinen Anruf übernehmen oder eine Tür öffnen können") | Push carries only Call-ID + minimal metadata + signature; app fetches live details/preview from the PBX over an authenticated, short-lived channel after wake |

## Feature Dependencies

```
[Reliable push wake (iOS PushKit / Android FCM high-priority)]
    └──requires──> [Push relay service with APNs/FCM credentials]
                       └──requires──> [Device registration (push token ↔ extension mapping in HA-Phone)]
                                          └──requires──> [QR provisioning (issues per-device identity)]

[Native call UI (CallKit / ConnectionService)]
    └──requires──> [Push wake] (must report call to system within OS time budget after push)
    └──enhances──> [Answer/reject/hangup, mute, speaker, hold] (these become "free" once native call UI is wired correctly)

[Post-answer SIP session establishment]
    └──requires──> [Native call UI accepted] AND [Push wake delivered Call-ID]
    └──requires──> [PJSIP/PJSUA2 core integration]

[Door-station video preview]
    └──requires──> [PBX-side call-type detection (recognize Akuvox extension/number)]
    └──requires──> [Short-lived signed preview URL, separate channel from push payload]
    └──enhances──> [Door-opener action] (preview screen is the natural place to put the door-open button)

[Door-opener action]
    └──requires──> [Door-station video preview OR at minimum an active/incoming door call]
    └──requires──> [Biometric confirmation gate] (security requirement, not optional for this feature)

[Multi-device-per-extension race-to-answer]
    └──requires──> [Device management (list, revoke, per-device credentials)]
    └──requires──> [Server-side authoritative call state] (to prevent double-answer and to cancel losing devices)

[Device management dashboard: revoke, re-provision, last-seen]
    └──requires──> [QR provisioning] (revocation is meaningless without unique per-device identities to revoke)

[Call transfer (attended)] ──requires──> [Hold] (attended transfer = hold + consult call + merge/transfer)

[Generic multi-provider SIP mode] ──conflicts──> [Reliable push wake, QR provisioning, device revocation]
[General SIP video calling] ──conflicts──> [HA-Phone's own PBX roadmap sequencing] (video deferred PBX-side)
```

### Dependency Notes

- **Native call UI requires push wake:** On iOS in particular, a VoIP push *must* result in a CallKit `reportNewIncomingCall` almost immediately, or iOS can penalize/throttle the app's future ability to receive VoIP pushes. This makes push wake and native call UI a single coupled unit for testing purposes, not two independent features.
- **Door-opener requires door-station preview (or an active door call) plus biometric gate:** ENTWICKLUNGSPLAN.md is explicit that a push alone must never be sufficient to open a door — the door-open action must always be gated behind an authenticated, live PBX round-trip and (per spec) an optional-but-recommended biometric confirmation.
- **Multi-device race-to-answer requires authoritative server-side call state:** without this, two devices can both "answer" and the PBX has no clean way to decide which one wins — this must live in HA-Phone's backend, not be negotiated client-side.
- **Device management requires QR provisioning:** revocation, re-provisioning, and "list devices" are meaningless unless every device already has a distinct identity/credential set established during onboarding — this is why QR provisioning must land before/alongside device management in the roadmap (already reflected in ENTWICKLUNGSPLAN.md §16 priority ordering).
- **Generic multi-provider SIP mode conflicts with the reliability story:** this is the most important anti-feature/table-stakes tension to flag for the roadmap — any temptation to add "just let power users type in a SIP server" must be resisted because it breaks the push/QR/revocation model that is this project's actual differentiator.

## MVP Definition

### Launch With (v1)

Matches ENTWICKLUNGSPLAN.md's own "Definition der ersten marktfähigen Version" (§17) and PROJECT.md's Active requirements — validated independently against competitor feature sets during this research.

- [ ] Reliable push-based wake for incoming calls on iOS (PushKit/CallKit) and Android (high-priority FCM/Telecom/full-screen intent) — this is the entire reason the project exists; nothing else matters if this fails
- [ ] Native system call UI (CallKit/Telecom), including on locked device
- [ ] Stable audio calls (Opus/G.722/G.711, mic, speaker, Bluetooth, DTMF)
- [ ] Outgoing calls
- [ ] QR-code-only provisioning (no manual SIP entry ever)
- [ ] Device management in HA-Phone dashboard (list, lock/revoke, delete, re-provision) — needed from day one because self-hosted admins have no vendor support desk to call
- [ ] Multi-device-per-extension with race-to-answer and cancel-push to losers
- [ ] Door-station video preview before answering (Akuvox) — called out repeatedly in PROJECT.md and ENTWICKLUNGSPLAN.md as a core differentiator, not a nice-to-have; should not be deferred past v1 despite higher complexity, because it is central to "why use this instead of Linphone"
- [ ] Door-opener action with optional biometric confirmation
- [ ] Diagnostics/status page (push registration, SIP status, permissions, last test) — essential for a self-supported audience

### Add After Validation (v1.x)

- [ ] Attended call transfer (blind transfer can ship in v1 as lower complexity; attended transfer is a natural v1.x add once hold/basic transfer are proven stable)
- [ ] Call history sync from PBX CDR (local-only call history is sufficient for v1)
- [ ] Favorites / speed dial
- [ ] Snapshot-saving from door preview (explicitly flagged in ENTWICKLUNGSPLAN.md as "sofern administrativ erlaubt" — needs an admin-side permission toggle first)
- [ ] Network-change resilience polish (basic Wi-Fi/cellular handling should work in v1; deeper NAT/TURN edge-case hardening is iterative)

### Future Consideration (v2+)

- [ ] General SIP video calling (deferred — blocked on HA-Phone's own PBX-side video roadmap, per PROJECT.md context)
- [ ] Multi-PBX-account switching within one app install
- [ ] Home Assistant action integration beyond door webhook (e.g., triggering scenes on call events)
- [ ] Additional door-station vendors beyond Akuvox (2N, DoorBird, Fanvil) — Akuvox is the only hardware currently owned/testable per PROJECT.md

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Push-based reliable call wake (iOS + Android) | HIGH | HIGH | P1 |
| Native CallKit/Telecom call UI | HIGH | HIGH | P1 |
| QR-code provisioning | HIGH | MEDIUM | P1 |
| Stable audio call (codecs, mic/speaker/BT, DTMF) | HIGH | MEDIUM | P1 |
| Outgoing calls | HIGH | LOW-MEDIUM | P1 |
| Device management (list/revoke/re-provision) | HIGH | MEDIUM | P1 |
| Multi-device race-to-answer | MEDIUM-HIGH | MEDIUM-HIGH | P1 |
| Door-station video preview (Akuvox) | HIGH (core differentiator) | HIGH | P1 |
| Door-opener with biometric gate | MEDIUM-HIGH | MEDIUM | P1 |
| Diagnostics/status page | MEDIUM (high for self-supported users) | LOW-MEDIUM | P1 |
| Hold / blind transfer | MEDIUM | MEDIUM | P2 |
| Attended transfer | MEDIUM | MEDIUM-HIGH | P2 |
| Call history / favorites / contacts polish | MEDIUM | LOW | P2 |
| Snapshot-saving from door preview | LOW-MEDIUM | LOW | P3 |
| General SIP video calling | LOW (blocked on PBX roadmap) | HIGH | P3 |
| Multi-PBX-account switching | LOW (out of stated audience) | MEDIUM-HIGH | P3 |
| Generic multi-provider SIP mode | N/A | N/A | Anti-feature — do not build |

**Priority key:**
- P1: Must have for launch
- P2: Should have, add when possible
- P3: Nice to have, future consideration

## Deep-Dive: Background Wake Mechanisms Across Competitors

This is the single most safety-critical table-stakes feature and deserves explicit competitor comparison, since it's what the whole project is built to solve.

| Product | Mechanism | User complaints found |
|---------|-----------|------------------------|
| **3CX Mobile App** | Own native app sends true VoIP push (PushKit on iOS) integrated with CallKit; on Android relies on high-priority FCM plus explicit exemption from battery optimization. 3CX's own docs/forum note that when the *same* SIP account is registered via a third-party client (Zoiper, Bria, Abto) instead of the 3CX app, CallKit does *not* launch for the incoming call — confirming that reliable native-call wake is only achieved when push delivery and CallKit reporting are tightly coupled inside a single vendor-controlled app, exactly the architecture HA-Phone's app is pursuing. (MEDIUM confidence — 3CX forum + support docs, not an official spec page) | Users report push failures traced to Android background-data restrictions, battery optimization not disabled, and (since Android 13) the app-level notification runtime permission not being granted — none of these are 3CX-app bugs per se, but rather OS-level configuration users must get right. This is a strong signal that a diagnostics/self-check screen (already in PROJECT.md scope) is essential, not optional. |
| **Zoiper** | Historically relies on a persistent SIP registration / wakelock model for reliability, with push notification support added as an option that depends on the SIP provider's server implementing it (i.e., push is NOT automatic/built-in — the PBX/provider side has to wire it up, similar to what HA-Phone must now build). | Users report missed calls tied to device-specific background restrictions (e.g., Huawei), inconsistent behavior over cellular vs Wi-Fi, and general "keeps saying registering" complaints. Confirms that keep-alive/always-registered approaches are fragile across the Android OEM fragmentation landscape — reinforcing the project's decision to avoid always-on registration. (MEDIUM confidence — community forum reports, consistent across multiple threads) |
| **Linphone / Flexisip** | Reference open-source implementation of the exact pattern HA-Phone is adopting: Flexisip (server) sends a platform push (PushKit/FCM) to wake the device *before* delivering the SIP INVITE, specifically because "mobile operating systems freeze running applications when the phone is idle." Linphone's docs also recommend very long REGISTER expiry (weeks/months) for push-enabled endpoints so the registrar keeps a stable device→push-token mapping without needing constant re-registration traffic. Reported as the most battery-efficient of the major mobile VoIP apps in independent comparisons. (MEDIUM confidence — official Linphone/Flexisip wiki + third-party comparison; the specific benchmark numbers are LOW confidence, single-source) | GitHub issues document historical high battery consumption complaints on Android, generally traced to background service/wakelock behavior in older versions rather than the push design itself. |
| **Yeastar Linkus** | Uses push notifications for call alerts on mobile; separately, QR-code login is a "convenience login" feature (see provisioning section below) rather than the actual call-wake mechanism — the two are related but distinct: QR solves *onboarding*, push solves *reachability*. (MEDIUM confidence — official Yeastar help docs) | No specific reliability complaints surfaced in this pass; not enough independent user-report volume found to assess confidently — flag as a gap. |

**Key takeaway for HA-Phone's app:** every vendor that has *solved* reliable background call delivery (3CX, Linphone/Flexisip) converges on the same pattern already chosen in ENTWICKLUNGSPLAN.md: platform push wakes the device, native call UI (CallKit/Telecom) is invoked immediately, and only *then* does the actual SIP/media session get established — never a persistently-held SIP registration as the delivery mechanism. Every vendor that has NOT fully solved it (Zoiper, when used against providers without native push support) shows exactly the failure modes (missed calls, "registering" hangs, OEM battery-optimization interference) this project is designed to avoid. The recurring, cross-vendor complaint pattern is OS/OEM configuration (battery optimization, notification permissions, background data restrictions) rather than the push architecture itself — which strongly validates PROJECT.md's plan to ship a diagnostics/status page as a P1, table-stakes feature rather than a nice-to-have.

## Deep-Dive: QR-Code / Zero-Touch Provisioning Patterns

| Product | UX flow | Security model | Confidence |
|---------|---------|-----------------|------------|
| **3CX** | Admin opens the extension in the Management Console → General tab → "QR code" button. Employee scans it in the 3CX mobile app, which auto-configures the app. A `.3cxconfig` file (e.g., emailed) is offered as a fallback when QR isn't practical. | The QR/config approach avoids the user ever typing server/port/credentials, but the underlying `.3cxconfig` file itself is a downloadable artifact (can be sent by email) rather than a strictly single-use, time-boxed token in the way ENTWICKLUNGSPLAN.md specifies — 3CX's public docs don't clearly describe a short expiry or single-use enforcement for the QR/config file, unlike the explicit "5-minute, one-time token" design in ENTWICKLUNGSPLAN.md. This is a place where HA-Phone's planned design is *more* secure than the observed 3CX pattern, not less. (MEDIUM confidence — 3CX forum/support docs, not official security whitepaper) | MEDIUM |
| **Yeastar Linkus** | Admin sends a "Linkus Welcome Email" containing a QR code; user installs the app, taps a QR-scan button, and the app logs in automatically. Yeastar's own docs state explicitly: QR code is valid for 24 hours and single-use. Also supports scanning a QR code shown on the desktop/web client to log in a second device (a different, session-transfer use case). | 24-hour single-use token is explicitly documented — closer to (but more generous than) ENTWICKLUNGSPLAN.md's 5-minute target. Notably, Yeastar's QR flow is positioned as *login*, and the credentials it grants access to are Linkus-cloud-mediated rather than raw SIP credentials, which sidesteps some of the "no SIP password in the QR" concerns HA-Phone must solve itself since it has no cloud mediation layer. | MEDIUM (official Yeastar help center docs) |

**Implication for HA-Phone:** Both incumbents validate the overall "admin generates QR in dashboard → user scans in app → done" flow as the industry-standard pattern (this is not a risky or novel UX to build). However, neither incumbent's publicly documented security model is as tight as what ENTWICKLUNGSPLAN.md already specifies (single-use, short 5-minute expiry, no SIP password ever inside the QR payload, per-device credential issuance, revocable, no persistent shared secret). HA-Phone's plan should be treated as the target bar, not weakened to match competitors — the "no SIP credentials in the QR" principle in particular is a genuine security differentiator worth keeping strict, since 3CX's `.3cxconfig`-by-email fallback is a comparatively weaker real-world pattern this project should explicitly avoid replicating.

## Deep-Dive: Door-Intercom / Video-Preview-Before-Answer Patterns

| Product | Pattern | Confidence |
|---------|---------|------------|
| **Akuvox SmartPlus** | On an incoming door call, the app can show a live monitoring/preview stream before the user taps to answer, letting the user decide whether to open the door without ever answering the call itself. A separate "Capture" function lets the user snapshot the live view or a recorded video into local "Capture Logs." | MEDIUM (official Akuvox knowledge base) |
| **DoorBird** | When the doorbell button is pressed, a push notification is sent to *all* registered devices simultaneously, and each shows a live view of the visitor before the user chooses to answer — explicitly decoupling "see who it is" from "accept the call." Live view can show multiple stations at once outside of a call context too (ambient monitoring, not just at ring-time). | MEDIUM (DoorBird's own marketing/FAQ pages; independent review corroborates the "see-before-answer" flow) |
| **2N** (not directly searched this pass) | Not independently verified in this research pass — treat as a gap; 2N's My2N/2N Access Commander apps are known in the industry to offer similar snapshot/live-view-before-answer UX, but this claim is LOW confidence (training-data only, not verified this session) and should be spot-checked if 2N hardware is ever targeted. | LOW |

**Implication for HA-Phone:** The "see live video/snapshot before answering, decoupled from actually accepting the SIP call" pattern is a well-established convention across dedicated intercom vendors (Akuvox, DoorBird) — it is NOT a novel UX to invent, but it is genuinely absent from every general-purpose PBX/softphone app reviewed (3CX, Yeastar Linkus, Zoiper, Linphone all lack this). This confirms the ENTWICKLUNGSPLAN.md design (§7, Modus B) — a short-lived, PBX-brokered preview stream separate from the SIP call itself — is aligned with how dedicated intercom apps already do it, and is the app's clearest differentiator versus every generic softphone. One nuance worth carrying into the architecture research: DoorBird's "push to all registered devices simultaneously, each with independent live view" maps directly onto HA-Phone's own multi-device-per-extension requirement — the preview stream must support concurrent viewers, not just a single client.

## Competitor Feature Analysis

| Feature | 3CX App | Yeastar Linkus | Zoiper / Linphone (generic softphones) | HA-Phone App Approach |
|---------|---------|-----------------|------------------------------------------|-------------------------|
| Reliable background call wake | Native VoIP push + CallKit, tightly integrated in-house | FCM/APNs push integrated with their cloud/on-prem PBX | Push support only if the SIP server/provider implements it (Linphone/Flexisip does; many generic SIP providers don't); otherwise persistent registration with reliability issues | Push-based wake via own relay (APNs/FCM), no persistent registration — matches the *best-in-class* pattern (3CX, Linphone/Flexisip), not the fragile generic-softphone default |
| Zero-touch provisioning | QR code / `.3cxconfig` file from admin console | QR code from welcome email, 24h single-use | None built-in — manual SIP entry is the default and often the only option | QR-only, single-use, short (~5 min) expiry, no SIP password in payload — stricter than both incumbents |
| Door-station video preview before answering | Not supported | Not supported | Not supported | Core differentiator; short-lived signed preview link brokered by PBX, decoupled from SIP call, matching Akuvox/DoorBird UX conventions |
| Multi-device per extension | Supported, but community forum threads show it's a point of admin confusion ("how to manage that") | Supported | Varies by provider/PBX backend, not a softphone-app feature per se | Explicit race-to-answer + active cancel-push to losing devices, backed by authoritative server-side call state — more deterministic than the "somewhat confusing" pattern reported for 3CX |
| Device revoke / management dashboard | Yes, via admin console | Yes, via admin console | No (not a PBX-app concept) | Yes — matches commercial-PBX table stakes, positioned as a differentiator only relative to the DIY Linphone status quo this project's users currently have |
| Self-hosted / no vendor cloud dependency | No — 3CX push always transits 3CX-operated infrastructure | No — Linkus is Yeastar-cloud/on-prem hybrid depending on edition | Yes, if paired with self-hosted PBX (Asterisk/FreePBX), but no integrated push/QR/device-mgmt story | Yes — explicit project goal; own push relay avoids dependency on Nabu Casa or a commercial PBX vendor's push infra |

## Sources

- [Push Notification with Custom VoIP app — 3CX Forums](https://www.3cx.com/community/threads/push-notification-with-custom-voip-app.71418/)
- [Android PUSH Notifications Help Guide — 3CX](https://www.3cx.com/blog/docs/android-troubleshooting-guide/)
- [3CX Android App PUSH Troubleshooting](https://www.3cx.com/docs/android-push-troubleshooting/)
- [How work PUSH notifications for 3CX app — 3CX Forums](https://www.3cx.com/community/threads/how-work-push-notifications-for-3cx-app.129989/)
- [How to Locate the QR Code for Extension Provisioning in 3CX (V20) — Aatrox Communications](https://support.aatroxcommunications.com.au/support/solutions/articles/51000435829-how-to-locate-the-qr-code-for-extension-provisioning-in-the-3cx-management-console-v20-)
- [3CX Mobile App Setup — Voxtelesys](https://voxtelesys.com/tutorial/3cx-mobile-app-setup)
- [Multiple App users and devices connected to a single extension — 3CX Forums](https://www.3cx.com/community/threads/multiple-app-users-and-devices-connected-to-a-single-extension-how-to-manage-that.115968/)
- [Receiving calls in background — Zoiper support](https://www.zoiper.com/en/support/answer/for/windows-phone/106/Receiving_calls_in_background)
- [Huawei Mate 20 Pro & missed calls — Zoiper Community](https://community.zoiper.com/6612/huawei-mate-20-pro-&-missed-calls)
- [Zoiper free on Android missed calls when calling over cellular — Zoiper Community](https://community.zoiper.com/6046/zoiper-free-android-missed-calls-when-calling-over-cellular)
- [Linphone 4.3 for iOS and Android — push notifications](https://www.linphone.org/en/news/linphone-4-3-for-ios-and-android/)
- [Push notifications — Flexisip / Linphone Wiki](https://wiki.linphone.org/xwiki/wiki/public/view/Flexisip/D.%20Specifications/Push%20notifications/)
- [High battery consumption using linphone.org — GitHub Issue #621](https://github.com/BelledonneCommunications/linphone-android/issues/621)
- [Yeastar Linkus Mobile Client Quick Start Guide](https://help.yeastar.com/en/linkus_client/topic/linkus-mobile-client-quick-start-guide.html)
- [Scan QR code to log in — Yeastar Linkus](https://help.yeastar.com/en/linkus_client/topic/scan-qr-code-to-log-in-pc.html)
- [Log in to Linkus with Extension Account Using QR Code — Yeastar](https://help.yeastar.com/en/p-series-linkus-cloud-edition/mobile-client-user-guide/log-in-to-linkus-with-extension-account-using-qr-code.html)
- [Akuvox SmartPlus App User Guide V7.4.2](https://knowledge.akuvox.com/docs/akuvox-smartplus-app-user-guide)
- [DoorBird App for IP Video Intercoms](https://www.doorbird.com/en/app)
- [DoorBird Intercom Review — Swiftlane](https://swiftlane.com/blog/doorbird-intercom-review/)
- [Add a Phone or Device to a PBX User — RingLogix Partner Support Center](https://support.ringlogix.com/portal/en/kb/articles/add-a-phone-or-device-to-a-pbx-user)
- Project internal documents: `/home/roto/projects/ha-phone-app/.planning/PROJECT.md`, `/home/roto/projects/ha-phone-app/ENTWICKLUNGSPLAN.md`

## Gaps / Not Independently Verified This Session

- 2N (My2N / 2N Access Commander) door-station app preview UX — not independently searched/verified this pass; assumed similar to Akuvox/DoorBird based on training data only (LOW confidence).
- Yeastar Linkus background-wake reliability complaints — insufficient independent user-report volume surfaced to assess confidently; flagged as an open gap rather than asserted.
- Exact official 3CX security spec for QR/`.3cxconfig` token expiry/single-use enforcement — not found in an authoritative security whitepaper, only inferred from forum/support docs; should not be treated as a confirmed weakness, just an unconfirmed strength of HA-Phone's stricter design.

---
*Feature research for: VoIP softphone / PBX companion mobile app (HA-Phone)*
*Researched: 2026-07-31*
