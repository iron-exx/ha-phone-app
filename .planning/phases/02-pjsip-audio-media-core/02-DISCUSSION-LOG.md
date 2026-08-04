# Phase 2: PJSIP Audio/Media Core - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-03 / 2026-08-04 (session interrupted and resumed from checkpoint)
**Phase:** 2-PJSIP Audio/Media Core
**Areas discussed:** PJSIP-Build-Strategie, Test-SIP-Server, Codec- & Netzwerk-Umgebung, Umfang Telefonie-UI, iOS-Verifikationsgrenze

---

## PJSIP-Build-Strategie

| Option | Description | Selected |
|--------|-------------|----------|
| Offiziell aus Quellcode bauen | Empfohlen laut STACK.md | ✓ |
| Erst Community-Paket zum schnellen Start, dann ersetzen | Schneller Start, aber Provenienz-/Patch-Risiko | |

**User's choice:** Offiziell aus Quellcode bauen.

| Option | Description | Selected |
|--------|-------------|----------|
| iOS: GitHub-Actions-macOS-Runner / Android: Sandbox | Empfohlen, passend zu Phase 1s Muster | ✓ |
| Beide Plattformen ausschließlich über CI bauen | Konsistenter, aber mehr CI-Abhängigkeit | |

**User's choice:** iOS via GitHub-Actions-macOS-Runner, Android in der Sandbox.
**Notes:** Diese beiden Fragen wurden bereits in der ersten (unterbrochenen) Session am 2026-08-03 beantwortet, vor dem Checkpoint-Resume.

---

## Test-SIP-Server

| Option | Description | Selected |
|--------|-------------|----------|
| Echte HA-Phone-Box | Realistischste Umgebung, aber Produktivbox | ✓ |
| Lokaler Wegwerf-Asterisk | Sauberer für Trial-and-Error, bildet echte Config nicht ab | |
| Öffentlicher SIP-Testdienst | Schnellster erster Testanruf, sagt nichts über HA-Phone aus | |

**User's choice:** Echte HA-Phone-Box.

| Option | Description | Selected |
|--------|-------------|----------|
| Eigene Test-Nebenstelle | Vermeidet Kollisionen mit echten Anrufen | ✓ |
| Bestehende Nebenstelle mitbenutzen | Einfacher, aber Kollisionsrisiko | |

**User's choice:** Eigene Test-Nebenstelle.

| Option | Description | Selected |
|--------|-------------|----------|
| Nur lokales Netz / gleicher Host | Kein Netzwerk-Workaround nötig, passt zur Roadmap-Reihenfolge | ✓ |
| Manuelle Tailscale-App als Übergangslösung | Testet auch außerhalb des LAN, nimmt Phase 5 nicht vorweg | |

**User's choice:** Nur lokales Netz / gleicher Host.

| Option | Description | Selected |
|--------|-------------|----------|
| Plain UDP wie bestehende Extensions | Kein Server-Setup nötig, entspricht heutigem HA-Phone-Verhalten | |
| TLS/SRTP jetzt für die Test-Extension aktivieren | Mehr Vorlaufaufwand, entwickelt gegen die sicherere Transportart | ✓ |

**User's choice:** TLS/SRTP jetzt aktivieren.
**Notes:** Abweichung von der Empfehlung. Bedeutet Cross-Repo-Arbeit an der separaten `Ha-Phone`-Box (sip_tls_port aktivieren, Zertifikat, TLS-Extension-Template), bevor der erste PJSIP-Testanruf möglich ist — in CONTEXT.md als D-06 mit expliziter Cross-Repo-Konsequenz vermerkt.

---

## Codec- & Netzwerk-Umgebung

| Option | Description | Selected |
|--------|-------------|----------|
| Alle drei jetzt verifizieren | Volle Abdeckung, keine spätere Überraschung | ✓ |
| Nur G.711 zuerst, Opus/G.722 später | Schnellerer erster Testanruf, Rest später in Phase 2 | |

**User's choice:** Alle drei Codecs jetzt verifizieren.

| Option | Description | Selected |
|--------|-------------|----------|
| Kein STUN/TURN in Phase 2 | Nicht nötig im LAN, gehört zu Phase 5 | ✓ |
| STUN jetzt schon konfigurieren | Vorarbeit für Phase 5, mehr Aufwand jetzt | |

**User's choice:** Kein STUN/TURN in Phase 2.

