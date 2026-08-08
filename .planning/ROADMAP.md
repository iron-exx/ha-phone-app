# Roadmap: HA-Phone App

## Overview

The journey starts by proving the one thing the whole project depends on — that a platform push (APNs/FCM) can reliably wake the app into a native call screen even when it's closed or the phone is locked — before investing in anything else. From there, the SIP/media core and QR-only provisioning are built as parallel-capable tracks, since neither depends on the other. Once real audio calls and real devices exist, the PBX-side call-state machine is layered on top to make multi-device ringing and first-accept-wins work. Network transport (Tailscale-based, replacing manual STUN/TURN) is hardened next — this phase needs a dedicated research spike before detailed planning, since it was a late architectural decision the original research didn't cover. The multi-tenant push-relay is deliberately built last among the "core" phases, once the push payload contract has proven stable through real usage. Door-station video preview and the door-opener action — the project's clearest differentiator — close out v1, sequenced after the reliability core is solid, though the Akuvox hardware spike can start early in parallel.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Push-Wakeup Proof of Concept** - Prove push→native-call-UI wake works reliably on real iOS and Android devices before building anything else (completed 2026-08-03)
- [ ] **Phase 2: PJSIP Audio/Media Core** - Stable two-way calls (in/out, hold, transfer, DTMF) over a transient SIP session
- [ ] **Phase 3: QR Provisioning & Device Management** - Zero-touch device setup by QR scan, managed from the HA-Phone dashboard
- [ ] **Phase 4: Call-State Orchestration, Multi-Device Race & Diagnostics** - PBX-authoritative call state powers multi-device ringing and an in-app diagnostics page
- [ ] **Phase 5: Tailscale Transport Hardening** - Ephemeral Tailscale-based SIP/media transport survives NAT and network handoff (needs dedicated research first)
- [ ] **Phase 6: Multi-Tenant Push-Relay Formalization** - Standalone signed relay lets any HA-Phone installation use the app, not just the original box
- [ ] **Phase 7: Door-Station Video Preview + Door-Opener** - See who's at the door before answering, and open it from the app

## Phase Details

### Phase 1: Push-Wakeup Proof of Concept
**Goal**: A platform push reliably wakes the app into native call UI on both iOS and Android, across real devices/app states — proven before any other capability is built.
**Depends on**: Nothing (first phase)
**Requirements**: PUSH-01, PUSH-02, PUSH-03, PUSH-04
**Success Criteria** (what must be TRUE):
  1. On iOS, a VoIP push wakes the app and CallKit shows the incoming call screen even when the app was fully terminated. **Per CONTEXT.md D-11 (zero-budget constraint, no paid Apple Developer Program membership), this is verified only structurally via GitHub Actions Simulator CI + unit tests (Plan 04) for Phase 1 — real physical-device verification is an accepted, unresolved gap; see `01-PHASE-SIGNOFF.md`.**
  2. On iOS, every VoIP push is reported to CallKit synchronously with no missed, delayed, or skipped reports across repeated real-device test calls. **Same D-11 scoping as criterion #1 applies — verified at the code-path/unit-test level (PushHandlerTests), not on real hardware; see `01-PHASE-SIGNOFF.md`.**
  3. On Android, a high-priority FCM message wakes the app and shows a full-screen incoming-call UI while backgrounded or the device is locked. **Scoped to Pixel-only for Phase 1 sign-off (per CONTEXT.md D-03): no non-Pixel OEM device (Samsung/Xiaomi/etc.) is currently available to the developer. Non-Pixel OEM coverage is explicitly deferred and tracked as a Phase 6 hardening backlog item — this criterion is NOT silently claimed satisfied by Pixel testing alone; see `01-PHASE-SIGNOFF.md` for the explicit resolution.**
  4. The Android app has completed the Play Console "calling app" declaration required for the Android 14+ full-screen-intent auto-grant. **Per CONTEXT.md D-12 (zero-budget constraint, no paid Google Play Developer account), this declaration is explicitly skipped for Phase 1 — the debug APK is sideloaded via `adb install` instead, and whether the full-screen-intent auto-grant still works without the declaration is recorded as an empirical finding in `01-PHASE-SIGNOFF.md`, not assumed either way.**
