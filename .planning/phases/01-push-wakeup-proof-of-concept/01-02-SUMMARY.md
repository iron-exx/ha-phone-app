---
phase: 01-push-wakeup-proof-of-concept
plan: 02
subsystem: ios-callkit
tags: [swift, swiftui, callkit, pushkit, cryptokit, xcodegen, ed25519]

# Dependency graph
requires:
  - phase: 01-01
    provides: "Signed push-event envelope contract (tools/envelope.py) and golden cross-language fixture that EnvelopeVerifier.swift must match byte-for-byte"
provides:
  - "ios-app/ source tree: XcodeGen project.yml (app + test targets, VoIP background mode, aps-environment entitlement)"
  - "EnvelopeVerifier.swift: CryptoKit Ed25519 canonicalizer/verifier reproducing tools/envelope.py's 203-byte golden fixture exactly"
  - "PushHandler.swift: PKPushRegistryDelegate that unconditionally reports every VoIP push to CallKit before any async verification (Pitfall 1), records VoIP token via didUpdate pushCredentials"
  - "CallProvider.swift: minimal CXProviderConfiguration + CXProviderDelegate"
  - "DiagnosticsLog.swift: JSON-lines event log persisted to Documents, survives process termination (D-10)"
  - "DiagnosticsView.swift: surfaces current VoIP token for copy-paste into tools/push_trigger.py --device-token, share-sheet log export"
affects: ["01-04-ci-pipeline"]

# Tech tracking
tech-stack:
  added: ["CryptoKit (Curve25519.Signing)", "PushKit (PKPushRegistry)", "CallKit (CXProvider/CXCallController)", "XcodeGen project.yml spec"]
  patterns:
    - "Report-first pattern: PushHandler always calls reportNewIncomingCall synchronously before any EnvelopeVerifier.verify/isExpired work, never gated on verification result"
    - "Testability wrapper: PKPushPayload/PKPushCredentials have no public initializers, so PushHandler exposes handleIncomingPush(dict:completion:) and recordPushTokenUpdate(hex:) as plain-value entry points that both the real delegate methods and unit tests call"
    - "Canonical JSON signing contract shared with tools/envelope.py: fixed alphabetical field order, no whitespace, UTF-8 bytes, sig field excluded from signed bytes"

key-files:
  created:
    - ios-app/project.yml
    - ios-app/HAPhoneTestApp/HAPhoneTestAppApp.swift
    - ios-app/HAPhoneTestApp/Info.plist
    - ios-app/HAPhoneTestApp/HAPhoneTestApp.entitlements
    - ios-app/HAPhoneTestApp/EnvelopeVerifier.swift
    - ios-app/HAPhoneTestApp/PushHandler.swift
    - ios-app/HAPhoneTestApp/CallProvider.swift
    - ios-app/HAPhoneTestApp/DiagnosticsLog.swift
    - ios-app/HAPhoneTestApp/DiagnosticsView.swift
    - ios-app/HAPhoneTestAppTests/EnvelopeVerifierTests.swift
    - ios-app/HAPhoneTestAppTests/PushHandlerTests.swift
    - ios-app/HAPhoneTestAppTests/DiagnosticsLogTests.swift
  modified: []

key-decisions:
  - "Refactored PushHandler's pushRegistry(_:didReceiveIncomingPushWith:for:completion:) into a thin wrapper calling a new handleIncomingPush(dict:completion:) method, since PKPushPayload has no public initializer and cannot be constructed with custom test fixtures -- mirrors the same PKPushCredentials wrapping the plan itself already prescribed for the token-update test"
  - "Added recordPushTokenUpdate(hex:) as a thin wrapper both the real didUpdate pushCredentials delegate method and PushHandlerTests call, so the token-update test exercises PushHandler itself rather than only the mock log directly"
  - "Verified the 203-byte golden canonical-bytes fixture against the actual tools/envelope.py implementation (not just the plan's prose) before writing the Swift test assertions, confirming byte-for-byte match"

requirements-completed: [PUSH-01, PUSH-02]

# Metrics
duration: 25min
completed: 2026-08-02
---

# Phase 1 Plan 02: iOS PushKit/CallKit Proof-of-Concept Summary

**XcodeGen-defined iOS app with a CryptoKit Ed25519 EnvelopeVerifier matching `tools/envelope.py` byte-for-byte, and a PushHandler that unconditionally reports every VoIP push to CallKit before any signature/expiry verification.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-08-02T11:53:00Z (approx.)
- **Completed:** 2026-08-02T11:58:00Z (approx.)
- **Tasks:** 3 completed
- **Files modified:** 12 (12 created, 0 modified beyond the app entry point created/overwritten within this plan)

## Accomplishments

