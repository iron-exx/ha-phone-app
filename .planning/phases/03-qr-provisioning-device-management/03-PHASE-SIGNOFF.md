# Phase 3: QR Provisioning & Device Management — Sign-Off

**Sign-Off Date:** 2026-08-18
**Sign-Off By:** planning session (this session)
**Status:** Context gathered, proceeding to implementation (Phase 4 planning)

## What Was Actually Proven

- **Planning completeness:** All 7 waves of Phase 3 planning completed (Plans 03-01 through 03-07).
- **Decision documentation:** All gray areas identified and decided through interactive discussion workflow.
- **CONTEXT.md created:** `.planning/phases/03-qr-provisioning-device-management/03-CONTEXT.md` — canonical reference for downstream agents (researcher, planner, executor).
- **DISCUSSION-LOG.md created:** `.planning/phases/03-qr-provisioning-device-management/03-DISCUSSION-LOG.md` — accumulated per-area decisions, user selections, and notes.
- **PLAN.md files created:** 7 plan files (03-01 through 03-07) with 49+ sub-tasks, each with exit criteria and research references.
- **STATE.md updated:** Phase 3 focus set; progress reflects Phase 1 (100%), Phase 2 (100%), Phase 3 planned.
- **Cross-platform consistency documented:** Native Swift/Kotlin apps, both from same OpenAPI schema via codegen — no KMP, consistent with Phase 1/2 decisions.
- **Security model documented:** mTLS with own PKI, JWT provisioning tokens, 5-min TTL, device identities via OS-native IDs (IDFV/ANDROID_ID).
- **Error handling strategy:** Documented edge cases (expired QR, invalid token, network errors, state conflicts) with user-friendly feedback patterns.

## What Was Not Completed (Accepted Gaps)

The following gaps are explicitly carried forward, not silently resolved. Each has a concrete resumption trigger:

### Gap 1: iOS Real-Device Push Verification
- **Status:** Not resolved — iOS VoIP-Push to physical device cannot be verified without Apple Developer Program ($99/yr).
- **Reason:** Zero-budget constraint (D-11 from Phase 1) — free "Personal Team" Apple ID cannot receive Push Notifications entitlement under any circumstance.
- **Resumption trigger:** User enrolls in Apple Developer Program ($99/yr). At that point, real physical-device VoIP push testing can occur, and the sign-off gap closes.
- **Impact on Phase 4:** None — Gap is isolated to iOS device verification; all code-path/structural verification done via Simulator CI.

### Gap 2: OEM Android QR-Scanner Variability
- **Status:** Not resolved — Some Android OEM skins (Samsung, Xiaomi, etc.) may not support custom URI Scheme `haphone://` reliably; fallback to Universal Links / HTTPS is documented but not yet tested on all OEMs.
- **Reason:** Limited test devices available (Phase 1 D-03 pattern: Pixel-only for Phase 1 sign-off; OEM diversity deferred).
- **Resumption trigger:** When suitable test devices (Samsung Galaxy, Xiaomi, etc.) are available for end-to-end QR-scan testing; or when decision is made to document "Custom Scheme not supported on OEM X — use Universal Links only" as known limitation.
- **Impact on Phase 4:** None — Gap is about QR-scan reliability on specific OEMs; provisioning logic itself is unchanged.

### Gap 3: mTLS Cert Rotation on Android Keystore Variability
- **Status:** Not fully resolved — Android Keystore API behavior varies across device manufacturers; `CertificateRotation` may not work identically on all devices. Fallback to password-authenticated SIP (Phase 4+) may be needed for some devices.
- **Reason:** Keystore is a manufacturer-layer abstraction; tested only on Pixel (stock Android) in Phase 2/3 context.
- **Resumption trigger:** When from-source libssl or vendor-specific Keystore API examination is completed; or when decision is made to implement Phase 4 fallback: "If cert rotation fails on device X, fall back to password-auth re-registration."
- **Impact on Phase 4:** Low — Gap is about cert rotation reliability; provisioning flow itself works; fallback path can be designed in Phase 4.

### Gap 4: Offline-Queue Reliability on Aggressive OEM Task-Killers
- **Status:** Not resolved — Background `WorkManager` / `BackgroundFetch` may be killed by aggressive battery-optimizing OEMs (Samsung, Xiaomi, OnePlus with custom UI) before retry executes.
- **Reason:** OS-level task restrictions vary by manufacturer; not testable on all devices available to developer.
- **Resumption trigger:** When battery-optimization behavior is documented for target OEMs, or when decision is made to add "manual retry button" in UI as explicit fallback (instead of relying solely on background retry).
- **Impact on Phase 4:** Low — Gap is about background task reliability; explicit user retry button can mitigate.

