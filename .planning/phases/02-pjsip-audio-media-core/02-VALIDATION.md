---
phase: 2
slug: pjsip-audio-media-core
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-04
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework (Android)** | JUnit 4 (`junit:junit:4.13.2`, confirmed in `EnvelopeVerifierTest.kt`) |
| **Framework (iOS)** | XCTest (confirmed in `PushHandlerTests.swift`/`EnvelopeVerifierTests.swift`/`DiagnosticsLogTests.swift`) |
| **Config file (Android)** | `android-app/app/build.gradle.kts` |
| **Config file (iOS)** | `ios-app/project.yml` (xcodegen-managed, no Podfile) |
| **Quick run command (Android)** | `./gradlew testDebugUnitTest` |
| **Quick run command (iOS)** | `xcodebuild test -scheme HAPhoneTestApp -destination 'platform=iOS Simulator,name=iPhone 16'` (Simulator-only per D-15/D-16) |
| **Full suite command** | Same as quick — no separate full/quick split exists yet in this project |
| **Estimated runtime** | ~30-60s per platform (unit-only, no device/emulator boot in the quick path) |

---

## Sampling Rate

- **After every task commit:** Run `./gradlew testDebugUnitTest` (Android) and/or `xcodebuild test ...` (iOS), whichever platform the task touched
- **After every plan wave that touches SIP signaling:** Run both platforms' unit suites, plus the manual CLI/real-call checks for CALL-01 and CALL-05
- **Before `/gsd-verify-work`:** Full suite green on both platforms + manual verification of CALL-01 (three codecs, real two-way audio) and CALL-05 (transient registration via `pjsip show contacts`/`pjsip show aor`) recorded in `02-PHASE-SIGNOFF.md`
- **Max feedback latency:** ~60 seconds (unit tests only; no emulator/simulator boot required for the quick path)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|--------------------|-------------|--------|
| 02-01-TBD | TBD | 0 | CALL-01 | — | Codec priority list includes opus/g722/pcma/pcmu after PJSIP init | unit | `./gradlew testDebugUnitTest --tests "*CodecConfigTest*"` | ❌ W0 | ⬜ pending |
| 02-01-TBD | TBD | TBD | CALL-01 | — | Audio routing changes propagate to `CallControlScope.currentCallEndpoint` | unit (fake CallControlScope) | `./gradlew testDebugUnitTest --tests "*AudioRoutingTest*"` | ❌ W0 | ⬜ pending |
| 02-01-TBD | TBD | TBD | CALL-01 | — | Real two-way audio over Opus/G.722/G.711 against the HA-Phone box | manual-only | `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md` | ❌ W0 | ⬜ pending |
| 02-01-TBD | TBD | TBD | CALL-02 | — | `sendDtmf` invoked with correct digit/method on keypad press | unit | `./gradlew testDebugUnitTest --tests "*DtmfControllerTest*"` | ❌ W0 | ⬜ pending |
| 02-01-TBD | TBD | TBD | CALL-03 | — | Dialpad-entered number produces correct `sip:` URI passed to `makeCall` | unit | `./gradlew testDebugUnitTest --tests "*DialpadTest*"` | ❌ W0 | ⬜ pending |
| 02-01-TBD | TBD | TBD | CALL-04 | — | Hold/unhold and blind-transfer target parsing produce correct `CallOpParam`/URI | unit | `./gradlew testDebugUnitTest --tests "*CallControlTest*"` | ❌ W0 | ⬜ pending |
| 02-01-TBD | TBD | TBD | CALL-05 | — | Registration only exists during call lifetime (register-on-call-start, unregister-on-call-end) | manual-only (corrected: `pjsip show contacts`/`pjsip show aor`, NOT `sip show registry`) | manual CLI check against Asterisk | manual doc: ❌ W0 | ⬜ pending |
| 02-XX-TBD | TBD | TBD | Cross-repo (HA-Phone) | T-2-01 | New `[transport-tls]` stanza + test extension provisioned and Asterisk starts cleanly | integration (HA-Phone repo) | `asterisk -rx "pjsip show transports"` after `cont-init.d` runs | ❌ W0 (new script logic) | ⬜ pending |
| 02-XX-TBD | TBD | TBD | Security (V5) | T-2-02 | Dialpad-entered numbers sanitized to `[0-9+*#]` before embedding in a SIP URI (dial/DTMF/transfer) | unit | `./gradlew testDebugUnitTest --tests "*DialpadSanitizeTest*"` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*
*Task IDs are TBD — the planner fills in real plan/task IDs and wave numbers when PLAN.md files are created; rows above are seeded directly from RESEARCH.md's Phase Requirements → Test Map so no requirement is dropped between research and planning.*

---

## Wave 0 Requirements

- [ ] `android-app/app/src/test/java/de/haphone/app/test/sip/CodecConfigTest.kt` — CALL-01 codec priority list
- [ ] `android-app/app/src/test/java/de/haphone/app/test/sip/DtmfControllerTest.kt` — CALL-02
- [ ] `android-app/app/src/test/java/de/haphone/app/test/sip/DialpadTest.kt` — CALL-03 (shared dialpad component, reused for D-13/D-14)
- [ ] `android-app/app/src/test/java/de/haphone/app/test/sip/CallControlTest.kt` — CALL-04
- [ ] `ios-app/HAPhoneTestAppTests/SipCallControllerTests.swift` — iOS-side equivalents, Simulator-only per D-16
- [ ] `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md` (new, mirrors Phase 1's `MANUAL_TEST_PROCEDURE.md`) — CALL-01/CALL-05 manual steps with the corrected `pjsip show contacts`/`pjsip show aor`/`pjsip show endpoint` commands
- [ ] Cross-repo smoke check in `~/projects/Ha-Phone` — no test currently exists for the new TLS transport/test-extension provisioning path; needs at least a check that `pjsip.conf` parses and `[transport-tls]` binds

*(Framework install: none needed — XCTest and JUnit 4 are already wired into both projects from Phase 1.)*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Real two-way audio over Opus/G.722/G.711, mic/speaker/Bluetooth routing | CALL-01 | No automated audio-quality harness in this project; requires a real device and real PBX | `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md` — place/receive a call on each codec, verify audibility both directions, verify Bluetooth routing switch |
| Transient SIP registration (register-on-call, unregister-after) | CALL-05 | Registration lifecycle timing isn't practically unit-testable against a real Asterisk registrar | Asterisk CLI: `pjsip show contacts`, `pjsip show aor`, `pjsip show endpoint` before/during/after a test call (corrected from D-10's original `sip show registry`, which doesn't exist on Asterisk 22 — `chan_sip` was removed) |
| iOS real-device audio path | CALL-01 (iOS only) | Zero-budget constraint — no paid Apple Developer Program enrollment yet (Phase 1 D-11) | Deferred; tracked in `02-PHASE-SIGNOFF.md` with resumption trigger = Apple Developer Program enrollment |
| Cross-repo TLS/SRTP test extension boots cleanly on the real HA-Phone box | Cross-repo | Requires the actual Asterisk container restart cycle, not just config-file inspection | Restart the HA-Phone container after `cont-init.d` changes, confirm `pjsip show transports` lists the new `transport-tls` entry with no startup errors |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending — planner to finalize task/wave IDs, then re-review before execution