**Plans**: 6 plans across 4 waves
Plans:
**Wave 1**
- [x] 01-01-PLAN.md — Signed push-event envelope contract (Ed25519) + standalone test-trigger CLI + manual test procedure doc (Wave 0)
- [x] 01-02-PLAN.md — iOS throwaway app: PushKit/CallKit unconditional-report handling, on-device diagnostics log (Wave 1)
- [x] 01-03-PLAN.md — Android throwaway app: FCM data-only handling, CallsManager/Telecom registration, CallStyle + full-screen intent (Wave 1)

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 01-04-PLAN.md — GitHub Actions macOS CI: XcodeGen + unsigned iOS Simulator build/test only, no Fastlane/TestFlight/paid Apple account (per D-11) (Wave 2)
- [x] 01-05-PLAN.md — Firebase project wiring (free) + adb-sideload Android manual test execution, empirically testing full-screen-intent without Play Console (per D-12) (Wave 2)

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 01-06-PLAN.md — Confirm iOS Simulator CI green + Phase 1 sign-off note documenting the D-11 iOS real-device gap and D-12 Android empirical finding (Wave 3)

### Phase 2: PJSIP Audio/Media Core
**Goal**: Users can carry a stable two-way call, in and out, with core telephony controls, over a SIP session that only exists for the duration of a call.
**Depends on**: Phase 1 (recommended parallel track — no hard functional blocker; can start once the push wake contract is understood)
**Requirements**: CALL-01, CALL-02, CALL-03, CALL-04, CALL-05
**Success Criteria** (what must be TRUE):
  1. User can accept an incoming call and hear/be heard over Opus/G.722/G.711 with working microphone, speaker, and Bluetooth audio routing.
  2. User can send DTMF tones during a call that are correctly received by the PBX/IVR.
  3. User can place an outgoing call to any extension.
  4. User can put an active call on hold and perform a blind transfer to another extension.
  5. The app's SIP registration is established only after answering or placing a call and torn down afterward — no persistent background registration.
**Plans**: 8 plans across 4 waves
Plans:
**Wave 1**
- [ ] 02-01-PLAN.md — Cross-repo HA-Phone TLS/SRTP test-extension provisioning (Wave 1)
- [x] 02-02-PLAN.md — Android PJSIP 2.17 native build (Opus, JNI/SWIG) (Wave 1)
- [ ] 02-03-PLAN.md — iOS PJSIP 2.17 build via GitHub Actions macOS runner (Wave 1)

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 02-04-PLAN.md — Android SIP call controller (codec/DTMF/hold/xfer/transient registration) (Wave 2)
- [x] 02-05-PLAN.md — iOS SIP call controller (PjsuaBridge, AudioSessionCoordinator) (Wave 2)

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 02-06-PLAN.md — Android UI (dialpad, outgoing call, active call screen) (Wave 3)
- [x] 02-07-PLAN.md — iOS UI (dialpad, outgoing call, active call screen) (Wave 3)

**Wave 4** *(blocked on Wave 3 completion)*
- [ ] 02-08-PLAN.md — Manual test procedure + Phase 2 sign-off (Wave 4)

### Phase 3: QR Provisioning & Device Management
**Goal**: New devices are set up purely by scanning a QR code, and the HA-Phone admin can manage which devices are attached to each extension.
**Depends on**: Nothing hard (can run in parallel with Phase 2); benefits from Phase 1's device/push-token model
**Requirements**: PROV-01, PROV-02, PROV-03
**Success Criteria** (what must be TRUE):
  1. User can scan a QR code shown by HA-Phone and end up fully provisioned (SIP identity + credentials) without typing any server, port, username, or password.
  2. Admin can open "Add Mobile Device" in the HA-Phone dashboard and get a time-limited, one-time-use provisioning token rendered as a QR code.
  3. Admin can view, lock, delete, and re-provision devices per extension from the HA-Phone dashboard.
**Plans**: TBD
**UI hint**: yes

