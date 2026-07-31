# Project Research Summary

**Project:** HA-Phone App
**Domain:** Native VoIP softphone companion app (iOS + Android) for a self-hosted Asterisk PBX, with a push-relay backend
**Researched:** 2026-07-31
**Confidence:** MEDIUM-HIGH

## Executive Summary

HA-Phone App is a native iOS/Android softphone tightly coupled to a self-hosted Asterisk PBX ("HA-Phone"), built to solve one specific reliability problem: calls must ring on a locked/closed phone without a permanently-open SIP registration or VPN tunnel. Research across stack, features, architecture, and pitfalls converges on a single well-precedented pattern already used by the vendors who have solved this (3CX, Linphone/Flexisip): a platform push (PushKit/APNs on iOS, high-priority data-only FCM on Android) wakes the app, the app reports the call to the native call UI (CallKit / self-managed `ConnectionService`) synchronously, and only *after* that does the app open a transient SIP/media session directly with the PBX. PJSIP/PJSUA2, built from official source per-platform, is the recommended shared SIP/media core; QR-based zero-touch provisioning and a signed, stateless multi-tenant push-relay (modeled on Matrix's Sygnal) round out the architecture. Door-station video preview (Akuvox) and the multi-device race-to-answer model are the project's clearest differentiators versus generic softphones (Zoiper/Linphone) and even commercial PBX apps (3CX/Yeastar Linkus), and both are explicitly scoped for v1 despite added complexity.

The single highest-risk unknown, confirmed independently by all four research tracks, is whether push-triggered wake into native call UI actually works reliably across real devices and OEM skins — not the relay's multi-tenancy design, not the SIP core, not the door-preview gateway. Pitfalls research is emphatic that failing to report every VoIP push to CallKit synchronously silently and permanently revokes the app's push capability, and that Android OEM battery/autostart layers (Samsung, Xiaomi, Huawei, OnePlus) defeat standard Android APIs entirely — both must be proven on real hardware in Phase 1, before any investment in the "architecturally interesting" multi-tenant relay. Security-critical rules are consistent throughout: push payloads must never carry SIP credentials, camera/RTSP URLs, or door-open authorization — they are wake signals only, and every accept/door-open action must be independently re-verified against live PBX state.

One open gap surfaced by cross-referencing PROJECT.md against the architecture research: PROJECT.md's Constraints/Active-Requirements now specify **Tailscale as the SIP/media transport layer** (replacing self-hosted STUN/TURN, with ephemeral per-call Tailscale connectivity rather than a permanent tunnel), decided *after* the architecture research was scoped. ARCHITECTURE.md's NAT/TURN section recommends a conventional self-hosted coturn (STUN+TURN) co-located with each PBX installation and does not address Tailscale (`tsnet` embedding, auth-key/OAuth node registration, ephemeral node lifecycle, or how Tailscale interacts with PJSIP's ICE/SRTP negotiation) at all. This is a real architectural gap, not just a missing citation — it should be flagged for a dedicated research or spike pass before the roadmap commits to a NAT-traversal approach in the audio-call phase.

## Key Findings

### Recommended Stack

The stack is largely pre-determined by PROJECT.md's own constraints (native Swift/SwiftUI + Kotlin/Compose, PJSIP/PJSUA2, FastAPI backend extension) and confirmed as sound by research rather than discovered fresh. The main stack decision requiring judgment — build PJSIP from official source vs. use community packaging (CocoaPod `Vialer-pjsip-iOS`, third-party AARs) or switch to Linphone SDK — resolves to: build from source per `docs.pjsip.org`, vendor the build in CI, and only use community/Linphone artifacts as prototyping shortcuts or study material, not shipped code.

**Core technologies:**
- PJSIP/PJSUA2 (2.16 stable): SIP signaling, SRTP/ICE/STUN/TURN, codecs — only cross-platform SIP core with first-party CallKit/PushKit and Kotlin guidance
- Swift/SwiftUI + PushKit/CallKit (iOS), Kotlin/Compose + FCM/Telecom (Android): mandated by native call-UI APIs, which are platform-language-only
- `aioapns` (async APNs client) + `firebase-admin` (FCM HTTP v1), both added to the existing FastAPI backend: current, maintained, async-native push-sending libraries; explicitly avoid unmaintained `apns2`/`PyAPNs2` and the deprecated legacy FCM server-key API
- Token-based (.p8) APNs auth, never certificate-based (.p12) — critical for a multi-tenant relay serving many independent PBX operators, since cert renewal failures would silently break push for every box sharing that cert

### Expected Features

**Must have (table stakes):** reliable push-based ringing when app is closed/locked (the #1 competitor complaint category across 3CX/Zoiper/Linphone reviews); native CallKit/Telecom call UI; answer/reject/hangup, mute, speaker, Bluetooth routing, DTMF; outgoing calls; QR-only provisioning; device management dashboard (list/revoke/re-provision); diagnostics/status page — essential for a self-hosted, vendor-support-free audience.

**Should have (competitive differentiators):** door-station video preview before answering (Akuvox) — the single feature no generic softphone or even commercial PBX app offers, and the project's clearest reason-to-switch; door-opener with biometric confirmation; multi-device-per-extension race-to-answer with active cancel-push to losers; stricter QR provisioning security (single-use, ~5min expiry, no SIP password in payload) than either 3CX or Yeastar's documented flows; self-hosted/no-vendor-cloud positioning.

**Defer (v1.x/v2+):** attended call transfer (blind transfer ships in v1); PBX-CDR-synced call history (local-only is fine for v1); snapshot-saving from door preview (needs admin permission toggle first); general SIP video calling (blocked on HA-Phone's own PBX roadmap); multi-PBX-account switching; additional door-station vendors beyond Akuvox.

**Explicit anti-features:** generic "enter any SIP server" mode, WebRTC/browser calling, enterprise call-center features, full call recording — all directly conflict with the reliability/security model this project depends on.

### Architecture Approach

The system splits into four hard boundaries: (1) Asterisk + FastAPI (HA-Phone) owns all call state, call-ID generation, and device registry — never the relay; (2) a genuinely separate, shared multi-tenant push-relay service holds the one set of APNs/FCM app credentials, verifies per-installation signatures, and is a stateless, "dumb pipe" forwarder (modeled directly on Matrix's Sygnal push-gateway pattern) that never sees call content; (3) the mobile app's push handler is thin and reactive — it reports to CallKit/Telecom immediately, then independently opens its own SIP/TLS+SRTP session directly to the PBX (never through the relay); (4) the PBX parks/holds the call (Pattern: "push is just a doorbell") while waiting for a device to wake and respond, with a 15-30s hold timeout before falling back to missed-call. Push payloads are minimal and non-actionable — Call-ID, caller metadata, expiry, signature only — with every actionable request (accept, door-open) re-verified against live server-side state.

**Major components:**
1. HA-Phone FastAPI backend (extended) — device registry, QR provisioning, call-hold orchestration, push event signing
2. Push-Relay (new, separate service) — tenant registration/signature verification, APNs/FCM credential holder, stateless forwarding with synchronous delivery-status response
3. Mobile app push/call-UI layer (native per platform) — thin PushKit/FCM handler, CallKit/`ConnectionService` reporting
4. Mobile app SIP/media core (PJSUA2, per platform) — registration, SDP/ICE/SRTP, DTMF, codec negotiation, established only after wake+answer

### Critical Pitfalls

1. **Not reporting every VoIP push to CallKit synchronously** — any conditional/delayed/skipped `reportNewIncomingCall` call risks app termination and, on a second offense, permanent VoIP push token revocation until reinstall. Fix: unconditional, synchronous report on every push including expired/duplicate/malformed cases; do server lookups only after reporting.
2. **Assuming standard Android battery-optimization exemption = reliable delivery** — Samsung/Xiaomi/Huawei/OnePlus all layer proprietary power-management daemons that ignore the standard `PowerManager` API entirely. Fix: OEM-specific onboarding deep-links to vendor autostart/battery screens, real multi-OEM device testing (not just Pixel/emulator) as a release gate, foreground-service-type `phoneCall` on receipt.
3. **High-priority FCM silently downgraded to normal priority** — Google tracks whether high-priority messages produce a visible notification within a rolling ~7-day window per install and silently demotes future messages if not, with zero server-side error signal. Fix: guarantee every call-type FCM message produces a visible CallStyle/full-screen notification, even on error paths (show "missed call" instead of nothing); instrument delivery latency.
4. **`USE_FULL_SCREEN_INTENT` default-deny on Android 14+** without a Play Console calling-app declaration or a runtime `canUseFullScreenIntent()` check — calls silently degrade to background notifications or crash. Fix: complete the Play Console declaration pre-submission, always check at runtime, and self-managed `ConnectionService` registration is what qualifies the app as a "calling app" for the auto-grant.
5. **Leaking long-lived door-camera credentials/URLs via push payload** — pushes are logged by OS infrastructure, cached, and visible in notification history; a leaked RTSP URL/credential grants standing access to a live camera feed. Fix: push carries only Call-ID + metadata + signature; the app fetches a short-lived, call-scoped preview token from the PBX only after waking, over an authenticated channel.

## Implications for Roadmap

Based on research, suggested phase structure (directly aligned with ENTWICKLUNGSPLAN.md §16 and ARCHITECTURE.md's "Suggested Build Order"):

### Phase 1: Push-Wakeup Proof of Concept
**Rationale:** This is the single highest-risk unknown in the entire project — everything else is contingent on push→native-call-UI wake actually working reliably across real devices/OEMs. Both STACK.md and PITFALLS.md independently flag this as the item that must be proven before any other investment.
**Delivers:** iOS PushKit→CallKit wake path and Android high-priority-FCM→Telecom/CallStyle wake path, tested on real devices (open/background/killed/locked states), using direct dev APNs/FCM credentials with the relay stubbed out entirely.
**Addresses:** "Reliable push-based wake" and "Native call UI integration" table-stakes features from FEATURES.md.
**Avoids:** Pitfall 1 (CallKit reporting failures/token revocation), Pitfall 2 (OEM battery-kill), Pitfall 3 (FCM silent downgrade), Pitfall 4 (full-screen-intent default-deny) — all flagged as Phase 1 items in PITFALLS.md.

### Phase 2: PJSIP/Media Core + QR Provisioning (parallel tracks)
**Rationale:** Neither the SIP/media core nor QR provisioning has a functional dependency on the push-relay; both can be built in parallel once Phase 1 proves the wake contract, per ARCHITECTURE.md's build order (steps 3-4).
**Delivers:** Stable audio calls (PJSUA2, registration, SRTP, DTMF) after accepting a (still-stubbed) push; QR-based zero-touch device provisioning against HA-Phone's device registry.
**Uses:** PJSIP/PJSUA2 from STACK.md; the `MobileDevice`/provisioning data model from ARCHITECTURE.md's project structure.
**Implements:** "Mobile app — SIP/media core" and "PBX — FastAPI backend" components from ARCHITECTURE.md.

### Phase 3: Call-Hold Orchestration, Accept/Cancel State Machine, Multi-Device Races
**Rationale:** Requires both a real push wake (Phase 1) and a real SIP core (Phase 2) to bridge into; multi-device races require the accept/already-taken state machine to exist first.
**Delivers:** Asterisk dialplan/ARI call-parking, `/api/calls/{callId}` and `/accept` endpoints, first-accept-wins with cancel-push fan-out to losing devices.
**Addresses:** "Multi-device-per-extension race-to-answer" differentiator (FEATURES.md); "PBX holds the call, push is a doorbell" pattern (ARCHITECTURE.md).

### Phase 4: NAT/Network-Transport Hardening — flagged for additional research before scoping
**Rationale:** ARCHITECTURE.md's default recommendation (self-hosted coturn STUN/TURN per PBX installation) is superseded by PROJECT.md's newer decision to use Tailscale as the SIP/media transport layer. This phase cannot be scoped confidently from current research alone (see Gaps below) and should not be planned in detail until a short Tailscale-transport spike/research pass resolves the open questions (tsnet embedding vs. auth-key node registration, ephemeral lifecycle, interaction with PJSIP's ICE negotiation).
**Delivers:** Resilient SIP/media transport surviving WiFi↔cellular handoff, reachable without manual STUN/TURN configuration.
**Avoids:** Pitfall 7 (NAT/TURN failure on network handoff) — but the *mechanism* for avoiding it needs to be re-derived for Tailscale rather than assumed from the coturn-based guidance in ARCHITECTURE.md.

### Phase 5: Multi-Tenant Push-Relay Formalization
**Rationale:** ARCHITECTURE.md explicitly warns against building the "proper" relay before the push/wake contract has stabilized (Anti-Pattern 3) — do this only once payload shape has settled through Phases 1-3.
**Delivers:** Standalone relay service with tenant registration, per-installation signing keys, revocation, rate-limiting — extracted from the Phase 1 stub.
**Implements:** The Sygnal-modeled "stateless signed forwarder" component from ARCHITECTURE.md.

### Phase 6: Door-Station Video Preview + Door-Opener
**Rationale:** Depends on a stable audio+push+provisioning foundation (per ARCHITECTURE.md build order); the RTSP/H.264 gateway spike against real Akuvox hardware can and should start early as a parallel technical spike, independent of this phase's main sequencing slot.
**Delivers:** Signed short-lived preview stream URL fetched post-wake, biometric-gated door-open action.
**Addresses:** The project's clearest competitive differentiator (FEATURES.md).
**Avoids:** Pitfall 5 (leaked camera credentials via push), Pitfall 8 (H.264 profile/latency mismatches).

### Phase Ordering Rationale

- Push-wake-to-native-UI is proven first because every other feature (audio, provisioning, multi-device, door preview) is worthless if calls don't reliably ring — this ordering is independently confirmed by STACK.md, FEATURES.md's competitor deep-dive, ARCHITECTURE.md's build order, and PITFALLS.md's phase mapping.
- The multi-tenant relay is deliberately built last among the "core" phases (not first, despite looking architecturally significant) because its contract must be derived from real payload iteration, not designed speculatively (ARCHITECTURE.md Anti-Pattern 3).
- Door-station preview, while a stated differentiator, is sequenced after the reliability core is solid, though its hardware-dependent gateway spike (H.264/RTSP profile validation) should start early in parallel since the Akuvox hardware is already available.

### Research Flags

Needs research/spike before detailed planning:
- **Phase 4 (Tailscale-as-transport):** PROJECT.md's Tailscale-transport decision was made after/outside the architecture research pass; ARCHITECTURE.md's NAT/TURN section assumes conventional self-hosted coturn and does not address `tsnet` embedding, ephemeral node registration, or Tailscale/ICE interaction. Run `/gsd-research-phase` (or an equivalent Tailscale-focused spike) before this phase is scoped in the roadmap.
- **Phase 6 (Door-station gateway):** RTSP→WebRTC/HTTP bridging and H.264 profile compatibility is hardware- and gateway-implementation-specific; PITFALLS.md recommends an early technical spike against real Akuvox hardware before committing to a gateway architecture.

Phases with standard, well-documented patterns (research-phase optional):
- **Phase 1 (Push wake):** Official Apple/Google/PJSIP docs are HIGH confidence and prescriptive; the main risk is execution/testing discipline, not unknown territory.
- **Phase 2 (SIP core, QR provisioning):** PJSIP build process and QR-based device provisioning both have official docs and multiple industry precedents (3CX, Yeastar) confirming the pattern.
- **Phase 5 (Relay):** Sygnal is a documented, open-source reference implementation of the exact pattern needed.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM-HIGH | iOS/Android platform APIs and APNs/FCM protocols verified against official docs (HIGH); PJSIP tooling/version pins and the build-vs-reuse call are judgment-based (MEDIUM) |
| Features | MEDIUM | WebSearch-verified across multiple competitor vendors (3CX, Yeastar, Zoiper, Linphone, Akuvox, DoorBird); no official API-doc source exists for this product/UX domain, and a few sub-claims (2N app UX, Yeastar reliability complaints) are explicitly flagged as unverified gaps |
| Architecture | MEDIUM-HIGH | Component boundaries and data flow backed by RFC 8599, official Apple/PJSIP docs (HIGH); the multi-tenant relay auth model is synthesized from the closest analog (Matrix Sygnal) since no directly comparable shared-relay-for-many-self-hosted-PBXes product exists publicly (MEDIUM) |
| Pitfalls | MEDIUM-HIGH | Apple/Google policy pitfalls verified against current developer docs (HIGH); OEM background-kill behavior is community/forum-sourced and is an inherently moving target (MEDIUM) |

**Overall confidence:** MEDIUM-HIGH

### Gaps to Address

- **Tailscale-as-media-transport is not covered by ARCHITECTURE.md at all.** PROJECT.md's Constraints and Active Requirements specify Tailscale as the SIP/RTP transport layer (replacing self-hosted STUN/TURN, ephemeral per-call connection, user-supplied Tailscale account in both app and HA-Phone) — this decision appears to postdate the architecture research scope, since ARCHITECTURE.md's NAT/TURN section recommends conventional coturn co-located with each PBX and never mentions Tailscale. Open technical questions requiring a dedicated research/spike pass: how the app establishes an ephemeral Tailscale node (embedded `tsnet` vs. system Tailscale app vs. auth-key/OAuth-client automated registration), how this interacts with PJSIP's own ICE/STUN/TURN negotiation (does Tailscale replace ICE entirely, or run alongside it as just another candidate path), whether "ephemeral, not persistent" Tailscale nodes are compatible with the "push wakes app, then app connects" timing model, and how this affects the multi-device-per-extension architecture (does each device need its own Tailscale node?). Flag explicitly for validation before Phase 4 (or wherever NAT/transport work lands) is scoped in the roadmap.
- **2N door-intercom app UX** (My2N/2N Access Commander) was not independently verified this research session — assumed similar to Akuvox/DoorBird based on training data only (LOW confidence). Not currently relevant since only Akuvox hardware is owned/planned, but should be spot-checked if 2N hardware is ever targeted.
- **Yeastar Linkus background-wake reliability** — insufficient independent user-report volume was found to assess confidently; treated as an open gap rather than a confirmed weakness or strength.
- **Exact PJSIP/NDK/Xcode version pins** shift with each PJSIP release; STACK.md explicitly recommends re-verifying against `docs.pjsip.org` build instructions at implementation time rather than trusting the version numbers captured during this research pass.

## Sources

### Primary (HIGH confidence)
- https://docs.pjsip.org (build instructions, iOS push notifications guide, Android/Kotlin sample) — official PJSIP docs
- https://developer.apple.com/documentation/PushKit — official PushKit/CallKit contract, mandatory synchronous `reportNewIncomingCall`
- https://firebase.google.com/docs/cloud-messaging — official FCM HTTP v1, message priority docs
- https://developer.android.com/develop/connectivity/telecom/selfManaged and /ui/compose/notifications/call-style — official Android Telecom/CallStyle docs
- https://source.android.com/docs/core/permissions/fsi-limits, https://support.google.com/googleplay/android-developer/answer/13392821 — official Android 14+ full-screen-intent restriction docs
- https://datatracker.ietf.org/doc/html/rfc8599 — SIP push notification support standard
- https://spec.matrix.org/unstable/push-gateway-api/ and https://github.com/matrix-org/sygnal — reference multi-tenant push-gateway pattern

### Secondary (MEDIUM confidence)
- 3CX, Yeastar, Zoiper, Linphone/Flexisip forum/support docs — competitor background-wake and QR-provisioning behavior comparison
- Akuvox SmartPlus and DoorBird official app documentation — door-station preview-before-answer UX pattern
- Apple Developer Forums threads on VoIP token revocation (`0xbaadca11`) — consistent across multiple independent threads
- Community OEM background-kill documentation ("Don't kill my app" project, dev.to survey) — Samsung/Xiaomi/Huawei/OnePlus power-management behavior

### Tertiary (LOW confidence)
- 2N My2N/Access Commander preview UX — training-data inference only, not independently verified this session

---
*Research completed: 2026-07-31*
*Ready for roadmap: yes, with Phase 4 (Tailscale transport) and Phase 6 (door-station gateway) flagged for a dedicated research/spike pass before detailed scoping*
