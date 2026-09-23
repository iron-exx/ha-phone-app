# Phase 5: Tailscale Transport Hardening - Context

**Gathered:** 2026-08-18
**Status:** Context discussed, proceeding to planning

<domain>
## Phase Boundary

SIP/media connections stay reachable across NAT and network changes (WiFi to cellular) using an ephemeral Tailscale connection instead of manual STUN/TURN configuration. Tailscale is transport only, never a wake-up mechanism. The app establishes the Tailscale-based path for SIP/RTP on demand when a call needs to connect, without a persistent background tunnel.

</domain>

<decisions>
## Implementation Decisions

### Tailscale Integration Model
- **Model:** Ephemeral, on-demand Tailscale connection — NOT a persistent background tunnel
- **Trigger:** Tailscale path established on-demand when a call needs to connect (after push wakeup and call acceptance)
- **Teardown:** Tailscale connection torn down after call ends (or during handoff re-negotiation)
- **Comparison vs STUN/TURN:** No manual STUN/TURN config needed from user; Tailscale handles NAT traversal natively; but Tailscale keys must be configured once in both app and HA-Phone box

### Tailscale Key Management
- **User input:** User enters their Tailscale Auth Key (or OAuth login) once in the HA-Phone Dashboard and once in the App Settings — never re-entered unless key rotation
- **Key type:** Auth Key (stable, machine identity) vs Ephemeral Node Registration (each device registers separately) — decided: Auth Key for simplicity, works with mesh topology
- **Storage:** Software-backed Keychain (iOS) / Keystore (Android) — same as device Credentials storage from Phase 3
- **Rotation:** Infrequent — user regenerates Auth Key in Tailscale admin console; new key entered in both apps; old key deprecated

### Tailscale ↔ PJSIP ICE Integration
- **Mechanism:** Tailscale provides its own NAT traversal via the Tailscale subnet mesh / exit node / direct mesh
- **PJSIP interaction:** PJSIP's ICE agent uses the Tailscale virtual interface (tailscale0 / tun0) as a candidate source
- **Candidate generation:** PJSIP gathers ICE candidates on the Tailscale IP address; SIP Offer/Answer includes `tailscale-candidate` m-line attribute (custom SDES extension) or standard `ufrag/pwd` with Tailscale IP in connection data
- **ICE/DTLS-SRTP:** Standard PJSIP ICE/DTLS-SRTP flow works over Tailscale — the virtual Tailscale interface appears as a regular network interface to the OS and PJSIP
- **Fallback:** If Tailscale is disconnected/unavailable, fall back to existing manual STUN/TURN configuration (still present as fallback, not removed)

### Multi-Device Considerations (per Extension)
- **Per-device Tailscale nodes:** Each registered device gets its own Tailscale node identity — this is important for the multi-device ring pattern from Phase 4
- **Key sharing:** Same Tailscale Auth Key works across all devices of one extension (mesh topology); each device independently establishes its own Tailscale connection
- **Coordination:** When Device A answers a call, it establishes Tailscale path; when Device B should also participate (e.g., attended transfer), Device B establishes its own Tailscale path independently
- **Handoff resilience:** During WiFi→cellular handoff, Tailscale re-routes the virtual IP seamlessly; PJSIP re-gathers ICE candidates on the new interface without dropping the SIP session

### On-Demand Connection Flow
1. Call comes in → Push wakeup → User answers
2. After call acceptance: App establishes Tailscale connection on-demand for SIP/RTP
3. PJSIP ICE gathers candidates on Tailscale IP
4. SIP session set up over Tailscale path
5. Media flows over Tailscale encrypted tunnel
6. Call ends → App tears down Tailscale connection (or keeps minimal keepalive, ≤ 5min idle timeout)
7. If new call comes during active call: Steps 2-4 repeat for the new call (parallel Tailscale paths possible)

