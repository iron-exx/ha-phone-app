# Architecture Research

**Domain:** VoIP-push-based native softphone (iOS + Android) coupled to a self-hosted Asterisk PBX, with a shared multi-tenant push-relay
**Researched:** 2026-07-31
**Confidence:** MEDIUM-HIGH (component boundaries and data flow: HIGH, backed by RFC 8599, Matrix Sygnal prior art, Apple/PJSIP docs; multi-tenant relay auth model: MEDIUM, synthesized from Sygnal's closest analogous pattern since no publicly documented "self-hosted PBX + shared push relay" product exists at this scale)

## Standard Architecture

### System Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│  Caller / SIP Trunk / Akuvox door station                            │
└───────────────────────────────┬──────────────────────────────────────┘
                                 ▼
┌──────────────────────────────────────────────────────────────────────┐
│  HA-PHONE PBX (per self-hosted installation — Asterisk 22 + FastAPI)  │
│  ┌───────────────┐   ┌────────────────────┐   ┌───────────────────┐  │
│  │ Asterisk core │──▶│ Call-hold / dialplan│──▶│ Push-trigger      │  │
│  │ (SIP/RTP/AMI) │   │ logic (FastAPI)     │   │ client (signs +   │  │
│  └───────────────┘   └────────────────────┘   │  calls Relay)     │  │
│         ▲                     │                └─────────┬─────────┘ │
│         │              ┌──────▼───────┐                   │           │
│         │              │ Device/Push  │                   │           │
│         │              │ registry DB  │                   │           │
│         │              │ + QR-token   │                   │           │
│         │              │ issuance     │                   │           │
│         │              └──────────────┘                   │           │
└─────────┼───────────────────────────────────────────────────┼─────────┘
          │  SIP TLS / SRTP (app ↔ PBX, direct, after wake)   │  HTTPS (signed event)
          │                                                    ▼
          │                                    ┌──────────────────────────────┐
          │                                    │  PUSH-RELAY (single shared    │
          │                                    │  multi-tenant service)        │
          │                                    │  - verifies PBX signature      │
          │                                    │  - holds APNs/FCM credentials │
          │                                    │  - maps pushkey → tenant PBX  │
          │                                    │  - forwards to Apple/Google   │
          │                                    │  - relays rejected/ack status │
          │                                    │    back to originating PBX    │
          │                                    └───────────┬──────────────────┘
          │                                                 ▼
          │                                     ┌────────────────────┐
          │                                     │ APNs (iOS)  /  FCM │
          │                                     │ (Android)          │
          │                                     └─────────┬──────────┘
          │                                                 ▼
          │                                     ┌────────────────────┐
          │                                     │ OS wakes app        │
          │                                     │ (PushKit / FCM svc) │
          │                                     └─────────┬──────────┘
          │                                                 ▼
          │                                     ┌────────────────────┐
          │                                     │ App → CallKit /     │
          │                                     │ Telecom reports call│
          │                                     └─────────┬──────────┘
          └────────────────────────────────────────────────┘
                     App opens SIP connection back to PBX directly
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| **PBX — Asterisk core** | SIP registration, dialplan, RTP/SRTP media, trunk/extension routing, actual call state machine | Asterisk 22, AMI/ARI events consumed by FastAPI |
| **PBX — FastAPI backend** | Device registry, QR provisioning token issuance/redemption, call-hold-until-push-response orchestration, call-ID generation, signs outbound push events, exposes `/api/mobile/*` and `/api/calls/*` | Existing HA-Phone backend, extended with new routers/tables |
| **Push-Relay (shared service)** | Holds the *one* set of APNs/FCM app credentials for the HA-Phone-app identity; authenticates inbound PBX instances; translates PBX event → APNs/FCM payload; returns delivery/rejection status; rate-limits and audits | New standalone service — Matrix Sygnal is the closest real-world analog (see below) |
| **APNs / FCM** | OS-level push transport | Apple/Google infrastructure, unmodified |
| **Mobile app — PushKit/FCM handler** | Wakes on push, immediately reports to CallKit/Telecom (mandatory on iOS ≥13), then independently opens SIP/TLS to the PBX | Native Swift/Kotlin push receiver, thin — no business logic |
| **Mobile app — SIP/media core (PJSIP)** | Registers, negotiates SDP, handles SRTP/ICE, DTMF, codecs | PJSUA2 wrapped per-platform |
| **Mobile app — CallKit/Telecom UI layer** | Native call screen, accept/reject, audio routing (speaker/Bluetooth) | CXProvider (iOS), ConnectionService/TelecomManager (Android) |

**Key boundary decision:** Call *state* and call-ID generation live exclusively in the PBX (Asterisk + FastAPI) — never in the relay, never in the app. The relay is a **stateless-per-call transport**: it does not know what a "call" is, only that it forwards an opaque signed envelope to a device. The app is a *reactor*: it never initiates call state, it only reports what the PBX told it via push, then confirms back to the PBX directly over its own SIP/HTTPS channel. This mirrors RFC 8599 (SIP push notifications) and the Matrix Sygnal push-gateway model, both of which explicitly keep the gateway "dumb" and stateless about the application-level event.

## Recommended Project Structure

```
HA-Phone (existing repo, extended)
├── backend/app/mobile/            # NEW: device registry, provisioning, push trigger
│   ├── models.py                  # MobileDevice, ProvisionToken tables
│   ├── provisioning.py            # QR token issue/redeem endpoints
│   ├── device_registry.py         # register/refresh-token/revoke
│   ├── call_hold.py               # holds Asterisk call via AMI/ARI pending push response
│   └── push_client.py             # signs event, POSTs to relay
├── backend/app/calls/              # NEW: call-scoped REST surface
│   └── routes.py                  # /api/calls/{callId}/accept|reject|hangup|door-open, preview
└── frontend/.../DeviceManagement/  # NEW: "Mobilgerät hinzufügen" dialog + device list UI

ha-phone-push-relay (new, separate repo/service)
├── src/
│   ├── auth/                      # PBX instance registration + signature verification
│   ├── tenants/                   # tenant (PBX instance) registry, revocation
│   ├── providers/
│   │   ├── apns.py                # HTTP/2 APNs client, VoIP push_type
│   │   └── fcm.py                 # FCM HTTP v1 client, high-priority data messages
│   ├── notify.py                  # POST /v1/notify — main relay endpoint
│   └── status.py                  # rejected/expired pushkey feedback to PBX
└── deploy/                        # single shared deployment, NOT per-PBX

ha-phone-app-ios/    (Swift/SwiftUI, PJSUA2, CallKit, PushKit)
ha-phone-app-android/ (Kotlin/Compose, PJSUA2, Telecom, FCM)
  common/sip-core/     # shared PJSIP wrapper logic per-platform (not literally shared code
                       # unless Kotlin Multiplatform is adopted later — YAGNI for v1)
```

### Structure Rationale

- **Push-relay as a genuinely separate repo/service**, not a module inside HA-Phone: it holds credentials shared across *all* HA-Phone installations (your own APNs cert / FCM project), so it cannot be bundled into the per-installation Home-Assistant add-on. This is a hard architectural boundary, not a preference.
- **Device/call logic stays inside HA-Phone's FastAPI**, not the relay: HA-Phone already owns extensions, trunks, AMI/ARI access — call-hold and call-ID generation need direct Asterisk control that the relay will never have.
- **No premature cross-platform code sharing** (Kotlin Multiplatform / shared C++ core) for v1: ENTWICKLUNGSPLAN.md itself flags this as optional/alternative, and the project's own constraint says native Swift/Kotlin. Revisit KMP only after both apps stabilize independently (YAGNI).

## Architectural Patterns

### Pattern 1: PBX Holds the Call, Push Is Just a Doorbell

**What:** On an incoming call, Asterisk answers into a holding state (e.g., ringing/Ringing/early-media or a dialplan "hold" park) *before* any device confirms it's awake. The push notification is not the call setup — it is a signed pointer telling the app "a call named `<callId>` exists, come get it."
**When to use:** Always, for this architecture — it's what makes push-based (non-persistent-registration) softphones work at all, since push delivery latency and success are not guaranteed.
**Trade-offs:** Requires the PBX to manage a timeout (typically 15-30s) for how long to hold before treating it as a missed call if no device responds; adds dialplan complexity (Asterisk `Wait`/`AGI`/ARI bridge-hold) but is unavoidable — this is the single most load-bearing pattern in the whole system.

### Pattern 2: Push Payload Is Minimal and Non-Actionable Alone

**What:** The push body carries only `callId`, caller display name/number, call-type (audio/video/door), expiry timestamp, and a signature — never SIP credentials, never a door-opener capability, never a long-lived media URL. After waking, the app calls back into the PBX (`GET /api/calls/{callId}`) to fetch full details and authenticate the actual action.
**When to use:** Every push sent, without exception (ENTWICKLUNGSPLAN.md §11 already mandates this).
**Trade-offs:** Costs one extra round trip after wake (small latency), but caps the blast radius of a leaked/replayed push notification to "an attacker can see a call is happening," not "an attacker can open the door."

**Example (illustrative payload):**
```jsonc
// APNs VoIP push aps payload (iOS)
{
  "aps": { "content-available": 1 },
  "callId": "c-2f9a3e",
  "callType": "audio",       // audio | video | door
  "caller": "Akuvox Tür",
  "callerNumber": "50",
  "expiresAt": 1785600042,
  "sig": "base64-ed25519-signature-over-above-fields"
}
```
```jsonc
// FCM data message (Android) — high priority, data-only (no notification payload,
// so the app controls the UI via CallStyle/Full-Screen-Intent itself)
{
  "message": {
    "token": "<fcm-token>",
    "android": { "priority": "high", "ttl": "30s" },
    "data": {
      "callId": "c-2f9a3e",
      "callType": "audio",
      "caller": "Akuvox Tür",
      "callerNumber": "50",
      "expiresAt": "1785600042",
      "sig": "base64-ed25519-signature-over-above-fields"
    }
  }
}
```

### Pattern 3: Relay as a Signed, Stateless Forwarder (Sygnal Model)

**What:** Each self-hosted PBX instance is a "tenant" of the relay analogous to how any Matrix homeserver is a tenant of a Sygnal push gateway. The PBX signs every outbound event with a per-installation key registered with the relay at provisioning time; the relay verifies the signature, looks up which provider (APNs/FCM) and credential set to use based on the *app identity* embedded in the device's pushkey/app_id (not the PBX's identity — all PBX instances share the same app identity/bundle ID), and forwards. It does not persist call state; it returns a synchronous `{"rejected": [...]}`-style response (Matrix Push Gateway API model) so the PBX can prune dead tokens.
**When to use:** This is the only pattern that lets one relay operator serve arbitrarily many independent self-hosted PBX operators without becoming a single point of trust for call content — the relay only ever sees metadata, and only the shape of it, not raw SIP data.
**Trade-offs:** Requires a PBX-instance registration/API-key-issuance step (see multi-tenant section below) that must exist before *any* PBX can send its first push, so it becomes a hard prerequisite, not an add-on.

