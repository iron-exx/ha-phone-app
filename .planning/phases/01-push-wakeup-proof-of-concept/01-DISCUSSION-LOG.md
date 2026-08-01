# Phase 1: Push-Wakeup Proof of Concept - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-01
**Phase:** 1-Push-Wakeup Proof of Concept
**Areas discussed:** Test-Geräte-Matrix, Test-Trigger-Mechanismus, Inhalt der Anrufanzeige im Prototyp, Umgang mit verspätetem/fehlgeschlagenem Push

---

## Test-Geräte-Matrix

| Option | Description | Selected |
|--------|-------------|----------|
| Aktuelles iPhone, aktuelle iOS-Version | Modernes iPhone-Modell mit aktueller iOS-Version | ✓ |
| Älteres iPhone (mehrere Jahre alt) | Relevant wegen abweichendem PushKit/CallKit-Verhalten | |
| Kein iPhone verfügbar / erst noch zu beschaffen | iOS-Tests müssten verschoben werden | |

**User's choice:** Aktuelles iPhone, aktuelle iOS-Version

| Option | Description | Selected |
|--------|-------------|----------|
| Pixel (Stock Android) | Gutmütigstes Verhalten, laut Recherche allein nicht ausreichend | ✓ |
| Samsung | Aggressive Battery-Optimization | |
| Xiaomi/Huawei/andere aggressive OEMs | Härtester Testfall | |
| Nur ein Gerät verfügbar (egal welches) | Phase 1 testet nur auf einem Gerät | |

**User's choice:** Pixel (Stock Android)
**Notes:** Kein Nicht-Pixel-OEM-Gerät verfügbar — Roadmap-Erfolgskriterium "Test auf Nicht-Pixel-OEM" ist damit nicht erfüllbar und wurde als offener Punkt in CONTEXT.md (D-03) festgehalten statt stillschweigend fallengelassen.

---

## Test-Trigger-Mechanismus

| Option | Description | Selected |
|--------|-------------|----------|
| Eigenständiges Test-Skript (direkt APNs/FCM) | Kleines CLI-Skript außerhalb von HA-Phone | ✓ |
| Minimaler Endpunkt in HA-Phone (echter Anruf über Asterisk) | Realistischer, aber mehr Aufwand in Phase 1 | |

**User's choice:** Eigenständiges Test-Skript (direkt APNs/FCM)

| Option | Description | Selected |
|--------|-------------|----------|
| Getrennt halten (empfohlen für Phase 1) | Testskript im ha-phone-app-Repo, HA-Phone unangetastet | ✓ |
| Schon jetzt in HA-Phone integrieren | Echter /api/mobile/test-push-Endpunkt schon jetzt | |

**User's choice:** Getrennt halten (empfohlen für Phase 1)

---

## Inhalt der Anrufanzeige im Prototyp

| Option | Description | Selected |
|--------|-------------|----------|
| Fester Platzhalter ("HA-Phone Testanruf") | Einfachster Weg, Fokus auf Weck-Nachweis | ✓ |
| Statische Test-Nummer/Name aus dem Push-Payload | Etwas realistischer | |

**User's choice:** Fester Platzhalter ("HA-Phone Testanruf")

| Option | Description | Selected |
|--------|-------------|----------|
| Unsigniert reicht für Phase 1 | Signatur ist Teil des späteren Relay-Modells (Phase 6) | |
| Von Anfang an signiert | Signatur-Schema (z.B. ed25519) schon in Phase 1 durchspielen | ✓ |

**User's choice:** Von Anfang an signiert
**Notes:** Nutzer möchte das Payload-Format von Anfang an so bauen, dass später keine Breaking Changes am Signatur-Schema nötig werden, auch wenn der volle Multi-Tenant-Relay erst in Phase 6 kommt.

---

## Umgang mit verspätetem/fehlgeschlagenem Push

| Option | Description | Selected |
|--------|-------------|----------|
| Nein, nur protokollieren (empfohlen für Phase 1) | Fehlerfälle geloggt, kein automatisches Retry | ✓ |
| Ja, einfaches Retry schon in Phase 1 | Erneutes Senden nach z.B. 5s ohne Bestätigung | |

**User's choice:** Nein, nur protokollieren (empfohlen für Phase 1)

| Option | Description | Selected |
|--------|-------------|----------|
| Definierte Anzahl Testanrufe pro Gerätezustand (empfohlen) | Objektiv nachprüfbar, z.B. 10 Testanrufe je Zustand | |
| Informelles "fühlt sich zuverlässig an" | Kein festes Zahlenziel | ✓ |

**User's choice:** Informelles "fühlt sich zuverlässig an"
**Notes:** Nutzer wählte bewusst gegen die empfohlene Option (definierte Testanzahl) — informelle Einschätzung reicht ihm für den Phase-1-Nachweis.

---

## Claude's Discretion

None — all areas resolved with explicit user choices.

## Deferred Ideas

- Non-Pixel Android OEM-Testabdeckung (Samsung/Xiaomi) — verschoben, bis passendes Testgerät verfügbar ist.
- Retry-/Timeout-Handling für verpasste/verspätete Pushes — explizit auf Phase 4/5 verschoben.
- Echte Inbound-Call-löst-Push-Verdrahtung über Asterisk AMI/ARI — verschoben bis Phase 2 (SIP-Kern) und Phase 4 (Call-State-Orchestrierung) existieren.
