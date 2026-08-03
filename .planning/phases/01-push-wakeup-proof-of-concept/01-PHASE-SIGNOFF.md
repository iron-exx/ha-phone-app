# Phase 1: Push-Wakeup Proof of Concept — Sign-Off

**Phase status:** Proceeding to Phase 2 with open gaps explicitly accepted below, not silently resolved. This is a zero-budget proof of concept (D-11/D-12); the honest documentation of what remains unverified **is** the deliverable of this sign-off, not a gap to be hidden.

## 1. What Was Actually Proven

- **PUSH-01 / PUSH-02 (iOS):** structurally verified via Plan 04's `.github/workflows/ios-ci.yml` — an unsigned build for the iOS Simulator plus the full unit test suite (`EnvelopeVerifierTests`, `PushHandlerTests`, `DiagnosticsLogTests`). **NOT verified on real iOS hardware.** No physical iPhone push-wake test (foreground, backgrounded, locked, terminated, or overnight standby) was ever performed in Phase 1. See §2 below.
- **PUSH-03 / PUSH-04 (Android):** verified for real on a device via Plan 05 — a real (free-tier) Firebase project (`haphone-e30ca`) delivering real FCM messages to a KVM-accelerated API 35 emulator running the same stock AOSP/Google-APIs build as a physical Pixel. All 5 measured app states passed (foreground ~0.3s, backgrounded ~0.3s, killed+screen-off ~1.6s, killed+deep-Doze ~1.4s, killed+secure-PIN-keyguard ~1.8s), every delivery reporting `isValid=true isExpired=false`. Screenshot evidence: `tools/logs/screenshots/killed_locked_incoming_call.png`, `tools/logs/screenshots/secure_locked_killed_incoming_call.png`. Full results: `tools/docs/MANUAL_TEST_PROCEDURE.md`.
- This also answers **D-12** (see §3): full-screen-intent works for a sideloaded self-managed-`ConnectionService` app with no Play Console declaration at all.

## 2. D-11: iOS Real-Device Verification Gap (Open — Accepted)

**Real physical-device push delivery for iOS is UNVERIFIED in Phase 1.** No backgrounded/locked/terminated/overnight-standby test was run on an actual iPhone. This is not a technical gap in the app code — it is a hard consequence of the zero-budget constraint: a free "Personal Team" Apple ID cannot receive the Push Notifications entitlement under any circumstance, regardless of distribution method (TestFlight or otherwise). Real VoIP push on a physical iPhone cannot be proven without a paid Apple Developer Program membership ($99/yr), which the user has explicitly declined to pay for during Phase 1.

What CAN and was done for free: Plan 02 built the full PushKit/CallKit wiring (`PushHandler.swift` reporting every push to CallKit synchronously and unconditionally, before verification — the report-first pattern Apple requires) and Plan 04 built a GitHub Actions macOS CI workflow that builds the app unsigned for the Simulator and runs its unit tests.

**Sub-gap: even that CI's live green run is unconfirmed from this sandbox.** Plan 04's Task 2 could not execute `gh workflow run` / `gh run list` because the `gh` CLI is not installed here, and this sandbox cannot push commits to the GitHub remote at all (no working credential helper — see project memory "Git Push Sandbox Workaround"). Plan 04's own SUMMARY documents this explicitly and relies on structural verification instead (YAML validity + grep-based acceptance checks: macOS runner present, `iphonesimulator` target present, exactly one `xcodegen generate` invocation, zero Fastlane/match/TestFlight/App-Store-Connect-API-key/secrets references). This plan (06) re-attempted the same `gh run list --workflow=ios-ci.yml` check and hit the identical `gh: Befehl nicht gefunden` result. **`.github/workflows/ios-ci.yml` is therefore authored and structurally verified but has never actually executed on GitHub's runners as of this sign-off.** It will run automatically on the next push to `main` touching `ios-app/**`, or on-demand via `workflow_dispatch`, once this branch reaches GitHub — that confirmation remains outstanding.

This gap closes whenever the user chooses to enroll in the Apple Developer Program. Plan 02's app code and the Simulator-verified test suite are expected to carry over largely unchanged; only signing/distribution infrastructure (a superset of Plan 04's current unsigned CI) would need to be added.

## 3. D-12: Android Full-Screen-Intent Empirical Finding

**Answer: YES — full-screen intent works, fully, with NO Play Console declaration**, for a sideloaded app that registers a self-managed `ConnectionService`/`PhoneAccount`. Measured 2026-08-03 against API 35 (`targetSdk = 35`, above the API 34 threshold where the restriction applies):

- `USE_FULL_SCREEN_INTENT: granted=true` in `dumpsys package`; the app-op was never denied (`Default mode: default`).
- `dumpsys notification --noredact` showed `fullscreenIntent=PendingIntent{...}` present and NMS-allowlisted.
- `IncomingCallActivity` was observed as `topResumedActivity` while `isKeyguardShowing=true` — the call UI displayed over a secure PIN lock screen, not just an unsecured one.