## Data Flow

### Full Incoming-Call Flow

```
1. Caller/trunk/door-station → Asterisk INVITE
2. Asterisk core → notifies FastAPI (AMI/ARI event) → FastAPI generates callId (e.g. ULID),
   parks/holds the call, writes call row {callId, extension, caller, type, state=ringing, expiresAt}
3. FastAPI looks up MobileDevice rows for that extension → for each device:
     push_client.py builds event, signs with PBX-instance private key,
     POST https://relay.ha-phone.io/v1/notify
       body: { "installationId": "...", "device": {"platform":"ios","pushToken":"..."},
               "event": {callId, callType, caller, callerNumber, expiresAt}, "sig": "..." }
4. Relay verifies sig against registered installation public key → looks up provider by device.platform
     → APNs HTTP/2 request (push_type: voip) or FCM HTTP v1 request (priority: high)
     → returns 200 { "rejected": [] } or lists invalid tokens back to the PBX synchronously
5. APNs/FCM deliver to device → OS wakes app in background
6. iOS: PushKit didReceiveIncomingPushWith → app MUST synchronously call
     CXProvider.reportNewIncomingCall(uuid, update, completion) before returning
   Android: FirebaseMessagingService.onMessageReceived (high priority + data-only) →
     app posts CallStyle notification / launches Full-Screen-Intent → registers call with
     TelecomManager.addNewIncomingCall
7. App (now in foreground-equivalent call UI state) → GET /api/calls/{callId} over HTTPS
     to the PBX directly (not via relay) → fetches full details, verifies expiresAt not passed
8. User accepts → app opens SIP/TLS registration+INVITE-answer to the PBX directly
     (PJSIP), independent of push channel from this point on
9. PBX bridges held call to the newly-registered SIP endpoint → SRTP media flows directly
     between app and PBX (ICE/STUN/TURN as needed)
10. App also POSTs /api/calls/{callId}/accept as an explicit ack (idempotency/multi-device
     race arbitration — see below) — SIP answer alone is the source of truth for media,
     the REST ack is for fast-cancelling sibling devices
11. On hangup: SIP BYE ends media; FastAPI marks call state=ended
```

