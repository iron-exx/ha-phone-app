---
phase: 2
slug: pjsip-audio-media-core
status: planned
nyquist_compliant: true
wave_0_complete: true
created: 2026-08-04
updated: 2026-08-04
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
| 02-04-T1 | 04 (Android) | 2 | CALL-01 | — | Codec priority list includes opus/g722/pcma/pcmu after PJSIP init | unit | `./gradlew testDebugUnitTest --tests "*CodecConfigTest*"` | ✅ planned | ⬜ pending execution |
| 02-05-T1/T3 | 05 (iOS) | 2 | CALL-01 | — | iOS SipCallController implements the same 5-op contract (structural/Simulator-only per D-15/D-16) | unit (XCTest via CI) | `xcodebuild test -scheme HAPhoneTestApp -destination 'platform=iOS Simulator,name=iPhone 16'` | ✅ planned | ⬜ pending execution |
| 02-06-T3 | 06 (Android) | 3 | CALL-01 | — | Audio Routing renders a real DropdownMenu bound to `CallControlScope.availableEndpoints`; tapping an entry calls `requestEndpointChange` (not a stub) | compile + manual (Bluetooth routing switch) | `./gradlew :app:compileDebugKotlin`; manual row in `PHASE2_MANUAL_TEST_PROCEDURE.md` | ✅ planned | ⬜ pending execution |
| 02-08-T1/T2 | 08 | 4 | CALL-01 | — | Real two-way audio over Opus/G.722/G.711 against the HA-Phone box | manual-only | `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md` | ✅ planned | ⬜ pending execution |
| 02-04-T3 | 04 (Android) | 2 | CALL-02 | — | `sendDtmf` invoked with correct digit/method on keypad press | unit | `./gradlew testDebugUnitTest --tests "*DtmfControllerTest*"` | ✅ planned | ⬜ pending execution |
| 02-06-T1 | 06 (Android) | 3 | CALL-03 | — | Dialpad-entered number produces correct `sip:` URI passed to `makeCall` | unit | `./gradlew testDebugUnitTest --tests "*DialpadTest*"` | ✅ planned | ⬜ pending execution |
| 02-07-T1/T2 | 07 (iOS) | 3 | CALL-03 | — | iOS DialedNumberState/DialpadView + CXStartCallAction outgoing-call reporting | unit (XCTest via CI) + structural | `xcodebuild test ...` (CI) | ✅ planned | ⬜ pending execution |
| 02-04-T3 | 04 (Android) | 2 | CALL-04 | — | Hold/unhold and blind-transfer target parsing produce correct `CallOpParam`/URI | unit | `./gradlew testDebugUnitTest --tests "*CallControlTest*"` | ✅ planned | ⬜ pending execution |
| 02-08-T1/T2 | 08 | 4 | CALL-05 | — | Registration only exists during call lifetime (register-on-call-start, unregister-on-call-end) | manual-only (corrected: `pjsip show contacts`/`pjsip show aor`, NOT `sip show registry`) | manual CLI check against Asterisk | ✅ planned | ⬜ pending execution |
| 02-01-T2/T3 | 01 | 1 | Cross-repo (HA-Phone) | T-2-01 | New `[transport-tls]` stanza + test extension provisioned and Asterisk starts cleanly | integration (pytest) + human-action checkpoint | `python3 -m pytest backend/tests/test_cont_init_tls.py -x`; `asterisk -rx "pjsip show transports"` after `cont-init.d` runs | ✅ planned | ⬜ pending execution |
| 02-04-T1 | 04 (Android) | 2 | Security (V5) | T-2-08 | Dialpad-entered numbers sanitized to `[0-9+*#]` before embedding in a SIP URI (dial/DTMF/transfer) | unit | `./gradlew testDebugUnitTest --tests "*DialpadSanitizeTest*"` | ✅ planned | ⬜ pending execution |
| 02-04-T2 | 04 (Android) | 2 | CALL-01 (D-09) | — | `NetworkChangeHandler.onNetworkAvailable()` invokes `IpChangeNotifier.handleIpChange()` (mid-call network-switch resilience) | unit (fake notifier) | `./gradlew testDebugUnitTest --tests "*NetworkChangeHandlerTest*"` | ✅ planned | ⬜ pending execution |
| 02-05-T3 | 05 (iOS) | 2 | CALL-01 (D-09) | — | `NetworkChangeHandler.onPathSatisfied()` invokes `IpChangeNotifying.handleIpChange()` (mid-call network-switch resilience) | unit (mock notifier, XCTest via CI) | `xcodebuild test ...` (CI) | ✅ planned | ⬜ pending execution |
| 02-04-T3 / 02-05-T3 | 04 / 05 | 2 | CALL-01..05 (config) | — | Real HA-Phone host/extension/password from Plan 01's checkpoint substituted into app config; no `<ha-phone-host>` placeholder survives | grep gate | `grep -Ec "<ha-phone-host>|TODO.*Plan 01" HAPhoneTestApplication.kt` / `HAPhoneTestAppApp.swift` returns 0 | ✅ planned | ⬜ pending execution |
| 02-08-T3 | 08 | 4 | D-09 | — | Mid-call WiFi-to-cellular network-switch outcome recorded (pass/fail/partial), not assumed | manual-only | `02-PHASE-SIGNOFF.md` D-09 section | ✅ planned | ⬜ pending execution |

