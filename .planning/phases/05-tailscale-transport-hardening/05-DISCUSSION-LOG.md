# Phase 5: Tailscale Transport Hardening - Discussion Log

**Phase:** 05-Tailscale-Transport-Hardening
**Discussion Date:** 2026-08-18
**Discussion Mode:** Default (interactive)

## Areas Discussed & Decisions

### 1. Tailscale Integration Model
- **Decision:** Ephemeral, on-demand Tailscale connection — NOT a persistent background tunnel
- **Rationale:** Matches project core principle (no permanent SIP registration, push-first); avoids battery drain; Tailscale mesh topology handles NAT traversal natively
- **Gray Areas Considered:**
  - Persistent vs. on-demand: Decision made for on-demand; persistent considered but rejected as violating core principle
  - Key type: Auth Key vs Ephemeral Node Registration — Auth Key chosen for simplicity; Ephemeral considered but adds complexity of per-device registration without significant benefit

### 2. Tailscale Key Management
- **Decision:** User enters Tailscale Auth Key once in both Dashboard and App; key rotation infrequent; stored in Keychain/Keystore
- **Rationale:** Simple user experience; one-time setup; infrequent rotation needed; matches zero-budget constraint
- **Gray Areas Considered:**
  - Auth Key vs OAuth login — Auth Key chosen (simpler, no Google/Twitter account needed); OAuth considered but adds auth complexity
  - Cloud vs local key storage — Cloud Tailscale account optional; local Keychain/Keystore storage chosen (private, no third-party server needed)

### 3. Tailscale ↔ PJSIP ICE Integration
- **Decision:** PJSIP ICE gathers candidates on Tailscale virtual interface; standard ICE/DTLS-SRTP flow works over Tailscale; custom `tailscale-candidate` m-line attribute for enhanced routing
- **Rationale:** Leverages existing PJSIP ICE flow; minimal new code; Tailscale IP appears as regular interface; custom attribute provides enhanced routing info if needed
- **Gray Areas Considered:**
  - Standard ICE vs custom m-line attribute — Standard ICE chosen first (less code); custom attribute added for future enhancements (Phase 6)
  - Candidate priority — Tailscale candidates given higher priority than Internet candidates (better NAT traversal); Internet candidates as fallback

### 4. Multi-Device Considerations
- **Decision:** Per-device Tailscale nodes; same Auth Key works across all devices (mesh topology); each device independently establishes connection
- **Rationale:** Matches Phase 4 multi-device ring pattern; each device needs its own path; shared key simplifies user onboarding
- **Gray Areas Considered:**
  - Shared vs per-device keys — Shared Auth Key chosen (user enters once); per-device keys considered but adds user burden; each device still has independent Tailscale session
  - Attended transfer during Tailscale call — Decision: each device establishes its own Tailscale path independently; no special coordination needed beyond Phase 4 call-state machine

### 5. On-Demand Connection Flow
- **Decision:** 7-step flow: Call → Answer → On-demand Tailscale establish → ICE gather → SIP set up → Media over Tailscale → Call end → Tear down
- **Rationale:** Clear, predictable flow; no persistent background tunnel; user understands when Tailscale is active (UI indicator)
- **Gray Areas Considered:**
  - Keepalive vs tear-down — On-demand tear-down chosen (no keepalive = no battery drain); keepalive considered but adds complexity and battery cost
  - Parallel calls — Decision: parallel Tailscale paths possible (each call gets its own ephemeral connection); no session merging

### 6. Fallback Configuration
- **Decision:** Manual STUN/TURN present as fallback; Tailscale primary; user notified if falling back
- **Rationale:** Ensures reliability; Tailscale may fail (key expired, background-killed); fallback preserves connectivity; user notified transparently
- **Gray Areas Considered:**
  - Fallback auto vs user prompt — Auto-fallback chosen (seamless); user prompt considered but adds interruption; "Tailscale unavailable → fall back to STUN/TURN" message in Diagnostics
  - TURN details in fallback — Phase 2 D-08 (no STUN/TURN in Phase 2) now re-introduced as optional fallback; user may configure or leave blank (then pure Tailscale-only mode)

### 7. Security & Privacy
- **Decision:** TAuth Key only; Tailscale does not see SIP content; no permanent tunnel; key rotation recommended
- **Rationale:** Minimal attack surface; respects privacy; matches zero-budget; user controls key rotation
- **Gray Areas Considered:**
  - Tailscale relay vs direct peer — Tailscale direct peer preferred (faster, lower latency); relay used when direct peer not possible (NAT); relay metadata logged but call content not exposed
  - Call content encryption — SIP over TLS + SRTP already encrypts; Tailscale adds transport-layer encryption (already covered by SRTP; Tailscale adds outer envelope encryption but this is minimal benefit over existing SIP/SRTP encryption)

## Checkpoint
All 7 gray areas discussed completely. All decisions captured in 05-CONTEXT.md. No remaining unresolved questions for Phase 5 discussion.

---

*Checkpoint file to be written after CONTEXT.md creation. Discussion log accumulated per-area with user selections.*