### Concrete API Contracts (illustrative, per-hop)

**Hop 1 — PBX → Relay (`POST /v1/notify`)**
```json
// Request
{
  "installationId": "inst_7f3c1a2b",
  "sentAt": "2026-07-31T14:32:00Z",
  "devices": [
    { "platform": "ios", "pushToken": "abcd...", "appId": "de.haphone.app.voip" }
  ],
  "event": {
    "callId": "c-2f9a3e",
    "callType": "audio",
    "caller": "Akuvox Tür",
    "callerNumber": "50",
    "expiresAt": "2026-07-31T14:32:30Z"
  },
  "sig": "base64-ed25519(installationPrivateKey, canonicalized-above)"
}

// Response 200
{ "rejected": [] }
// or, on stale token:
{ "rejected": ["abcd..."] }
// Non-200 (e.g. 401 bad sig, 403 revoked installation, 429 rate-limited) → PBX must NOT retry
// silently forever; treat as delivery failure and fall back to normal ring-only behavior.
```

**Hop 2 — App → PBX (`GET /api/calls/{callId}`)**
```json
// Response 200
{
  "callId": "c-2f9a3e",
  "state": "ringing",
  "callType": "audio",
  "caller": "Akuvox Tür",
  "callerNumber": "50",
  "expiresAt": "2026-07-31T14:32:30Z",
  "sipTarget": "sip:50@pbx.example.de:5061;transport=tls",
  "isDoorStation": true,
  "previewUrl": "https://pbx.example.de/api/calls/c-2f9a3e/preview?t=<short-lived-token>"
}
// 404/410 if expired or already answered elsewhere -> app must silently withdraw its
// CallKit/Telecom UI immediately (Apple requires ending the reported call promptly if
// it turns out to be stale, or future pushes may be throttled).
```

