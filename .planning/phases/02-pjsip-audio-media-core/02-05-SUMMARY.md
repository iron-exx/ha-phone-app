---
phase: 02-pjsip-audio-media-core
plan: 05
subsystem: telephony
tags: [pjsip, pjsua2, ios, callkit, sip, dtmf, codec-priority, swift, objc++, xcconfig]

# Dependency graph
requires:
  - phase: 02-pjsip-audio-media-core (plan 01)
    provides: cross-repo HA-Phone TLS/SRTP test-extension prerequisite (D-06) -- NOTE, not yet live-verified, see Deviations
  - phase: 02-pjsip-audio-media-core (plan 03)
    provides: PJSIP 2.17 iOS build (pjsua2.xcframework), ios-ci.yml wiring, config_site.h Opus enablement
provides:
  - SipCallController public API (makeCall/answer/hold/mute/transfer/sendDtmf/hangup) implementing CALL-01..05
  - PjsuaBridge -- real Obj-C++ Endpoint/Account/Call lifecycle owner, including inbound-call handle (HAPhoneAccount::onIncomingCall) and D-09 handleIpChange
  - AudioSessionCoordinator -- AVAudioSession config scoped strictly to CXProvider didActivate/didDeactivate
  - NetworkChangeMonitor/NetworkChangeHandler/IpChangeNotifying seam driving D-09 mid-call network-switch recovery
  - CallProvider.swift extended with hold/mute/DTMF CXAction handlers
  - Secrets.xcconfig -> Info.plist -> Bundle.main pattern for real per-environment test credentials (iOS equivalent of Android's local.properties -> BuildConfig)
affects: [02-pjsip-audio-media-core (plan 07 - dialpad/call UI), 02-pjsip-audio-media-core (plan 08 - manual test procedure), 02-VALIDATION]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Secrets.xcconfig (gitignored) -> project.yml Info.plist $(VAR) substitution -> Bundle.main at runtime, for real per-environment test credentials (not tracked source) -- iOS analog of Android's local.properties -> BuildConfig"
    - "NS_SWIFT_NAME pinning on every Obj-C++ bridge method to remove Clang-importer name-mangling ambiguity when no Swift compiler is available to verify against"
    - "Report-First / Attach-SIP-After (CXAnswerCallAction gates the real SIP answer, never call-reporting time)"

key-files:
  created:
    - ios-app/HAPhoneTestApp/Sip/DialString.swift
    - ios-app/HAPhoneTestApp/Sip/SipCallOperations.swift
    - ios-app/HAPhoneTestApp/Sip/PjsuaBridge.h
    - ios-app/HAPhoneTestApp/Sip/PjsuaBridge.mm
    - ios-app/HAPhoneTestApp/Sip/AudioSessionCoordinator.swift
    - ios-app/HAPhoneTestApp/Sip/SipCallController.swift
    - ios-app/HAPhoneTestApp/Sip/NetworkChangeMonitor.swift
    - ios-app/HAPhoneTestAppTests/DialStringTests.swift
    - ios-app/HAPhoneTestAppTests/SipCallControllerTests.swift
    - ios-app/HAPhoneTestAppTests/NetworkChangeHandlerTests.swift
    - ios-app/Secrets.xcconfig.example
    - ios-app/Secrets.xcconfig (gitignored, not committed)
  modified:
    - ios-app/HAPhoneTestApp/CallProvider.swift
    - ios-app/HAPhoneTestApp/HAPhoneTestAppApp.swift
    - ios-app/project.yml
    - .github/workflows/ios-ci.yml
    - .gitignore
  deleted:
    - ios-app/HAPhoneTestApp/Sip/PjsuaSmokeCheck.h
    - ios-app/HAPhoneTestApp/Sip/PjsuaSmokeCheck.mm

key-decisions:
  - "Real HA-Phone test-extension host/port/username/password compiled into the app via Secrets.xcconfig (gitignored) -> project.yml Info.plist $(SIP_TEST_*) substitution -> Bundle.main at runtime, instead of the plan's illustrative literal Swift string constants -- security-motivated deviation mirroring Plan 04's Android approach, see below"
  - "Added NS_SWIFT_NAME to every PjsuaBridge.h method to pin exact Swift call-site names, since this sandbox has no Swift compiler to verify the Clang importer's default 'Omit Needless Words' name-mangling for 'VerbWithNoun:' selectors"
  - "Deleted PjsuaSmokeCheck.h/.mm (Plan 03 smoke check), superseded by PjsuaBridge's real Endpoint/Account/Call lifecycle"

requirements-completed: [CALL-01, CALL-02, CALL-03, CALL-04, CALL-05]

# Metrics
duration: ~20min
completed: 2026-08-08
---

# Phase 2 Plan 05: iOS SIP Call Controller Summary

**PJSUA2-backed Obj-C++ PjsuaBridge + Swift SipCallController implementing makeCall/answer/hold/mute/transfer/sendDtmf/hangup with digit sanitization, CallKit-scoped audio session activation, D-09 network-change recovery, and both-direction call handling (incoming via HAPhoneAccount::onIncomingCall, outgoing via makeCallWithUri:).**

## Performance

- **Duration:** ~20 min
- **Completed:** 2026-08-08
- **Tasks:** 3
- **Files modified:** 18 (12 created, 5 modified, 2 deleted; Secrets.xcconfig created but gitignored/not committed)

## Accomplishments
- Pure-Swift `DialString`/`SipCallOperations` contracts (CALL-01/D-07-adjacent digit sanitization mirroring server-side `_dial_string`, T-2-08), matching Plan 04's Android contracts exactly
- Real Obj-C++ `PjsuaBridge` wrapping PJSUA2 `Endpoint`/`Account`/`Call`, with all 3 CALL-01 codecs prioritized (opus/48000, g722/16000, pcma/pcmu), dev-scoped self-signed TLS cert acceptance (T-2-09), and `srtpSecureSignaling=1` (T-2-10)
- `HAPhoneAccount::onIncomingCall` constructs the incoming `Call` wrapper and stores it as `activeCall` -- closes the previously-permanent null-activeCall gap for inbound calls (checker blocker fix, iteration 4), mirroring Plan 04's Android `PjsuaEndpointHolder.onIncomingCall` fix
- `AudioSessionCoordinator` confines all `AVAudioSession` configuration to `CXProvider`'s `didActivate`/`didDeactivate` callbacks
- `NetworkChangeMonitor`/`NetworkChangeHandler`/`IpChangeNotifying` seam wires real `NWPathMonitor` path-satisfied events to `PjsuaBridge.handleIpChange` (D-09), with the decision logic isolated for unit testing
- `SipCallController` implements all 5 CALL-01..05 operations against the `SipCallOperations` seam, with CR-01-style disconnect-on-answer-failure via `CXEndCallAction`
- `CallProvider.swift`'s `CXProviderDelegate` extended with `CXSetHeldCallAction`/`CXSetMutedCallAction`/`CXPlayDTMFCallAction` handlers plus `didActivate`/`didDeactivate` audio-session wiring; `CXAnswerCallAction` re-confirmed (no fix needed) to gate the real SIP answer strictly on CallKit's genuine user-answer signal
- Full `DialStringTests`/`SipCallControllerTests`/`NetworkChangeHandlerTests` XCTest suites authored (mirroring existing `PushHandlerTests.swift` convention), to run in CI (Plan 03's `ios-ci.yml` Simulator job)

## Task Commits

1. **Task 1: Define shared contracts -- DialString, SipCallOperations** - `b800a18` (feat)
2. **Task 2: Real PjsuaBridge Obj-C++ wrapper (Endpoint/Account/Call, transient registration, inbound-call capture)** - `d5b080d` (feat)
3. **Task 3: SipCallController + AudioSessionCoordinator + CallProvider wiring** - `3b43c4f` (feat)

**Plan metadata:** (pending — this commit)

## Files Created/Modified
- `ios-app/HAPhoneTestApp/Sip/DialString.swift` - `sanitize`/`toSipUri`, shared by dial/DTMF/transfer
- `ios-app/HAPhoneTestApp/Sip/SipCallOperations.swift` - Testable seam over PJSUA2 Call/Account + `PjsuaBridgeSipCallOperations` adapter
- `ios-app/HAPhoneTestApp/Sip/PjsuaBridge.h`/`.mm` - Real Endpoint/Account/Call lifecycle, `HAPhoneAccount::onIncomingCall`, `handleIpChange`, `NS_SWIFT_NAME`-pinned selectors
- `ios-app/HAPhoneTestApp/Sip/AudioSessionCoordinator.swift` - AVAudioSession config scoped to CallKit callbacks
- `ios-app/HAPhoneTestApp/Sip/NetworkChangeMonitor.swift` - D-09 testable seam (`IpChangeNotifying`) + real `NWPathMonitor` wiring
- `ios-app/HAPhoneTestApp/Sip/SipCallController.swift` - Public CALL-01..05 API
- `ios-app/HAPhoneTestApp/CallProvider.swift` - Hold/mute/DTMF CXAction handlers + audio-session activation
- `ios-app/HAPhoneTestApp/HAPhoneTestAppApp.swift` - Owns `PjsuaBridge`, `SipCallController`, `NetworkChangeMonitor`; reads real test-extension config from `Bundle.main`
- `ios-app/project.yml` - `configFiles: Secrets.xcconfig` (Debug/Release) + `SIPTest*` Info.plist keys with `$(SIP_TEST_*)` substitution
- `.github/workflows/ios-ci.yml` - Provisions a placeholder `Secrets.xcconfig` from the tracked `.example` before `xcodegen generate`, since CI has no real credentials
- `.gitignore` - Added `ios-app/Secrets.xcconfig`
- `ios-app/Secrets.xcconfig.example` - Tracked template (placeholder values)
- `ios-app/Secrets.xcconfig` - (gitignored, not committed) real test-extension host/port/username/password
- 3 new XCTest files under `ios-app/HAPhoneTestAppTests/`
- Deleted `ios-app/HAPhoneTestApp/Sip/PjsuaSmokeCheck.h`/`.mm` (superseded by `PjsuaBridge`)

## Decisions Made
- Wired the real test-extension credentials through `Secrets.xcconfig` → Info.plist `$(SIP_TEST_*)` build-setting substitution → `Bundle.main` at runtime, rather than literal Swift string constants in `HAPhoneTestAppApp.swift` (see Deviations) -- this repo has a public GitHub remote, so committing a real LAN PBX password to git history would be effectively permanent exposure even after a later rotation. This is the direct iOS analog of Plan 04's Android `local.properties -> BuildConfig` decision, and matches the `swift/security.md` rule ("Use environment variables or `.xcconfig` files for build-time secrets... never hardcode secrets in source").
- Added `NS_SWIFT_NAME` annotations to every `PjsuaBridge.h` method rather than relying on the Clang importer's default Objective-C-to-Swift name transformation, because this sandbox has no Swift compiler available to verify the exact generated names for `VerbWithNoun:`-shaped selectors (e.g. `registerAccountWithDomain:username:password:`) before Plan 03's CI run does. This removes a plausible silent CI-only compile failure risk.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical / Security] Real test-extension credentials wired via `Secrets.xcconfig`/Info.plist/`Bundle.main`, not hardcoded Swift literals**
- **Found during:** Task 3, `HAPhoneTestAppApp.swift` credential substitution step
- **Issue:** The plan's `must_haves` and acceptance criteria require the real HA-Phone test-extension host/extension/password (confirmed valid: host `192.168.7.10`, port `5061`, extension `13`, password `[REDACTED -- see security note below]`) to be "compiled into the app config" with "no placeholder token" surviving. The plan's illustrative snippet showed this as literal Swift string constants directly in `HAPhoneTestAppApp.swift`, a file tracked in git with a public GitHub remote already pushed to (`github.com/iron-exx/ha-phone-app`). Committing a real password for the user's home Asterisk PBX to git history is a standing, essentially-permanent exposure regardless of later rotation, and directly contradicts the loaded `swift/security.md` rule (use `.xcconfig` files for build-time secrets, never hardcode).
  - **Security note (added retroactively, code review CR-1):** this line's own parenthetical originally repeated the real password in plaintext -- ironic, since the fix being documented here was specifically to avoid exactly that. Redacted here; this exact string, having been pushed to the public remote in another file (`tools/docs/PHASE2_MANUAL_TEST_PROCEDURE.md`), must be rotated on the real box regardless of this file's correction.
- **Fix:** Added `ios-app/Secrets.xcconfig` (gitignored) with the real `SIP_TEST_HOST`/`_PORT`/`_USERNAME`/`_PASSWORD` build settings, and a tracked `Secrets.xcconfig.example` template with placeholder values. Wired `project.yml` to set this as the `HAPhoneTestApp` target's `configFiles` (Debug/Release) and to inject four new `SIPTest*` Info.plist keys using `$(SIP_TEST_*)` build-setting substitution. `HAPhoneTestAppApp.swift` now reads these via `Bundle.main.object(forInfoDictionaryKey:)` in a small `SipTestConfiguration` enum instead of literal strings -- functionally still "compiled into the app config" at build time (Info.plist values are baked into the app bundle), and the file contains zero placeholder tokens (verified by the plan's own grep gate, which returns 0 as required) and zero real secret text.
- **Files modified:** `ios-app/project.yml`, `ios-app/HAPhoneTestApp/HAPhoneTestAppApp.swift`, `.github/workflows/ios-ci.yml`, `.gitignore`, `ios-app/Secrets.xcconfig.example` (tracked), `ios-app/Secrets.xcconfig` (gitignored, not committed)
- **Verification:** `grep -Ec "<ha-phone-host>|<substitute-real-host...>|..." ios-app/HAPhoneTestApp/HAPhoneTestAppApp.swift` returns `0`; a grep for the real password against `ios-app/` showed only the gitignored `Secrets.xcconfig`; `git status --short` confirms `Secrets.xcconfig` is never staged; `git check-ignore -v ios-app/Secrets.xcconfig` confirms the ignore rule
- **Committed in:** `3b43c4f`