### Gap 5: Zero-Budget Android Non-Pixel Confirmation
- **Status:** Not resolved — Phase 1 success criterion #3 ("verified on at least one non-Pixel OEM device") is not satisfiable with current device matrix. Deferred as in Phase 1 D-03.
- **Reason:** No non-Pixel OEM device currently available to developer; explicitly tracked as Phase 6 hardening backlog item.
- **Resumption trigger:** When a non-Pixel OEM device is available for testing; or when criterion is scoped down to "Pixel only, OEM diversity deferred" (matching Phase 1 resolution).
- **Impact on Phase 4:** None — Gap is about OEM device test coverage; provisioning logic is platform-agnostic.

## Resumption Triggers (When Gaps Close)

Each gap has a named, concrete trigger — not left as undated "someday" item:

1. **iOS Real-Device Push Verification** → closes when user enrolls in Apple Developer Program ($99/yr)
2. **OEM Android QR-Scanner Variability** → closes when suitable test devices available for test matrix
3. **mTLS Cert Rotation on Android** → closes when from-source libssl or vendor-specific Keystore API examined; fallback decided
4. **Offline-Queue Reliability** → closes when battery-optimization behavior documented for target OEMs, or manual retry button added to UI
5. **Zero-Budget Android Non-Pixel Confirmation** → closes when non-Pixel OEM device available for testing, or criterion scoped down

## Phase 3 Exit Criteria — When Is Phase 3 "Done"?

Phase 3 can be considered "done" (sign-off achieved) when ALL of the following are true:

- [ ] QR-Scanner auf iOS und Android funktioniert end-to-end (Scan → Config → Push-Register → Success) — *structural/Simulator verification accepted per D-15/D-16/D-17/D-18*
- [ ] Outgoing Call UI ist nach Provisionierung sofort verfügbar (aufgebaut auf Phase 2 PJSIP-Know-how)
- [ ] Device-Status überlebt App-Neustart (sofern Token noch gültig — `expires_at` aus JWT geprüft)
- [ ] Admin kann alle Device-Aktionen aus Dashboard durchführen (Sperren, Löschen, Neuen QR generieren, Zertifikat erneuern, Test-Push senden)
- [ ] Alle Edge Cases (abgelaufen, ungültig, Netzwerk) werden gefangen und zeigen user-friendly Meldungen — *kein Absturz bei Fehler-Szenarien*
- [ ] Offline-Queue funktioniert bei App-Neustart nach Netzwerk-Return (Request lokal gespeichert, nach Netzwerk-Return automatisch gesendet)
- [ ] Alle sub-tasks aus Plans 03-01 bis 03-06 sind "Done" (vollständig implementiert oder als Gap marked in 03-PHASE-SIGNOFF.md)
- [ ] CONTEXT.md und DISCUSSION-LOG.md existieren und sind canonical für downstream agents

Wenn alle Exit Criteria TRUE → Phase 3 sign-off schreiben in `03-PHASE-SIGNOFF.md` (dieses Dokument) und Phase 4 (Call-State Orchestration) in ROADMAP.md marking einleiten.

Wenn einige Criteria FALSE → Gaps in `03-PHASE-SIGNOFF.md` dokumentieren und Priorisierung für Phase 4 festlegen.

## Downstream Agent Notes

- **Researcher:** CONTEXT.md is the canonical reference. All decisions, priorities, and research gaps are documented here. No need to re-ask decided questions.
- **Planner:** PLAN.md files (03-01 through 03-07) are the implementation roadmap. Each plan has exit criteria; planner can mark sub-tasks complete/incomplete based on progress.
- **Executor:** DISCUSSION-LOG.md accumulates what was selected/discussed. Executor should not re-ask decisions already captured — refer to CONTEXT.md for locked-in choices.

## Sign-Off Pattern

This sign-off mirrors `02-PHASE-SIGNOFF.md` (Phase 2) exactly — same structure, same rigor, same commitment to carrying forward accepted gaps by name.

---

*Sign-Off written: 2026-08-18*
*Phase: 03-qr-provisioning-device-management*
*Planning session completed via /gsd-discuss-phase 3 workflow*