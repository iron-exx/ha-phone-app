# Phase 2: PJSIP Audio/Media Core - Context

**Gathered:** 2026-08-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Users can carry a stable two-way call, in and out, with core telephony controls (mute, audio routing, DTMF, hold, blind transfer), over a SIP session that only exists for the duration of a call. Covers CALL-01 through CALL-05. Built on top of Phase 1's proven push-wake path — CallKit (`CallProvider.swift`) and self-managed Telecom `ConnectionService` (`CallRegistration.kt`) are the existing scaffolding PJSIP audio plugs into; this phase does not rebuild call reporting/wake, only adds the SIP/media layer behind it.

</domain>

<decisions>
## Implementation Decisions

### PJSIP-Build-Strategie
- **D-01:** PJSIP is built officially from source (not the community CocoaPod/AAR or third-party prebuilt binaries) — per STACK.md's recommendation.
- **D-02:** Matching Phase 1's pattern: iOS build runs on a GitHub Actions macOS runner; Android build runs here in the sandbox.

### Test-SIP-Server
- **D-03:** Phase 2 develops and tests against the real HA-Phone box (`~/projects/Ha-Phone`, Asterisk 22 LTS), not a throwaway local Asterisk or a public SIP test service — most realistic environment, matches actual codecs/routing/NAT config the shipped app will face.
- **D-04:** A dedicated test extension is created on the HA-Phone box for Phase 2 (not one of the active 10-99 extensions) — avoids collisions with real household calls during unstable development.
- **D-05:** Test devices (iOS Simulator / Android emulator / sandbox) reach the HA-Phone box over the local network only during Phase 2 — no Tailscale, no port-forwarding. Matches the roadmap's sequencing (transport hardening is Phase 5's job, not Phase 2's).
- **D-06:** Existing HA-Phone extensions run plain UDP (`sip_tls_port=-1` in `extensions.py`, hardcoded `transport=udp` in the proxy/route headers) — but the new Phase 2 test extension will use **TLS/SRTP instead**, deviating from that default. **Cross-repo consequence:** this requires changes to the separate `Ha-Phone` repo (enabling `sip_tls_port`, provisioning a certificate, adding a `transport-tls` extension template) before the first PJSIP test call can happen — not just work inside `ha-phone-app`. Planner should scope this HA-Phone-side setup work explicitly, not assume it's a given.

### Codec- & Netzwerk-Umgebung
- **D-07:** All three codecs named in CALL-01 (Opus, G.722, G.711) are verified for real against the HA-Phone box in Phase 2 — full coverage now, not phased within Phase 2.
- **D-08:** No STUN/TURN setup in Phase 2. Local-network-only testing (D-05) has no NAT to traverse, and ICE/STUN/TURN belongs to Phase 5 (Tailscale Transport Hardening), which will replace/subsume it. Avoids duplicate work.
- **D-09:** Mid-call network-switch handling (WiFi↔cellular, ICE restart per PITFALLS.md Pitfall 7) **is in scope for Phase 2**. Rationale: PITFALLS.md maps this to an old ENTWICKLUNGSPLAN "Phase 3 audio hardening" that no longer exists in the current ROADMAP — Phase 3 is now QR Provisioning. Since there's no later phase that would otherwise pick this up, and CALL-01 requires a "stable" two-way call, network-switch resilience is treated as part of Phase 2's stability bar, not deferred.
- **D-10:** The transient SIP registration behavior (D-05/CALL-05 from Phase 1: registration only exists for the duration of a call, no persistent background registration) is verified manually via network sniff / Asterisk CLI (`sip show registry`) during test calls — not an automated test. Consistent with Phase 1's informal, qualitative acceptance style (D-09 in Phase 1's context).