**Hop 3 — App → PBX (`POST /api/calls/{callId}/accept`)**
```json
// Request
{ "deviceId": "dev_9c11", "acceptedAt": "2026-07-31T14:32:04Z" }

// Response 200 (first responder)
{ "status": "accepted", "sipTarget": "sip:50@pbx.example.de:5061;transport=tls" }

// Response 409 (already accepted by a sibling device)
{ "status": "already_taken", "byDeviceId": "dev_4471" }
```

## Multi-Tenant Model for the Push-Relay

The relay must serve many independent, mutually-untrusting self-hosted PBX operators while holding one shared set of Apple/Google app credentials (since credentials are bound to *app identity*, not per-installation). The closest working precedent is **Matrix's Sygnal**: one push-gateway operator, many independent homeserver operators, no direct trust relationship required between homeserver operators and the gateway operator beyond a registration handshake — confidence MEDIUM/HIGH on the pattern itself (matrix.org, Sygnal docs), LOW-MEDIUM on the specific mechanics below since they must be designed fresh for this project (no existing "shared VoIP push relay for many self-hosted PBXes" product was found publicly documented).

- **Tenant = installation, not extension/device.** Each HA-Phone installation registers itself once with the relay (e.g. during initial add-on setup or first QR provisioning) and receives an `installationId` + asymmetric keypair (private key stored only on the PBX, public key stored by the relay). All later `/v1/notify` calls are signed with that private key — the relay never needs to trust the PBX's TLS client cert or IP, just the signature, which also survives the PBX being behind NAT/dynamic IP/Home-Assistant network changes.
- **Registration/auth flow:** `POST /v1/tenants/register` from the PBX during add-on first-run (or lazily on first push attempt), authenticated by a bootstrap secret embedded in the add-on config (or, more robust: an out-of-band admin-approved activation code, mirroring the QR-provisioning UX already planned) → relay issues `installationId` + accepts the PBX's public key (generated locally, private key never leaves the box).
- **Routing acks back:** because the relay is stateless per-call, "routing acks back" is not a persistent-connection problem — the relay's HTTP response to `/v1/notify` *is* the ack (delivered/rejected token list), synchronously, in the same request/response cycle. No separate callback channel is needed. This is a deliberate simplification versus a bidirectional streaming model and keeps the relay stateless and horizontally scalable.
- **Stale/revoked instances:** relay maintains a tenant status column (`active`/`revoked`/`suspended`). Revocation should be supportable both by the relay operator (abuse response, e.g. rate-limit violations) and self-service by the PBX owner (uninstall/factory reset flow that calls `/v1/tenants/deregister`). A revoked installationId causes all future `/v1/notify` calls to receive 403, forcing that PBX to fall back to non-push behavior (still allows manual dial-in via existing SIP/Tailscale route as a degraded mode).
- **Abuse/rate-limiting:** since anyone can in principle stand up an HA-Phone box and register with the shared relay, apply per-tenant rate limits (pushes/minute) tied to `installationId`, and consider requiring a lightweight one-time "activation" step (e.g. verifying a GitHub-issued or email-verified operator identity) before granting production push credentials, to avoid the shared APNs/FCM app identity getting throttled or banned due to one bad-actor installation. This is a design detail to firm up in the relay's own phase, not needed for the dev-stub phase.

