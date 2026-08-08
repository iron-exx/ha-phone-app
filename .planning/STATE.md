---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
stopped_at: Completed 02-05-PLAN.md (iOS SIP call controller -- PjsuaBridge, SipCallController, AudioSessionCoordinator, NetworkChangeMonitor, CallProvider wiring)
last_updated: "2026-08-08T13:13:44.740Z"
last_activity: 2026-08-08
progress:
  total_phases: 7
  completed_phases: 1
  total_plans: 14
  completed_plans: 9
  percent: 64
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-07-31)

**Core value:** Ein eingehender Anruf klingelt zuverlässig über die native Anrufoberfläche, egal ob die App geschlossen oder das Gerät gesperrt ist — ohne dauerhaft laufende SIP-Verbindung oder VPN-Tunnel im Hintergrund.
**Current focus:** Phase 02 — pjsip-audio-media-core

## Current Position

Phase: 02 (pjsip-audio-media-core) — EXECUTING
Plan: 5 of 8 complete (wave 1: 02-01 cross-repo HA-Phone TLS extension still pending -- no dependency between 02-01/02-02)
Status: Ready to execute
Last activity: 2026-08-08

Progress: [██████░░░░] 64%

## Performance Metrics

**Velocity:**

- Total plans completed: 6
- Average duration: - min
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1 | 6 | - | - |

**Recent Trend:**

- Last 5 plans: -
- Trend: -

*Updated after each plan completion*
| Phase 02 P04 | 30min | 3 tasks | 17 files |
| Phase 02 P05 | 20min | 3 tasks | 18 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Roadmap: Push-wake proven first (Phase 1) because every other capability is worthless if calls don't ring reliably.
- Roadmap: SIP/media core and QR provisioning split into two phases (2 and 3) that can be built in parallel — neither has a functional dependency on the other.
- Roadmap: Multi-tenant push-relay deliberately sequenced last among core phases (Phase 6) — its contract must be derived from real payload iteration, not designed speculatively.
- Phase 02 Plan 02: Cross-compiled libopus 1.5.2 from source per-ABI (arm64-v8a, x86_64) using the NDK's per-API-level clang wrapper, instead of the sandbox's system libopus-dev, which only ships a host x86_64 library unusable for Android cross-compilation.
- Phase 02 Plan 02: SWIG's Java/JNI binding generation must run inside the per-ABI build loop (not once after it) -- it links against whichever ABI's static libs the currently-active build.mak/TARGET_ARCH describes.
- [Phase 02]: Phase 02 Plan 04: Real HA-Phone test-extension credentials wired via local.properties -> BuildConfig fields, not hardcoded Kotlin literals, to avoid committing a live LAN PBX password to the public GitHub repo (kotlin/security.md).
- [Phase 02]: Phase 02 Plan 04: PJSUA2 SWIG 4.2.0 bindings generate plain int constants (no enum types/.swigValue()) and androidx.core.telecom's CallControlScope.disconnect() requires a DisconnectCause argument -- both discovered by compiling against real bindings, not assumed from illustrative plan snippets.
- [Phase 02]: Phase 02 Plan 05: Real HA-Phone test-extension credentials wired via Secrets.xcconfig -> Info.plist $(SIP_TEST_*) substitution -> Bundle.main, not hardcoded Swift literals, mirroring Plan 04's Android local.properties -> BuildConfig pattern (avoids committing a live LAN PBX password to the public repo).
- [Phase 02]: Phase 02 Plan 05: Added NS_SWIFT_NAME to every PjsuaBridge.h method to pin exact Swift call-site names, since this sandbox has no Swift compiler to verify Clang's default Objective-C-to-Swift name-mangling for VerbWithNoun: selectors.

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 5 (Tailscale Transport Hardening) has no prior research coverage — the Tailscale-as-transport decision (tsnet vs. auth-key/OAuth node registration, ICE interaction, ephemeral lifecycle) postdates ARCHITECTURE.md. `/gsd-plan-phase 5` must trigger a dedicated research pass before producing a detailed plan.
- Phase 7 (Door-Station): RTSP→app video bridging and H.264 profile compatibility is hardware-specific; an early technical spike against the real Akuvox hardware is recommended before committing to a gateway architecture, and can start in parallel with earlier phases.
- Android PUSH-04 has a hard external dependency: Google Play requires an explicit "calling app" declaration in Play Console for full-screen-intent apps (since Jan 2025) — tracked as a Phase 1 success criterion, not to be silently assumed done.
- Plan 01's live TLS transport deploy on the real HA-Phone box is still pending (git push to the box not yet done by the user) -- Plan 04's SIP config code is complete and compiles against the real test-extension credentials, but no end-to-end call has been verified live yet. Also: Plan 01 specified the test extension should come from the 80-99 sub-range (D-04), but the extension actually supplied/used is 13 (inside the active 10-99 household range) -- needs reconciliation before Plan 08's manual test.
- 02-03-SUMMARY.md is missing even though Plan 02-03's commits (5551283, 9a5c12b) already exist in git log -- Plan 03's summary/state-update step appears to have been skipped in an earlier session. Worth a follow-up to backfill 02-03-SUMMARY.md for the dependency-graph/context-assembly tooling.

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Telefonie | CALL-06 Attended Transfer, CALL-07 CDR-Sync, CALL-08 Favoriten | v1.x | Requirements definition |
| Türstation | DOOR-03 Snapshot speichern | v1.x | Requirements definition |
| Netzwerk | OPS-04 Vertiefte Netzwerkwechsel-Härtung | v1.x | Requirements definition |
| Integration | FUT-01..04 (Video, Multi-PBX, weitere HA-Aktionen, weitere Türstationshersteller) | v2 | Requirements definition |

## Session Continuity

Last session: 2026-08-08T13:13:44.726Z
Stopped at: Completed 02-05-PLAN.md (iOS SIP call controller -- PjsuaBridge, SipCallController, AudioSessionCoordinator, NetworkChangeMonitor, CallProvider wiring)
Resume file: None
</content>
</invoke>