| Option | Description | Selected |
|--------|-------------|----------|
| In Phase 2 | Keine spätere Hardening-Phase existiert mehr dafür | ✓ |
| Explizit nach Phase 2 verschieben | Erstmal nur stabiles Netz, Netzwerkwechsel als offener Punkt | |

**User's choice:** Netzwerkwechsel-Handling gehört in Phase 2.

| Option | Description | Selected |
|--------|-------------|----------|
| Manuell per Netzwerk-Sniff/Log | Kein Testcode nötig, passt zu Phase 1s informellem Stil | ✓ |
| Automatisierter Test | Mehr Aufwand, verhindert stille Regression | |

**User's choice:** Manuelle Verifikation per Netzwerk-Sniff/Log.

---

## Umfang Telefonie-UI

| Option | Description | Selected |
|--------|-------------|----------|
| Nur die 5 CALL-01..05-Controls | Alles was Requirements verlangen, nicht mehr | ✓ |
| Minimal-Harness ohne echte UI | Nur Debug-Buttons/Logs, Polish später | |

**User's choice:** Die 5 CALL-Controls bekommen echte UI.

| Option | Description | Selected |
|--------|-------------|----------|
| Einfaches Texteingabefeld | Minimal, reicht für CALL-03 | |
| Klassischer Ziffernblock (Dialpad) | Näher am Endzustand, mehr UI-Aufwand | ✓ |

**User's choice:** Klassischer Ziffernblock (Dialpad) — Abweichung von der Empfehlung.

| Option | Description | Selected |
|--------|-------------|----------|
| Denselben Ziffernblock wiederverwenden | Ein Baustein für beide Zwecke | ✓ |
| Eigene, kompaktere In-Call-Tastatur | Näher am Endzustand einer echten Telefon-App | |

**User's choice:** Denselben Ziffernblock für DTMF wiederverwenden.

| Option | Description | Selected |
|--------|-------------|----------|
| Ziffernblock wiederverwenden | Konsistent mit vorheriger Wiederverwendungs-Entscheidung | ✓ |
| Eigener Transfer-Dialog | Trennt die Aktion klarer, zusätzliches UI-Element | |

**User's choice:** Ziffernblock auch für Blind-Transfer-Ziel wiederverwenden.

---

## iOS-Verifikationsgrenze

| Option | Description | Selected |
|--------|-------------|----------|
| Android-first, iOS parallel im Simulator | Beide Plattformen implementiert, iOS strukturell verifiziert | ✓ |
| Android-first, iOS erst nach Budget-Entscheidung | iOS-Teil zurückgestellt bis Apple-Developer-Entscheidung | |

**User's choice:** Android-first, iOS parallel im Simulator.

| Option | Description | Selected |
|--------|-------------|----------|
| Nur Struktur/Unit-Tests | Kein echter Audio-Ein/Ausgang über Simulator | ✓ |
| Auch echtes Audio via Host-Mac | Näher an echter CALL-01-Verifikation, kein CallKit/Lock-Screen-Verhalten | |

**User's choice:** Nur Struktur/Unit-Tests im Simulator.

| Option | Description | Selected |
|--------|-------------|----------|
| Ja, eigenes Sign-off-Dokument | Konsistent mit Phase 1s Stil | ✓ |
| Nur als Notiz in CONTEXT/Verification | Weniger Dokumentationsaufwand | |

**User's choice:** Eigenes `02-PHASE-SIGNOFF.md`, analog zu Phase 1.

| Option | Description | Selected |
|--------|-------------|----------|
| Konkreter Trigger | Macht die Bedingung greifbar | ✓ |
| Offener Punkt ohne festen Trigger | Bleibt generisch offen wie in Phase 1 | |

**User's choice:** Konkreter Trigger — Nachholen sobald Apple Developer Program aktiv ist.

---

## Claude's Discretion

None — every gray area in this discussion had an explicit user choice; no "you decide" options were used.

## Deferred Ideas

- STUN/TURN and full NAT traversal — deferred to Phase 5 (Tailscale Transport Hardening).
- Real iOS physical-device audio verification — deferred until Apple Developer Program enrollment (tracked in `02-PHASE-SIGNOFF.md`).
- Full contacts/address book for dialing — belongs to Phase 3 (QR Provisioning & Device Management).
- Automated regression test for transient SIP registration — raised, not adopted for Phase 2; no future phase assigned yet.