### Fallback Configuration
- **Manual STUN/TURN still present:** Tailscale is the preferred primary transport; if Tailscale is unavailable (key expired, app background-killed, etc.), the app falls back to the existing STUN/TURN config from Phase 2
- **User notification:** "Tailscale-Verbindung nicht verfügbar — es wird auf STUN/TUReturnfallback gearbeitet — Erreichbarkeit may eingeschränkt sein"
- **Configuration:** TURN server details (from Phase 2 D-08: no STUN/TURN in Phase 2, but now re-introduced as fallback) stored in HA-Phone Dashboard; user configures once if they want fallback

### Security & Privacy
- **Tailscale credentials:** Only the Auth Key; Tailscale does NOT see SIP call content; only metadata (connection established, duration, bandwidth)
- **No permanent tunnel:** The Tailscale SOCKS proxy / exit node is NOT run in permanent background; only ephemeral per-call connection
- **Key rotation:** Regular key rotation recommended; old keys invalidated on next entry
- **Local network preference:** If user is on same local LAN as HA-Phone box, Tailscale may route through direct peer connection (LAN speeds, no exit node needed)

### Configuration Flow
1. **HA-Phone Dashboard:** Admin enters Tailscale Auth Key → saved in HA-Phone box config
2. **App Settings:** User enters same Tailscale Auth Key (or signs in with Tailscale account) → saved in app Keychain/Keystore
3. **First call after provisioning:** App establishes Tailscale connection on demand
4. **Subsequent calls:** App reuses stored Auth Key; if key expired, user prompted to re-enter
5. **Key rotation:** User enters new Auth Key in both Dashboard and App; old key deprecated after next successful connection

## Exit Criteria (Phase 5 Planning)

- Tailscale on-demand connection established after call acceptance
- PJSIP ICE candidates include Tailscale virtual interface
- Call survives WiFi→cellular handoff (tested on Pixel emulator + real devices)
- Fallback to STUN/TURN works if Tailscale unavailable
- User has entered Tailscale Auth Key once in both Dashboard and App
- Multi-device per Extension: each device independently establishes Tailscale path

## Research References

- `.planning/research/STACK.md` — Tailscale integration points, PJSIP over Tailscale, NAT traversal patterns
- `.planning/research/PITFALLS.md` — Tailscale Pitfalls, Pitfall 8 (Tailscale over Cellular), Pitfall 9 (Multi-device Tailscale keys)
- `.planning/PROJECT.md` — Constraints (zero-budget, native only, Tailscale transport-only not wake mechanism)
- `.planning/REQUIREMENTS.md` — OPS-03 traceability
- `.planning/ROADMAP.md` — Phase 5: Tailscale Transport Hardening
- ENTWICKLUNGSPLAN.md §10 (Backend-Schnittstellen), §12 (Entwicklungsphasen — Phase 5: Tailscale Transport Hardening), §13 (Testmatrix — Netzwerkwechsel)

## Depends On

- Phase 2: PJSIP Audio/Media Core — SIP core must be functional and able to use custom ICE candidates (Tailscale IPs)
- Phase 3: QR Provisioning & Device Management — Devices must be provisioned and registered before Tailscale can be associated with them
- HA-Phone Backend: Tailscale Auth Key stored in box config; Fallback STUN/TURN config present
- CONTEXT.md: Device identity, multi-device per Extension model, mTLS credentials

## Carried-Forward Decisions from Prior Phases

- D-11 (Phase 1): Zero-budget — Tailscale Auth Key is free (Tailscale Free Tier); no extra cost for infrastructure; Ephemeral on-demand model avoids persistent tunnel costs
- D-15/D-16/D-17/D-18 (Phase 2): iOS structurally verified; Tailscale iOS SDK integration tested on Pixel/Android first; iOS real-device testing deferred if it requires additional Apple Developer costs (but Tailscale has free tier, so may be different)
- OpenAPI-Codegen (Phase 2/3/4): Tailscale config API endpoints generated from HA-Phone schema → both iOS and Android clients get consistent config UI
- D-09 (Phase 2): Network-switch resilience — Tailscale re-route behavior during WiFi→cellular handoff is a key enabler for this feature
- Phase 4 Diagnostics (04-03): Tailscale connection status will be added to the Diagnostics screen (Push, SIP, Permissions, Calls, + Tailscale status)