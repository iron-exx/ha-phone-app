# Phase 1: Push-Wakeup Proof of Concept - Context

**Gathered:** 2026-08-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Prove that a platform push (APNs on iOS, FCM on Android) reliably wakes the app into native call UI (CallKit / self-managed ConnectionService) on real devices — closed app, locked device, backgrounded — before any SIP media, QR provisioning, or push-relay infrastructure exists. No real PBX call flow yet: a standalone test-trigger script sends the push directly. Success is judged qualitatively by the developer, not against a fixed test-count target.

</domain>

<decisions>
## Implementation Decisions

### Test-Geräte-Matrix
- **D-01:** iOS testing device is the user's own current-generation iPhone on current iOS.
- **D-02:** Android testing device is a Pixel (stock Android) only — no Samsung/Xiaomi/other aggressive-OEM device currently available.
- **D-03 (flagged concern):** ROADMAP.md's Phase 1 success criterion #3 ("verified on at least one non-Pixel OEM device") is not satisfiable with the current device matrix. Planner should either scope the criterion down to "Pixel only, OEM diversity deferred" or flag it as blocked pending a borrowed/purchased test device — do not silently drop it.

### Test-Trigger-Mechanismus
- **D-04:** Phase 1 does not touch HA-Phone (Asterisk/FastAPI) at all. A standalone test-trigger script/CLI, living in the ha-phone-app repo (e.g. `tools/`), sends VoIP push (APNs) / high-priority data push (FCM) directly to the test device.
- **D-05:** No real inbound call via Asterisk AMI/ARI in this phase — that end-to-end wiring is deferred to a later phase once the SIP core (Phase 2) and PBX-side call-state (Phase 4) exist.

### Inhalt der Anrufanzeige im Prototyp
- **D-06:** The native call screen shows a fixed placeholder ("HA-Phone Testanruf") — no real caller-ID/name resolution in this phase (that's Phase 4's PBX-side phonebook lookup).
- **D-07:** The push payload is signed from the start (user chose to design/implement the signing scheme now, e.g. ed25519, rather than adding it retroactively in Phase 6 when the multi-tenant relay is formalized). Planner/researcher should treat "define and implement the push-event signing envelope" as in-scope for Phase 1, even though the full multi-tenant relay is out of scope until Phase 6.

### Umgang mit verspätetem/fehlgeschlagenem Push
- **D-08:** No retry/timeout logic in Phase 1. Failed or late push delivery is logged (sent timestamp vs. received/reported timestamp) in the test script, not automatically retried. Retry/hardening is explicitly deferred to Phase 4/5.
- **D-09:** Acceptance is judged informally ("feels reliable" after manual test calls across app states: open, backgrounded, locked, overnight standby) — no fixed numeric test-count/success-rate target for Phase 1's Definition of Done.

### iOS Build Environment (no local Mac available)
- **D-10:** The user has no Mac/Xcode available locally. iOS is built via a **GitHub Actions macOS runner** (Fastlane or plain `xcodebuild`), signed with an Apple Developer account (already planned per PROJECT.md), and distributed via **TestFlight** for on-device testing. The user installs/updates the build through the TestFlight app on their own iPhone — there is no local Xcode debug-install loop. Planner must include CI pipeline setup (GitHub Actions workflow, code signing/provisioning profile, TestFlight upload) as an explicit Phase 1 task, not an assumed prerequisite. Iteration speed will be CI-round-trip-bound (minutes per build), not instant — factor this into task sequencing and expectations.
- **Consequence for testing:** Since VoIP push cannot be tested in the iOS Simulator under any circumstance (confirmed in RESEARCH.md), and there is no local device debugging via Xcode, all iOS push/CallKit verification happens via TestFlight builds installed on the user's physical iPhone. Console log inspection for debugging will rely on either TestFlight crash/feedback reports or a remote-logging approach (e.g., the app posting debug events to a simple endpoint) rather than a live Xcode console — planner/researcher should account for this when designing the test-trigger script's feedback loop.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Stack & Platform Constraints
- `.planning/research/STACK.md` — PJSIP version/build guidance, PushKit/CallKit and FCM/Telecom library choices, what NOT to use (not fully needed in Phase 1 beyond the push/CallKit sections, but sets the platform baseline)
- `.planning/research/PITFALLS.md` — Hard platform rules for this phase: iOS CallKit synchronous-report requirement (token revocation risk since iOS 26 SDK on repeated failure), Android Play Console "calling app" declaration (required since Jan 2025 for full-screen-intent), FCM's 7-day priority-downgrade mechanism, OEM background-kill patterns
- `.planning/research/ARCHITECTURE.md` — Confirms Phase 1 can stub the relay with direct APNs/FCM calls from a dev script; call-hold/call-ID logic belongs to the PBX, not this phase
- `ENTWICKLUNGSPLAN.md` §3 (Zielplattformen), §6 (Ablauf eines eingehenden Anrufs), §11 (Sicherheit — push signing requirement: "Ein Push darf allein keinen Anruf übernehmen... Signatur"), §13 (Testmatrix — informs but does not mandate the app-state test list used in D-09)

### Project Constraints
- `.planning/PROJECT.md` — Constraints section (native Swift/Kotlin, no Flutter/RN; Tailscale is transport-only, never wake mechanism — irrelevant to Phase 1 but do not let researcher/planner conflate the two)

No other external specs — requirements fully captured in decisions above.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
None — greenfield repository, no existing code in ha-phone-app.

### Established Patterns
None yet established.

### Integration Points
None in this phase — Phase 1 explicitly does not integrate with HA-Phone (see D-04, D-05).

</code_context>

<specifics>
## Specific Ideas

- Test-trigger tooling lives in the app repo itself (e.g. `tools/`), not in HA-Phone — keeps the repo boundary clean until the SIP/provisioning phases land.
- Push payload signing (D-07) should be designed with the eventual multi-tenant relay (Phase 6) in mind, even though only a single dev signing key is needed now — avoid a payload format that would require a breaking change later.

</specifics>

<deferred>
## Deferred Ideas

- Non-Pixel Android OEM test coverage (Samsung/Xiaomi) — deferred until a suitable device is available; flagged as an open concern (D-03), not silently dropped.
- Retry/timeout handling for missed or late pushes — explicitly deferred to Phase 4/5 hardening (D-08).
- Real inbound-call-triggers-push wiring via Asterisk AMI/ARI — deferred until Phase 2 (SIP core) and Phase 4 (call-state orchestration) exist.

### Reviewed Todos (not folded)
None — no pending todos existed for this project yet.

</deferred>

---

*Phase: 1-Push-Wakeup Proof of Concept*
*Context gathered: 2026-08-01*