### Phase 4: Call-State Orchestration, Multi-Device Race & Diagnostics
**Goal**: HA-Phone holds authoritative call state so multiple devices per extension can all ring, with first-accept-wins and immediate cancellation of the rest, and users/admins can see the health of push, SIP, and call state.
**Depends on**: Phase 2, Phase 3
**Requirements**: PROV-04, OPS-01
**Success Criteria** (what must be TRUE):
  1. When multiple devices are registered to one extension, all of them ring on an incoming call.
  2. Whichever device answers first wins the call, and every other ringing device stops immediately via a server-triggered cancel push.
  3. User can open a diagnostics/status page in the app showing push-registration state, SIP status, permission status, and the result of the last test push/call.
**Plans**: TBD
**UI hint**: yes

### Phase 5: Tailscale Transport Hardening
**Goal**: SIP/media connections stay reachable across NAT and network changes (WiFi to cellular) using an ephemeral Tailscale connection instead of manual STUN/TURN configuration — Tailscale is transport only, never a wake-up mechanism.
**Depends on**: Phase 2
**Requirements**: OPS-03
**Success Criteria** (what must be TRUE):
  1. User enters their Tailscale account once, in both the app and HA-Phone, with no further manual network configuration required.
  2. When a call needs to connect, the app automatically establishes a Tailscale-based path for SIP/RTP on demand, without a persistent background tunnel.
  3. An active call survives a WiFi-to-cellular network handoff without dropping audio.
**Plans**: TBD
**Research needed**: Yes — flagged by research/SUMMARY.md. The Tailscale-as-transport decision (tsnet embedding vs. auth-key/OAuth-client ephemeral node registration, interaction with PJSIP's own ICE/STUN/TURN negotiation, ephemeral node lifecycle, per-device node implications for the multi-device model) postdates the architecture research and was never resolved there. `/gsd-plan-phase` should trigger a dedicated research pass for this phase before producing a detailed plan.

### Phase 6: Multi-Tenant Push-Relay Formalization
**Goal**: A standalone, shared push-relay service accepts signed call events from any HA-Phone installation — not just the original dev box — and forwards them to APNs/FCM, enabling other operators to run the app against their own box.
**Depends on**: Phase 1 (stable push payload contract), Phase 4 (stable call-state/cancel contract)
**Requirements**: OPS-02
**Success Criteria** (what must be TRUE):
  1. A HA-Phone installation other than the original dev box can register with the relay and have its signed call events delivered to a device via APNs/FCM.
  2. The relay never has access to call content, SIP credentials, or camera URLs — only signed, minimal call-event metadata passes through it.
  3. A single misbehaving or revoked installation's signing key can be disabled at the relay without affecting any other installation.
**Plans**: TBD

### Phase 7: Door-Station Video Preview + Door-Opener
**Goal**: Users see a live snapshot of who's at the door before answering, and can open the door from the app with optional biometric confirmation.
**Depends on**: Phase 4 (stable call-state + push foundation); the Akuvox hardware/RTSP gateway spike may start early in parallel with any earlier phase
**Requirements**: DOOR-01, DOOR-02
**Success Criteria** (what must be TRUE):
  1. When a call comes in from the Akuvox door station, the user sees a video snapshot/preview before accepting the call, delivered via a short-lived signed link that is separate from the push payload itself.
  2. User can trigger the door-opener action from within the app during or after seeing the preview.
  3. The door-opener action can require Face ID / Touch ID / device PIN confirmation before it executes.
**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7

| Phase | Plans Complete | Status | Completed |
|-------|-----------------|--------|-----------|
| 1. Push-Wakeup Proof of Concept | 6/6 | Complete    | 2026-08-03 |
| 2. PJSIP Audio/Media Core | 1/8 | In progress | - |
| 3. QR Provisioning & Device Management | 0/TBD | Not started | - |
| 4. Call-State Orchestration, Multi-Device Race & Diagnostics | 0/TBD | Not started | - |
| 5. Tailscale Transport Hardening | 0/TBD | Not started | - |
| 6. Multi-Tenant Push-Relay Formalization | 0/TBD | Not started | - |
| 7. Door-Station Video Preview + Door-Opener | 0/TBD | Not started | - |
</content>
