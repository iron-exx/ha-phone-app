# Phase 2: PJSIP Audio/Media Core — Sign-Off

**Phase status:** Proceeding to Phase 3 with open gaps explicitly accepted below, not silently resolved. Per D-17, this sign-off exists specifically to carry those gaps forward by name, each with a concrete resumption trigger — matching the precedent `01-PHASE-SIGNOFF.md` set for Phase 1's own zero-budget constraints.

## What Was Actually Proven

- **Android build + unit tests (real compile, not structural-only):** `sip-core` Gradle module wraps PJSIP 2.17 built from official source for `arm64-v8a` + `x86_64` with a from-source-cross-compiled Opus 1.5.2 (Plan 02); `:app` compiles against the real SWIG/JNI bindings (Plan 04's `SipCallController` — `makeCall`/`answer`/`hold`/`mute`/`transfer`/`sendDtmf`/`hangup`, transient registration, both-direction Telecom wiring); UI is complete and symmetric with iOS (Plan 06 — dialpad, `OutgoingCallActivity`, `ActiveCallActivity`). `./gradlew testDebugUnitTest --console=plain` → `BUILD SUCCESSFUL`, **24/24 tests, 0 failures** (`CallControlTest` x5, `DialpadSanitizeTest` x4, `NetworkChangeHandlerTest` x1, `EnvelopeVerifierTest` x5, `DtmfControllerTest` x2, `CodecConfigTest` x2, `DialpadTest` x5) — re-confirmed by 02-08's prior session (2026-08-12) and cross-checked against `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md`'s recorded figures. This session attempted an independent third re-run from a fresh worktree checkout and hit a build-artifact gap specific to that fresh worktree, not a code regression — see "Re-verification note" below.
- **HA-Phone backend (cross-repo, real execution, re-run this session):** `python3 -m pytest backend/tests/test_api.py backend/tests/test_cont_init_tls.py` against `~/projects/Ha-Phone/ha-phone` → **93 passed, 2 skipped, 0 failed** (95 collected). Independently re-executed by this session (not just cited from the prior session's doc) using a scratch-installed `pydantic` on `PYTHONPATH` to work around the pre-existing, out-of-scope `pydantic==2.5.3`/`sqlmodel==0.0.38` `model_dump(context=...)` incompatibility documented since `02-01-SUMMARY.md` — result matched the previously recorded figures exactly, with zero shared-environment or repo files touched.
- **iOS build + link + unit tests (real CI execution, not structural-only):** PJSIP 2.17 built from source on the GitHub Actions macOS runner (Plan 03), linked into the app via an Obj-C++ bridge (`PjsuaBridge`), with `SipCallController` (Plan 05) and the SwiftUI dialpad/`OutgoingCallView`/`ActiveCallView` (Plan 07) built on top. The `build-test` GitHub Actions job is **green end-to-end** — PJSIP build, XcodeGen, app build+link, AND unit tests, not just a YAML/structural check — on commit `d6b623e7ff59a16aa9243ac18a7e8664678da823`: https://github.com/iron-exx/ha-phone-app/actions/runs/31588437266/job/94087580778. This session independently re-confirmed this via the public GitHub REST API (`GET /repos/iron-exx/ha-phone-app/commits/d6b623e7.../check-runs`) rather than trusting the prior session's citation: `"name": "build-test"`, `"status": "completed"`, `"conclusion": "success"`, `started_at`/`completed_at` both present, `html_url` matching exactly.
- **Config-substitution grep gates (Plan 04 Task 3 / Plan 05 Task 3, cited as closed — see item 6 below):** both `HAPhoneTestApplication.kt` (Android) and `HAPhoneTestAppApp.swift` (iOS) re-confirmed by this session to contain zero leftover `<ha-phone-host>`/`TODO`-style placeholders.
- **Cross-repo TLS/SRTP provisioning (code-complete, not yet live — see gap #2 below):** Plan 01 added `Extension.transport`/`media_encryption` fields, conditional conf-template rendering, and the `cont-init.d` self-signed TLS cert + `[transport-tls]` Asterisk transport stanza (commits `e2666cf`, `2f96ad5` in `~/projects/Ha-Phone`). This code is verified correct but has not yet taken effect on the live box.
- **Cross-reference, all 7 implementation plans (02-01 through 02-07) have SUMMARY.md files on disk:**
  - 02-01: `Extension.transport`/`media_encryption` model fields + TLS cont-init.d stanza (Tasks 1-2 complete; Task 3 — the live extension creation + add-on restart — is a human-action checkpoint, see gap #2).
  - 02-02: PJSIP 2.17 built from source for Android with cross-compiled Opus, wired into a local `sip-core` Gradle module.
  - 02-03: PJSIP 2.17 built from source for iOS via GitHub Actions; Task 3's checkpoint (real CI green run) is RESOLVED as of this session's independent re-verification above; the one named gap it carries forward is Opus being disabled for iOS (see gap #3 below).
  - 02-04: `SipCallController` (Android) implementing the full call-control surface, real test-extension credentials wired via `local.properties` → `BuildConfig` (not hardcoded).
  - 02-05: `PjsuaBridge` + `SipCallController` (iOS) implementing the same call-control surface, real test-extension credentials wired via `Secrets.xcconfig` → Info.plist (gitignored, not hardcoded).
  - 02-06: Android dialpad + `OutgoingCallActivity`/`ActiveCallActivity` UI, wired to the real `SipCallController`/`CallControlScope`.
  - 02-07: iOS dialpad + `OutgoingCallView`/`ActiveCallView` UI, made reachable via `CallSessionState` + `.fullScreenCover` (closing a prior navigation gap).

**Re-verification note (this session):** attempting an independent third re-run of the Android suite from a freshly checked-out worktree surfaced that this worktree lacks several gitignored, locally-built artifacts present only in the main checkout (`local.properties`, `google-services.json`, and — critically — the vendored/compiled `third_party/pjproject` native build output the `sip-core` module links against). The first two were trivially copied in (confirmed gitignored via `git check-ignore`, not tracked, no secret-in-git risk); rebuilding the third (a from-source NDK cross-compile) is a multi-hour undertaking wildly out of scope for writing this sign-off, so it was not attempted. This is an expected consequence of `02-02-SUMMARY.md`'s own documented pattern ("gitignored vendored `third_party/` + built output, rebuilt deterministically from a pinned tag every CI run") applied to a fresh worktree rather than a code regression — the 24/24 figure is not invented, it is cited from two independent prior real runs (`e8c09ca` session 2026-08-08, corrected+re-run in the `9597db6` session 2026-08-12) plus this session's confirmation of the backend and iOS-CI figures by other means.

## 1. Plan 02-08 Task 2: Real-Device Manual Verification Matrix (Open — Accepted)

**Not run.** This plan's own Task 2 is a `type="checkpoint:human-verify" gate="blocking"` step. No automated action was available: real SIP calls, Bluetooth audio routing, and physical WiFi-to-cellular network switching require a real Android device, the live HA-Phone box, Bluetooth audio hardware, and a cellular radio — none of which exist in this Linux sandbox. This was named as a blocking checkpoint in `02-08-SUMMARY.md`'s prior session, not silently skipped.

**Resumption trigger:** a human follows `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md` end-to-end with real hardware (a real Android device, or the API 35 emulator substitution Phase 1 used, explicitly noted if substituted) and reports the completed Result Log Table back — codec-by-codec pass/fail for CALL-01's 6-row matrix, DTMF, hold+transfer, the actual D-09 network-switch outcome, and the CALL-05 registration-lifecycle confirmation via `pjsip show contacts`/`pjsip show aor 13`/`pjsip show endpoint 13`.

**Direct consequence — D-09 mid-call network-switch outcome:** not observed, not assumed. This plan's own `<verification>`/`<success_criteria>` require the sign-off to report "the actual D-09 network-switch outcome... not assumed," which structurally requires Task 2 to have run first. It has not. The Result Log Table in `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md` records every CALL-01/CALL-05/D-09 row as blank/pending, not pass or fail — this sign-off preserves that honesty rather than inventing a result.

## 2. Plan 02-01 Task 3: Live TLS/SRTP Test Extension Never Deployed (Open — Accepted)

**Not resolved.** Plan 01's Task 3 (create the dedicated 80-99-sub-range TLS test extension via the real HA-Phone API, restart the add-on so `cont-init.d` re-runs and picks up the `[transport-tls]` stanza, confirm via `pjsip show transports`) is its own `type="checkpoint:human-action"` blocking gate — writing to the live production PBX database and restarting its container are explicitly out of bounds for any sandboxed session. `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md` states plainly at its top: "the TLS transport is NOT YET LIVE on the box."

**Resumption trigger (cited verbatim from `02-01-SUMMARY.md`'s "Checkpoint: Task 3" section, not re-derived here):**
```bash
# Restart first: Home Assistant -> Settings -> Add-ons -> HA-Phone -> Restart
# Then, via the add-on's built-in terminal/SSH:
asterisk -rx "pjsip show transports"
# Expect: a transport-tls row bound to 0.0.0.0:5061, alongside existing transport-udp/transport-udp-ipv6
```
The extension-creation `curl` commands against `http://<ha-phone-host>/api/extensions` (list existing, then `POST` with `transport: "tls"`, `media_encryption: "sdes"`) are likewise specified in that same section and were never run against the live box from any sandbox.

**Note — extension-number discrepancy, already flagged, not newly discovered here:** the extension actually wired into both apps' build configs (`13`) is inside the active 10-99 household range, not Plan 01's intended 80-99 sub-range (D-04). `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md` flags this explicitly and instructs confirming with the household PBX admin before any real test call. Not reconciled by this sign-off — carried forward, see below.

## 3. Opus Codec Disabled for iOS (Open — Accepted)

**Confirmed still in effect.** `ios-app/HAPhoneTestApp/Sip/config_site.h` sets `PJMEDIA_HAS_OPUS_CODEC 0`. Root cause: Homebrew's `opus` build is macOS-native (dylib or static `.a` alike) and cannot link into an iOS or iOS-Simulator binary regardless of CPU architecture. This was discovered and fixed during the session that resolved Plan 03's Task 3 CI checkpoint (the fix chain around commits `89585ac` "drop Opus for now" and `44b3dcd` "compile Opus out of PJSIP too, not just out of the link step," both ancestors of the final green-CI commit `d6b623e7` on `main`). PJSIP's own bundled codecs (G.711 PCMU/PCMA, GSM, iLBC, Speex) remain available on iOS; G.722 is unaffected (not Opus-dependent).

**Practical consequence:** CALL-01's codec matrix is Opus-Android-only in practice until this gap closes. `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md`'s iOS Status section states this explicitly and its Result Log Table marks the entire iOS row as not performed.

**Resumption trigger:** a from-source iOS cross-compile of libopus (`arm64-ios` + `arm64-ios-simulator`), explicitly deferred as its own separate task — not part of Phase 2's scope, and not attempted opportunistically here.

## 4. D-15/D-16/D-17 iOS Real-Device Audio Verification Gap (Open — Accepted)

Per `02-CONTEXT.md`'s own decisions, quoted directly rather than re-framed:

- **D-15:** "iOS is built in parallel with Android in Phase 2, not deferred. Android gets full real-hardware verification (matching Phase 1's pattern); iOS stays structurally/Simulator-verified only — PJSIP build + audio-path unit tests run, no real call on a physical iPhone. This directly extends Phase 1's D-11 (zero-budget Apple Developer Program constraint) into Phase 2."
- **D-16:** "'iOS verified in Simulator' means structure/unit-test level only — PJSIP builds, SIP signaling/registration is checked — **not** real audio I/O through the Simulator's host-Mac microphone/speakers, even though modern Simulators support that. Matches Phase 1's precedent (CallKit reporting was verified structurally, not via a real call)."
- **D-17:** "Phase 2 produces its own `02-PHASE-SIGNOFF.md` (mirroring Phase 1's `01-PHASE-SIGNOFF.md` pattern) that explicitly documents the iOS real-device audio verification gap as an accepted, carried-forward item — not silently marked done." (This document is that artifact.)

**What this means concretely:** real audio I/O has never been tested on a physical iPhone, nor on a Simulator instance using real host-Mac microphone/speaker hardware. Only PJSIP build success plus `SipCallControllerTests.swift`/`NetworkChangeHandlerTests`/`DialedNumberStateTests` unit-level verification (now confirmed via a real green CI run, not just structural checks — see "What Was Actually Proven" above) has occurred. The Mute/Hold CallKit round-trip specifically (`ActiveCallView` → `CXCallController` → `CallProviderDelegate` → `SipCallController`) was verified only by cross-checking method signatures and CallKit action initializers against the real, already-compiled Plan 05 interfaces (per `02-07-SUMMARY.md`'s "Issues Encountered" section: "structurally only... no `xcodebuild build`/`xcodebuild test` was run or could be run in this environment") — not via an automated end-to-end test exercising an actual call.

## 5. D-18 Resumption Trigger

Per `02-CONTEXT.md` D-18, named verbatim, not left as an undated "someday" item:

**This gap closes when the user enrolls in the Apple Developer Program ($99/yr).**

Plan 05's `SipCallController.swift` and Plan 07's SwiftUI call-control UI are expected to carry over largely unchanged; only signing/distribution infrastructure (a superset of Plan 03's current unsigned-CI pipeline) would need to be added to run on a physical device.

## 6. D-10 Correction — Confirmed Permanent (Closed)

The legacy Asterisk CLI command referenced by the original ROADMAP-level assumption for verifying transient registration does not exist on this Asterisk 22 box (`chan_sip` — the subsystem that command belonged to — was removed entirely). Confirmed still correctly reflected in `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md`: the CALL-05 verification section instructs `pjsip show contacts` / `pjsip show aor 13` / `pjsip show endpoint 13` exclusively, and explicitly states the legacy command "does NOT exist and must never be run." Re-confirmed by this session:
```
grep -c "pjsip show contacts" tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md  → 2
```
The non-existent legacy command does not appear anywhere in the doc as an instruction. This correction is permanent, not a point-in-time snapshot.

## 7. Config Substitution Confirmation (Closed Gate)

Plan 04 Task 3 and Plan 05 Task 3 each carried a hard, zero-tolerance acceptance-criteria grep gate: the real HA-Phone host/extension/password (from Plan 01's Task 3 checkpoint output — host `192.168.7.10`, extension `13`, password stored only in gitignored `local.properties`/`Secrets.xcconfig`, never in git history) must be substituted into `HAPhoneTestApplication.kt` (Android) and `HAPhoneTestAppApp.swift` (iOS), with zero leftover `<ha-phone-host>`/`TODO` placeholder tokens. Both gates **pass**, re-confirmed by this session:
```
grep -Ec "<ha-phone-host>|TODO.*Plan 01" android-app/app/src/main/java/de/haphone/app/test/HAPhoneTestApplication.kt  → 0
grep -Ec "<ha-phone-host>|TODO.*Plan 01" ios-app/HAPhoneTestApp/HAPhoneTestAppApp.swift  → 0
```
This is a closed gate, not carried forward.

## Carried Forward

The following are known, explicitly accepted as still-open items going into Phase 3, not silently resolved by this sign-off:

1. **Plan 02-08 Task 2 (real-device manual verification matrix)** — remains open; see gap #1 above. Nothing in Phase 3 (QR provisioning) functionally depends on it, but it must be revisited before either app is considered production-ready for real calls.
2. **Plan 02-01 Task 3 (live TLS/SRTP extension deployment on the real HA-Phone box)** — remains open; see gap #2 above. This is the actual precondition for gap #1 — Task 2's real-device matrix cannot produce a single real pass/fail result until the TLS transport is live on the box.
3. **Codec/routing issues from real testing** — none to report, because Task 2 never ran; no real-call codec or routing defect has been surfaced yet by actual hardware testing. This is explicitly different from "verified clean" — it means untested, not passing.
4. **Opus disabled for iOS** — see gap #3 above; deferred as its own from-source libopus iOS cross-compile task.
5. **D-15/D-16/D-17/D-18 iOS real-device audio verification** — see gaps #4/#5 above; blocks nothing in Phase 3 (QR provisioning is Android-and-iOS-agnostic at the SIP/media layer), but must be revisited before any real iOS user install.
6. **DTLS-SRTP vs SDES (RESEARCH.md Open Question 2)** — shipped with SDES per the original recommendation (Plan 01's `media_encryption = sdes` conf-template line, Plan 05's `srtpUse = PJMEDIA_SRTP_MANDATORY`). DTLS-SRTP was not implemented and is revisited only if a specific reason to prefer it emerges later (e.g., Phase 5's Tailscale/production transport hardening) — not a default assumption to revisit otherwise.
7. **iOS Mute/Hold CallKit round-trip** — sanity-checked manually only via signature/API-shape cross-checking against the real Plan 05 interfaces (see gap #4 above), not via an automated end-to-end test exercising an actual call. Real verification happens together with gap #4's resolution.
8. **Extension-number discrepancy (`13` vs. the intended 80-99 sub-range, D-04)** — flagged in `tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md`, not reconciled by this sign-off. Must be confirmed safe with the household PBX admin before any real test call runs against it, independent of and prior to gap #1's resumption.
9. **STATE.md's "02-03-SUMMARY.md is missing" blocker note is stale** — `02-03-SUMMARY.md` exists on disk and documents Task 3's resolution (see "What Was Actually Proven" above). Not corrected here — STATE.md is orchestrator-owned in this worktree-parallel execution model, not touched by this plan.

---
*Phase: 02-pjsip-audio-media-core*
*Sign-off written: 2026-08-12*
