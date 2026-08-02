# Manual Test Procedure: Push-Wakeup Proof of Concept (Phase 1)

This procedure exercises the push-wakeup path built in this phase: a
signed envelope (`tools/envelope.py`) sent via `tools/push_trigger.py`
toward a real iOS or Android device, verifying the native call UI
appears reliably across app states. There is no real inbound call via
Asterisk in this phase (per D-04/D-05) -- the test-trigger script sends
the push directly.

## Device Matrix Scope (D-03)

- **iOS test device:** the developer's own current-generation iPhone,
  running current iOS (D-01).
- **Android test device:** a Pixel, stock Android, only (D-02).
- **Non-Pixel OEM coverage (Samsung, Xiaomi, and other aggressive-OEM
  Android devices) is explicitly deferred, not silently dropped.**
  ROADMAP.md's Phase 1 success criterion #3 ("verified on at least one
  non-Pixel OEM device") is not satisfiable with the current device
  matrix -- no such device is currently available. Phase 1 sign-off is
  scoped to Pixel-only; OEM diversity is revisited as a backlog item at
  Phase 6 hardening, per RESEARCH.md Open Question #3's recommendation.
  This is the explicit resolution to that success criterion for this
  phase -- it is tracked as deferred, not assumed done.

## App States to Exercise (D-09)

Per CONTEXT.md decision D-09, the following five app states are
exercised across manual test runs:

1. **Foreground** -- app open and visible on screen.
2. **Backgrounded** -- app sent to background (home button / swipe up),
   not force-quit.
3. **Locked** -- device screen off / lock screen active.
4. **Terminated** -- app fully force-quit / swiped away from the
   app-switcher (iOS) or recent-apps list (Android).
5. **Overnight standby** -- device locked and idle for 8+ hours,
   started before sleep and checked the following morning. This state
   is the one most likely to expose OS-level Doze/App Standby
   interference, even on stock Android/Pixel, and is run as its own
   long-duration test rather than a quick check.

## Per Test Run

1. Put the device in the target app state (one of the five above).
2. From the ha-phone-app repo, run the test-trigger script for the
   target platform and state, for example:
   ```
   python3 tools/push_trigger.py --platform ios --state locked --device-token <token>
   python3 tools/push_trigger.py --platform android --state backgrounded --device-token <token>
   ```
   The script signs a fresh envelope, sends the push, and logs a
   `sentAt` timestamp (its own local clock) to `tools/logs/push_log.csv`.
3. Observe the device: does the native call UI (CallKit on iOS, the
   incoming-call notification/ConnectionService flow on Android) appear?
   A rough stopwatch/eyeball estimate of latency is sufficient -- per
   D-09 there is no fixed numeric latency target for Phase 1.
4. The app itself logs `receivedAt` (when its push handler fired) and
   `reportedAt` (when `reportNewIncomingCall`/`addCall` returned). For
   iOS specifically, since a *terminated* app has no live Xcode console
   available (no local Mac, per D-10), the app must persist these
   timestamps to a local log file on wake and the developer reads them
   back afterward via TestFlight. For Android, `adb logcat` can be used
   directly against the connected Pixel.
5. Record pass/fail and the rough latency in the Result Log Table
   below. Repeat across at least a few runs per state -- no fixed count
   is required (D-09), but enough repetitions to form a qualitative
   "does this feel reliable" judgment.
6. Run the **overnight standby** state specifically as its own
   long-duration test: trigger the push once before going to sleep with
   the device already locked and idle, then check the result the next
   morning. Do not substitute a short locked-state test for this run --
   its purpose is to catch OS-level background-kill behavior that only
   manifests after extended idle time.

## Result Log Table

| Date | Platform | State | sentAt | receivedAt | reportedAt | Latency (rough) | Pass/Fail | Notes |
|------|----------|-------|--------|------------|------------|------------------|-----------|-------|
| 2026-08-02 | ios | foreground | 09:00:00 | 09:00:01 | 09:00:01 | ~1s | Pass | Example row -- CallKit UI appeared immediately |
| 2026-08-02 | android | locked | 09:05:00 | 09:05:03 | 09:05:04 | ~3-4s | Pass | Example row -- screen woke, incoming-call UI shown |
| 2026-08-03 | ios | overnight | 23:30:00 | 07:12:00 | 07:12:01 | (next morning) | Fail | Example row -- push did not arrive until manual app open; investigate iOS background delivery |

## D-09 Acceptance

Per decision D-09, Phase 1's Definition of Done does **not** use a fixed
numeric test-count or success-rate target. Acceptance is the developer's
own qualitative judgment -- "this feels reliable" -- formed after enough
repetitions across all five app states listed above to be confident in
that judgment. The overnight-standby state is run at least once as its
own dedicated long-duration test (not skipped or approximated by a
shorter run), since it is the state most likely to reveal aggressive
platform power-management behavior that a short foreground/backgrounded
test cannot surface.

If a state repeatedly fails (push never wakes the app), that is a real
Phase 1 blocker to investigate before proceeding -- it should not be
silently averaged away by successes in other states.