### Umfang Telefonie-UI
- **D-11:** Phase 2 builds real UI for exactly the 5 CALL-01..05 controls (mute, audio routing/speaker, DTMF keypad, hold, blind transfer, outgoing-call entry) — no more, no less. Stays test-harness-flavored like Phase 1's placeholder call screen, but these specific controls get real UI, not just debug buttons.
- **D-12:** Outgoing call target entry (CALL-03) uses a classic numeric dialpad (not a plain text field) — closer to the app's eventual end state, even though contacts/address book don't exist until Phase 3 (QR provisioning).
- **D-13:** The same dialpad component is reused in-call for sending DTMF tones (CALL-02) — one UI building block for both dialing and DTMF, not two.
- **D-14:** The same dialpad component is also reused for entering the blind-transfer target (CALL-04) — consistent with D-13's reuse decision.

### iOS-Verifikationsgrenze
- **D-15:** iOS is built in parallel with Android in Phase 2, not deferred. Android gets full real-hardware verification (matching Phase 1's pattern); iOS stays structurally/Simulator-verified only — PJSIP build + audio-path unit tests run, no real call on a physical iPhone. This directly extends Phase 1's D-11 (zero-budget Apple Developer Program constraint) into Phase 2.
- **D-16:** "iOS verified in Simulator" means structure/unit-test level only — PJSIP builds, SIP signaling/registration is checked — **not** real audio I/O through the Simulator's host-Mac microphone/speakers, even though modern Simulators support that. Matches Phase 1's precedent (CallKit reporting was verified structurally, not via a real call).
- **D-17:** Phase 2 produces its own `02-PHASE-SIGNOFF.md` (mirroring Phase 1's `01-PHASE-SIGNOFF.md` pattern) that explicitly documents the iOS real-device audio verification gap as an accepted, carried-forward item — not silently marked done.
- **D-18:** The sign-off names a concrete resumption trigger: real iOS audio verification is picked back up specifically when the user enrolls in the Apple Developer Program ($99/yr) — not left as an undated "someday" item.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Stack & Platform Constraints
- `.planning/research/STACK.md` — PJSIP 2.16 build guidance (official source build, iOS/Android build instructions), what NOT to use (community CocoaPods/AARs)
- `.planning/research/PITFALLS.md` — Pitfall 7 (NAT/TURN and mid-call network-switch handling, now in-scope per D-09), Pitfall-to-Phase Mapping table (note: its phase numbers use the old ENTWICKLUNGSPLAN numbering, not the current ROADMAP — Phase 2 here corresponds to its "Phase 3 Produktionsfähige Audiotelefonie")
- `.planning/research/ARCHITECTURE.md` — Pattern 1 (PBX holds the call, push is just a doorbell) confirms PJSIP/SIP logic belongs in the app, call-hold/transfer semantics come from the PBX side

### Prior Phase Decisions
- `.planning/phases/01-push-wakeup-proof-of-concept/01-CONTEXT.md` — D-11 (zero-budget Apple Developer constraint, directly extended by D-15/D-16 here), D-04/D-05 (test-trigger boundary, superseded now that real SIP/media exists)
- `.planning/phases/01-push-wakeup-proof-of-concept/01-PHASE-SIGNOFF.md` — the sign-off pattern D-17 explicitly replicates; also documents that Phase 1's iOS CI has never actually run on GitHub's runners (relevant since Phase 2 CI depends on the same pipeline)

### Project Constraints
- `ENTWICKLUNGSPLAN.md` §8 (Audio/Codec-Handling), §13 (Testmatrix)
- `.planning/PROJECT.md` — Constraints section (native Swift/Kotlin, PJSIP/PJSUA2 as shared SIP core, Tailscale is transport-only and belongs to Phase 5 not this phase)

### HA-Phone Box (cross-repo, real Asterisk backend)
- `~/projects/Ha-Phone/ha-phone/backend/models.py` — `transport` field (`udp | tcp | tls`) on the trunk/extension model, relevant to D-06's TLS/SRTP decision
- `~/projects/Ha-Phone/ha-phone/backend/routers/extensions.py` — current extension provisioning hardcodes `transport=udp` and disables `sip_tls_port` (-1); D-06 requires changing this for the new Phase 2 test extension
- `~/projects/Ha-Phone/ha-phone/backend/conf_templates/pjsip_extensions.conf.j2`, `pjsip_trunk.conf.j2` — Asterisk PJSIP config templates the test extension's TLS setup will need to follow/extend

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `android-app/app/src/main/java/de/haphone/app/test/CallRegistration.kt` — wraps `androidx.core.telecom.CallsManager`, already registers the app as a self-managed calling app and exposes a `CallControlScope` receiver (with `disconnect()`) on call registration. PJSIP audio hooks into this via the `onRegistered` callback's `CallControlScope`.
- `ios-app/HAPhoneTestApp/CallProvider.swift` — the existing CallKit `CXProvider` wrapper from Phase 1; PJSIP audio session setup must coordinate with CallKit's `didActivate:`/`didDeactivate:` audio session callbacks (per STACK.md's "do not configure the audio session outside those callbacks" warning).
- `tools/push_trigger.py`, `tools/envelope.py` — Phase 1's signed push-envelope tooling; Phase 2's outbound test calls don't need push at all (no incoming push involved for MO calls), but inbound test calls still route through this same envelope path.

### Established Patterns
- Zero-budget constraint (D-11 from Phase 1) — no paid Apple Developer Program, no paid Google Play Console. Directly shapes D-15/D-16/D-17/D-18 here.
- Phase sign-off documents (`0N-PHASE-SIGNOFF.md`) as the project's established way to carry forward accepted, undone-but-not-hidden gaps — D-17 continues this pattern.
- Informal/qualitative acceptance ("feels reliable", per Phase 1's D-09) rather than fixed numeric pass-rate targets — carried into D-10 here.

### Integration Points
- Android: `CallRegistration.reportIncomingCall`'s `onRegistered` callback is where PJSIP media/audio setup attaches, and where `disconnect()` is available if SIP negotiation fails.
- iOS: `CallProvider.swift`'s CXProvider delegate callbacks (`didActivate`/`didDeactivate` on `AVAudioSession`) are where PJSIP's audio session must plug in.
- HA-Phone backend (`~/projects/Ha-Phone`): a new dedicated test extension (D-04) with TLS/SRTP transport (D-06) needs to be provisioned there before any PJSIP test call is possible — this is real cross-repo setup work, not just app-side code.

</code_context>

<specifics>
## Specific Ideas

- The dialpad UI component is deliberately designed for three reuse contexts from day one: outgoing-call dialing (D-12), in-call DTMF (D-13), and blind-transfer target entry (D-14) — one component, three call sites.
- The iOS audio-verification gap should be resolved with a named, concrete trigger ("when Apple Developer Program is active") rather than a vague "later" — same rigor as Phase 1's D-11 documentation.

</specifics>

<deferred>
## Deferred Ideas

- STUN/TURN and full NAT traversal — explicitly deferred to Phase 5 (Tailscale Transport Hardening), which replaces/subsumes this rather than layering Tailscale on top of a separately-built STUN/TURN setup (D-08).
- Real iOS physical-device audio verification — deferred until the user enrolls in the Apple Developer Program (D-18); tracked via `02-PHASE-SIGNOFF.md`, not silently dropped.
- Full contacts/address book for dialing — belongs to Phase 3 (QR Provisioning & Device Management); Phase 2's dialpad (D-12) is a deliberate stand-in, not a preview of Phase 3's UI.
- Automated regression test for transient SIP registration — the manual verification in D-10 is accepted for Phase 2; an automated guard against future regression was raised but not adopted now (no explicit future phase assigned — worth revisiting if a hardening/regression-test phase is added later).

### Reviewed Todos (not folded)
None — no pending todos matched Phase 2's scope (`todo.match-phase` returned zero matches).

</deferred>

---

*Phase: 2-PJSIP Audio/Media Core*
*Context gathered: 2026-08-04*