*Status: ⬜ pending execution · ✅ green · ❌ red · ⚠️ flaky*
*Task/plan/wave IDs above are synced to the 8 finalized PLAN.md files (02-01 through 02-08) as of this revision. "✅ planned" means the task/test exists in a committed PLAN.md; execution status flips to ✅ green/❌ red only after `/gsd-execute-phase` runs.*

---

## Wave 0 Requirements

All Wave 0 (and Wave 1/2/3) test scaffolds are now defined directly in the finalized PLAN.md files rather than left as future work -- listed here with their owning plan for traceability:

- [x] `android-app/app/src/test/java/de/haphone/app/test/sip/CodecConfigTest.kt` — CALL-01 codec priority list (Plan 04, Task 1)
- [x] `android-app/app/src/test/java/de/haphone/app/test/sip/DtmfControllerTest.kt` — CALL-02 (Plan 04, Task 3)
- [x] `android-app/app/src/test/java/de/haphone/app/test/sip/DialpadSanitizeTest.kt` — Security V5 sanitize contract (Plan 04, Task 1)
- [x] `android-app/app/src/test/java/de/haphone/app/test/sip/CallControlTest.kt` — CALL-04/CALL-05 lifecycle (Plan 04, Tasks 2-3)
- [x] `android-app/app/src/test/java/de/haphone/app/test/sip/NetworkChangeHandlerTest.kt` — D-09 mid-call network-switch seam (Plan 04, Task 2)
- [x] `android-app/app/src/test/java/de/haphone/app/test/sip/DialpadTest.kt` — CALL-03 (shared dialpad component, reused for D-13/D-14) (Plan 06, Task 1)
- [x] `ios-app/HAPhoneTestAppTests/DialStringTests.swift` — iOS sanitize contract (Plan 05, Task 1)
- [x] `ios-app/HAPhoneTestAppTests/SipCallControllerTests.swift` — iOS-side equivalents, Simulator-only per D-16 (Plan 05, Task 3)
- [x] `ios-app/HAPhoneTestAppTests/NetworkChangeHandlerTests.swift` — D-09 mid-call network-switch seam (Plan 05, Task 3)
- [x] `ios-app/HAPhoneTestAppTests/DialedNumberStateTests.swift` — iOS dialpad state (Plan 07, Task 1)
- [x] `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md` (new, mirrors Phase 1's `MANUAL_TEST_PROCEDURE.md`) — CALL-01/CALL-05/D-09 manual steps with the corrected `pjsip show contacts`/`pjsip show aor`/`pjsip show endpoint` commands (Plan 08, Task 1)
- [x] Cross-repo pytest in `~/projects/Ha-Phone/ha-phone/backend/tests/test_cont_init_tls.py` — TLS transport/test-extension provisioning path, checks `[transport-tls]` stanza content and idempotency guard (Plan 01, Task 2)

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

- [x] All tasks have `<automated>` verify or Wave 0 dependencies (manual-only rows for CALL-01 real-audio/CALL-05/D-09-outcome are explicitly flagged `manual-only`, matching Phase 1's precedent)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (all listed above now exist as concrete tasks in committed PLAN.md files)
- [x] No watch-mode flags
- [x] Feedback latency < 60s (unit-only quick path unchanged)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** task/wave IDs synced to the 8 finalized PLAN.md files (02-01 through 02-08) as of this revision (iteration 1). Re-review after `/gsd-execute-phase` flips per-row execution status from "pending execution" to green/red.