## Suggested Build Order (Dependency-Driven)

This directly maps onto ENTWICKLUNGSPLAN.md §16 but makes the relay's staging explicit, since it is the piece with the least existing precedent to fall back on.

1. **Push-wakeup proof of concept, single dev PBX, relay stubbed out or skipped entirely.** Call PBX's FastAPI directly to APNs (HTTP/2) and FCM (HTTP v1) using your *own* dev Apple/Firebase credentials, no signing, no multi-tenant anything. Goal: prove `reportNewIncomingCall` / Telecom wake-up actually works reliably in all app states (open/background/killed/locked) — this is the highest-risk unknown and has zero dependency on QR provisioning or the relay.
   - **Yes, the relay can and should be stubbed for phase 1** — a hardcoded single-tenant "relay" (even just the PBX calling APNs/FCM directly with locally-stored credentials) is architecturally identical to the final version's *inner* provider-calling logic; only the tenant-routing/signature-verification layer is deferred.
2. **Native call UI integration** (CallKit / Telecom) wired to the stubbed push, still no real SIP registration — validates the OS-level call lifecycle contract independent of PJSIP.
3. **PJSIP/PJSUA2 SIP+media core**, app registers to dev PBX after accepting the stubbed push, stable audio call end-to-end. This can happen in parallel with step 2 on each platform.
4. **QR provisioning.** Can be built in parallel with 1-3 since it has no functional dependency on push — it only needs the PBX's existing device-registry data model, which should in fact be designed together with step 1's device/token storage (build the `MobileDevice` table once, use it for both). Practically: provisioning unlocks *installing the app on a second real device*, so do it before multi-device races (step 6) and before onboarding any non-dev-team tester.
5. **Call-hold-until-push-response logic in Asterisk dialplan/ARI**, replacing "just ring both SIP contact and push" with the real "park the call, wait for push-triggered SIP registration, then bridge" flow, plus the `/api/calls/{callId}` and `/accept` endpoints. This depends on 1 and 3 both existing (need real push wake + real SIP re-registration to bridge into).
6. **Multi-device races** (multiple phones per extension, first-accept-wins, abort-push to losers) — depends on 5 being solid, since it requires the accept/already_taken state machine.
7. **Only now build the real multi-tenant push-relay** — extract the direct-APNs/FCM logic from step 1 into a standalone service, add tenant registration/signing/revocation. Do this once the *shape* of the push event is stable (steps 1-6 will have iterated on payload fields several times); building the relay too early means re-doing its API contract repeatedly.
8. **NAT/STUN/TURN hardening + network-change handling** (WiFi↔cellular) — logically independent of the relay, but needs a stable SIP/media core (step 3) first; do this before videotelefonie since video amplifies every NAT/bandwidth problem.
9. **Video, then door-station preview/opener** — as ENTWICKLUNGSPLAN.md phases 4-5, both depend on a stable audio+push+provisioning foundation.

**Key implication for the roadmap:** the multi-tenant relay is *not* a Phase-1 blocker. Treat "direct APNs/FCM calls from the dev PBX" as an explicit, intentional throwaway/refactor-later stub, not a shortcut to be ashamed of — this is exactly the risk-first ordering the original plan already recommends (§16: push-wakeup before everything else).

