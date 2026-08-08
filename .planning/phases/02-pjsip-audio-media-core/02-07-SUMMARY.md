---
phase: 02-pjsip-audio-media-core
plan: 07
subsystem: ui
tags: [ios, swiftui, callkit, dialpad, dtmf, avroutepickerview, fullscreencover]

# Dependency graph
requires:
  - phase: 02-pjsip-audio-media-core (plan 05)
    provides: SipCallController (makeCall/answer/hold/mute/transfer/sendDtmf/hangup), CallProviderDelegate (CXProviderDelegate), AppDelegate wiring PjsuaBridge/SipCallController
provides:
  - Reusable 3x4 DialpadView + DialedNumberState (one component, three call sites: dial/DTMF/transfer, mirrors Android's Plan 06 exactly)
  - OutgoingCallView -- CALL-03 entry screen, reports via CXStartCallAction through CXCallController
  - CallProviderDelegate extended with CXStartCallAction handling (Plan 05 only covered incoming-call actions)
  - CallSessionState -- shared singleton ObservableObject toggled by CXAnswerCallAction/CXStartCallAction (true) and CXEndCallAction (false)
  - ActiveCallView -- real Mute/Hold/Audio-Routing/Keypad/Transfer/End-Call UI for CALL-01..05, Mute/Hold/DTMF routed through CXCallController requests, Audio Routing via AVRoutePickerView only
  - HAPhoneTestAppApp's WindowGroup presents ActiveCallView via .fullScreenCover bound to CallSessionState.shared.isCallActive, for both incoming and outgoing calls
affects: [02-pjsip-audio-media-core (plan 08 - manual test procedure), 02-VALIDATION]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "CallSessionState singleton ObservableObject (mirrors AppDelegate.shared's minimal-DI style) drives .fullScreenCover presentation from CXProviderDelegate action handlers -- closes the checker-iteration-3 blocker where ActiveCallView was built but unreachable"
    - "AppDelegate.shared static accessor lets SwiftUI views reach SipCallController/CallProviderDelegate without a DI container, consistent with this throwaway app's existing minimal style"
    - "Mute/Hold/DTMF UI actions issue real CXCallController requests (never call SipCallController directly from the view layer) so CallKit's own system UI state stays authoritative"

key-files:
  created:
    - ios-app/HAPhoneTestApp/Sip/DialedNumberState.swift
    - ios-app/HAPhoneTestApp/DialpadView.swift
    - ios-app/HAPhoneTestApp/OutgoingCallView.swift
    - ios-app/HAPhoneTestApp/ActiveCallView.swift
    - ios-app/HAPhoneTestAppTests/DialedNumberStateTests.swift
  modified:
    - ios-app/HAPhoneTestApp/CallProvider.swift
    - ios-app/HAPhoneTestApp/HAPhoneTestAppApp.swift
    - ios-app/HAPhoneTestApp/DiagnosticsView.swift

key-decisions:
  - "Kept XCTest (not Swift Testing) for DialedNumberStateTests.swift -- the global swift/testing.md rule recommends Swift Testing for new tests, but this project's entire existing test suite (PushHandlerTests, DialStringTests, SipCallControllerTests, NetworkChangeHandlerTests, EnvelopeVerifierTests, DiagnosticsLogTests -- all from Plans 01/03/05) is XCTest-based; introducing a second test framework for one new file would fragment the suite for no functional benefit in a project with no prior Swift Testing precedent"
  - "AppDelegate.sipCallController and .callProviderDelegate widened from private to private(set), plus a new static AppDelegate.shared accessor -- exactly as the plan specified, giving SwiftUI views (OutgoingCallView, ActiveCallView) a path to the CallKit/SIP layer without introducing a DI container into this test-harness app"

requirements-completed: [CALL-01, CALL-02, CALL-03, CALL-04]

# Metrics
duration: ~12min
completed: 2026-08-08
---

# Phase 2 Plan 07: iOS Dialpad + Outgoing/Active Call UI + CallSessionState Wiring Summary

**Reusable SwiftUI DialpadView + OutgoingCallView (CXStartCallAction-reported dialing) and ActiveCallView (real Mute/Hold/AVRoutePickerView/Keypad/Transfer/End-Call), made actually reachable via a CallSessionState singleton that CallProviderDelegate toggles and HAPhoneTestAppApp presents through .fullScreenCover -- closing the checker-iteration-3 blocker where ActiveCallView existed but had no navigation path.**

## Performance

- **Duration:** ~12 min
- **Completed:** 2026-08-08
- **Tasks:** 3
- **Files modified:** 8 (5 created, 3 modified)

## Accomplishments
- `DialedNumberState` + `DialpadView` -- one 3x4 SwiftUI grid (digits + letter subtext, 44pt min tap target), reused at 3 call sites (outgoing dial, in-call DTMF, blind-transfer target) per D-12/D-13/D-14, mirroring Android's Plan 06 `DialedNumberState.kt`/`DialpadComposable.kt` shape exactly
- `OutgoingCallView` implements CALL-03: dialpad-driven extension entry, places calls via `CXCallController().request(CXStartCallAction)` rather than calling `SipCallController` directly -- the SIP `makeCall` only happens inside `CallProviderDelegate`'s new `CXStartCallAction` handler, matching CallKit's report-first contract
- `CallProviderDelegate` gains the `CXStartCallAction` handler Plan 05 didn't cover (Plan 05 only wired incoming-call actions): reports outgoing-call-started, calls `SipCallController.makeCall`, then reports connected -- this is what triggers `didActivate` for outgoing calls, giving them the same audio-session activation path incoming calls already had
- `ActiveCallView` hosts exactly the 5 CALL-01..05 controls (Mute, Hold, Audio Routing, Keypad, Transfer, End Call) per 02-UI-SPEC.md's layout; Mute/Hold/DTMF route through real `CXCallController` requests (`CXSetMutedCallAction`/`CXSetHeldCallAction`/`CXPlayDTMFCallAction`) so CallKit's own system UI stays authoritative; Audio Routing uses `AVRoutePickerView` exclusively (zero direct `AVAudioSession` references in the UI layer, verified by grep); Transfer calls `SipCallController.transfer` directly (no dedicated CallKit action exists for blind-transfer initiation)
- **Blocker fix (checker iteration 3):** added `CallSessionState`, a shared singleton `ObservableObject` toggled by `CallProviderDelegate`'s `CXAnswerCallAction`/`CXStartCallAction` handlers (`isCallActive = true` on success) and `CXEndCallAction` (`isCallActive = false`). `HAPhoneTestAppApp`'s `WindowGroup` now observes it and presents `ActiveCallView` via `.fullScreenCover(isPresented: $callSessionState.isCallActive)` for both incoming and outgoing calls -- without this, `ActiveCallView`/its Keypad/Transfer sheets would have been completely unreachable
- `DiagnosticsView` gains a "Dial" toolbar entry point (`NavigationLink` to `OutgoingCallView`), matching Android's `MainActivity` "Dial" button from Plan 06

## Task Commits

1. **Task 1: DialedNumberState + reusable DialpadView** - `cb88cbe` (feat)
2. **Task 2: OutgoingCallView + CXStartCallAction reporting (CALL-03)** - `2d7c023` (feat)
3. **Task 3: ActiveCallView (Mute/Hold/Routing/Keypad/Transfer/End Call) + CallSessionState presentation wiring** - `f1554bf` (feat)

**Plan metadata:** (pending -- this commit)

## Files Created/Modified
- `ios-app/HAPhoneTestApp/Sip/DialedNumberState.swift` - append/backspace/clear/toCallUri, sanitizes each appended character via `DialString.sanitize` (T-2-08)
- `ios-app/HAPhoneTestApp/DialpadView.swift` - shared 3x4 `LazyVGrid` dialpad
- `ios-app/HAPhoneTestAppTests/DialedNumberStateTests.swift` - append/backspace/clear/toCallUri coverage
- `ios-app/HAPhoneTestApp/OutgoingCallView.swift` - CALL-03 entry screen, places calls via `CXStartCallAction`
- `ios-app/HAPhoneTestApp/CallProvider.swift` - `CXStartCallAction` handler, `activeCallUUID` tracking, `CallSessionState` singleton toggled from `CXAnswerCallAction`/`CXStartCallAction`/`CXEndCallAction`
- `ios-app/HAPhoneTestApp/HAPhoneTestAppApp.swift` - `AppDelegate.shared` static accessor, `sipCallController`/`callProviderDelegate` widened to `private(set)`, `WindowGroup` presents `ActiveCallView` via `.fullScreenCover`
- `ios-app/HAPhoneTestApp/ActiveCallView.swift` - Active Call screen hosting all 5 CALL-01..05 controls
- `ios-app/HAPhoneTestApp/DiagnosticsView.swift` - "Dial" toolbar entry point

## Decisions Made
See `key-decisions` in frontmatter -- kept XCTest for consistency with the project's existing test suite (no Swift Testing precedent anywhere in this codebase), and widened `AppDelegate`'s CallKit/SIP properties to `private(set)` exactly as the plan specified for minimal-DI SwiftUI access.

## Deviations from Plan

None -- plan executed exactly as written. Every illustrative code snippet in the plan (task actions) was checked against the actual as-built API surface from Plan 05's `SipCallController.swift` (`makeCall(_:) throws`, `transfer(_:) throws`, `hangup()`, `hold(_:)`, `mute(_:)`, `sendDtmf(_:)` -- confirmed by reading the real file, not assumed) and `CallProvider.swift`'s existing `CallProviderDelegate` (confirmed `CXAnswerCallAction`/`CXEndCallAction`/`CXSetHeldCallAction`/`CXSetMutedCallAction`/`CXPlayDTMFCallAction` handlers already present, `didActivate`/`didDeactivate` already wired) before editing. All method signatures, CallKit action initializers (`CXStartCallAction(call:handle:)`, `CXSetMutedCallAction(call:muted:)`, `CXSetHeldCallAction(call:onHold:)`, `CXPlayDTMFCallAction(call:digits:type:)`, `CXEndCallAction(call:)`), and grep-based acceptance criteria matched on the first attempt -- no auto-fixes (Rules 1-3) were needed and no architectural questions (Rule 4) arose.

## Issues Encountered

**Sandbox verification limits (expected, per D-02/D-15/D-16):** This is a Linux sandbox with no Xcode/xcodebuild/Swift compiler available. All Swift code in this plan was verified **structurally only**: every file's existence, every grep-matched signature/pattern from the plan's acceptance criteria (all 20+ checks re-run and confirmed passing after all 3 tasks -- see command output in this execution), and manual reasoning about SwiftUI/CallKit API shapes (property wrapper requirements for `.fullScreenCover(isPresented:)` needing a two-way `Binding<Bool>`, which `@Published var isCallActive` without `private(set)` correctly provides via `$callSessionState.isCallActive`; `CXPlayDTMFCallAction`'s three-argument initializer; etc.), cross-checked against the real, already-compiled Plan 05 interfaces rather than assumed from the plan's illustrative snippets alone. No `xcodebuild build`/`xcodebuild test` was run or could be run in this environment. Real compilation and XCTest execution happens exclusively on Plan 03's GitHub Actions macOS runner (`ios-ci.yml`), which has not been re-triggered as part of this execution -- the next push to `main` touching `ios-app/**` will be the first real compile/test signal for this plan's code. This is consistent with every prior iOS plan in this phase (03, 05) and is not a new gap.

**Graphify rebuild (project CLAUDE.md housekeeping, not a plan blocker):** Ran the project's mandated post-edit graph rebuild (`python3 -c "from graphify.watch import _rebuild_code..."`) after committing all 3 tasks. It completed AST extraction over all 4134 tracked files but failed at the visualization step with a pre-existing tool limitation ("Graph has 43157 nodes - too large for HTML viz. Use --no-viz or reduce input size") -- this is unrelated to this plan's changes (the node count is project-wide, not iOS-specific) and no `graphify-out/` files were modified as a result (rebuild failed before any write). Out of scope for this plan to fix; noted here rather than silently ignored.

## User Setup Required

None for this plan directly. Carried forward from Plan 05/01 (unresolved, not new here): a developer building the iOS app locally needs `ios-app/Secrets.xcconfig` populated with real HA-Phone test-extension credentials (gitignored, not committed); Plan 01's live TLS transport deploy on the real HA-Phone box is still pending user action before any real call (incoming or outgoing) can succeed end-to-end.

## Next Phase Readiness
- All 5 CALL-01..05 controls now have real, structurally-verified UI on iOS for both incoming and outgoing calls, with the previously-missing navigation/presentation path (`CallSessionState` -> `.fullScreenCover`) now in place -- iOS and Android (Plan 06) are UI-complete and symmetric for Phase 2's scope.
- Real compile/test verification of this plan's Swift code is still pending Plan 03's CI pipeline actually running against this commit (next push to `main` touching `ios-app/**`) -- not yet confirmed green as of this summary, consistent with every prior iOS plan in this phase.
- Blocker carried forward (not new to this plan): Plan 01's live TLS transport deploy on the real HA-Phone box is still pending user action before Plan 08's manual end-to-end test call can succeed on either platform.
- Plan 08's manual test procedure can now exercise the full iOS UI surface (Dial -> Outgoing Call -> Active Call with Mute/Hold/Routing/Keypad/Transfer -> End Call, plus Incoming Call -> Answer -> Active Call) once the live TLS transport is confirmed on the real HA-Phone box.

---
*Phase: 02-pjsip-audio-media-core*
*Completed: 2026-08-08*

## Self-Check: PASSED

All 5 created files verified present on disk; all 3 task commits (`cb88cbe`, `2d7c023`, `f1554bf`) verified in `git log`.