**2. [Rule 3 - Blocking] `NS_SWIFT_NAME` pinning added to every `PjsuaBridge.h` method**
- **Found during:** Task 3, writing `PjsuaBridgeSipCallOperations` (the Swift-side adapter calling into the Obj-C++ bridge committed in Task 2)
- **Issue:** Objective-C methods like `registerAccountWithDomain:username:password:` and `makeCallWithUri:` are imported into Swift via Clang's "Omit Needless Words" heuristic, whose exact output (e.g. `registerAccount(withDomain:username:password:)` vs `registerAccount(domain:username:password:)`) cannot be verified without a real Swift compiler -- unavailable in this Linux sandbox (D-02). Guessing wrong would produce a Task 3 compile failure only discoverable on Plan 03's GitHub Actions macOS CI run, several steps removed from this task.
- **Fix:** Added `NS_SWIFT_NAME(...)` to every method declared in `PjsuaBridge.h` (Task 2's file), pinning the exact Swift-visible name (e.g. `NS_SWIFT_NAME(registerAccount(domain:username:password:))`). The underlying Objective-C selectors/signatures are unchanged, so this is purely additive and does not affect the `.mm` implementation or any of Task 2's already-committed grep-based acceptance criteria (all substring matches still hold).
- **Files modified:** `ios-app/HAPhoneTestApp/Sip/PjsuaBridge.h` (a Task 2 file, amended during Task 3)
- **Verification:** All Task 2 acceptance-criteria greps re-run and still pass after the edit; `PjsuaBridgeSipCallOperations` now calls the pinned names unambiguously
- **Committed in:** `3b43c4f`

**3. [Rule 3 - Blocking] New `Secrets.xcconfig`/CI plumbing had no prior precedent in this repo**
- **Found during:** Task 3, wiring the credential-substitution pattern
- **Issue:** Unlike Android (which already had `local.properties` + a `build.gradle.kts` reading pattern from Phase 1), iOS had no existing secret-handling mechanism, and `ios-ci.yml` generates the Xcode project fresh via `xcodegen generate` on every run -- if `Secrets.xcconfig` (gitignored) is absent, `configFiles:` in `project.yml` would make `xcodegen generate` fail outright in CI, breaking the Simulator structural build/test that Plan 03 established.
- **Fix:** Added a CI step that copies the tracked `Secrets.xcconfig.example` to `Secrets.xcconfig` only if the latter doesn't already exist, immediately before the `xcodegen generate` step. CI never has real credentials and never exercises a live call (D-15/D-16), so placeholder values are sufficient there.
- **Files modified:** `.github/workflows/ios-ci.yml`
- **Committed in:** `3b43c4f`

---

**Total deviations:** 3 (1 Rule 2 security-motivated credential-handling change with accompanying CI/build-config plumbing, 2 Rule 3 blocking-issue fixes to avoid unverifiable-in-sandbox Swift/Obj-C interop and CI breakage)
**Impact on plan:** All fixes were necessary either for security (avoiding a committed live LAN PBX password) or to avoid a plausible CI-only failure this sandbox cannot detect directly. No scope creep -- functional behavior matches the plan's intent (`SipCallController`'s public API, `PjsuaBridge`'s PJSUA2 operations, CallKit wiring) in every case.

## Issues Encountered

**Sandbox verification limits (expected, per D-02/D-15/D-16):** This is a Linux sandbox with no Xcode/xcodebuild/Swift compiler available. All Swift/Obj-C++ code in this plan was verified **structurally only** -- file existence, exact grep-matched signatures/patterns from the plan's acceptance criteria, and manual reasoning about Objective-C-to-Swift interop (mitigated for `PjsuaBridge` specifically via explicit `NS_SWIFT_NAME` pinning, see Deviations #2). No `xcodebuild build`/`xcodebuild test` was run or could be run in this environment. Real compilation and `XCTest` execution happens exclusively on Plan 03's GitHub Actions macOS runner (`ios-ci.yml`), which has not been re-triggered as part of this execution -- the next push to `main` touching `ios-app/**` will be the first real compile/test signal for this plan's code. This is consistent with every prior iOS plan in this phase (03, and this one) and is not a new gap.

**Credential substitution / pending-deploy caveat (important for Plan 08, mirrors 02-04-SUMMARY.md verbatim):** The real host/extension/password used here (`192.168.7.10:5061`, extension `13`) were supplied directly as confirmed-valid values for this execution, matching exactly what Plan 04 (Android) used. `.planning/phases/02-pjsip-audio-media-core/02-01-SUMMARY.md` still does not exist on disk -- Plan 01 has not produced it. Per the execution brief: Plan 01's live-box TLS transport deploy (activating the real `[transport-tls]` Asterisk transport on the HA-Phone box) is code-complete but **has not been confirmed live** -- a git push to the real box is still pending from the user. This means:
- The iOS app's SIP config code is complete and structurally verified against these real values (satisfying this plan's acceptance criteria).
- A real end-to-end call against the live box has **not** been verified yet on either platform -- that remains Plan 08's job, which should not assume the TLS transport is confirmed live.
- The extension-range discrepancy flagged in 02-04-SUMMARY.md (extension `13` is inside the active 10-99 household range, not the 80-99 sub-range D-04 specifies for dedicated test extensions) applies identically here and is not re-investigated in this iOS-side plan.