## NAT / STUN / TURN / Network-Change Architecture

- **The push-relay plays no role here — it is purely orthogonal.** Once the app has been woken and opened its own SIP/TLS connection to the PBX, all subsequent signaling and media are a direct app↔PBX conversation; the relay is never in that path and has no visibility into media negotiation.
- **TURN should be hosted by/alongside each self-hosted PBX**, not centrally. Since HA-Phone already runs as a Home Assistant add-on with a known public/reachable address (or Tailscale/reverse-proxy), the natural place for a TURN server (e.g. coturn) is on the same host or docker network as Asterisk, with credentials issued per-device at provisioning time (short-lived TURN credentials handed out via the QR-provisioning payload / `/api/mobile/config`, matching ENTWICKLUNGSPLAN.md §5's "STUN- und TURN-Konfiguration" field). This keeps TURN under the same trust/ops boundary as the rest of the PBX and avoids the relay operator ever touching media traffic or bearing its bandwidth cost.
- **STUN can point at any public STUN server** (Google's public STUN, or self-hosted coturn's STUN mode) — low-stakes, no credentials needed, mainly used for ICE candidate gathering to detect the app's public IP/port before falling back to TURN relay.
- **Network-change handling (WiFi↔cellular)** is entirely a PJSIP/ICE concern on the app side: on network change, the app should treat this like a fresh reconnect — re-run ICE gathering, potentially re-INVITE with updated SDP, and keep SIP registration state machine in the app aware that a network transition may require a full ICE restart (RFC 5245 ICE restart) rather than assuming the existing candidate pairs remain valid. This must be tested explicitly (ENTWICKLUNGSPLAN.md §13 already lists WiFi/cellular switch as a required test case) but does not touch push or the relay at all.
- **Only exception where relay-adjacent infra matters:** if TURN is ever centralized in the future (e.g. to help NAT'd PBX installations that can't open inbound ports at all), that would be a *separate* shared service from the push-relay — do not conflate them even though both are "central services serving many PBXes." TURN needs to carry media bandwidth cost; the relay never carries media. Not needed for v1 given HA-Phone's existing remote-access assumptions (Tailscale/reverse-proxy already used for SIP/media reachability per PROJECT.md constraints).

## Anti-Patterns

### Anti-Pattern 1: Putting Call State or Business Logic in the Push-Relay

**What people do:** Let the relay track "is this call still active," "who accepted," or generate call-IDs itself, because it's tempting to centralize logic in the one service that touches all installations.
**Why it's wrong:** The relay serves many independent, mutually-distrusting PBX operators. If it holds call state, a relay outage or bug becomes a call-routing outage for every installation simultaneously, and the relay operator becomes a full party to every customer's call metadata rather than a dumb pipe — a much bigger security/privacy/liability surface, and contrary to the project's own stated principle (ENTWICKLUNGSPLAN.md §11: "Ein Push darf allein keinen Anruf übernehmen").
**Do this instead:** Relay only forwards signed, opaque, short-lived envelopes and reports token-level delivery status. All call semantics stay in each PBX.

### Anti-Pattern 2: App Trusts the Push Payload as Authoritative

**What people do:** Render caller info, ring, or (worse) allow door-opening directly from the push payload contents without re-verifying against the PBX.
**Why it's wrong:** Push payloads are size-limited, cached by the OS, potentially replayed/delayed, and traverse a third-party relay — treating them as ground truth invites spoofing/replay and stale-data bugs (e.g., ringing for a call that the caller already abandoned).
**Do this instead:** Push is only a wake signal + minimal display hint; the app must call back to the PBX (`GET /api/calls/{callId}`) for anything actionable, and the PBX must re-validate expiry/state server-side on every accept/door-open request.

### Anti-Pattern 3: Building the Full Multi-Tenant Relay Before Push-Wakeup Is Proven

**What people do:** Design the "proper" relay (tenant registry, signing, revocation, rate limiting) first because it looks like the biggest, most "architectural" piece of work.
**Why it's wrong:** The riskiest unknown in this whole project is whether iOS/Android reliably wake a killed app via VoIP push/high-priority FCM into CallKit/Telecom — not the relay's multi-tenancy model. Investing in relay infrastructure before that's proven risks building the wrong contract (payload shape, timing assumptions) and having to redo it.
**Do this instead:** Stub the relay as direct-provider-calls from a single dev PBX first (see Build Order step 1); only formalize multi-tenancy once the push/wake contract has stabilized through real device testing.

### Anti-Pattern 4: Persistent SIP Registration to Avoid Push Complexity

**What people do:** Keep the app registered to the PBX at all times (classic softphone pattern) to sidestep the push-wake complexity, relying on OS background execution.
**Why it's wrong:** This is explicitly the failure mode the whole project exists to avoid (PROJECT.md Core Value) — iOS/Android aggressively kill background network connections, so persistent registration alone is why the existing Linphone+Tailscale setup is unreliable.
**Do this instead:** Register only reactively, after a push wake, and drop registration again once the call ends (or keep a short-lived low-power state, per ENTWICKLUNGSPLAN.md §2 step 9).

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| APNs | HTTP/2, token or cert auth, `push_type: voip`, held only by the relay | VoIP push type is unlimited-size/immediate-delivery but requires immediate CallKit reporting or iOS penalizes future delivery |
| FCM | HTTP v1 API, high-priority **data-only** messages, held only by the relay | Must actually surface a visible notification promptly or Google may downgrade priority for the sender over time |
| coturn (TURN/STUN) | Per-PBX-installation, co-located with Asterisk | Credentials issued via provisioning payload / `/api/mobile/config`, short-lived |
| Akuvox door station | SIP INVITE to PBX + vendor snapshot/RTSP API for preview | PBX-side gateway generates short-lived preview token, never a raw RTSP credential, per ENTWICKLUNGSPLAN.md §7 |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Asterisk core ↔ FastAPI backend | AMI/ARI events + control | Existing HA-Phone integration pattern, extend rather than replace |
| FastAPI backend ↔ Push-relay | Signed HTTPS REST (`/v1/notify`) | Stateless, synchronous ack in response |
| Push-relay ↔ APNs/FCM | Provider-native SDK/HTTP | No PBX-specific logic here |
| Mobile app ↔ PBX | Two channels: HTTPS REST (`/api/calls/*`, `/api/mobile/*`) for control/provisioning, SIP/TLS+SRTP for actual call signaling/media | Never routed through the relay |
| Mobile app ↔ OS push framework | PushKit (iOS) / FCM SDK (Android) | Thin, no business logic, only forwards to app's own call-handling layer |

## Sources

- [RFC 8599 — Push Notification Support for SIP](https://datatracker.ietf.org/doc/html/rfc8599) — standardizes how push params are carried in SIP REGISTER Contact URI; directly informs PJSIP registration design (HIGH confidence, IETF standard)
- [PJSIP — iOS Push Notifications guide](https://docs.pjsip.org/en/latest/specific-guides/other/ios_push_notifications.html) — PushKit/CallKit integration guidance for PJSUA2-based apps (HIGH confidence, official PJSIP docs)
- [Apple Developer — Responding to VoIP Notifications from PushKit](https://developer.apple.com/documentation/PushKit/responding-to-voip-notifications-from-pushkit?language=objc) — mandatory synchronous `reportNewIncomingCall` requirement (HIGH confidence, official Apple docs)
- [Matrix Specification — Push Gateway API](https://spec.matrix.org/unstable/push-gateway-api/) — closest real-world precedent for a stateless multi-tenant push relay serving independent server operators; request/response shape (`rejected` array) adapted here (HIGH confidence for the pattern, official spec)
- [matrix-org/sygnal (GitHub)](https://github.com/matrix-org/sygnal) — reference implementation of the above pattern in production, "no contract between homeserver and gateway operators" model directly informs the relay's tenant-registration design (MEDIUM-HIGH confidence)
- [PortSIP Knowledge Base — How Push Notifications Work with PortSIP PBX](https://support.portsip.com/development-portsip/mobile-push-notifications/how-do-push-notifications-work-with-portsip-pbx) — confirms the "PBX holds/attempts SIP, falls back to push, app re-registers on wake" pattern in a comparable commercial PBX product (MEDIUM confidence, vendor docs, single source)
- ENTWICKLUNGSPLAN.md (project-internal) — original detailed plan, source of the German-language requirements this research maps onto architecturally (project source of truth)

---
*Architecture research for: VoIP-push softphone + self-hosted PBX + shared multi-tenant push relay*
*Researched: 2026-07-31*