- `ios-app/project.yml` defines an XcodeGen spec for the `HAPhoneTestApp` app target (bundle id `de.systemwerk.haphone.test`, `UIBackgroundModes: [voip]`, `aps-environment: development` entitlement) and `HAPhoneTestAppTests` unit test target, so the entire Xcode project can be generated from text without ever needing Xcode in this sandbox.
- `EnvelopeVerifier.swift` implements `canonicalBytes(from:)`, `verify(dict:publicKeyHex:)`, and `isExpired(dict:now:)` using CryptoKit's `Curve25519.Signing`. Independently re-verified the 203-byte golden canonical fixture against the live `tools/envelope.py` module (not just the plan's prose) -- output matched the Swift test's expected string exactly.
- `PushHandler.swift` is a `PKPushRegistryDelegate` that calls `reportNewIncomingCall` synchronously and unconditionally for every push (well-formed, malformed, expired, or tampered) before any `EnvelopeVerifier` call runs -- confirmed via line-number ordering (`reportNewIncomingCall` at line 82, `EnvelopeVerifier.verify` at line 86 in the same function). Invalid/expired payloads are ended via `CXEndCallAction` only after the mandatory report. Also records the VoIP device token via `didUpdate pushCredentials` so it can be copied into `tools/push_trigger.py --device-token`.
- `CallProvider.swift` provides the minimal `CXProviderConfiguration` (video disabled, one call group, one call per group, generic handle type) and a bare-bones `CXProviderDelegate`.
- `DiagnosticsLog.swift` persists JSON-lines events (`receivedAt`, `reportedAt`, `signatureValid`/`signatureInvalid`, `pushTokenUpdated:<hex>`) to a file in the app's Documents directory, so they survive full process termination -- the D-10 fallback for a device with no live Xcode console attached.
- `DiagnosticsView.swift` surfaces the most recently registered VoIP token in a copyable/selectable text field plus a "Copy Token" button, lists all raw log lines, and offers a `ShareLink`-based log export.
- `HAPhoneTestAppApp.swift` wires `PKPushRegistry` (`.voIP` desired push type), `CXProvider`, `CallProviderDelegate`, and `PushHandler` together at launch via a `UIApplicationDelegateAdaptor`, using the Plan 01 dev fixture public key as a placeholder.

## Task Commits

Each task was committed atomically:

1. **Task 1: XcodeGen project scaffold + Ed25519 EnvelopeVerifier (CryptoKit)** - `773ae62` (feat)
2. **Task 2: PushHandler (PushKit) + CallProvider (CallKit) -- unconditional synchronous report + token registration** - `ad8c7a3` (feat)
3. **Task 3: On-device diagnostics log + diagnostics view showing token + app wiring** - `171ab0a` (feat)

**Plan metadata:** (this commit)

## Files Created/Modified

- `ios-app/project.yml` - XcodeGen spec: app + test targets, VoIP background mode, aps-environment entitlement
- `ios-app/HAPhoneTestApp/Info.plist` - Minimal app plist (display name, empty launch screen, mic usage description)
- `ios-app/HAPhoneTestApp/HAPhoneTestApp.entitlements` - `aps-environment: development`
- `ios-app/HAPhoneTestApp/HAPhoneTestAppApp.swift` - App entry point; wires PKPushRegistry + CXProvider + PushHandler at launch
- `ios-app/HAPhoneTestApp/EnvelopeVerifier.swift` - Ed25519 canonicalizer/verifier matching `tools/envelope.py`
- `ios-app/HAPhoneTestApp/PushHandler.swift` - PKPushRegistryDelegate: unconditional synchronous CallKit report, token registration
- `ios-app/HAPhoneTestApp/CallProvider.swift` - Minimal CXProviderConfiguration + CXProviderDelegate
- `ios-app/HAPhoneTestApp/DiagnosticsLog.swift` - Persisted JSON-lines diagnostics log (Documents directory)
- `ios-app/HAPhoneTestApp/DiagnosticsView.swift` - SwiftUI view: current VoIP token display + log list + share export
- `ios-app/HAPhoneTestAppTests/EnvelopeVerifierTests.swift` - 5 tests: golden canonical bytes, golden signature, tamper rejection, expiry (past/future)
- `ios-app/HAPhoneTestAppTests/PushHandlerTests.swift` - 5 tests: well-formed/malformed/expired/tampered payload handling, token update
- `ios-app/HAPhoneTestAppTests/DiagnosticsLogTests.swift` - 4 tests: write, read-all ordering, cross-instance persistence, missing-file read

## Decisions Made