No other issues -- all structural grep-based acceptance criteria passed cleanly against the real PJSUA2 API surface as documented in 02-RESEARCH.md.

## User Setup Required

None for this plan directly beyond what Plan 04/01 already carry forward. A developer building the iOS app locally against the real PBX must copy `ios-app/Secrets.xcconfig.example` to `ios-app/Secrets.xcconfig` and fill in the real credentials (already done on this machine for continued Plan 08 use) -- a fresh clone will need this file re-created, exactly mirroring Android's `local.properties` requirement noted in 02-04-SUMMARY.md.

## Next Phase Readiness
- `SipCallController`/`CallProvider.swift` are ready for Plan 07 (dialpad + Active/Outgoing Call UI) to bind against `AppDelegate.sipCallController`.
- Plan 08's manual test procedure needs the real credentials to exercise a live call -- they are in `ios-app/Secrets.xcconfig` (gitignored) on this machine; whoever runs Plan 08 must ensure that file is present and populated (not committed, so a fresh checkout will need it re-added), exactly as with Android's `local.properties`.
- Blocker carried forward (not new to this plan): Plan 01's live TLS transport deploy on the real HA-Phone box is still pending user action before any real call can succeed on either platform.
- Real compile/test verification of this plan's Swift/Obj-C++ code is still pending Plan 03's CI pipeline actually running against this commit (next push to `main` touching `ios-app/**`) -- not yet confirmed green as of this summary.

---
*Phase: 02-pjsip-audio-media-core*
*Completed: 2026-08-08*

## Self-Check: PASSED

All 12 created files verified present on disk (including gitignored `Secrets.xcconfig`); `PjsuaSmokeCheck.h`/`.mm` confirmed deleted; all 3 task commits (`b800a18`, `d5b080d`, `3b43c4f`) verified in `git log`.