**Interpretation and its limits, quoted/paraphrased from `tools/docs/MANUAL_TEST_PROCEDURE.md`:** the Play Console declaration governs Play-Store-*distributed* apps specifically — a sideloaded install never goes through that review path, so the permission stays granted purely on the strength of the self-managed `ConnectionService` registration. **This proves nothing about Play-Store-distributed builds**, where the declaration governs the grant and would need re-testing if the project is ever distributed that way. It is recorded here so a future phase does not mistake this for a blanket "the declaration is never needed."

Note this also **supersedes Plan 03's original stated expectation** that Plan 05 would perform the Play Console "calling app" declaration (see Plan 03's SUMMARY "Next Phase Readiness" / ERRATA note) — that expectation was replaced by the D-12 decision to skip Play Console entirely and test empirically instead.

## 4. ROADMAP Success Criterion #3 Resolution

ROADMAP.md's Phase 1 success criterion #3 originally required Android push-wake to be "verified on at least one non-Pixel OEM device."

**Resolution: scoped down to Pixel-only for Phase 1 sign-off, per D-03/CONTEXT.md.** No Samsung/Xiaomi/other aggressive-OEM device is currently available to the developer, so this criterion is **not** silently claimed satisfied by the Pixel-class testing that was done. Non-Pixel OEM coverage is deferred and tracked as a **Phase 6 hardening backlog item**, not dropped.

A related, narrower scoping note: the actual device used for Plan 05's testing was a KVM-accelerated Android Emulator (API 35, Pixel 6 profile), not the physical Pixel named in D-02. This substitution is justified in `tools/docs/MANUAL_TEST_PROCEDURE.md` — the AVD runs the same stock AOSP/Google-APIs build and receives real FCM against the real Firebase project, so the Pixel-vs-emulator distinction is not load-bearing for PUSH-03/PUSH-04. It does **not** substitute for OEM-specific power management (still deferred, as above) or for true multi-hour overnight standby — the emulator's Doze state was forced (`dumpsys deviceidle force-idle`) rather than reached through actual multi-hour idle, so naturally-occurring long-standby behavior on real hardware remains unproven.

## 5. D-09 Qualitative Acceptance

Per D-09, Phase 1's Definition of Done uses the developer's own qualitative judgment ("does this feel reliable") rather than a fixed numeric pass-rate target. For the Android side, that judgment is **met**: the completed result table in `tools/docs/MANUAL_TEST_PROCEDURE.md` shows consistent, fast (sub-2-second) wake-and-display across all five exercised app states after resolving two initial false-negative artifacts (`am force-stop` vs. `am kill`, and a leftover-activity-state Doze re-run — both documented as test-setup issues, not push-path defects, in Plan 05's SUMMARY). No numeric pass rate is invented here beyond what the table already shows; that table is the evidence trail, not a summary statistic layered on top of it.

This qualitative acceptance is **Android-only**. It is explicitly not extended to iOS real-device behavior, which — per §2 — was never tested at all and therefore cannot be judged "reliable" or otherwise.

## 6. Carried Forward

The following are known, explicitly accepted as still-open items going into Phase 2, not silently resolved by this sign-off:

1. **iOS real-device push verification (D-11)** — remains open pending the user's decision to enroll in the Apple Developer Program. Blocks nothing in Phase 2 (SIP/media core), which is Android-first-agnostic, but must be revisited before any real iOS user install.
2. **Plan 04's iOS CI has never actually run on GitHub's runners** — authored and structurally verified only; `gh` is not installed in this sandbox and this sandbox cannot push to the GitHub remote. The live green-run confirmation is outstanding until the branch reaches GitHub via push or merge.
3. **`POST_NOTIFICATIONS` is never requested at runtime in the Plan 03 Android app** — `granted=false` on a fresh install, which since API 33 suppresses *all* notifications, making the whole push-wake path appear silently broken to a real user despite the underlying mechanism working correctly. Granted manually via `adb` to unblock Phase 1 testing. Not a Phase 1 blocker (the wake mechanism itself is proven), but must be fixed before any real user installs the app.
4. **D-03 device matrix** — non-Pixel OEM coverage (Samsung, Xiaomi, etc.) remains deferred, tracked as a Phase 6 hardening backlog item. Additionally, an emulator was substituted for the physical Pixel (justified in §4 above); OEM-specific power management and true naturally-occurring multi-hour standby remain unproven since Doze was forced rather than organically reached.
5. **Signing** — the push-envelope signing key is currently a single dev Ed25519 keypair (per D-07). Phase 6 will formalize key distribution for the multi-tenant relay.
6. **No retry/timeout logic exists yet** for missed or late pushes (per D-08) — explicitly deferred to Phase 4/5 hardening.
7. **The Android full-screen-intent grant without a Play Console declaration (D-12)** is empirically known-good for the sideload case tested here, but has not been (and cannot yet be) re-verified against a Play-Console-distributed build; that re-verification is only relevant if/when the project is ever distributed through the Play Store.

---
*Phase: 01-push-wakeup-proof-of-concept*
*Sign-off written: 2026-08-03*