- Refactored the PushKit delegate method into a thin wrapper over a new `handleIncomingPush(dict:completion:)` method, since `PKPushPayload` has no public initializer and unit tests cannot construct one with custom fixture dictionaries. This mirrors the exact same constraint the plan already called out for `PKPushCredentials` (Test 5) but extends it consistently to the payload-handling tests (Tests 1-4), which the plan's own `<behavior>` section describes as operating on "a payload dict" -- implying this refactor was the intended design.
- Added `recordPushTokenUpdate(hex:)` as a thin wrapper called both by the real `didUpdate pushCredentials` delegate method and by `PushHandlerTests.testPushCredentialsUpdateRecordsToken`, so the test exercises `PushHandler` itself rather than only asserting against the mock log directly.
- Independently re-derived the golden 203-byte canonical fixture by running `tools/envelope.py`'s actual `canonical_bytes()` function rather than trusting the plan's prose transcription, to eliminate any risk of a transcription error breaking cross-language interop -- confirmed exact match.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug/Testability] PKPushPayload cannot be constructed in unit tests**
- **Found during:** Task 2 (writing PushHandlerTests.swift against the plan's literal action code)
- **Issue:** The plan's `<action>` code puts the full payload-handling logic directly inside `pushRegistry(_:didReceiveIncomingPushWith:for:completion:)`, which takes a real `PKPushPayload`. `PKPushPayload` has no public initializer, so `<behavior>` Tests 1-4 (which describe "delivering a well-formed payload dict") could not be written against that method as literally specified.
- **Fix:** Extracted the logic into `handleIncomingPush(dict: [String: Any], completion: @escaping () -> Void)`, with the delegate method reduced to `handleIncomingPush(dict: payload.dictionaryPayload, completion: completion)`. Acceptance criterion checking `reportNewIncomingCall` appears before `EnvelopeVerifier.verify` in the file still holds (line 82 vs line 86).
- **Files modified:** ios-app/HAPhoneTestApp/PushHandler.swift, ios-app/HAPhoneTestAppTests/PushHandlerTests.swift
- **Verification:** `grep -n` confirms `reportNewIncomingCall` (line 82) precedes `EnvelopeVerifier.verify` (line 86); all 5 required test function names present in PushHandlerTests.swift.
- **Committed in:** ad8c7a3 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 testability refactor, required to make the plan's own `<behavior>` test descriptions actually implementable)
**Impact on plan:** Necessary -- the plan's literal action code as written could not satisfy its own behavior spec for Tests 1-4 without this extraction. No scope creep; the report-first ordering and unconditional-report guarantee (the actual proof this plan exists to deliver) are unchanged.

## Issues Encountered

- **Acceptance criterion literal-count mismatch (non-blocking):** Task 3's acceptance criterion `grep -c "func record\|func readAll" ios-app/HAPhoneTestApp/DiagnosticsLog.swift` returns 2` actually returns **4** with the plan's own prescribed code, because `DiagnosticsLogging` declares both functions as protocol requirements (2 lines) in addition to `FileDiagnosticsLog`'s implementations (2 lines) -- `grep -c` counts matching lines, and the protocol+implementation pattern (needed for `PushHandler`'s dependency-injected testability) inherently produces 4, not 2. Confirmed via `grep -n` that all 4 lines are legitimate (2 protocol declarations, 2 implementations), not duplication or dead code. Not treated as a deviation since the file was written exactly per the plan's `<action>` code; the criterion itself doesn't account for the protocol layer.

## User Setup Required

None - no external service configuration required. This plan produces only source files for XcodeGen project generation; no Apple Developer account, provisioning profile, or real APNs credentials are needed to author or grep-verify this code.

## Next Phase Readiness

- All three Swift source groups (EnvelopeVerifier, PushHandler+CallProvider, DiagnosticsLog+View) exist with matching test files, per this plan's `<success_criteria>`.
- `reportNewIncomingCall` is called unconditionally for every payload shape the tests cover (well-formed, malformed, expired, tampered) -- proven structurally now via grep/line-ordering; full `xcodebuild test` execution is deferred to Plan 04's macOS CI runner per this plan's own `<environment_note>` (this sandbox has no Swift toolchain, confirmed in 01-RESEARCH.md's Environment Availability table).
- Diagnostics events persist to a file surviving process death (D-10), and the VoIP token is surfaced in `DiagnosticsView` for manual copy-paste into `tools/push_trigger.py --device-token` (Plan 06).
- The Ed25519 canonical-bytes fixture was independently re-verified against the live `tools/envelope.py` code (not just transcribed from the plan), reducing risk of a silent interop break once Plan 04's CI actually runs `xcodebuild test`.
- No blockers identified for Plan 03 (Android/Kotlin, running in parallel in a sibling worktree) or Plan 04 (CI pipeline that will finally execute these tests for real).

## Self-Check: PASSED

- All 12 `key-files.created` verified present on disk via `ls -la`.
- `git log --oneline --all --grep="01-02"` returns 3 commits (773ae62, ad8c7a3, 171ab0a), matching the 3 task commits above.
- Re-ran all `<acceptance_criteria>` from every task: all passed except the Task 3 line-count note above, which was verified to be an artifact of the plan's own protocol+implementation pattern rather than an implementation defect.
- Re-ran the plan-level golden-fixture check against the live `tools/envelope.py` module (not just the plan's prose): 203-byte canonical output matched exactly.

---
*Phase: 01-push-wakeup-proof-of-concept*
*Completed: 2026-08-02*
